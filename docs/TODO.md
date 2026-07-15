# Paint-n-Seek — Feature Backlog

This backlog turns the July 12, 2026 playtest notes into concrete feature
requests. It is planning documentation; items are unimplemented unless marked
**SHIPPED**.

**Shipped so far (2026-07-12):**

- `BRAND-01` **SHIPPED**: the game, menu title, desktop exports, release
  artifacts, launcher UI, and package lookup now use Paint-n-Seek. The current
  GitHub repository URL remains unchanged so installed launchers keep updating.
- `ROLE-01` **SHIPPED**: lobby role preferences feed a persistent,
  least-recently-served assignment history with fair fallback when preferences
  are one-sided.
- `ROUND-02` **SHIPPED**: seeking ends after the last available shot fully
  resolves, while preserving last-shot sweeps and rechecking ammo after seeker
  disconnects.
- `NET-01` **SHIPPED**: available LAN hosts advertise over UDP and appear in a
  live, deduplicated join list with compatibility and player-count details;
  manual IP remains available.
- `REVEAL-01` **SHIPPED**: survivor poses and paint remain intact in RESULTS,
  frozen ragdolls cannot be pushed, high-contrast markers reveal survivors,
  and Tab switches between the scoreboard and read-only scene inspection.
- `SETTINGS-01` expanded slice: fixed/per-hider ammo, cooldown, all scoring
  values, validation, defaults, lobby replication, and guest review are now
  implemented. Character scale remains deferred pending physics playtesting.
- `SCORE-01` **SHIPPED**: survival, visible-risk, find, and end-bonus scoring
  are server-authoritative, shown separately in results, and host-tuneable.
- `UI-01` implementation complete, Windows hardware QA pending: every screen
  now shares one theme and 1280×720 logical canvas policy, the lobby scrolls
  safely at short heights, and 1280×720 plus 1920×1080 render reviews pass.
- `UI-02` **SHIPPED**: the main menu has a paint-led responsive layout, strong
  host/join hierarchy, animated code-drawn backdrop, styled LAN games, complete
  credits, and a persisted Reduce Motion control.
- `HIDE-01` **SHIPPED**: hiders can confirm or undo readiness during PAINT;
  everyone sees an aggregate count, and the host can release seekers early
  once every active hider is ready.
- `ROUND-01` **SHIPPED**: every player can ready up from results; once all
  connected players opt in, the host can immediately reload the game scene for
  another round without breaking up the lobby.
- `ROUND-03` **SHIPPED**: results remain open without a countdown until the host
  deliberately starts the next round or a player leaves.
- `MOVE-02` **SHIPPED**: living hiders move at 20% horizontal speed during SEEK;
  seekers, spectators, jump height, and wall-climb speed remain unchanged.
- `SCORE-02` **SHIPPED**: results show current-round and cumulative session
  totals. Totals survive replay and ordinary returns to the same lobby, and
  reset when the player leaves or a new host/join session begins.
- `SETTINGS-01` slice: hiding time, seeking time, and ammo per hider are
  host-editable in the lobby (`scripts/lobby.gd` `_add_setting_spin`).
- `SCORE-01` slice: results show a per-player breakdown (survival, bold,
  finds, bonus) instead of one opaque number; `MatchState` now tracks the
  components and derives the total from them.
- Fix found along the way: the RESULTS scoreboard was being hidden by the
  phase broadcast that follows the score broadcast (`hud.gd` `on_phase`).
- `BUG-01` **SHIPPED**: removed the extra half-turn from movement yaw, so the
  character model now faces its travel direction instead of walking backward.
- `MOVE-01` **SHIPPED**: holding Space climbs continuously while airborne and
  touching a wall; holding U returns an active player to their assigned spawn.
- `PAINT-01` **SHIPPED**: strokes carry the camera-ray axis and paint every
  vertex inside that through-body footprint, including hidden back surfaces.

## Effort and grouping at a glance

Effort is relative to this project, including multiplayer synchronization,
headless rule tests, UI, and playtesting—not just the number of code changes.
`XS` is a quick, low-risk change; `S` is small; `M` is a contained feature;
`L` crosses several systems; `XL` is a new game loop. Estimates can change
after investigation, especially for bugs.

| ID | Effort | Confidence | Best grouping | Why |
| --- | --- | --- | --- | --- |
| `BRAND-01` | **SHIPPED** | High | Standalone | Product, package, export, release, and launcher names now use Paint-n-Seek. |
| `BUG-01` | **SHIPPED** | High | Movement regression test | The movement yaw included an extra half-turn, making the model face opposite its travel direction. |
| `UI-01` | **IMPLEMENTED — Windows QA pending** | High | `UI-02`, `SETTINGS-01` | Shared theme, logical scaling, safe-area layouts, and scroll containment are complete; capture the matching Windows hardware screenshots at the next playtest. |
| `REVEAL-01` | **SHIPPED** | Medium | `ROUND-01`, results presentation | Results preserve poses, reveal survivors, and support scene inspection. |
| `SCORE-01` | **SHIPPED** | High | `SCORE-02`, `SETTINGS-01` | Results break down every component and the host can tune all scoring values. |
| `HIDE-01` | **SHIPPED** | High | `ROUND-01`, `CAMERA-01` | Server-authoritative readiness gates an explicit host early-start action. |
| `ROUND-02` | **SHIPPED** | High | `MOVE-02`, round-end rules | Ammo exhaustion is checked after final-shot resolution and roster changes. |
| `MOVE-02` | **SHIPPED** | High | `ROUND-02`, `SETTINGS-01` | Living hiders now use a fixed seek-phase-only 0.2 horizontal speed multiplier. |
| `PAINT-01` | **SHIPPED** | High | Paint regression tests | Camera-ray-aligned cylindrical strokes paint front and hidden back surfaces while retaining the brush footprint. |
| `NET-01` | **SHIPPED** | High | Lobby and main-menu UI | UDP discovery advertises existing ENet lobbies and populates a live join list. |
| `CAMERA-01` | M | Medium | `HIDE-01`, existing spectator camera | Eliminated-player spectating may be reusable, but living-hider control locking needs care. |
| `UI-02` | **SHIPPED** | High | `UI-01`, `BRAND-01` | Paint-led menu layout, styling, restrained motion, reduced-motion persistence, and interaction feedback are implemented. |
| `SCORE-02` | **SHIPPED** | High | `ROUND-01`, `ROLE-01` | Session totals use live peer identity and survive round scene reloads. |
| `MOVE-01` | **SHIPPED** | High | Movement regression tests | Continuous climbing requires wall contact; hold-to-confirm unstuck has a cooldown and is disabled while frozen. |
| `MOVE-03` | S–M | High | `MOVE-01`, Hallwyl map collision | Add map-specific perimeter recovery plus authoritative position validation so near-map escapes return players safely instead of leaving them outside. |
| `ROUND-01` | **SHIPPED** | High | `ROLE-01`, `SCORE-02` | Results readiness gates a host-controlled same-session scene reload. |
| `ROUND-03` | **SHIPPED** | High | `ROUND-01`, results presentation | RESULTS is now an untimed phase with stable scores and persistent ready-up controls. |
| `ROLE-01` | **SHIPPED** | High | `ROUND-01`, `SCORE-02` | Preferences, persistent history, fairness, replication, and rule tests are implemented. |
| `SETTINGS-01` | L | High | All rule features | The UI is straightforward, but several settings affect different runtime systems and validation rules. |
| `AVATAR-01` | S–M prototype / L body-scale | Medium | `MOVE-01`, `BUG-01` | Making maps uniformly larger may achieve the desired relative size more safely than scaling the articulated bodies. |
| `NET-02` | M feasibility spike / XL migration | Low | `NET-01`, networking architecture | Iroh may enable identity-based connections, NAT traversal, and relay fallback, but replacing Godot ENet requires an integration prototype first. |
| `MODE-01` | XL | High | Build after reusable round/settings state | Requires a second authoritative game loop, ghost state, tag handoffs, UI, scoring, and edge-case tests. |
| `AVATAR-02` | **SHIPPED** | Medium | Avatar contract + physics/play tests | Human, Cat, and Dog share one catalog-driven painting/ragdoll pipeline with replicated lobby selection. |

