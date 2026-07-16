# Paint-n-Seek — Design & Architecture

A multiplayer hide-and-seek "paint yourself to blend in" game, inspired by
MECCHA CHAMELEON (Steam, 2026). You stay in your chosen Human, Cat, or Dog body
— no prop morphing — and camouflage it with colors sampled from the world.

## Core loop

1. **Lobby** — players join a hosted game, preview/select a body, and the host
   picks seeker count and map, then starts.
2. **PAINT phase (90 s)** — Hiders spawn in the map with a pure-white body.
   They sample colors from the world (eyedropper) and paint their own body,
   pick a hiding spot, and settle into position. Seekers wait in a sealed pen
   with a "blindfold" overlay so they can't scout.
3. **SEEK phase (180 s)** — Seekers are released with shotguns (raycast shots,
   cooldown + limited ammo). Hiders may still move and keep painting.
   - Seeker shoots a hider → hider eliminated (becomes a spectator).
   - All hiders eliminated → seekers win. Timer expires → surviving hiders win.
4. **REVEAL phase (10 s)** — surviving hiders freeze in their final poses and
   receive visible markers while everyone sees where they hid.
5. **RESULTS (untimed)** — scoreboard and replay readiness remain open until
   the host deliberately starts another round or players leave. Ready-ups are
   advisory; the host never has to wait for every connected player.

## Scoring (the signature mechanic)

- **Hiders**: +1/s survival while alive during SEEK. **Bold bonus +3/s** while
  alive AND inside a seeker's line of sight (within seeker view cone, raycast
  unobstructed). Hiding in plain sight scores more than cowering behind a wall.
- **Seekers**: +100 per elimination, +50 team bonus each if all hiders found.
- Eliminated hiders keep their accumulated points; survivors get +75 bonus.

## Session skill balancing

- Every stable lobby identity has independent **hiding** and **seeking**
  ratings. A round compares each hider with the current seeker team's average:
  survival is a hider win and elimination is a seeker win. New estimates move
  quickly; the update rate settles after repeated games.
- On replay, only hiders are resized. Lower-rated hiders become smaller,
  higher-rated hiders become larger, strong seekers face smaller hiders, and
  struggling seekers face larger hiders. The two effects combine and clamp to
  25%–125% of the selected avatar's authored size.
- The multiplier is applied while constructing body meshes, movement and shot
  collisions, ragdoll joints, paint brushes, cameras, nameplates, and gameplay
  anchors. Seekers remain at their normal authored size.
- Ratings are server-authoritative and live for the current lobby session,
  including reconnects with the same lobby identity; leaving the lobby resets
  them. Both ratings appear on the results screen and hiders see their current
  size percentage in the HUD.

## The paint mechanic (MVP implementation)

- Each catalog-authored body is assembled from **subdivided BoxMeshes** with a
  species-specific articulated part layout and constrained physics joint graph.
  Every segment supports
  **vertex-color painting**:
  - Materials use `vertex_color_use_as_albedo = true` (works in Compatibility).
  - Painting = raycast from the third-person camera crosshair onto your own
    body part, then pass a cylindrical brush volume along the camera ray through
    the complete character. Every vertex within the projected brush radius is
    colored, including occluded and back-facing surfaces. No UV math or texture
    readback is needed.
  - Strokes replicate as compact RPCs containing body-local endpoints, color,
    radius, and the through-body ray axis. Each peer transforms the axis into
    every articulated part's local space, including rotated ragdoll pieces.
    A round uses a frozen active-player roster. Late joiners remain connected
    on a waiting screen and are promoted only when the host starts the next
    round, so they never appear halfway through a live simulation.
- **Eyedropper**: read the rendered frame's center pixel
  (`viewport.get_texture().get_image().get_pixel(...)`) — samples anything on
  screen regardless of material. On-demand only (click), so the readback cost
  is fine.
- Future upgrade path (documented, not built): per-part paint *textures* with
  analytic box UVs for smooth strokes; palette mixing UI.

## Multiplayer model

- Godot high-level multiplayer, **ENet**, listen server (host = server+player).
  Join by IP:port (LAN / port-forward for now; lobby service is future work).
