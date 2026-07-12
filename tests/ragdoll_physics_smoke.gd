extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.1, 8)
	floor_shape.shape = box
	floor_shape.position.y = -0.05
	floor.add_child(floor_shape)
	world.add_child(floor)

	var player: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	player.name = "1"
	player.role = MatchState.Role.HIDER
	player.phase = MatchState.Phase.PAINT
	player.frozen = false
	world.add_child(player)

	await physics_frame
	await physics_frame
	player.set_ragdoll(true)
	for i in 180:
		await physics_frame

	var torso: RigidBody3D = player.body.part_bodies[player.body.part_index("Torso")]
	var laid_down := torso.global_position.y < 0.8
	var tilted := absf(torso.global_transform.basis.y.normalized().dot(Vector3.UP)) < 0.8
	print("ragdoll torso y=%.3f, up-dot=%.3f" % [torso.global_position.y,
			absf(torso.global_transform.basis.y.normalized().dot(Vector3.UP))])
	quit(0 if laid_down and tilted else 1)