### Easiest useful slices

These are good candidates when a small, independent improvement is wanted:

1. **SHIPPED** — `BRAND-01`: product, export, release, and launcher naming now
   consistently uses Paint-n-Seek.
2. **SHIPPED** — `BUG-01`: characters now face their travel direction instead
   of walking backward.
3. **IMPLEMENTED** — `UI-01`: consistent shared theme/scaling and scroll-safe
   screen layouts; matching Windows hardware screenshots remain QA-only.
4. **SHIPPED** — `REVEAL-01`: final poses are preserved and survivors can be
   inspected from the results screen.
5. **SHIPPED** — hiding time and seeking time are exposed in the lobby
   settings (`SETTINGS-01` slice).
6. **SHIPPED** — both per-hider and fixed-per-seeker ammo modes are exposed in
   the lobby settings.
7. **SHIPPED** — results display the `SCORE-01` scoring breakdown (survival,
   bold, finds, end bonus).
8. Prototype a uniformly enlarged copy of one map for `AVATAR-01` — this may
   deliver the smaller-character feel without changing player physics.
9. **SHIPPED** — `ROUND-02`: seeking ends once all remaining seekers have spent
   their ammunition, after resolving the final shot.
10. **SHIPPED** — `MOVE-02`: living hiders move at one-fifth horizontal speed
    once seeking starts.
11. `MOVE-03` — add automatic Hallwyl perimeter recovery for players who slip
    just outside the museum without falling into the existing recovery plane.
12. **SHIPPED** — `ROUND-03`: the final results screen stays open until players
    deliberately replay or leave.

`AVATAR-01` may look like a simple scale change but should not be treated as a
quick body-scaling win because the current character is an articulated physics
body. Testing a larger map first is the lower-risk version of the idea.

## P0 — Fix movement and orientation blockers

### BUG-01: Character faces backwards while moving — **SHIPPED**

**Problem:** Pressing forward moved the player camera-forward, but the character
model permanently faced the opposite direction and appeared to walk backward.

**Resolution:** The travel-to-yaw calculation added `PI`, rotating the character
root 180 degrees away from its velocity. Removing that half-turn aligns the
model with travel while the existing camera counter-rotation keeps the view
stable.

**Acceptance criteria:**

- Forward, backward, left, and right travel all turn the character toward the
  direction of movement.
- Camera-relative controls and the camera's world yaw remain unchanged.
- Remote players receive the corrected root yaw through existing transform
  synchronization.
- A regression test covers all four cardinal travel directions.

### MOVE-01: Recover from walls and climb upward — **SHIPPED**

**Problem:** A player can become stuck against or inside level collision.

**Resolution:** While airborne and touching a wall, holding Space supplies a
steady upward climbing speed. Climbing has no duration limit, but stops as soon
as Space is released or wall contact is lost. As a fallback, holding U for 1.25
seconds returns an active player to their assigned spawn; a 10-second cooldown
prevents rapid reuse, and frozen seekers cannot use it to escape their pen.

**Acceptance criteria:**

- Holding Space while airborne and in wall contact moves the player upward at
  a limited, tunable speed for as long as contact is maintained.
- Releasing Space immediately returns the player to normal gravity.
- The mechanic cannot be used to fly in open space because it requires wall
  contact; maps should treat wall climbing as normal traversal.
- Server/peer movement remains synchronized.
- Holding U returns an active player to their assigned spawn after a short
  confirmation, with a cooldown to limit accidental or repeated use.

**Chosen design:** Continuous wall-assisted climbing with no duration limit.
Wall contact is the eligibility condition; open-air hovering is not allowed.

### MOVE-03: Recover players who escape the museum perimeter

**Problem:** Players can noclip or climb through gaps in the Hallwyl Museum's
collision and remain close to the building but outside the playable map. The
existing fall-recovery plane catches players only after they drop far below the
level, while manual unstuck requires the escaped player to notice the problem
and hold the recovery key.

**Requested behavior:** Add layered, map-specific failsafes that automatically
return an active player to their assigned safe spawn when they leave the
Hallwyl Museum's playable bounds, including near-ground areas immediately
outside its walls. Keep the existing under-map recovery and manual unstuck as
fallbacks, and repair confirmed collision holes where practical.

**Acceptance criteria:**

- Define the Hallwyl Museum's valid playable region explicitly; do not use a
  loose world-sized box that treats the exterior beside the building as valid.
- Perimeter and under-map recovery cover every side and corner of the museum,
  including places reachable by wall climbing, ragdoll motion, or squeezing
  through collision seams.
- Crossing a recovery boundary returns the player to their assigned safe spawn,
  clears unsafe velocity/interpolation targets, and avoids repeated teleport
  loops at the destination.
- Legitimate interior rooms, stairs, upper floors, doorways, and any intended
  courtyards or roof areas do not trigger recovery.
- The host validates synchronized player positions against the active map's
  bounds so a client cannot remain outside merely by missing or bypassing a
  local `Area3D` trigger.
- Recovery preserves role, paint, score, ammo, phase, and elimination state;
  define whether an active ragdoll stands up on recovery and apply that behavior
  consistently.
