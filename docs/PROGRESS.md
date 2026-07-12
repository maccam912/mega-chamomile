# Mega Chamomile — Progress Log

Read DESIGN.md first for the what/why. This file tracks exactly where the
build is so a fresh session can pick up instantly.

## Status: extensible animal avatars shipped (session 9, 2026-07-12)

### Session 9: animal avatar roster (`AVATAR-02`)

- Added a data-driven avatar contract and a launch roster of Human, Cat, and
  Dog. Each profile owns its articulated part/joint layout plus collision,
  camera, nameplate, targeting, eye, gun, and preview anchors.
- The lobby now provides a rotating body preview and per-player selector. The
  server validates and replicates the choice through the player registry, and
  match setup/replays preserve it.
- Painting, shooting hit shapes, movement, crouching, complete-body strokes,
  ragdoll pose replication, and stand-up restoration remain shared code rather
  than species branches.
- Line-of-sight targets and cameras adapt to body height; ragdolled targeting
  follows the moving center of mass.
- Species scale is authored once and applied uniformly to the rig, joints,
  movement collision, camera offsets, gameplay anchors, gun, ragdoll impulse,
  stroke spacing, and brush radius. The cat is about 1.0 m tall, the dog about
  1.25 m, and the human about 1.77 m.
- Verified: 174 headless checks pass. Human ragdoll regression passes; cat and
  dog physics smoke checks confirm stable settling, ragdoll painting, and pose
  restoration; full cat and dog solo rounds completed PAINT → SEEK → RESULTS.

## Status: seek-phase hider slowdown shipped (session 8, 2026-07-12)

### Session 8: hider seek movement (`MOVE-02`)
- **Living hiders move at 20% horizontal speed during SEEK.** Both standing and
  crouched movement use the same fixed multiplier; PAINT movement and seeker
  movement remain unchanged.
- Entering SEEK clamps leftover paint-phase horizontal momentum so hiders
  cannot carry a full-speed sprint into the hunt. Early SEEK uses the same
  phase state and therefore applies the slowdown immediately.
- Spectator flight, jump velocity, and wall-climb velocity remain unchanged.
  Ragdoll mode does not move the hider body, so standing again cannot bypass
  the state-derived speed.
- Verified: 147 headless checks pass, including role/phase/crouch/replay and
  early-SEEK coverage plus transition momentum clamping; Godot editor-load
  check is clean.

## Previous status: indefinite results screen shipped (session 7, 2026-07-12)

### Session 7: untimed results (`ROUND-03`)
- **RESULTS stays open indefinitely** instead of advancing to a `DONE` phase
  and automatically returning everyone to the lobby. The host deliberately
  starts a replay after all connected players ready up; anyone can still leave
  through the Escape menu.
- The results countdown setting and automatic lobby-return RPC were removed.
  The HUD clears and stops its timer in RESULTS, and its guidance now explains
  that the screen remains open.
- Final score snapshots do not change while the phase is open, and readiness
  continues to react to player toggles and disconnects through the existing
  session state.
- Verified: 137 headless checks pass, including ticking RESULTS two minutes
  beyond the old timeout and checking stable scores; Godot editor-load check is
  clean.

## Previous status: hidden readiness + early seeking shipped (session 6, 2026-07-12)

### Session 6: paint-phase readiness (`HIDE-01`)
- **Hiders can report ready** from the PAINT HUD or with `H`, and can undo that
  confirmation until SEEK begins. Everyone sees `ready / total`; personalized
  RPCs reveal only the aggregate count and the receiving player's own state.
- **Host-controlled early seeking** unlocks only when every active hider is
  ready. The host clicks Start Seeking Now or presses `Enter`; readiness never
  advances the phase automatically, and the ordinary countdown remains intact.
- `MatchState` validates phase, role, readiness, undo, and the explicit early
  transition. Disconnects immediately reduce the required hider count and can
  unlock the host action when all remaining hiders are ready.
- Verified: 134 headless checks pass; Godot editor-load check is clean; a
  two-instance ENet match completed without readiness RPC errors; deterministic
  1280x720 render review confirmed the PAINT controls and status do not overlap.

## Previous status: quick replay + session scoring shipped (session 5, 2026-07-12)

### Session 5: consecutive-round foundation (`ROUND-01`, `SCORE-02`)
- **Quick replay from results** (`ROUND-01`): every player gets a reversible
  Ready for Next Round confirmation. The host's Start Next Round button unlocks
  only when every connected player has opted in, then reloads the game scene
  without disconnecting the lobby. `ROUND-03` subsequently removed the RESULTS
  timer entirely.
