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