- The safety check works during PAINT and SEEK without releasing a frozen seeker
  early or granting an escaped player an advantageous destination.
- Add map regression tests for representative points just beyond each perimeter
  edge, all corners, below the floor, known collision gaps, and valid points
  near the boundary.
- Playtest the repaired collision and recovery volumes with normal movement,
  continuous wall climbing, crouching, jumping, and ragdoll motion.

## P1 — Make consecutive rounds easy and fair

### ROUND-01: Quick replay from results — **SHIPPED**

**Requested behavior:** Add a prominent **Play Again** button to the results
screen so the same lobby can immediately start another round without making
everyone reconnect.

**Resolution:** Results now give every connected player a reversible
**Ready for Next Round** confirmation. The host's **Start Next Round** action
unlocks when everyone is ready and reloads the game scene directly. The new
scene reconstructs all round-only bodies, paint, roles, spawns, timers, ammo,
and eliminations while the `Net` autoload preserves lobby-session state.

**Acceptance criteria:**

- The host can start a replay from the results screen.
- Players remain in the same session and keep their cumulative scores.
- The next round resets round-only state: alive/eliminated status, ammo,
  paint/body state, spawns, timers, and ready/hidden state.
- Roles are assigned again using `ROLE-01`; the previous assignment is not
  blindly reused.
- Players who do not opt in yet see a clear waiting/confirmation state.

### ROUND-03: Keep the final results screen open indefinitely — **SHIPPED**

**Problem:** The final RESULTS screen currently lasts only about ten seconds.
That is not enough time for everyone to review the scoreboard, discuss the
round, and mark themselves ready for the next one.

**Requested behavior:** Remove the automatic RESULTS timeout. The end screen
and its ready-up controls should remain available without a time limit until
the players deliberately start the next round, return to the lobby, or leave
the session.

**Resolution:** RESULTS is now an untimed authoritative phase. Its HUD timer is
stopped and hidden, final scores remain unchanged, and replay readiness stays
active until the host deliberately starts the next round. Players can leave at
any time through the existing Escape menu.

**Acceptance criteria:**

- Entering RESULTS no longer starts a countdown toward `DONE`, lobby return, or
  any other automatic scene transition.
- The HUD does not show a misleading results countdown or urgency warning.
- Every connected player can toggle **Ready for Next Round** at any time while
  the results screen remains open.
- Becoming ready does not automatically start the next round; the host's
  existing **Start Next Round** action remains the deliberate transition and
  unlocks under the readiness rules from `ROUND-01`.
- A player who never readies up can keep the results screen open indefinitely;
  explicit leave/return actions remain available so nobody is trapped there.
- Joins, disconnects, and readiness changes update the required ready count
  without restoring a timer or silently advancing the phase.
- Score snapshots, cumulative session totals, surviving poses, and reveal state
  remain stable no matter how long RESULTS stays open.
- Headless tests tick RESULTS well beyond the old duration and confirm that it
  remains active until an explicit replay or exit action occurs.

### ROLE-01: Preference-aware, fair role assignment — **SHIPPED**

**Requested behavior:** Let each player choose **Prefer Seeker**, **Prefer
Hider**, or **No Preference**. Across replays, role assignment should honor
preferences when possible while rotating seeker duty fairly.

**Assignment rules:**

1. Track each player's recent role history across rounds in the current lobby.
2. If there is at least one seeker volunteer and at least one hider volunteer,
   fill roles from the matching preference pools first.
3. Within a pool, prioritize the player who has gone the most rounds without
   that role; randomly break exact ties.
4. Fill any remaining slots using the same least-recently-served/round-robin
   rule across all eligible players.
5. If nobody prefers seeker **or** nobody prefers hider, ignore all preferences
   for that round and use one fair round-robin across the whole lobby.
6. A reconnect or preference change must not erase already-recorded role
   history for the current lobby.

**Acceptance criteria:**

- No player repeatedly receives seeker while another equally eligible player
  has waited longer.
- The algorithm works when the number of requested seekers changes.
- The host and all clients see preferences and the final assignment.
- Automated tests cover volunteers, conflicting preferences, no volunteers,
  one-sided volunteers, ties, player departures, and repeated rounds.

## P1 — Expand host match settings

### SETTINGS-01: Full match customization

**Requested behavior:** Give the host controls for all major round parameters.

**Initial settings:**

- Hiding/painting duration
- Seeking duration
- Number of seekers
- Ammo per seeker (support a fixed amount; optionally retain the current
  per-hider multiplier as a separate mode)
- Shot cooldown
- Character scale
- Scoring values: survival rate, line-of-sight rate, found/elimination points,
  survivor bonus, and seeker sweep bonus
- Map

**Acceptance criteria:**

- Each setting has a label, safe minimum/maximum, sensible step size, and a
  restore-default option.
- Only the host can change settings; all players can review them before play.
- Settings are locked once a round starts and apply consistently to the server
  and every client.
- Invalid combinations are prevented, including seekers greater than or equal
  to the player count in a normal multiplayer round.
- Replay preserves the lobby's chosen settings unless the host changes them.

### HIDE-01: Hiders can report ready and finish hiding early — **SHIPPED**

**Requested behavior:** During the hiding/painting phase, each hider can mark
themselves **Hidden**. When every active hider is marked hidden, the host can
skip the remaining countdown and begin seeking.

**Resolution:** During PAINT, an active hider can use the HUD control or press
`H` to confirm and undo readiness. Every peer receives only the aggregate
`ready / total` count plus its own state. When all current hiders are ready, the
host's **Start Seeking Now** control unlocks (`Enter` is the captured-mouse
shortcut); readiness alone never changes phase. The server revalidates role,
phase, and the complete active-hider set for every request and rebroadcasts the
count after disconnects.

**Acceptance criteria:**

- The Hidden control is available only to active hiders during the hiding phase.
- Hiders can undo their Hidden status until seeking begins.
- Everyone sees `hidden / total hiders` readiness progress, but seekers receive
  no positional information.
- Disconnects and role changes update the required count correctly.
- When all hiders are ready, the host sees a clear **Start Seeking Now** action;
  seeking does not begin silently.
- The normal countdown still starts seeking if players never mark themselves
  hidden.

## P1 — Tighten seek-phase pacing

### ROUND-02: End the round when all seekers are out of ammo — **SHIPPED**

**Problem:** Once every seeker has completely exhausted their ammunition, they
cannot eliminate another hider. Letting the seek timer continue only prolongs a
round whose outcome can no longer change.

**Requested behavior:** During SEEK, finish the round early with a hider win as
soon as all active seekers have zero ammunition and at least one hider remains
alive. Resolve the shot that consumed the final round before evaluating ammo
exhaustion so a last-shot hit can still eliminate its target or complete a
seeker sweep.