- `Net.gd` autoload: host/join, `players: {peer_id: {name, role, ...}}`
  registry replicated via reliable RPCs, connection/disconnection signals.
- The server snapshots `round_player_ids` when loading a round. Scene barriers,
  role assignment, spawning, and disconnect effects use that snapshot; newly
  registered peers are marked waiting until the following snapshot.
- `game.tscn` uses a **MultiplayerSpawner** (players spawn as `str(peer_id)`,
  input authority = that peer) and **MultiplayerSynchronizer** for transforms.
- **Server-authoritative rules**: phase machine, timers, role assignment,
  eliminations, and scoring all run in `MatchState` on the server only;
  clients receive phase changes / scores / eliminations via RPCs.
- Shot validation on the server: seeker sends shot ray (origin, dir); server
  raycasts and applies elimination.

## Testable game logic (non-negotiable)

`scripts/match_state.gd` is a plain `RefCounted` — **no scene tree, no
networking, no rendering**. It holds phases, timers, roles, alive/eliminated,
scores, and win conditions, advanced by `tick(delta)` and fed by plain calls
(`add_player`, `start_match`, `report_shot_hit`, `set_in_sight`, ...). A whole
match plays out in a headless unit test:
`godot --headless -s tests/run_tests.gd` (custom micro-runner, no addon).

## Scene / file layout

```
autoload/Game.gd        # scene transitions + app state (current match settings)
autoload/Net.gd         # ENet host/join + player registry + signals
scripts/match_state.gd  # PURE match rules (testable headless)
scripts/session_state.gd # replay totals, role rotation, and role skill ratings
scripts/player.gd       # CharacterBody3D: move, camera, paint, shoot
scripts/avatar_catalog.gd # data-authored human/cat/dog rigs + gameplay anchors
scripts/paintable_body.gd # shared segmented avatar, vertex paint + ragdoll API
scripts/game.gd         # wires Net + MatchState + spawner + HUD (thin shell)
scenes/main_menu.tscn   # name, host, join
scenes/lobby.tscn       # player list, seeker count, start
scenes/game.tscn        # Map + Players + HUD + ResultsOverlay
scenes/player.tscn
maps/map_basic.tscn     # colored-zone blockout arena
maps/map_empty.tscn     # editor-authored blank map scaffold
tests/run_tests.gd      # headless assert-based test suite for MatchState
assets/                 # copied Kenney CC0 (UI, audio, font)
docs/DESIGN.md, PROGRESS.md
```

## Controls

- WASD move, Space jump or continuously climb while touching a wall, hold U
  for 1.25 seconds to return to the assigned spawn, mouse orbit camera
  (captured), Esc release mouse.
- Hider: **LMB paint**, **RMB (hold) eyedrop** world color at crosshair,
  scroll = brush size, **R / Ragdoll button** = lie down or stand back up,
  **H** = confirm/undo hidden readiness during PAINT.
  Ragdoll uses WASD/Space/C free-flight; entering paint mode temporarily
  returns the camera to an orbit around the body's live center of mass.
  Entering ragdoll preserves the player's linear and angular point velocities
  across all articulated body segments.
  Palette bar shows current color.
- Seeker: **LMB shoot** (cooldown 0.8 s, ammo = 3× hider count).
- Host: **Enter** starts SEEK early once every active hider is ready.

## Config defaults (Game.gd)

| Setting | Default |
| --- | --- |
| Port | 24565 |
| Paint phase | 90 s |
| Seek phase | 180 s |
| After-round reveal | 10 s (host-configurable in lobby) |
| Results | Untimed |
| Seekers | 1 (host-configurable in lobby) |
| Map | Basic Arena (host-configurable in lobby) |
| Shot cooldown / ammo | 0.8 s / 3× hiders |

## Deliberate MVP cuts (future work)

- Two selectable maps: the generated `map_basic` blockout and an intentionally
  blank, editor-authored `map_empty` scaffold for manual level building.
- No host migration or dedicated server build. Late joiners wait for the next
  round rather than entering the current simulation.
- Vertex-paint resolution is chunky (by design, blocky aesthetic) — texture
  painting is the quality upgrade later.
- Ragdoll provides a natural lying pose; authored poses/emotes are still future work.
- Lobby is IP-based; no matchmaking/party codes yet.
