# Kenney scene generator

`generate_kenney_scenes.gd` scans every `.glb` below `assets/models` and writes
a matching reusable `StaticBody3D` scene below `scenes/objects/kenney`.

Each generated scene contains:

- the original GLB as its visible `Model` child;
- one exact concave `CollisionShape3D` per mesh;
- a shared 3x scale chosen for this project's 1.7 m player.

The scale is applied to the visual model and baked into the collision vertices;
the `StaticBody3D` itself stays at an identity scale for stable physics.

The shared scale preserves Kenney's relative proportions. It makes `barrel.glb`
about 1.03 m tall, while larger structures and trees remain proportionally larger.
Change `KENNEY_SCALE` in the script and rerun if the art direction needs a
different global size.

Run it from the project root whenever GLBs are added or changed:

```sh
godot --headless --path . --script res://tools/generate_kenney_scenes.gd
```

The script only overwrites scenes carrying its `generated_by` metadata. It will
skip an unrelated hand-authored scene at the same output path. Existing scenes
outside the generated folder, including `scenes/objects/barrel_2.tscn`, are not
modified.

## Hallwyl Museum scene generator

`generate_hallwyl_scene.gd` turns the Hallwyl Museum source GLB into the binary
static scene used by its map. It preserves the visible model and bakes each
room mesh into a concave collision shape. The flat presentation floor-plan mesh
is intentionally excluded from physics because it sits beneath the playable
museum.

Run it after replacing or reimporting the source GLB:

```sh
godot --headless --path . --script res://tools/generate_hallwyl_scene.gd
```

The generated scene carries the model's CC BY 4.0 attribution metadata; the
human-readable attribution is in `assets/map_assets/ATTRIBUTION.md`.
