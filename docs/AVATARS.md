# Avatar authoring

Avatar bodies are data entries in `scripts/avatar_catalog.gd`. `PaintableBody`
turns each entry into the subdivided meshes, hit shapes, vertex-paint surfaces,
rigid bodies, joints, and replicated ragdoll pose used by `Player`.

## Required contract

Each avatar has:

- A stable ID and player-facing label.
- A uniform authored `scale`. Parts, joint anchors, movement collision, camera,
  gameplay anchors, lobby preview, weapon, and paint-brush radius all derive
  from it.
- `parts`: uniquely named boxes with a size, center position, and optional Euler
  rotation. Feet should rest at local `y = 0`; visual forward is `-Z`.
- `joints`: one less joint than parts, forming a connected tree. Hinges need
  lower/upper limits; cone joints need swing/twist limits.
- A `root_part` that receives the initial ragdoll impulse.
- One or more movement capsules (radius, height, and position) that cover the
  silhouette; quadrupeds use separate front/back capsules.
- Camera pivot and orbit distance.
- Nameplate, line-of-sight target, seeker eye, and weapon positions.
- A preview height used only by the lobby camera.

## Adding another body

1. Add its profile to `AvatarCatalog.AVATARS` and its ID to `ORDER`.
2. Keep every paintable visible segment in `parts`; the shared mesh builder adds
   vertex colors and matching shot collision automatically.
3. Connect every segment exactly once through `joints`. Tune conservative joint
   limits so the released rig settles without folding through itself.
4. Tune the capsule and gameplay anchors against the visible silhouette. Do not
   add species checks to `Player`; a missing hook belongs in this contract.
5. Run `godot --headless -s tests/run_tests.gd` and
   `godot --headless -s tests/animal_physics_smoke.gd`.
6. Playtest painting from several angles, seeker aim fairness, camera clearance,
   spawn fit, crouching, wall climbing, ragdoll settling, and multiplayer replay.

`AvatarCatalog.contract_errors()` is the automated gate for required fields,
part references, and a connected rig. The animal physics smoke test also checks
finite/contained settling, painting after release, and standing-pose recovery.