**Acceptance criteria:**

- A seeker reaching zero ammo does not end the round while another active
  seeker still has at least one shot.
- After the final available shot is fully resolved, the server ends SEEK
  immediately if every active seeker is at zero ammo and any hider survives.
- If that final shot eliminates the last living hider, seekers win normally;
  the ammo-exhaustion rule must not overwrite the sweep result.
- The early finish uses the same authoritative score snapshot, survivor bonus,
  results transition, and reveal flow as a normal seek timeout.
- Seeker disconnects and other roster changes re-evaluate the remaining active
  seekers without allowing clients to decide the outcome locally.
- Headless rule tests cover one seeker, multiple seekers, a final-shot miss, a
  final-shot elimination, and a final-shot seeker sweep.

### MOVE-02: Slow hiders to one-fifth speed during seeking — **SHIPPED**

**Problem:** After receiving the full hiding and painting head start, hiders can
still run at normal speed during SEEK and dodge seekers instead of relying on
their chosen camouflage and hiding position.

**Requested behavior:** When PAINT ends and SEEK begins, reduce each living
hider's intentional movement speed to 20% of its paint-phase value. Seekers keep
their normal speed. The initial version should use a fixed `0.2` multiplier;
it can become a validated host setting later through `SETTINGS-01` if playtests
show that tuning is useful.

**Resolution:** Player movement now derives horizontal speed from role, phase,
elimination state, and crouch state. Living hiders use a fixed `0.2` multiplier
during SEEK, including an early start, and paint-phase momentum is clamped when
the hunt begins. Seekers and eliminated spectators remain at full speed. Jump
and wall-climb speeds remain unchanged because they provide vertical traversal
rather than sustained horizontal evasion.

**Acceptance criteria:**

- Hiders retain normal movement throughout PAINT, including when the host uses
  `HIDE-01` to start seeking early.
- On entry to SEEK, living hiders' normal and crouched horizontal movement are
  exactly one-fifth of their corresponding paint-phase speeds.
- Seekers' movement speed is unchanged, and eliminated/spectator movement does
  not accidentally inherit the hider penalty.
- The multiplier cannot be bypassed by toggling crouch, ragdoll/stand state, or
  another existing movement mode; wall-climb and jump behavior receive an
  explicit playtest decision rather than silently restoring full-speed travel.
- The correct speed is restored on replay and whenever a player is initialized
  outside the SEEK hider state.
- Multiplayer movement remains server-consistent, and automated tests cover
  the PAINT-to-SEEK transition, early seek start, role differences, and replay
  reset.

## P1 — Paint through the complete character

### PAINT-01: Paint front and back vertices in one stroke — **SHIPPED**

**Problem:** Painting currently affects only the visible face of the character,
leaving vertices on the back side unchanged unless the player rotates to expose
them.

**Resolution:** Each replicated stroke now includes its camera-ray axis in
body-local space. Every articulated body part transforms that axis into its own
local space and colors vertices by perpendicular distance to it, producing a
cylindrical brush volume through the complete character. This preserves the
existing radius and falloff while reaching occluded and back-facing vertices.

**Acceptance criteria:**

- One stroke paints matching vertices on both the visible and hidden sides of
  the character.
- Back-facing or depth-occluded vertices do not require rotating the character
  toward the camera before they can be painted.
- The through-body behavior preserves the configured brush radius, falloff, and
  sampled color.
- A stroke affects only vertices inside its brush footprint and does not spill
  across unrelated parts solely because they are hidden from view.
- The resulting paint state remains synchronized for all players and survives
  the same phase transitions as existing paint.
- Add coverage for front-to-back strokes on the humanoid and include this
  behavior in the paintability contract for future avatar bodies.

## P1 — Make LAN games easy to join

### NET-01: Discover hosted games on the local network — **SHIPPED**

**Problem:** Joining a nearby game currently requires finding and typing the
host's LAN IP address every time.

**Requested behavior:** Automatically discover compatible games advertised on
the local network and show them in a selectable join list. Joining a discovered
game should reuse the existing ENet connection flow; manual IP entry remains
available as a fallback.

**Acceptance criteria:**

- A host advertises its lobby on the LAN while it is available to join.
- The join screen continuously discovers and lists compatible local lobbies
  without requiring an internet service.
- Each result shows enough information to distinguish games, including host or
  lobby name, player count, and compatibility/version status.
- Selecting a result fills in the connection details and joins through the
  existing flow without requiring the player to type an IP address.
- Multiple hosts can appear at once, duplicate advertisements are coalesced,
  and stale or closed lobbies disappear promptly.
- Discovery works on supported desktop platforms and fails gracefully when
  multicast/broadcast traffic is blocked by the network or local firewall.
- Manual IP entry remains available for diagnostics and networks where
  automatic discovery cannot work.

## P1 — Multi-round scoring

### SCORE-01: Reward risky visibility and time unfound — **SHIPPED**

**Requested behavior:** Score hiders from both (a) time spent inside any
seeker's unobstructed line of sight and (b) how long they remain unfound.
The build already awards survival points and an extra line-of-sight rate; this
request should make both components explicit in the results and tuneable via
`SETTINGS-01`.

**Acceptance criteria:**

- Accumulate survival time only while a hider is active and not found.
- Accumulate visible time while at least one living seeker has an unobstructed
  view of that hider; define and test whether multiple simultaneous seekers
  multiply the rate (default: do not multiply it).
- Freeze a hider's round score when found, apart from any explicit end bonus.
- Results show a breakdown for survival, visible-risk bonus, found/survived
  outcome, and total—not only a single opaque number.
- Server-authoritative scoring remains stable across different frame rates.

### SCORE-02: Carry a session scoreboard across rounds — **SHIPPED**

**Requested behavior:** Keep cumulative player scores while the lobby plays
successive rounds.

**Resolution:** A pure `SessionState` owned by `Net` records authoritative
round snapshots and adds `round_score` and `session_score` to each replicated
results row. Live peer IDs are the session identity: disconnecting forfeits
that identity and its total, while reconnecting starts at zero under a new peer
ID. Leaving or starting a new host/join session resets all totals.

**Acceptance criteria:**

- Results show both current-round points and session total.
- Quick replay preserves totals; leaving the lobby or starting a new session
  resets them.
- A temporary disconnect/reconnect policy is defined so duplicate identities
  cannot inherit or create scores accidentally.
- Role rotation and cumulative scores are separate; score does not influence
  who becomes seeker.

## P1 — Round-end reveal

### REVEAL-01: Preserve hiding poses and let seekers inspect survivors — **SHIPPED**

