# Paint-n-Seek — Feature Backlog

This backlog turns the July 12, 2026 playtest notes into concrete feature
requests. It is planning documentation only; none of these items are
implemented yet.

## Effort and grouping at a glance

Effort is relative to this project, including multiplayer synchronization,
headless rule tests, UI, and playtesting—not just the number of code changes.
`XS` is a quick, low-risk change; `S` is small; `M` is a contained feature;
`L` crosses several systems; `XL` is a new game loop. Estimates can change
after investigation, especially for bugs.

| ID | Effort | Confidence | Best grouping | Why |
| --- | --- | --- | --- | --- |
| `BRAND-01` | XS | High | Standalone | Mostly a finite rename/search pass. |
| `BUG-01` | S | Medium | `AVATAR-01` camera/aim verification | Likely spawn/model yaw alignment, but the root cause still needs reproduction. |
| `UI-01` | S–M | High | `UI-02`, `SETTINGS-01` | Central display scaling and theme sizing should address most Retina/Windows inconsistency, followed by a screen audit. |
| `REVEAL-01` | S pose preservation / M full reveal | Medium | `ROUND-01`, results presentation | Keeping ragdoll state should be small; synchronized highlights and seeker-only results movement cross gameplay and rendering systems. |
| `SCORE-01` | S–M | High | `SCORE-02`, `SETTINGS-01` | The core survival and line-of-sight scoring already exists; breakdowns and configuration are the new work. |
| `HIDE-01` | M | High | `ROUND-01`, `CAMERA-01` | A contained ready-state and phase-transition feature. |
| `CAMERA-01` | M | Medium | `HIDE-01`, existing spectator camera | Eliminated-player spectating may be reusable, but living-hider control locking needs care. |
| `UI-02` | M | High | `UI-01`, `BRAND-01` | A focused main-menu layout, styling, motion, and audio pass without changing game rules. |
| `SCORE-02` | M | High | `ROUND-01`, `ROLE-01` | Needs session-lifetime player identity and score state. |
| `MOVE-01` | M | Medium | `AVATAR-01` physics playtest | Collision checks, exploit limits, and networked movement make this more than a jump tweak. |
| `ROUND-01` | M–L | High | `ROLE-01`, `SCORE-02` | Replay UI is small; reliably resetting a round while preserving session state is the larger part. |
| `ROLE-01` | L | High | `ROUND-01`, `SCORE-02` | Adds persistent history, preference UI, a fairness algorithm, replication, and many rule tests. |
| `SETTINGS-01` | L | High | All rule features | The UI is straightforward, but several settings affect different runtime systems and validation rules. |
| `AVATAR-01` | S–M prototype / L body-scale | Medium | `MOVE-01`, `BUG-01` | Making maps uniformly larger may achieve the desired relative size more safely than scaling the articulated bodies. |
| `MODE-01` | XL | High | Build after reusable round/settings state | Requires a second authoritative game loop, ghost state, tag handoffs, UI, scoring, and edge-case tests. |
| `AVATAR-02` | XL | Medium | `AVATAR-01`, painting/ragdoll architecture | Distinct animal silhouettes require new paintable bodies, physics rigs, hitboxes, cameras, and balance rules. |

### Easiest useful slices

These are good candidates when a small, independent improvement is wanted:

1. `BRAND-01` — easiest overall, though it creates broad file churn and is best
   done when the name is considered final.
2. Investigate and fix `BUG-01` — probably small if reproduction confirms one
   spawn/model orientation mismatch.
3. Establish consistent UI scaling for `UI-01`, then audit the existing screens
   at representative Retina and Windows resolutions.
4. Preserve surviving hiders' final ragdoll poses when the seek timer expires —
   the smallest independently useful slice of `REVEAL-01`.
5. Expose hiding time and seeking time in the existing lobby settings — the
   smallest useful slice of `SETTINGS-01` because both values already exist in
   the central configuration.
6. Expose fixed ammo or the existing ammo-per-hider value — another contained
   `SETTINGS-01` slice.
7. Extend `SCORE-01` to display the scoring breakdown — the underlying survival
   and visible-time calculation is already present.
