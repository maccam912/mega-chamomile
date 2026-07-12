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
	box.size = Vector3(40, 0.1, 40)
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
	var standing_view: Vector3 = player._camera.global_position
	var inherited_velocity := Vector3(2.0, 0, -1.5)
	var inherited_turn := Vector3.UP * 1.2
	player.velocity = inherited_velocity
	player._yaw_rate = inherited_turn.y
	var starting_mass_center: Vector3 = player.body.center_of_mass_global()
	player.set_ragdoll(true)
	var lower_leg: RigidBody3D = player.body.part_bodies[
			player.body.part_index("LowerLegL")]
	var lower_leg_radius: Vector3 = lower_leg.global_position - player.global_position
	var expected_leg_velocity: Vector3 = inherited_velocity \
			+ inherited_turn.cross(lower_leg_radius)
	var momentum_inherited: bool = lower_leg.linear_velocity.distance_to(
			expected_leg_velocity) < 0.02 and lower_leg.angular_velocity.distance_to(
			inherited_turn) < 0.02
	await physics_frame
	var initial_fly_continuous: bool = player._camera.global_position.distance_to(
			standing_view) < 0.25
	for i in 179:
		await physics_frame

	var torso: RigidBody3D = player.body.part_bodies[player.body.part_index("Torso")]
	var torso_y := torso.global_position.y
	var torso_up_dot := absf(torso.global_transform.basis.y.normalized().dot(Vector3.UP))
	var laid_down := torso_y < 0.8
	var tilted := torso_up_dot < 0.8
	var travel_direction := inherited_velocity.normalized()
	var mass_center_travel: Vector3 = player.body.center_of_mass_global() - starting_mass_center
	var continued_forward: bool = mass_center_travel.dot(travel_direction) > 1.0

	player.set_paint_mode(true)
	await physics_frame
	var orbit_centered: bool = player._rig.global_position.distance_to(
			player.body.center_of_mass_global()) < 0.02
	var orbit_enabled: bool = is_equal_approx(player._spring.spring_length,
			player.ORBIT_SPRING_LENGTH)

	var orbit_view: Vector3 = player._camera.global_position
	player.set_paint_mode(false)
	await physics_frame
	var fly_enabled: bool = is_zero_approx(player._spring.spring_length)
	var orbit_to_fly_continuous: bool = player._camera.global_position.distance_to(
			orbit_view) < 0.25
	var fly_start: Vector3 = player._rig.global_position
	Input.action_press("move_forward")
	for i in 10:
		await physics_frame
	Input.action_release("move_forward")
	var fly_moved: bool = player._rig.global_position.distance_to(fly_start) > 0.25

	player.set_ragdoll(false)
	var follow_restored: bool = is_equal_approx(player._spring.spring_length,
			player.ORBIT_SPRING_LENGTH) and player._rig.position.is_equal_approx(
			player.NORMAL_CAMERA_PIVOT)
	print("ragdoll torso y=%.3f, up-dot=%.3f" % [torso_y, torso_up_dot])
	print("momentum inherited=%s, continued forward=%s (%.2fm)" % [momentum_inherited,
			continued_forward, mass_center_travel.dot(travel_direction)])
	print("camera initial=%s, orbit=%s, fly=%s, transition=%s, moved=%s, restored=%s" % [
			initial_fly_continuous, orbit_centered and orbit_enabled, fly_enabled,
			orbit_to_fly_continuous, fly_moved, follow_restored])
	quit(0 if laid_down and tilted and momentum_inherited and continued_forward \
			and initial_fly_continuous and orbit_centered \
			and orbit_enabled and fly_enabled and orbit_to_fly_continuous and fly_moved \
			and follow_restored else 1)