**Problem:** When the seeking timer expires, hiders should not stand up or lose
the pose that made their hiding spot work. Seekers should get a satisfying
chance to discover what they missed.

**Requested behavior:** When time expires with surviving hiders, preserve each
hider exactly as they were—including ragdoll pose, body transform, and paint—
then reveal them with a visible outline, pulse, or blink. During this results
inspection period, seekers can continue walking and looking around the map to
see where everyone was hiding.

**Resolution:** Round completion now enters a dedicated, server-authoritative
`REVEAL` phase before the untimed results screen. It defaults to 10 seconds,
is configurable by the host, freezes surviving hiders in their exact pose, and
adds high-contrast survivor markers while seekers inspect the completed scene.

**Round-end behavior:**

- Freeze surviving hiders in their final pose. Do not force them to stand up,
  rebuild their body, teleport, or reset their paint when entering results.
- Let seekers retain normal walking, camera, and look controls while the
  untimed results inspection remains open.
- Disable seeker shooting, tags, ammo use, scoring, eliminations, painting, and
  any other action that could change the completed result.
- Visually highlight every surviving hider after a brief reveal beat. Start with
  a high-contrast pulsing outline; use a blinking silhouette or marker if an
  outline is unreliable in the Compatibility renderer.
- Keep the scoreboard available without forcing it to cover the whole screen;
  seekers should be able to inspect the scene and deliberately open or close the
  detailed results.
- Continue to the normal lobby/replay flow only after an explicit player action
  under `ROUND-03`. Only then may round-only bodies and poses be reset.

**Acceptance criteria:**

- A ragdolled survivor remains in the same articulated pose and world position
  when SEEK changes to RESULTS, within normal network synchronization tolerance.
- A standing or moving survivor is frozen in their exact final state rather than
  automatically entering ragdoll or being repositioned.
- Every surviving hider is clearly identifiable against both bright and dark
  map surfaces; the effect does not depend on their paint color.
- Seekers can walk and look but cannot shoot, score, tag, collide in a way that
  moves frozen hiders, or alter the result.
- Hiders cannot move their body during inspection, but may orbit or use a
  read-only camera so they are not stuck behind a results overlay.
- The reveal begins only after the authoritative server ends scoring, ensuring
  the highlight itself never adds line-of-sight points.
- The feature works for multiple seekers, multiple survivors, disconnected
  players, and both ragdolled and upright hiders.
- If all hiders were already found, results can skip the survivor-reveal walk or
  show eliminated locations separately; do not create fake survivors.

**Design decisions:**

- Do not time-limit the overall inspection or ready-up state. A short reveal
  beat may have its own presentation delay, but it must not close RESULTS or
  pressure players to ready up.
- Prefer an effect visible to everyone so hiders can enjoy the reveal too, while
  keeping seeker movement privileges separate.
- Consider a short one- or two-second pause before highlighting survivors, so
  seekers can first process that time expired and then get the reveal.
- Decide whether seeker collision with the map remains fully normal; regardless,
  seekers must not be able to push or disturb frozen ragdolls.

## P2 — Character and spectator experience

### AVATAR-01: Make characters substantially smaller

**Requested behavior:** Reduce the humanoid size so hiding and camouflage fit
the desired feel, while keeping interaction and readability intact.

**Preferred first experiment — enlarge the maps:** Before resizing player
bodies, test uniformly scaling an entire map up so unchanged characters appear
smaller relative to rooms, furniture, and hiding spaces. This may be easier and
safer because it avoids retuning the articulated ragdoll, player collision,
camera, aiming, and painting code.

Map enlargement is not free: spawn transforms, seeker pens, recovery volumes,
interaction distances, movement speed, jump/climb reach, line-of-sight range,
lighting, and round timers may need proportional adjustment. Use uniform scale
only, verify imported collision at the new size, and test each map separately;
do not assume one root-node scale will behave correctly for procedural and
imported maps alike.

**Acceptance criteria:**

- Compare at least one enlarged-map prototype against one smaller-body
  prototype before choosing the production approach.
- Start the map experiment at 150% and 200% of current dimensions while leaving
  character bodies unchanged.
- Choose a target scale through playtesting; start by testing 50% and 65% of
  current body size only if map enlargement does not produce the desired feel.
- Scale the visual body, collision, camera height/distance, paint brush world
  radius, nameplate placement, aim target, movement clearances, and spawn
  offsets together if the body-scaling approach is chosen.
- If map enlargement is chosen, update and verify spawn positions, seeker
  containment, catch/recovery volumes, movement pacing, reach distances,
  line-of-sight limits, and phase durations for the new dimensions.
- Characters do not fall through floors, enter forbidden gaps, or become
  impractical to hit.
- Prefer a fixed, tested scale per map. Make scale host-configurable through
  `SETTINGS-01` only if multiple scale values prove safe and fun.

### CAMERA-01: Let a living hider watch the seeker — **SHIPPED**

**Requested behavior:** During the seek phase, a hider who is still in play can
switch from their own camera to a read-only follow camera on a seeker, then
switch back to their body. With multiple seekers, they can cycle among them.

**Resolution:** Living hiders can press `V` during SEEK, after leaving paint
mode, to follow and cycle through active seekers before returning to their own
camera. Following freezes local movement and painting (including an articulated
ragdoll pose), never touches the seeker's authority, and shows the current
seeker plus cycle position in the HUD.

**Acceptance criteria:**

- The feature is available only to living hiders during the seek phase; it does
  not depend on the pre-seek Hidden readiness button from `HIDE-01`.
- While following a seeker, the hider cannot move or paint. Their body stays in
  place until they return to their own camera.
- The camera never changes or obstructs the seeker's controls.
- Multiple seekers can be cycled with clear UI showing who is being followed.
- The follow view begins no earlier than the seek phase, so it cannot reveal
  the seeker pen or other pre-round information.
- Returning to the hider camera restores the correct body/camera state.

**Fair-play note:** This gives a living hider privileged seeker information.
Limit it to casual/private games or expose it as a host setting if playtests
show that voice chat makes it exploitable.

## P3 — Explore easier internet connections

### NET-02: Investigate Iroh for easier internet connections

