# Mega Chamomile — Progress Log

Read DESIGN.md first for the what/why. This file tracks exactly where the
build is so a fresh session can pick up instantly.

## Status: paint feel + camera orbit fixes after second playtest (session 3, 2026-07-11)

### Session 3: paint strokes, brush ring, orbit regression
- **Camera orbit while captured was dead** (playtest: "mouse captured but view
  doesn't change"). Root cause: the HUD crosshair ColorRect sits at dead
  center — exactly where every captured-mouse motion event lands — and
  Controls default to MOUSE_FILTER_STOP, so the GUI consumed the motion before
  player `_unhandled_input`. In session 1 the WASD spin bug masked this. Fix:
  `_pass_mouse_through()` recursively sets MOUSE_FILTER_IGNORE on every HUD
  control (hud.gd), incl. the late-built results overlay. Regression test
  walks the HUD and asserts no STOP controls.
- **Painting was dotted, not continuous** ("bloop bloop bloop, ~4 dots/sec"):
  16Hz sampling + no interpolation left gaps on fast drags. Now the brush
  samples every frame and consecutive hits become a *stroke*: an RPC carries
  (from, to, color, radius) and every peer stamps along the segment at
  radius/2 spacing (paintable_body.gd `stroke()`). Holding still sends
  nothing (min-step dedupe); jumps > 0.35m aren't connected (no lines drawn
  through the torso when the cursor skims off an edge). Stamps now paint all
  parts they touch, so strokes don't seam at part boundaries. Old
  `splat(part_idx, ...)` / `apply_splat` RPC replaced by
  `splat_at`/`stroke`/`apply_stroke`.
- **Brush ring at the cursor** in paint mode: hud.gd draws a color ring w/
  dark halo at the cursor, sized to the brush's true projected on-screen
  radius (player.gd `brush_cursor_px()` unprojects radius at hit distance).
  Its center stays transparent so RMB samples the rendered surface beneath it,
  not the brush color itself. The little 40px preview next to the swatch remains.
- **Under-map fall recovery**: a hidden catch volume below the arena returns
  the local player to their assigned match spawn and clears their velocity.
  Normal transform sync propagates the recovery to the other peers.

### Session 2: playtest feedback fixes
- **Fixed the WASD spin bug**: the body turns to face travel direction by
  rotating the CharacterBody root, but the camera rig is a child of that root
  → rotating the root dragged the camera → feedback loop → constant spinning.
  Fix: counter-rotate `_rig.rotation.y` by the same yaw delta so the camera's
  world yaw holds still while the body turns (player.gd `_local_move`).
- **F toggles paint mode** (hiders only): cursor released, LMB click/drag
  directly on your body to paint (ray from cursor, not crosshair), RMB
  eyedrops the pixel under the cursor, MMB-drag orbits the camera, wheel
  resizes brush. Auto-exits when painting becomes illegal (eliminated/results).
  Crosshair-paint while captured still works too.
- **Esc is now a pause menu** (scripts/pause_menu.gd): Resume / Leave Match /
  Quit. Match keeps running (multiplayer). While open, the local player's
  input is blocked (`ui_blocked`). Replaced the old raw mouse-capture toggle.
- **Everything is InputMap actions** (app.gd `_setup_input_map`): `pause`
  (Esc), `toggle_paint_mode` (F), `brush_grow`/`brush_shrink` (wheel), plus
  the existing move/jump/crouch/primary_action/eyedrop — rebindable later.
- **HUD**: brush-size preview circle next to the swatch, "PAINT MODE" banner
  under the timer, crosshair hides in paint mode, hints rewritten.
- Verified: 38 headless checks pass, headless solo E2E full loop clean,
  windowed screenshot shows new HUD. Paint-mode feel NOT yet human-tested.

## Session 1 status: MVP COMPLETE & VERIFIED (2026-07-11)

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
- Paint-mode feel (F → cursor painting) after the session-2 overhaul.
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
- `scripts/hud.gd`, `scripts/main_menu.gd`, `scripts/lobby.gd`,
  `scripts/pause_menu.gd` (Esc overlay; match keeps running)
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
