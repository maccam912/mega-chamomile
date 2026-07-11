class_name PaintableBody
extends Node3D
## A blocky humanoid built from subdivided BoxMeshes whose vertices can be
## painted. Painting sets vertex colors within a brush radius of a point in
## this node's local space — no UVs, no texture readback, and a paint stroke
## replicates as just (from_pos, to_pos, color, radius).
##
## Each part also gets a StaticBody3D on collision layer 2 ("paintable") with
## metadata: part_idx (int) and peer_id (set by the owning player) so paint
## and shot raycasts can identify what they hit.

const PAINT_LAYER := 2  # collision layer bitmask value

## name, size, center position (local; feet at y=0), facing -Z.
const PARTS := [
	{"name": "LegL", "size": Vector3(0.22, 0.72, 0.22), "pos": Vector3(-0.13, 0.36, 0)},
	{"name": "LegR", "size": Vector3(0.22, 0.72, 0.22), "pos": Vector3(0.13, 0.36, 0)},
	{"name": "Torso", "size": Vector3(0.5, 0.6, 0.28), "pos": Vector3(0, 1.02, 0)},
	{"name": "ArmL", "size": Vector3(0.16, 0.6, 0.16), "pos": Vector3(-0.34, 1.02, 0)},
	{"name": "ArmR", "size": Vector3(0.16, 0.6, 0.16), "pos": Vector3(0.34, 1.02, 0)},
	{"name": "Head", "size": Vector3(0.36, 0.36, 0.36), "pos": Vector3(0, 1.5, 0)},
]
const VERT_SPACING := 0.05
const STAMP_SPACING := 0.5  ## stroke stamps this fraction of the radius apart
const MAX_STAMPS := 24      ## safety cap per stroke segment

var part_meshes: Array[MeshInstance3D] = []
var part_bodies: Array[StaticBody3D] = []
var _part_arrays: Array = []        # cached mesh arrays per part
var _part_positions: Array = []     # PackedVector3Array per part (part-local)
var _part_colors: Array = []        # PackedColorArray per part


func build(peer_id: int, base_color: Color) -> void:
	for i in PARTS.size():
		var spec: Dictionary = PARTS[i]
		var size: Vector3 = spec["size"]
		var box := BoxMesh.new()
		box.size = size
		box.subdivide_width = clampi(int(ceilf(size.x / VERT_SPACING)), 2, 14)
		box.subdivide_height = clampi(int(ceilf(size.y / VERT_SPACING)), 2, 14)
		box.subdivide_depth = clampi(int(ceilf(size.z / VERT_SPACING)), 2, 14)

		var arrays := box.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(verts.size())
		colors.fill(base_color)
		arrays[Mesh.ARRAY_COLOR] = colors

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mi := MeshInstance3D.new()
		mi.name = spec["name"]
		mi.position = spec["pos"]
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		mat.roughness = 0.9
		mi.material_override = mat
		add_child(mi)

		var sb := StaticBody3D.new()
		sb.collision_layer = PAINT_LAYER
		sb.collision_mask = 0
		sb.set_meta("part_idx", i)
		sb.set_meta("peer_id", peer_id)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		sb.add_child(col)
		mi.add_child(sb)

		part_meshes.append(mi)
		part_bodies.append(sb)
		_part_arrays.append(arrays)
		_part_positions.append(verts)
		_part_colors.append(colors)

## Paints one soft-edged splat at a body-space point. Every part the brush
## sphere touches gets painted, so strokes don't seam at part boundaries.
func splat_at(local_pos: Vector3, color: Color, radius: float) -> void:
	stroke(local_pos, local_pos, color, radius)


## Stamps splats along a body-space segment so a fast brush drag leaves a
## continuous line instead of spaced dots. This is what replicates over the
## wire: (from, to, color, radius), expanded into stamps on every peer.
func stroke(from_pos: Vector3, to_pos: Vector3, color: Color, radius: float) -> void:
	var spacing := maxf(radius * STAMP_SPACING, 0.01)
	var steps := mini(int(ceilf(from_pos.distance_to(to_pos) / spacing)), MAX_STAMPS)
	var dirty := {}
	_stamp(from_pos, color, radius, dirty)
	for s in range(1, steps + 1):
		_stamp(from_pos.lerp(to_pos, float(s) / steps), color, radius, dirty)
	for part_idx: int in dirty:
		_rebuild(part_idx)


## Blend `color` into every vertex within `radius` of a body-space point,
## across all parts. No rebuild; touched parts are recorded in `dirty`.
func _stamp(local_pos: Vector3, color: Color, radius: float, dirty: Dictionary) -> void:
	for part_idx in part_meshes.size():
		var p: Vector3 = local_pos - PARTS[part_idx]["pos"]  # into part-local space
		var reach: Vector3 = PARTS[part_idx]["size"] * 0.5 + Vector3.ONE * radius
		if absf(p.x) > reach.x or absf(p.y) > reach.y or absf(p.z) > reach.z:
			continue  # brush sphere can't touch this part
		var verts: PackedVector3Array = _part_positions[part_idx]
		var colors: PackedColorArray = _part_colors[part_idx]
		var changed := false
		for i in verts.size():
			var d := verts[i].distance_to(p)
			if d <= radius:
				var t: float = clampf((1.0 - d / radius) * 2.0, 0.0, 1.0)
				colors[i] = colors[i].lerp(color, t)
				changed = true
		if changed:
			_part_colors[part_idx] = colors
			dirty[part_idx] = true


func fill_all(color: Color) -> void:
	for i in part_meshes.size():
		var colors: PackedColorArray = _part_colors[i]
		colors.fill(color)
		_part_colors[i] = colors
		_rebuild(i)


func set_parts_collidable(enabled: bool) -> void:
	for sb in part_bodies:
		sb.collision_layer = PAINT_LAYER if enabled else 0


func body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for sb in part_bodies:
		rids.append(sb.get_rid())
	return rids


func _rebuild(part_idx: int) -> void:
	var arrays: Array = _part_arrays[part_idx]
	arrays[Mesh.ARRAY_COLOR] = _part_colors[part_idx]
	var mesh := part_meshes[part_idx].mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