8. Prototype a uniformly enlarged copy of one map for `AVATAR-01` — this may
   deliver the smaller-character feel without changing player physics.

`AVATAR-01` may look like a simple scale change but should not be treated as a
quick body-scaling win because the current character is an articulated physics
body. Testing a larger map first is the lower-risk version of the idea.

## P0 — Fix movement and orientation blockers

### BUG-01: Seeker starts or appears facing backwards

**Problem:** The seeker can enter the round facing the wrong direction.

**Requested behavior:** A seeker should face the intended direction when the
round starts and when the hiding area opens. The character model, camera, aim
direction, and movement-forward direction should agree.

**Acceptance criteria:**

- Every seeker spawn defines a deliberate initial facing direction.
- The local camera and remote character model show the same forward direction.
- The first shot travels toward the center of the seeker's crosshair.
- This works for every map and for multiple seekers.

### MOVE-01: Recover from walls and climb or float upward

**Problem:** A player can become stuck against or inside level collision.

**Requested behavior:** Holding Space while blocked should give the player a
controlled way to move upward, such as a slow climb/float. Releasing Space
restores normal gravity. This should complement the existing under-map recovery.

**Acceptance criteria:**

- Holding Space near a blocking wall moves the player upward at a limited,
  tunable speed after a short eligibility check.
- Releasing Space immediately returns the player to normal gravity.
- The mechanic cannot be used to fly indefinitely in open space or escape the
  playable map.
- Server/peer movement remains synchronized.
- Add a fallback unstuck action or automatic safe-spawn reset for geometry
  cases the movement assist cannot solve.

**Design decision needed:** Choose between wall-climb, short hover, or a hybrid.
The preferred first prototype is a short wall-assisted climb because it fixes
the reported problem without turning Space into unrestricted flight.

## P1 — Make consecutive rounds easy and fair

### ROUND-01: Quick replay from results

**Requested behavior:** Add a prominent **Play Again** button to the results
screen so the same lobby can immediately start another round without making
everyone reconnect.

**Acceptance criteria:**

- The host can start a replay from the results screen.
- Players remain in the same session and keep their cumulative scores.
- The next round resets round-only state: alive/eliminated status, ammo,
  paint/body state, spawns, timers, and ready/hidden state.
- Roles are assigned again using `ROLE-01`; the previous assignment is not
  blindly reused.
- Players who do not opt in yet see a clear waiting/confirmation state.

### ROLE-01: Preference-aware, fair role assignment

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
- Results duration
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

### HIDE-01: Hiders can report ready and finish hiding early

**Requested behavior:** During the hiding/painting phase, each hider can mark
themselves **Hidden**. When every active hider is marked hidden, the host can
skip the remaining countdown and begin seeking.

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

## P1 — Multi-round scoring

### SCORE-01: Reward risky visibility and time unfound

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

### SCORE-02: Carry a session scoreboard across rounds

**Requested behavior:** Keep cumulative player scores while the lobby plays
successive rounds.

**Acceptance criteria:**

- Results show both current-round points and session total.
- Quick replay preserves totals; leaving the lobby or starting a new session
  resets them.
- A temporary disconnect/reconnect policy is defined so duplicate identities
  cannot inherit or create scores accidentally.
- Role rotation and cumulative scores are separate; score does not influence
  who becomes seeker.

## P1 — Round-end reveal

### REVEAL-01: Preserve hiding poses and let seekers inspect survivors

**Problem:** When the seeking timer expires, hiders should not stand up or lose
the pose that made their hiding spot work. Seekers should get a satisfying
chance to discover what they missed.

**Requested behavior:** When time expires with surviving hiders, preserve each
hider exactly as they were—including ragdoll pose, body transform, and paint—
then reveal them with a visible outline, pulse, or blink. During this results
inspection period, seekers can continue walking and looking around the map to
see where everyone was hiding.

**Round-end behavior:**

- Freeze surviving hiders in their final pose. Do not force them to stand up,
  rebuild their body, teleport, or reset their paint when entering results.
- Let seekers retain normal walking, camera, and look controls for the duration
  of the inspection period.
- Disable seeker shooting, tags, ammo use, scoring, eliminations, painting, and
  any other action that could change the completed result.