- **Cumulative session scoring** (`SCORE-02`): new pure `SessionState` tracks
  integer totals across round scene reloads. Results show both round and session
  points and sort by the cumulative total. Leaving/new host/new join resets the
  session; a disconnected peer's identity and score are removed, so a new peer
  cannot inherit them accidentally.
- The existing fresh-scene setup resets round-only paint, bodies, roles, ammo,
  eliminations, spawns, and timers. Role assignment runs again through the
  current random allocator, leaving the session model ready for `ROLE-01`.
- Verified: 121 headless checks pass; two-instance ENet E2E delivered identical
  round/session score fields to host and guest and returned cleanly to lobby;
  deterministic 1280x720 render review confirmed the results/readiness layout.

## Previous status: first backlog slices shipped (session 4, 2026-07-12)

### Session 4: lobby match settings + results score breakdown (docs/TODO.md slices)
- **Fixed persistent backward-facing movement** (`BUG-01`): the travel-to-yaw
  calculation added `PI`, so the character model faced exactly opposite its
  camera-relative velocity. The extra half-turn is gone; a regression test
  verifies forward, backward, left, and right travel headings.
- **Added wall climbing and manual unstuck** (`MOVE-01`): holding Space while
  airborne and touching a wall climbs continuously at 2.5 m/s, with no duration
  limit. Holding U for 1.25 seconds returns an active player to their assigned
  spawn; the action has a 10-second cooldown and is disabled while frozen.
- **Paint now passes through the complete character** (`PAINT-01`): strokes
  replicate their camera-ray axis and use a cylindrical vertex-distance test,
  painting matching front, occluded, and back surfaces with the same footprint
  and falloff. The ray is transformed per articulated ragdoll part.
- **Lobby settings** (`SETTINGS-01` slices): host can now set hiding time
  (15–300s), seeking time (30–600s), and ammo per hider (1–10) next to the
  existing seeker count and map pickers. One `_add_setting_spin()` helper in
  lobby.gd binds a SpinBox to an App.settings key; initial value is set with
  `set_value_no_signal` so out-of-range CLI overrides (`--fast-phases` 4s/6s)
  display clamped but are never written back.
- **Results breakdown** (`SCORE-01` slice): MatchState players now accumulate
  `survival`, `bold`, `kills`, `bonus` separately; the total is *derived*
  (`score_of()`) so breakdown and total can't drift. `scores_snapshot()` rows
  carry the components; hud.gd renders a small gray line under each player
  ("survival +10   bold +3   survived +75" / "found 2  +200   sweep bonus +50").
- **Bug found & fixed**: the RESULTS scoreboard was invisible in real matches —
  the server broadcasts scores *then* the phase change, and `hud.on_phase()`
  unconditionally hid `_results`. Now it only hides it for non-RESULTS phases;
  regression-tested.
- Verified: 110 headless checks pass (new: through-body back-face painting and
  footprint containment, cardinal travel headings, wall-contact
  climbing, open-air rejection, ordinary jump preservation, unstuck hold and
  cooldown, score breakdowns, results-overlay survival); 2-instance ENet E2E
  clean with breakdown fields replicated; windowed screenshots confirm the new
  lobby rows and the results overlay with breakdown.

## Previous status: paint feel + camera orbit fixes after second playtest (session 3, 2026-07-11)

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

### File map
- `autoload/app.gd` — settings, scene transitions, InputMap, CLI flags
  (`--host --join --name --avatar ID --autostart N --fast-phases --quit-after S
  --screenshot path --screenshot-at S`)
- `autoload/net.gd` — ENet host/join, player registry, ALL orchestration RPCs
- `scripts/match_state.gd` — PURE rules (phases/roles/scores/ammo/wins)
- `scripts/game_scene.gd` — server: MatchState+LoS+shots; all: spawn/FX/HUD
- `scripts/player.gd` — move/camera/paint/eyedrop/shoot/sync/spectator
- `scripts/avatar_catalog.gd` — human/cat/dog rig and gameplay-anchor profiles
- `scripts/paintable_body.gd` — shared segmented avatar, vertex splats + ragdoll
- `scripts/hud.gd`, `scripts/main_menu.gd`, `scripts/lobby.gd`,
  `scripts/pause_menu.gd` (Esc overlay; match keeps running)
- `maps/map_basic.gd` — data-driven ZONES array; maps must expose
  `hider_spawns()/seeker_spawns()/set_seek_open(bool)`
- `maps/map_empty.tscn` — blank editor-authored floor/lighting scaffold;
  its script only implements the map contract and creates no objects
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
5. Build out `map_empty.tscn` manually in the editor; it is already selectable
   from the host's lobby settings.
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