**Concept:** Run a focused feasibility spike on using the
[Iroh networking stack](https://docs.iroh.computer/what-is-iroh) so players
could connect by a stable endpoint identity or invitation instead of exchanging
IP addresses. Evaluate its discovery, authenticated QUIC connections, NAT
traversal, and relay fallback without assuming it can directly replace Godot's
current `ENetMultiplayerPeer`.

**Investigation goals:**

- Prototype the smallest viable Godot integration, comparing GDExtension,
  `iroh-ffi`, and a sidecar process rather than committing to an architecture
  up front.
- Determine whether Iroh datagrams or streams can back Godot's high-level
  multiplayer/RPC model, or whether adopting it would require a separate game
  transport and replication layer.
- Demonstrate two peers discovering or exchanging endpoint information,
  connecting across different networks, and completing a minimal gameplay
  message round trip.
- Test direct connections, NAT traversal, network changes, and relay fallback;
  record latency, bandwidth, reconnection behavior, and failure messages.
- Define the player-facing connection flow, such as short invitation codes,
  shareable tickets, or a friends/lobby discovery service, without exposing raw
  endpoint details unnecessarily.
- Evaluate export size, supported platforms, Rust/native build maintenance,
  relay hosting and operating cost, service availability, abuse controls, and
  security implications.
- Keep `NET-01` independent: LAN discovery should still work without Iroh or an
  internet connection.
- Do not replace the current ENet implementation until a prototype proves that
  hosting, joining, replication, disconnect handling, and representative
  gameplay traffic work reliably in exported builds.

**Reference:** Iroh currently documents endpoint-ID-based discovery, direct
QUIC connections with NAT traversal, and encrypted relay fallback. These are
promising capabilities to evaluate, not evidence that it already integrates
with Godot or this game's authoritative multiplayer model.

## P3 — Long-term avatar variety

### AVATAR-02: Let players choose an animal body — **SHIPPED**

**Concept:** Let each player select an animal instead of always playing as a
humanoid. Animal bodies should still support the core fantasy: sampling colors,
painting the body, moving into a hiding spot, and settling into a convincing
pose.

**Resolution:** The lobby now offers a rotating preview and replicated choice
of Human, Cat, or Dog. All three are catalog-authored segmented rigs backed by
one paint/ragdoll implementation. Each profile supplies its parts, joint graph,
character collision, camera, nameplate, targeting, eye, weapon, and preview
anchors. Selection lives in the network player registry, so peers agree on the
body and quick replays preserve it. Contract tests cover every roster entry and
a physics smoke test releases, paints, and restores both animal ragdolls. See
`docs/AVATARS.md` for the extension checklist. Uniform authored scaling keeps
the cat smallest, the dog between cat and human, and every physics/gameplay
anchor proportional to the rendered body.

**Suggested rollout:**

1. Build one proof-of-concept animal with a silhouette meaningfully different
   from the humanoid, such as a cat or dog.
2. Validate painting, movement, camera, collision, ragdoll/posing, networking,
   shooting/tagging, line of sight, and round-end reveals on that body.
3. Define a reusable avatar-body contract and authoring checklist.
4. Add a small launch roster only after the first animal proves the pipeline.

**Acceptance criteria:**

- Players can preview and select an available body in the lobby or a separate
  customization screen before the round starts.
- The selection is replicated so every peer sees the same body for that player.
- Every animal supports painting across its complete visible body without major
  seams or unreachable areas.
- Movement, camera height/distance, spawn placement, nameplates, footsteps,
  ghost state, follow cameras, and round-end outlines adapt to the selected body.
- Each body has appropriate collision and shot/tag targets that follow its
  visible silhouette closely enough to feel fair.
- Ragdoll or an animal-appropriate posing system can settle the body naturally
  without exploding, clipping excessively, or resetting at phase changes.
- Late joins/reconnects and quick replays preserve or correctly restore the
  selected body.
- Automated contract tests verify that every selectable avatar provides the
  required paint, spawn, targeting, camera, network, and reveal hooks.

**Design considerations:**

- Different silhouettes create real gameplay advantages. A cat, snake, bird,
  and humanoid cannot share identical visibility and hiding opportunities.
  Start with similarly sized quadrupeds, or let hosts choose between a
  **cosmetic/balanced roster** and an intentionally asymmetric casual roster.
- Avoid forcing every animal into the humanoid skeleton. Define a common
  gameplay interface while allowing different rigs, segment layouts, poses, and
  camera offsets.
- Decide whether seekers may also choose animals. The simplest consistent rule
  is that all roles use their selected body, but seeker weapon placement and aim
  must work for every shape.
- Animal scale should be authored and tested per body rather than exposed as an
  unrestricted multiplier. Coordinate this with the map-versus-body scaling
  decision in `AVATAR-01`.
- Art scope grows quickly: each animal needs meshes, paintable surface data,
  collision, physics/pose setup, sounds, UI preview art, and multiplayer tests.
  A documented authoring pipeline is more valuable than a large first roster.

## P2 — Additional game modes

### MODE-01: Paint Tag

**Concept:** Add a continuous tag mode that uses the same movement, painting,
and hiding systems but passes the seeker role from player to player instead of
eliminating hiders or ending after one sweep.

**Default round flow:**

1. The host chooses a total match duration (suggested default: 10 minutes) and
   ghost grace period (suggested default: 30 seconds).
2. One player starts as the seeker, selected using the fair role history from
   `ROLE-01` where practical.
3. When the seeker successfully tags a hider, that hider immediately becomes
   the new seeker.
4. The previous seeker becomes a ghost for the configured grace period. They
   use this time to move to a hiding spot and repaint themselves.
5. When the grace period expires, the ghost becomes a normal, visible hider in
   their current location—as though they had been hiding there all along.
6. Tag handoffs continue until the match clock expires.

**Ghost behavior:**

- Ghosts are invisible to all other players but remain visible to themselves.
- Ghosts can move through other player bodies without colliding with them.
- Ghosts still collide with the map so they cannot walk through walls, floors,
  locked areas, or outside the playable space.
- Ghosts can move and paint themselves during the grace period.
- Ghosts cannot tag, be tagged, block shots/rays, or affect other players.
- The HUD clearly shows the remaining ghost time and warns before visibility
  returns.
- Becoming visible is an authoritative server event synchronized for everyone.

**Tagging rules to define during prototyping:**

- Start with a close-range touch/tag action rather than seeker ammunition.
- Add a short handoff cooldown so the new seeker cannot instantly tag the
  previous seeker as their ghost period ends.
- Decide whether the seeker is visibly marked for everyone; default to a clear
  seeker outline/nameplate so the mode reads as tag rather than standard seek.
- Decide what happens if the current seeker disconnects; default to selecting
  the eligible player who has spent the least total time as seeker.

**Scoring proposal:**

- Award points for each second spent as a normal hider.
- Award a tag bonus when the seeker hands off the role.
- Track total time spent as seeker, with less seeker time acting as a positive
  tiebreaker.
- Do not award normal hide-and-seek line-of-sight bonuses until playtesting
  confirms they encourage useful behavior in this faster mode.

**Acceptance criteria:**

- The host can select **Paint Tag** separately from the standard game mode.
- Total match duration and ghost grace period are configurable through
  `SETTINGS-01`, with safe minimums and maximums.
- Exactly one active seeker exists whenever at least two eligible players are
  connected.
- A valid tag transfers the seeker role exactly once, even with network delay
  or repeated collision events.
- The previous seeker receives the complete ghost grace period and becomes a
  visible hider at the correct server-authoritative time.
- Late joins, current-seeker disconnects, ghost disconnects, and two-player
  matches have defined, tested outcomes.
- Results show tags made, time spent seeking, time spent hiding, and total
  points; session totals can carry across replays through `SCORE-02`.
- Automated tests simulate repeated tag handoffs and confirm that the mode ends
  only when its overall match clock expires (or too few players remain).

## P2 — Rename the game

### BRAND-01: Rename “Mega Chamomile” to “Paint-n-Seek” — **SHIPPED**

**Acceptance criteria:**

- Update the window title, menus, lobby, documentation headings, package/export
  names, icons or wordmarks containing text, and repository-facing metadata.
- Preserve third-party credits and the MECCHA CHAMELEON inspiration note.
- Search case-insensitively for the old name and verify that no player-facing
  references remain.

## P1/P2 — UI consistency and presentation

### UI-01 (P1): Make UI scale consistently on Retina and Windows displays — **IMPLEMENTED; WINDOWS QA PENDING**

**Problem:** Fonts and controls appear much smaller on a Retina Mac display
than when the same build is tested on a Windows machine.

**Requested behavior:** Menus, HUD text, buttons, and interaction targets should
have a consistent apparent size across macOS Retina/high-DPI and Windows
displays. Players should not need to lower their display resolution to read or
use the interface comfortably.

**Implementation direction:** Define one project-wide content-scaling policy
and one shared UI theme instead of compensating screen by screen with unrelated
font sizes. Base layouts on anchors and containers, use logical UI dimensions,
and account for the operating system's display scale. Add a user-facing UI scale
option only if automatic scaling cannot cover the tested displays reliably.

**Acceptance criteria:**

- Test the main menu, lobby, pause menu, HUD, results, and settings at minimum on
  a Retina Mac and a Windows display at comparable physical sizes.
- Verify representative resolutions including 1920×1080, 2560×1440, and a
  Retina/high-DPI resolution available on the test Mac.
- Text has a comparable apparent size on both platforms and remains crisp.
- Buttons and other interaction targets remain comfortably clickable and do not
  overlap, clip, or fall outside safe screen bounds.
- Windowed resizing and fullscreen preserve the intended layout and aspect
  behavior.
- HUD elements do not become excessively large at low resolutions or tiny at
  high resolutions.
- If a UI scale setting is needed, provide a small tested range, live preview,
  reset-to-default action, and persistence between launches.
- Capture comparison screenshots using the same screens and game state so the
  cross-platform result can be reviewed side by side.

### UI-02 (P2): Give the main menu more pizzazz — **SHIPPED**

**Requested behavior:** Spruce up at least the main menu so the game immediately
communicates its playful paint-and-hide identity instead of feeling like a plain
utility screen. Extend the style to the lobby and results later if the main-menu
direction works.

**Suggested first pass:**

- A strong **Paint-n-Seek** title treatment and short one-line premise
- A colorful painted or in-engine map backdrop with a readable foreground panel
- Small, restrained motion such as drifting paint, a hiding character, or a
  slow camera move
- Clear visual hierarchy for Play/Host, Join, Settings, and Quit
- Hover/press feedback and a short paint-like transition or sound
- Credits and version information kept available without competing with the
  primary actions

**Acceptance criteria:**

- The main actions remain understandable within a few seconds for a first-time
  player.
- Decoration never reduces text contrast or obscures controls.
- Motion can be reduced or disabled and does not distract from typing a player
  name or address.
- The menu scales correctly under `UI-01` and supports mouse and keyboard input.
- Visuals perform smoothly on the project's minimum target hardware and do not
  delay reaching multiplayer setup.
- The style establishes reusable colors, fonts, panels, buttons, spacing, and
  transitions for later lobby/results polish.
- Final title work uses the `BRAND-01` name and does not discard required
  third-party credits.

## Related implementation bundles

The priorities indicate player impact, not a mandatory delivery order. The
following bundles describe features that are cheaper or safer when designed
together.

### Bundle A: Session and replay foundation

**Features:** `ROUND-01`, `ROUND-03`, `ROLE-01`, `SCORE-02`

These all need state that survives one round but ends when the lobby session
ends: stable player identity, previous roles, readiness for another round, and
cumulative score. Define one session model first, then let each feature use it.
Implementing them independently risks three different ideas of when a session
starts, resets, or survives a reconnect.

`ROUND-01` originally shipped with random reassignment; `ROLE-01` now replaces
that hook with persistent preference-aware rotation.

### Bundle B: Rules and host configuration

**Features:** `SETTINGS-01`, `HIDE-01`, `ROUND-02`, `MOVE-02`, `SCORE-01`,
configurable parts of `MOVE-01`, `AVATAR-01`, and `MODE-01`

Use one validated, replicated settings schema with per-mode sections. The
lobby can initially expose just hiding time, seeking time, ammo, and seeker
count; later features can add their values without creating separate settings
systems. Rules should receive an immutable snapshot at round start so a host
cannot accidentally change an active round. Keep ammo exhaustion authoritative
and evaluate it only after a shot has resolved; use a fixed hider slowdown first
and expose it here only if playtesting shows a setting is worthwhile.

### Bundle C: Hider state and cameras

**Features:** `HIDE-01`, `CAMERA-01`, existing eliminated-player spectating

Share camera-follow code and input-locking behavior, but keep concepts distinct:
**Hidden** is pre-seek readiness, **following** is a living hider's optional
camera mode during seek, and **spectating** is the state after elimination.
Using separate state names prevents a camera switch from accidentally affecting
the ready count or win conditions.

### Bundle D: Character physics and spatial assumptions

**Features:** `MOVE-01`, `MOVE-02`, `MOVE-03`, `AVATAR-01`, `BUG-01`

Test these in the same movement/physics pass. Character scale changes wall
clearance, step height, camera origin, aim direction, and spawn orientation,
while climbing changes which geometry is reachable. Each supported map needs a
small spawn-and-movement smoke test at the minimum and maximum allowed scale.
The seek-phase hider multiplier must apply after these base movement values are
chosen so character or map-scale experiments cannot accidentally cancel it.

Try uniform map enlargement before player-body scaling. It preserves player
physics but changes traversal distances, jump/climb reach relative to scenery,
line-of-sight ranges, and round pacing. Body scaling has the inverse tradeoff:
maps retain their current pacing, but nearly every player and ragdoll spatial
constant must be retuned.

### Bundle E: Paint Tag mode

**Features:** `MODE-01`, with foundations from `SETTINGS-01`, `ROUND-01`,
`SCORE-02`, and parts of `ROLE-01`

Paint Tag should reuse the session, configuration, scoreboard, player, and
painting systems, but its active-round rules should remain separate from the
standard hide-and-seek phase machine. A mode-specific pure rules object (or a
shared interface implemented by each mode) will be easier to test than filling
the current match rules with tag-only conditionals.

The mode can be prototyped earlier with fixed 10-minute/30-second defaults; the
full settings UI is helpful but not a hard blocker.

### Bundle F: Interface foundation and menu polish

**Features:** `UI-01`, `UI-02`, `BRAND-01`, and the UI portions of
`SETTINGS-01`

Fix content scaling and establish a reusable theme before doing detailed menu
decoration. The main-menu pass can define the game's visual language, while the
lobby/settings work reuses its controls and spacing. Apply the final name during
this pass if `BRAND-01` has not already shipped. Keep the scaling work separable
so `UI-01` can land as a functional improvement before the visual redesign is
finished.

### Bundle G: Results and round transition

**Features:** `REVEAL-01`, `ROUND-01`, `ROUND-03`, `SCORE-01`, `SCORE-02`, and
the results UI portion of `UI-02`

Define one authoritative end-of-round snapshot containing final poses, round
scores, survivors, and winner before enabling reveal visuals or inspection
movement. That snapshot feeds the scoreboard and remains unchanged throughout
the inspection period. Quick replay then resets scene state while preserving
only the session totals and role history. `REVEAL-01` can ship earlier: pose
preservation and seeker inspection do not require cumulative scoring or replay.
The results snapshot and scene stay alive without a countdown until an explicit
replay or exit action.

### Bundle H: Reusable avatar system

**Features:** `AVATAR-02`, `AVATAR-01`, `MOVE-01`, `CAMERA-01`, `REVEAL-01`,
and Paint Tag ghost presentation from `MODE-01`

Before adding multiple animals, extract the assumptions currently tied to the
humanoid body into a shared avatar contract: paintable parts, collision and
target points, camera anchors, movement dimensions, pose/ragdoll behavior,
visibility toggles, audio anchors, and reveal effects. Build and test the first
animal against that contract. This avoids copying humanoid-specific fixes into
every new body.

## Cross-feature design considerations

### Score comparability across settings and modes

Longer rounds, different scoring rates, multiple seekers, and Paint Tag will
produce totals that are not naturally comparable. The scoreboard should retain
raw fun session totals, but results should also label the mode and settings used.
Keep standard-mode and tag-mode round breakdowns distinct. Do not let score
affect fair role rotation.

### Role preferences in Paint Tag

Preferences apply directly to standard mode. In Paint Tag they should influence
only the initial seeker, because later seeker changes are caused by tags. Track
standard seeker assignments separately from tag-mode seeker time so playing one
mode does not unexpectedly distort fairness in the other.

### Hidden readiness versus follow camera

Do not require a hider to remain marked Hidden to use `CAMERA-01`: readiness is
only meaningful before seeking begins. During seek, following a seeker must
freeze the hider's local controls and leave their body vulnerable in place. A
host setting may disable this feature in competitive games because voice chat
can turn it into live seeker surveillance.

### Ghost visibility and collision

Paint Tag ghosts need a dedicated replicated gameplay state, not only a locally
hidden mesh. Other clients must omit the body, nameplate, footsteps, paint
effects, and targeting while the ghost still sees their own body normally.
Disable player-to-player interaction without disabling map collision. Ghosts
must remain subject to map bounds and the normal under-map recovery.

### Character scale affects game balance

Smaller characters are harder to see and hit, fit into more geometry, require
less paint area, and change the meaning of line-of-sight checks. Establish one
safe default before making scale host-configurable. If scale becomes a setting,
record it with round results and keep all players at the same scale.

Enlarging a map can create a similar visual ratio while keeping hitboxes and
paint behavior stable, but it also makes players slower relative to the level
and can make jumps, climbing, furniture access, seeker range, and existing
timers feel wrong. Choose between map scale and body scale per measured
playtest results, not solely by implementation effort.

### Climbing affects map boundaries

Wall-assisted movement makes climbable walls normal traversal, so seeker pens
and level boundaries must use ceilings, overhangs, or other geometry where
escape matters. Climbing requires wall contact but deliberately has no height or
duration limit. Paint Tag ghosts should not gain extra wall traversal beyond the
normal player movement rules. `MOVE-03` adds a second line of defense for the
Hallwyl Museum: explicit playable bounds and recovery around the near-ground
exterior, not only the global under-map plane.

### Replay ownership and readiness

Decide whether **Play Again** means an immediate host action or a vote/readiness
flow. A practical first version is host-controlled replay with visible player
ready states and an option to return to the lobby settings screen. Always clear
round-only state while preserving exactly the session fields defined in Bundle
A.

### Rename timing

`BRAND-01` is technically independent and easy. Doing it now makes the project
feel coherent sooner; waiting until major UI changes land reduces repeated
string and screenshot updates. Either choice is safe as long as the final rename
uses one case-insensitive search pass.

### High-DPI scaling versus intentional visual size

Treat `UI-01` as an apparent-size and layout problem, not merely a request for
larger font numbers. macOS Retina and Windows display scaling can map physical
pixels to logical UI units differently. Choose a single scaling policy, then
tune the shared theme against physical readability. Avoid platform-specific
magic numbers unless testing proves they are necessary.

### Menu polish versus functional expansion

`UI-02` should establish reusable presentation without blocking gameplay tasks.
Do the shared theme and responsive layout first; backdrop art, animation, and
sound can layer on afterward. Coordinate the final menu composition with
`SETTINGS-01` so new controls have a planned destination, and with `BRAND-01` so
the title treatment is created once.

### Results inspection versus completed game state

Allowing movement during results must not mean the match is still active. End
the authoritative rules and capture scores first, then enter a separate
inspection state with a narrow control allowlist. Preserve ragdoll transforms
without leaving them physically pushable. The reveal outline must be purely
presentational and must not feed back into line-of-sight scoring, tagging, or
role assignment.

### Avatar choice versus competitive fairness

Animal selection changes more than appearance: silhouette, height, paintable
area, hit target, camera viewpoint, hiding spaces, and movement clearance all
affect outcomes. Keep physical gameplay values server-authoritative and visible
in the lobby. For competitive play, use a curated roster with comparable
advantages; reserve extreme body shapes for an explicitly asymmetric or casual
mode.