- Visually highlight every surviving hider after a brief reveal beat. Start with
  a high-contrast pulsing outline; use a blinking silhouette or marker if an
  outline is unreliable in the Compatibility renderer.
- Keep the scoreboard available without forcing it to cover the whole screen;
  seekers should be able to inspect the scene and deliberately open or close the
  detailed results.
- At the end of inspection, continue to the normal lobby/replay flow. Only then
  may round-only bodies and poses be reset.

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

- Make the inspection duration configurable with the results duration in
  `SETTINGS-01`; retain the current results duration as the initial default.
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

### CAMERA-01: Let a living hider watch the seeker

**Requested behavior:** During the seek phase, a hider who is still in play can
switch from their own camera to a read-only follow camera on a seeker, then
switch back to their body. With multiple seekers, they can cycle among them.

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

## P3 — Long-term avatar variety

### AVATAR-02: Let players choose an animal body

**Concept:** Let each player select an animal instead of always playing as a
humanoid. Animal bodies should still support the core fantasy: sampling colors,
painting the body, moving into a hiding spot, and settling into a convincing
pose.

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

### BRAND-01: Rename “Mega Chamomile” to “Paint-n-Seek”

**Acceptance criteria:**

- Update the window title, menus, lobby, documentation headings, package/export
  names, icons or wordmarks containing text, and repository-facing metadata.
- Preserve third-party credits and the MECCHA CHAMELEON inspiration note.
- Search case-insensitively for the old name and verify that no player-facing
  references remain.

## P1/P2 — UI consistency and presentation

### UI-01 (P1): Make UI scale consistently on Retina and Windows displays

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

### UI-02 (P2): Give the main menu more pizzazz

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

**Features:** `ROUND-01`, `ROLE-01`, `SCORE-02`

These all need state that survives one round but ends when the lobby session
ends: stable player identity, previous roles, readiness for another round, and
cumulative score. Define one session model first, then let each feature use it.
Implementing them independently risks three different ideas of when a session
starts, resets, or survives a reconnect.

`ROUND-01` can still ship before preferences if its first role reassignment uses
the current random selection and leaves a clean hook for `ROLE-01`.

### Bundle B: Rules and host configuration

**Features:** `SETTINGS-01`, `HIDE-01`, `SCORE-01`, configurable parts of
`MOVE-01`, `AVATAR-01`, and `MODE-01`

Use one validated, replicated settings schema with per-mode sections. The
lobby can initially expose just hiding time, seeking time, ammo, and seeker
count; later features can add their values without creating separate settings
systems. Rules should receive an immutable snapshot at round start so a host
cannot accidentally change an active round.

### Bundle C: Hider state and cameras

**Features:** `HIDE-01`, `CAMERA-01`, existing eliminated-player spectating

Share camera-follow code and input-locking behavior, but keep concepts distinct:
**Hidden** is pre-seek readiness, **following** is a living hider's optional
camera mode during seek, and **spectating** is the state after elimination.
Using separate state names prevents a camera switch from accidentally affecting
the ready count or win conditions.

### Bundle D: Character physics and spatial assumptions

**Features:** `MOVE-01`, `AVATAR-01`, `BUG-01`

Test these in the same movement/physics pass. Character scale changes wall
clearance, step height, camera origin, aim direction, and spawn orientation,
while climbing changes which geometry is reachable. Each supported map needs a
small spawn-and-movement smoke test at the minimum and maximum allowed scale.

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

**Features:** `REVEAL-01`, `ROUND-01`, `SCORE-01`, `SCORE-02`, and the results
UI portion of `UI-02`

Define one authoritative end-of-round snapshot containing final poses, round
scores, survivors, and winner before enabling reveal visuals or inspection
movement. That snapshot feeds the scoreboard and remains unchanged throughout
the inspection period. Quick replay then resets scene state while preserving
only the session totals and role history. `REVEAL-01` can ship earlier: pose
preservation and seeker inspection do not require cumulative scoring or replay.

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

Wall-assisted movement can invalidate seeker pens and level boundaries. Mark
surfaces or areas where climbing is allowed, or require a strict combination of
wall contact, height limit, and short duration. Paint Tag ghosts should not gain
extra wall traversal beyond the normal player movement rules.

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
