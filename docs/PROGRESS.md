# Mega Chamomile — Progress Log

Read DESIGN.md first for the what/why. This file tracks exactly where the
build is so a fresh session can pick up instantly.

## Status: MVP COMPLETE & VERIFIED (session 1, 2026-07-11)

The full game loop exists and runs: menu → host/join lobby → paint phase →
seek phase → results → back to lobby, multiplayer over ENet, with the
paint-yourself mechanic, eyedropper, seeker shooting, LoS bold scoring,
eliminations, spectator mode, sounds, and HUD.

### Verified (don't re-verify, build on it)
- `godot --headless -s tests/run_tests.gd` → **38 checks pass**: full match
  flows, roles, ammo/cooldown, bold scoring math, disconnect wins, solo mode,
  vertex splat painting (paints near hit, not far; fill_all works).
- **Headless 2-instance E2E over real ENet** (see README for the command):
  host+guest connected, roles split, phases flowed PAINT→SEEK→RESULTS→lobby
  on both peers, LoS bold points actually accrued server-side (guest scored
  98 = ~6s spotted survival + 75 bonus), clean exit.
- **Windowed smoke + screenshot review**: HUD (role card, phase banner,
  timer, alive count, swatch, hints, SEEKERS RELEASED banner), white blocky
  humanoid, colored zones, nameplate — all render on GL Compatibility.
  Lighting tuned so ambient+sun ≈ 1.0 (was overbright, washed out floor).

### NOT yet verified (first things to playtest)
- Actual mouse-driven painting/eyedropping in a live window (splat math is
  unit-tested, raycast→splat wiring is not human-tested).
- Shooting a real painted hider across two windows; tracer visuals.
- Feel/tuning: mouse sens, camera distance, brush size, LoS cone width.

### File map (everything is code-built; .tscn files are 3-line shells)
- `autoload/app.gd` — settings, scene transitions, InputMap, CLI flags
  (`--host --join --name --autostart N --fast-phases --quit-after S
  --screenshot path --screenshot-at S`)
- `autoload/net.gd` — ENet host/join, player registry, ALL orchestration RPCs
- `scripts/match_state.gd` — PURE rules (phases/roles/scores/ammo/wins)
- `scripts/game_scene.gd` — server: MatchState+LoS+shots; all: spawn/FX/HUD
- `scripts/player.gd` — move/camera/paint/eyedrop/shoot/sync/spectator
- `scripts/paintable_body.gd` — subdivided-box humanoid, vertex splats
- `scripts/hud.gd`, `scripts/main_menu.gd`, `scripts/lobby.gd`
- `maps/map_basic.gd` — data-driven ZONES array; maps must expose
  `hider_spawns()/seeker_spawns()/set_seek_open(bool)`
- `tests/run_tests.gd` — headless suite

### Next steps (in rough priority order)
1. **Two-window human playtest** (host + join 127.0.0.1): paint feel, shoot
   feel, tune constants at the top of player.gd / game_scene.gd.
2. Paint UX: brush preview ring on the body, recent-colors palette row,
   maybe a symmetric-paint toggle.
3. Juice: hit particles/paint poof on elimination, muzzle flash, camera
   shake, waiting-pen ceiling (seekers can currently jump-peek? pen walls are
   3.5m — probably fine), round-start countdown ("3..2..1").
4. Poses: lean/flatten-against-wall (the third P of the original game).
5. More maps: copy map_basic.gd, edit ZONES + spawns (contract in the file).
6. Later: texture painting upgrade (analytic box UVs), party codes/lobby
   service instead of raw IPs, host migration, late-join spectators.

### Gotchas learned (respect these)
- Autoload is `App`, not `Game` — a scene root named "Game" would collide
  with an autoload named "Game" at /root and break RPC paths.
- Orchestration RPCs live on Net (autoload) because autoload paths always
  exist on every peer; scene-node RPCs race scene loading. Barriers
  (`notify_scene_ready` / `notify_match_ready`) gate match start.
- MatchState must stay free of scene/network imports so tests stay headless.
- Eyedropper reads the rendered frame → keep total light energy ≈ 1.0 so
  sampled pixels ≈ albedo, or painted colors won't match walls.
- BoxMesh.get_mesh_arrays() + ARRAY_COLOR + vertex_color_use_as_albedo works
  fine on GL Compatibility; rebuild via clear_surfaces+add_surface_from_arrays.
