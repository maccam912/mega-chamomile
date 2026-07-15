class_name PaintableBody
extends Node3D
## A segmented, paintable avatar. AvatarCatalog supplies the authored parts,
## joints, and gameplay anchors; painting and ragdolling are shared by every rig.

const PAINT_LAYER := 2

const VERT_SPACING := 0.05
const STAMP_SPACING := 0.5
const MAX_STAMPS := 24

var part_meshes: Array[MeshInstance3D] = []
var part_bodies: Array[RigidBody3D] = []
var joints: Array[Joint3D] = []
var ragdolled := false
var avatar_id := AvatarCatalog.DEFAULT_ID
var profile: Dictionary = {}
var parts: Array = []

var _part_arrays: Array = []
var _part_positions: Array = []
var _part_colors: Array = []
var _remote_targets: Array[Transform3D] = []
var _authored_transforms: Array[Transform3D] = []


func build(peer_id: int, base_color: Color,
		selected_avatar := AvatarCatalog.DEFAULT_ID) -> void:
	avatar_id = AvatarCatalog.normalize(selected_avatar)
	profile = AvatarCatalog.profile(avatar_id)
	parts = profile["parts"]
	for i in parts.size():
		var spec: Dictionary = parts[i]
		var size: Vector3 = spec["size"]
		var authored := Transform3D(
				Basis.from_euler(spec.get("rot", Vector3.ZERO)), spec["pos"])
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
		rb.transform = authored
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
		_authored_transforms.append(authored)

	_build_joints()


func _build_joints() -> void:
	for spec: Dictionary in profile["joints"]:
		if spec["type"] == "hinge":
			_add_hinge(spec["name"], spec["a"], spec["b"], spec["anchor"],
					spec["lower"], spec["upper"])
		else:
			_add_cone(spec["name"], spec["a"], spec["b"], spec["anchor"],
					spec["swing"], spec["twist"])


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
	for i in parts.size():
		if parts[i]["name"] == part_name:
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
			var root := part_bodies[part_index(profile["root_part"])]
			# Tip toward current travel. At rest, retain the small forward nudge
			# that prevents the released upright rig balancing on both feet.
			var horizontal_motion := Vector3(inherited_velocity.x, 0, inherited_velocity.z)
			var fall_direction := (
					horizontal_motion.normalized() if horizontal_motion.length_squared() > 0.01
					else -global_transform.basis.z)
			root.apply_central_impulse(
					(fall_direction * 0.7 + Vector3.UP * 0.08) * float(profile["scale"]))
	else:
		for i in part_bodies.size():
			var rb := part_bodies[i]
			rb.freeze = true
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.collision_mask = 0
			rb.top_level = false
			rb.transform = _authored_transforms[i]


## Preserve an articulated pose for results inspection without rebuilding the
## standing rig. Disabling collisions keeps walking seekers from disturbing it.
func freeze_ragdoll_pose() -> void:
	if not ragdolled:
		return
	for rb in part_bodies:
		rb.freeze = true
		rb.sleeping = true
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.collision_mask = 0


## Resume a locally simulated ragdoll after a temporary read-only camera view.
## Unlike set_ragdoll(), this preserves every articulated part transform.
func resume_ragdoll_pose() -> void:
	if not ragdolled:
		return
	for rb in part_bodies:
		rb.collision_mask = 1
		rb.freeze = false
		rb.sleeping = false


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


func splat_at(local_pos: Vector3, color: Color, radius: float,
		through_axis: Vector3) -> void:
	stroke(local_pos, local_pos, color, radius, through_axis)


## Paint uses a cylinder centered on each visible-surface stamp and extending
## through the complete avatar along the camera ray. Callers must provide that
## ray in body-local space so the same footprint can be reconstructed by every
## peer and transformed correctly for independently rotated ragdoll parts.
func stroke(from_pos: Vector3, to_pos: Vector3, color: Color, radius: float,
		through_axis: Vector3) -> void:
	var axis := through_axis.normalized()
	if axis.is_zero_approx() or radius <= 0.0:
		return
	var spacing := maxf(radius * STAMP_SPACING, 0.01)
	var steps := mini(int(ceilf(from_pos.distance_to(to_pos) / spacing)), MAX_STAMPS)
	var dirty := {}
	_stamp(from_pos, color, radius, axis, dirty)
	for s in range(1, steps + 1):
		_stamp(from_pos.lerp(to_pos, float(s) / steps), color, radius, axis, dirty)
	for part_idx: int in dirty:
		_rebuild(part_idx)


func _stamp(local_pos: Vector3, color: Color, radius: float,
		through_axis: Vector3, dirty: Dictionary) -> void:
	var world_point := global_transform * local_pos if is_inside_tree() else Vector3.ZERO
	var world_axis := (
			(global_transform.basis * through_axis).normalized()
			if is_inside_tree() else Vector3.ZERO)
	for part_idx in part_meshes.size():
		var p: Vector3
		var axis: Vector3
		if is_inside_tree():
			p = part_bodies[part_idx].global_transform.affine_inverse() * world_point
			axis = (part_bodies[part_idx].global_transform.basis.inverse() * world_axis).normalized()
		else:
			p = part_bodies[part_idx].transform.affine_inverse() * local_pos
			axis = (part_bodies[part_idx].transform.basis.inverse() * through_axis).normalized()
		# Cheap conservative rejection: if the paint axis misses a sphere around
		# the entire part, it cannot touch any of that part's vertices.
		var center_distance := _distance_to_axis(Vector3.ZERO, p, axis)
		var part_radius: float = (parts[part_idx]["size"] as Vector3).length() * 0.5
		if center_distance > part_radius + radius:
			continue
		var verts: PackedVector3Array = _part_positions[part_idx]
		var colors: PackedColorArray = _part_colors[part_idx]
		var changed := false
		for i in verts.size():
			var d := _distance_to_axis(verts[i], p, axis)
			if d <= radius:
				var t: float = clampf((1.0 - d / radius) * 2.0, 0.0, 1.0)
				colors[i] = colors[i].lerp(color, t)
				changed = true
		if changed:
			_part_colors[part_idx] = colors
			dirty[part_idx] = true


static func _distance_to_axis(point: Vector3, axis_origin: Vector3,
		axis_direction: Vector3) -> float:
	var offset := point - axis_origin
	return (offset - axis_direction * offset.dot(axis_direction)).length()


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
