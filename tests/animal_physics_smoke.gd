extends SceneTree
## Physics-level smoke test for every non-human catalog rig.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 0.1, 20)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.05
	floor.add_child(floor_collision)
	world.add_child(floor)

	var bodies: Array[PaintableBody] = []
	var starts: Array[Vector3] = []
	for i in 2:
		var avatar_id: String = ["cat", "dog"][i]
		var body := PaintableBody.new()
		body.position = Vector3(-2.0 if i == 0 else 2.0, 0.02, 0)
		world.add_child(body)
		body.build(50 + i, Color.WHITE, avatar_id)
		starts.append(body.center_of_mass_global())
		bodies.append(body)

	await physics_frame
	for body in bodies:
		body.set_ragdoll(true, true, Vector3(0, 0, -0.8), Vector3.UP * 0.4)
	for i in 240:
		await physics_frame

	var passed := true
	for i in bodies.size():
		var body := bodies[i]
		var avatar_id := body.avatar_id
		var center := body.center_of_mass_global()
		var finite := center.is_finite()
		var contained := center.distance_to(starts[i]) < 8.0 and center.y > -0.5 and center.y < 3.0
		var tilted := false
		for part in body.part_bodies:
			if absf(part.global_basis.y.normalized().dot(Vector3.UP)) < 0.9:
				tilted = true
				break
		var root_part: RigidBody3D = body.part_bodies[body.part_index(body.profile["root_part"])]
		var local_hit := body.global_transform.affine_inverse() * root_part.global_position
		body.splat_at(local_hit, Color.RED, 0.25, Vector3.BACK)
		var painted := _painted_vertex_count(body) > 0
		body.set_ragdoll(false, false)
		var restored := true
		for part_idx in body.part_bodies.size():
			if body.part_bodies[part_idx].top_level or not body.part_bodies[part_idx].transform \
					.is_equal_approx(body._authored_transforms[part_idx]):
				restored = false
				break
		print("%s: finite=%s contained=%s settled=%s painted=%s restored=%s" % [
				avatar_id, finite, contained, tilted, painted, restored])
		passed = passed and finite and contained and tilted and painted and restored
	quit(0 if passed else 1)


func _painted_vertex_count(body: PaintableBody) -> int:
	var count := 0
	for colors: PackedColorArray in body._part_colors:
		for color: Color in colors:
			if color.r > 0.8 and color.g < 0.5:
				count += 1
	return count
