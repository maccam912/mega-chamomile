class_name PaintableBody
extends Node3D
## A segmented, paintable humanoid. Each box is a frozen RigidBody3D while the
## player is walking; ragdoll mode releases the pieces into a jointed physics
## rig. Paint is still stored as per-vertex color on each segment.

const PAINT_LAYER := 2

## name, size, center position (body-local; feet at y=0), facing -Z.
## Limb segments meet at the elbow/knee anchors so the joints read clearly.
const PARTS := [
	{"name": "LowerLegL", "size": Vector3(0.22, 0.36, 0.22), "pos": Vector3(-0.13, 0.18, 0)},
	{"name": "LowerLegR", "size": Vector3(0.22, 0.36, 0.22), "pos": Vector3(0.13, 0.18, 0)},
	{"name": "UpperLegL", "size": Vector3(0.24, 0.38, 0.24), "pos": Vector3(-0.13, 0.55, 0)},
	{"name": "UpperLegR", "size": Vector3(0.24, 0.38, 0.24), "pos": Vector3(0.13, 0.55, 0)},
	{"name": "Pelvis", "size": Vector3(0.46, 0.22, 0.28), "pos": Vector3(0, 0.81, 0)},
	{"name": "Torso", "size": Vector3(0.5, 0.52, 0.28), "pos": Vector3(0, 1.15, 0)},
	{"name": "UpperArmL", "size": Vector3(0.17, 0.31, 0.17), "pos": Vector3(-0.34, 1.245, 0)},
	{"name": "UpperArmR", "size": Vector3(0.17, 0.31, 0.17), "pos": Vector3(0.34, 1.245, 0)},
	{"name": "LowerArmL", "size": Vector3(0.16, 0.34, 0.16), "pos": Vector3(-0.34, 0.92, 0)},
	{"name": "LowerArmR", "size": Vector3(0.16, 0.34, 0.16), "pos": Vector3(0.34, 0.92, 0)},
	{"name": "Head", "size": Vector3(0.36, 0.36, 0.36), "pos": Vector3(0, 1.59, 0)},
]

const VERT_SPACING := 0.05
const STAMP_SPACING := 0.5
const MAX_STAMPS := 24

var part_meshes: Array[MeshInstance3D] = []
var part_bodies: Array[RigidBody3D] = []
var joints: Array[Joint3D] = []
var ragdolled := false

var _part_arrays: Array = []
var _part_positions: Array = []
var _part_colors: Array = []
var _remote_targets: Array[Transform3D] = []


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

		var rb := RigidBody3D.new()
		rb.name = spec["name"] + "Physics"
		rb.position = spec["pos"]
		rb.mass = maxf(0.25, size.x * size.y * size.z * 18.0)
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.collision_layer = PAINT_LAYER
		rb.collision_mask = 0
		rb.set_meta("part_idx", i)
		rb.set_meta("peer_id", peer_id)
		add_child(rb)

		var mi := MeshInstance3D.new()
		mi.name = spec["name"]
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		# Eyedropped colors come from the rendered (sRGB) viewport. Without this,
		# mid-range vertex values are treated as linear and render much brighter
		# than both the sampled pixel and the HUD swatch.
		mat.vertex_color_is_srgb = true
		mat.albedo_color = Color.WHITE
		mat.roughness = 0.9
		mi.material_override = mat
		rb.add_child(mi)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		rb.add_child(col)

		part_meshes.append(mi)
		part_bodies.append(rb)
		_part_arrays.append(arrays)
		_part_positions.append(verts)
		_part_colors.append(colors)

	_build_joints()


func _build_joints() -> void:
	# Hinge joints keep elbows and knees bending in a human-looking plane.
	_add_hinge("KneeL", "UpperLegL", "LowerLegL", Vector3(-0.13, 0.36, 0), -0.08, 2.35)
	_add_hinge("KneeR", "UpperLegR", "LowerLegR", Vector3(0.13, 0.36, 0), -0.08, 2.35)
	_add_hinge("ElbowL", "UpperArmL", "LowerArmL", Vector3(-0.34, 1.09, 0), -2.35, 0.08)
	_add_hinge("ElbowR", "UpperArmR", "LowerArmR", Vector3(0.34, 1.09, 0), -2.35, 0.08)

	# Ball-like constrained joints give the hips, shoulders, neck, and waist
	# enough freedom to settle naturally without folding inside-out.
	_add_cone("HipL", "Pelvis", "UpperLegL", Vector3(-0.13, 0.72, 0), 0.7, 0.35)
	_add_cone("HipR", "Pelvis", "UpperLegR", Vector3(0.13, 0.72, 0), 0.7, 0.35)
	_add_cone("Waist", "Pelvis", "Torso", Vector3(0, 0.91, 0), 0.4, 0.25)
	_add_cone("ShoulderL", "Torso", "UpperArmL", Vector3(-0.3, 1.35, 0), 1.0, 0.65)
	_add_cone("ShoulderR", "Torso", "UpperArmR", Vector3(0.3, 1.35, 0), 1.0, 0.65)
	_add_cone("Neck", "Torso", "Head", Vector3(0, 1.41, 0), 0.35, 0.25)


func _add_hinge(joint_name: String, a_name: String, b_name: String,
		anchor: Vector3, lower: float, upper: float) -> void:
	var joint := HingeJoint3D.new()
	joint.name = joint_name
	joint.position = anchor
	joint.set("angular_limit/enable", true)
	joint.set("angular_limit/lower", lower)
	joint.set("angular_limit/upper", upper)
	_add_joint(joint, a_name, b_name)


func _add_cone(joint_name: String, a_name: String, b_name: String,
		anchor: Vector3, swing: float, twist: float) -> void:
	var joint := ConeTwistJoint3D.new()
	joint.name = joint_name
	joint.position = anchor
	joint.swing_span = swing
	joint.twist_span = twist
	_add_joint(joint, a_name, b_name)


func _add_joint(joint: Joint3D, a_name: String, b_name: String) -> void:
	add_child(joint)
	var a := part_bodies[part_index(a_name)]
	var b := part_bodies[part_index(b_name)]
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.exclude_nodes_from_collision = true
	joints.append(joint)


func part_index(part_name: String) -> int:
	for i in PARTS.size():
		if PARTS[i]["name"] == part_name:
			return i
	return -1


func set_ragdoll(active: bool, simulate: bool, inherited_velocity: Vector3 = Vector3.ZERO,
		inherited_angular_velocity: Vector3 = Vector3.ZERO) -> void:
	if ragdolled == active:
		return
	ragdolled = active
	_remote_targets.clear()
	if active:
		for rb in part_bodies:
			var world_pose := rb.global_transform if is_inside_tree() else rb.transform
			rb.top_level = true
			if is_inside_tree():
				rb.global_transform = world_pose
			else:
				rb.transform = world_pose
			rb.collision_mask = 1 if simulate else 0
			rb.freeze = not simulate
			rb.sleeping = false
			if simulate:
				# A turning rigid character gives each point a different tangential
				# velocity: v(point) = v(root) + angular_velocity × radius.
				var radius: Vector3 = world_pose.origin - global_position
				rb.linear_velocity = inherited_velocity \
						+ inherited_angular_velocity.cross(radius)
				rb.angular_velocity = inherited_angular_velocity
		if simulate:
			var torso := part_bodies[part_index("Torso")]
			# Tip toward current travel. At rest, retain the small forward nudge
			# that prevents the released upright rig balancing on both feet.
			var horizontal_motion := Vector3(inherited_velocity.x, 0, inherited_velocity.z)
			var fall_direction := (
					horizontal_motion.normalized() if horizontal_motion.length_squared() > 0.01
					else -global_transform.basis.z)
			torso.apply_central_impulse(fall_direction * 0.7 + Vector3.UP * 0.08)
	else:
		for i in part_bodies.size():
			var rb := part_bodies[i]
			rb.freeze = true
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.collision_mask = 0
			rb.top_level = false
			rb.transform = Transform3D(Basis.IDENTITY, PARTS[i]["pos"])


func capture_pose() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for rb in part_bodies:
		pose.append(rb.global_transform if is_inside_tree() else rb.transform)
	return pose


func center_of_mass_global() -> Vector3:
	if part_bodies.is_empty():
		return global_position
	var weighted_position := Vector3.ZERO
	var total_mass := 0.0
	for rb in part_bodies:
		weighted_position += rb.global_position * rb.mass
		total_mass += rb.mass
	return weighted_position / maxf(total_mass, 0.001)


func set_remote_pose(pose: Array) -> void:
	if pose.size() != part_bodies.size():
		return
	var first_pose := _remote_targets.is_empty()
	_remote_targets.clear()
	for value in pose:
		_remote_targets.append(value as Transform3D)
	if first_pose:
		for i in part_bodies.size():
			part_bodies[i].global_transform = _remote_targets[i]


func interpolate_remote_pose(delta: float) -> void:
	if _remote_targets.size() != part_bodies.size():
		return
	var weight := minf(1.0, delta * 16.0)
	for i in part_bodies.size():
		part_bodies[i].global_transform = part_bodies[i].global_transform.interpolate_with(
				_remote_targets[i], weight)


func splat_at(local_pos: Vector3, color: Color, radius: float) -> void:
	stroke(local_pos, local_pos, color, radius)


func stroke(from_pos: Vector3, to_pos: Vector3, color: Color, radius: float) -> void:
	var spacing := maxf(radius * STAMP_SPACING, 0.01)
	var steps := mini(int(ceilf(from_pos.distance_to(to_pos) / spacing)), MAX_STAMPS)
	var dirty := {}
	_stamp(from_pos, color, radius, dirty)
	for s in range(1, steps + 1):
		_stamp(from_pos.lerp(to_pos, float(s) / steps), color, radius, dirty)
	for part_idx: int in dirty:
		_rebuild(part_idx)


func _stamp(local_pos: Vector3, color: Color, radius: float, dirty: Dictionary) -> void:
	var world_point := global_transform * local_pos if is_inside_tree() else Vector3.ZERO
	for part_idx in part_meshes.size():
		var p: Vector3
		if is_inside_tree():
			p = part_bodies[part_idx].global_transform.affine_inverse() * world_point
		else:
			p = part_bodies[part_idx].transform.affine_inverse() * local_pos
		var reach: Vector3 = PARTS[part_idx]["size"] * 0.5 + Vector3.ONE * radius
		if absf(p.x) > reach.x or absf(p.y) > reach.y or absf(p.z) > reach.z:
			continue
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
	for rb in part_bodies:
		rb.collision_layer = PAINT_LAYER if enabled else 0


func body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for rb in part_bodies:
		rids.append(rb.get_rid())
	return rids


func _rebuild(part_idx: int) -> void:
	var arrays: Array = _part_arrays[part_idx]
	arrays[Mesh.ARRAY_COLOR] = _part_colors[part_idx]
	var mesh := part_meshes[part_idx].mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
