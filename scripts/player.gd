extends CharacterBody3D
## One player. The peer whose id matches the node name has input authority and
## simulates movement; everyone else lerps toward synced transforms. Painting
## replicates as tiny splat RPCs; shooting is requested from the server.

const SPEED := 5.0
const CROUCH_SPEED := 2.4
const JUMP_VELOCITY := 4.6
const WALL_CLIMB_SPEED := 2.5
const FLY_SPEED := 8.0
const UNSTUCK_HOLD_SECONDS := 1.25
const UNSTUCK_COOLDOWN_SECONDS := 10.0
const MOUSE_SENS := 0.0025
const SYNC_INTERVAL := 0.05
const PAINT_MIN_STEP := 0.35  ## of brush radius: cursor travel before restamping
const PAINT_MAX_GAP := 0.35   ## m: bigger jumps between samples aren't connected
const PAINT_RANGE := 4.0
const SHOOT_RANGE := 60.0
const NORMAL_CAMERA_PIVOT := Vector3(0, 1.45, 0)
const ORBIT_SPRING_LENGTH := 2.6
const CAMERA_LOCAL_OFFSET := Vector3(0, 0, 0.1)

var peer_id := 1
var display_name := "?"
var role: int = MatchState.Role.NONE
var phase: int = MatchState.Phase.LOBBY
var eliminated := false
var current_color := Color("b5493a")
var brush_radius := 0.09
var ammo := 0
var shot_cooldown_left := 0.0
var frozen := true  ## nobody moves until the first phase broadcast
var paint_mode := false  ## F: cursor visible, click your body to paint
var ragdolled := false  ## R/HUD button: release the articulated paintable rig
var ui_blocked := false  ## pause menu open: swallow all gameplay input
var respawn_position := Vector3.ZERO  ## assigned match spawn; fall recovery target

var body: PaintableBody
var _rig: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _nameplate: Label3D
var _collision: CollisionShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _sync_timer := 0.0
var _stroke_active := false  ## LMB held and last sample hit our body
var _stroke_last := Vector3.ZERO  ## body-space point of the last stamp
var _paint_sound_timer := 0.0
var _footstep_timer := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_crouch := false
var _yaw_rate := 0.0  ## most recent local turn speed, inherited by ragdoll pieces
var look_dir := Vector3.FORWARD  ## synced; server uses it for LoS cones
var _unstuck_hold := 0.0
var _unstuck_cooldown := 0.0

var _snd_paint: AudioStreamPlayer3D
var _snd_eyedrop: AudioStreamPlayer
var _footsteps: Array[AudioStream] = []
var _snd_foot: AudioStreamPlayer3D
var _last_foot_pos := Vector3.ZERO


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1

	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	_collision.shape = capsule
	_collision.position = Vector3(0, 0.85, 0)
	add_child(_collision)

	body = PaintableBody.new()
	body.name = "Body"
	add_child(body)
	var base := Color(0.13, 0.13, 0.16) if role == MatchState.Role.SEEKER else Color.WHITE
	body.build(peer_id, base)
	if role == MatchState.Role.SEEKER:
		_add_gun()

	_nameplate = Label3D.new()
	_nameplate.name = "Nameplate"
	_nameplate.text = display_name
	_nameplate.position = Vector3(0, 1.95, 0)
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.font_size = 48
	_nameplate.pixel_size = 0.004
	_nameplate.modulate = Color(1, 1, 1, 0.9)
	_nameplate.outline_size = 8
	add_child(_nameplate)

	_snd_paint = AudioStreamPlayer3D.new()
	_snd_paint.stream = load("res://assets/audio/paint.ogg")
	_snd_paint.volume_db = -6
	add_child(_snd_paint)
	_snd_foot = AudioStreamPlayer3D.new()
	_snd_foot.volume_db = -14
	add_child(_snd_foot)
	for i in 5:
		_footsteps.append(load("res://assets/audio/footstep_concrete_00%d.ogg" % i))

	_target_pos = position
	_last_foot_pos = position

	if is_local():
		_rig = Node3D.new()
		_rig.position = NORMAL_CAMERA_PIVOT
		add_child(_rig)
		_spring = SpringArm3D.new()
		_spring.spring_length = ORBIT_SPRING_LENGTH
		_spring.position = Vector3(0.35, 0, 0)  # slight over-shoulder offset
		_spring.collision_mask = 1
		_spring.add_excluded_object(get_rid())
		_rig.add_child(_spring)
		_camera = Camera3D.new()
		_camera.position = CAMERA_LOCAL_OFFSET
		_spring.add_child(_camera)
		_camera.make_current()
		_snd_eyedrop = AudioStreamPlayer.new()
		_snd_eyedrop.stream = load("res://assets/audio/eyedrop.ogg")
		add_child(_snd_eyedrop)
		_update_mouse_mode()


func _add_gun() -> void:
	var gun := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.1, 0.12, 0.7)
	gun.mesh = m
	gun.position = Vector3(0.34, 1.15, -0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	gun.material_override = mat
	add_child(gun)


## Called on every peer when the server broadcasts a phase change.
func on_phase(new_phase: int, extra: Dictionary) -> void:
	phase = new_phase
	if is_local():
		match phase:
			MatchState.Phase.PAINT:
				frozen = role == MatchState.Role.SEEKER
			MatchState.Phase.SEEK:
				frozen = false
				if role == MatchState.Role.SEEKER and extra.has("ammo"):
					ammo = extra["ammo"]
			MatchState.Phase.RESULTS:
				frozen = true
				set_ragdoll(false)


func set_nameplate_visible(v: bool) -> void:
	_nameplate.visible = v


func on_eliminated() -> void:
	set_ragdoll(false)
	eliminated = true
	body.visible = false
	body.set_parts_collidable(false)
	_nameplate.visible = false
	for child in get_children():
		if child is MeshInstance3D:  # the gun, if any
			child.visible = false
	collision_mask = 0  # spectators fly through everything


func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or ui_blocked:
		return
	if event is InputEventMouseMotion:
		# Free look while captured; in paint mode, orbit only while MMB is held
		# so the cursor can travel to the body without the camera chasing it.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_orbit(event.relative)
		elif paint_mode and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_orbit(event.relative)
	elif event.is_action_pressed("toggle_paint_mode"):
		if paint_mode:
			set_paint_mode(false)
		elif _can_paint():
			set_paint_mode(true)
	elif event.is_action_pressed("brush_grow"):
		brush_radius = minf(brush_radius + 0.02, 0.25)
	elif event.is_action_pressed("brush_shrink"):
		brush_radius = maxf(brush_radius - 0.02, 0.05)
	elif event.is_action_pressed("toggle_ragdoll"):
		toggle_ragdoll()
	elif event.is_action_pressed("eyedrop") and _can_paint():
		_eyedrop()


func _orbit(relative: Vector2) -> void:
	_rig.rotation.y -= relative.x * MOUSE_SENS
	_rig.rotation.x = clampf(_rig.rotation.x - relative.y * MOUSE_SENS, -1.2, 1.2)


func set_paint_mode(on: bool) -> void:
	if paint_mode == on:
		return
	paint_mode = on
	if ragdolled and is_local():
		if paint_mode:
			_enter_ragdoll_orbit_camera()
		else:
			_enter_ragdoll_fly_camera()
	_update_mouse_mode()


func set_ui_blocked(blocked: bool) -> void:
	ui_blocked = blocked
	if is_local():
		_update_mouse_mode()


func recover_to_spawn() -> void:
	if ragdolled and body != null:
		set_ragdoll(false)
	position = respawn_position
	velocity = Vector3.ZERO
	_target_pos = respawn_position
	_stroke_active = false


func recover_from_fall() -> void:
	recover_to_spawn()


func _update_mouse_mode() -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE if ui_blocked or paint_mode
		else Input.MOUSE_MODE_CAPTURED
	)


func _physics_process(delta: float) -> void:
	if is_local():
		var used_unstuck := _update_unstuck(delta)
		if ragdolled and paint_mode:
			# The physics rig can keep sliding after it lands. Track its current
			# mass center so paint-mode orbit never drifts away from the body.
			_rig.global_position = body.center_of_mass_global()
		var yaw_before := rotation.y
		if not used_unstuck:
			_local_move(delta)
		if not ragdolled:
			_yaw_rate = clampf(wrapf(rotation.y - yaw_before, -PI, PI) / maxf(delta, 0.001),
					-12.0, 12.0)
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer = 0.0
			look_dir = -_camera.global_transform.basis.z
			var pose: Array = body.capture_pose() if ragdolled else []
			rpc(&"sync_state", position, rotation.y, look_dir,
					Input.is_action_pressed("crouch") and not ragdolled, ragdolled, pose)
	else:
		position = position.lerp(_target_pos, minf(1.0, 14.0 * delta))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, 14.0 * delta))
		if ragdolled:
			body.interpolate_remote_pose(delta)
		else:
			body.scale.y = move_toward(body.scale.y, 0.62 if _target_crouch else 1.0, 3.0 * delta)
		_remote_footsteps(delta)


func _process(delta: float) -> void:
	if not is_local():
		return
	shot_cooldown_left = maxf(0.0, shot_cooldown_left - delta)
	_paint_sound_timer = maxf(0.0, _paint_sound_timer - delta)
	if paint_mode and not _can_paint():
		set_paint_mode(false)  # eliminated or phase ended mid-painting
	if ui_blocked or not Input.is_action_pressed("primary_action"):
		_stroke_active = false  # stroke ends when LMB lifts or the menu opens
	if ui_blocked:
		return
	if paint_mode:
		if Input.is_action_pressed("primary_action"):
			_paint_sample(get_viewport().get_mouse_position())
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_pressed("primary_action"):
			if _can_paint():
				_paint_sample(get_viewport().get_visible_rect().size / 2.0)
			elif _can_shoot() and Input.is_action_just_pressed("primary_action"):
				_try_shoot()


func _local_move(delta: float) -> void:
	if eliminated:
		if not ui_blocked:
			_fly_move(delta)
		return
	if ragdolled:
		velocity = Vector3.ZERO
		if not paint_mode and not ui_blocked:
			_ragdoll_fly_camera(delta)
		return
	if frozen or ui_blocked:
		# No input, but keep gravity so opening the menu mid-jump can't hover.
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return
	var crouching := Input.is_action_pressed("crouch")
	body.scale.y = move_toward(body.scale.y, 0.62 if crouching else 1.0, 3.0 * delta)

	velocity.y = vertical_velocity_for_movement(
			velocity.y, is_on_floor(), is_on_wall(),
			Input.is_action_pressed("jump"), Input.is_action_just_pressed("jump"),
			crouching, _gravity, delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_yaw := _rig.global_rotation.y
	var dir := (Basis(Vector3.UP, cam_yaw) * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := CROUCH_SPEED if crouching else SPEED
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		# The body turns to face travel direction. The camera rig is a child of
		# this rotating root, so counter-rotate it by the same delta — otherwise
		# the view spins with the body and feeds back into the move direction.
		var new_yaw := lerp_angle(rotation.y, yaw_for_travel(dir), minf(1.0, 10.0 * delta))
		_rig.rotation.y -= wrapf(new_yaw - rotation.y, -PI, PI)
		rotation.y = new_yaw
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()
	_local_footsteps(delta)


## Character meshes and the gun are authored facing Godot's -Z forward axis.
## Convert horizontal travel to a root yaw without adding a half-turn, which
## would make the character appear to walk backward while movement stayed
## camera-relative.
static func yaw_for_travel(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Holding jump supplies a steady climb only while airborne and touching a
## wall. There is intentionally no duration limit: losing wall contact or
## releasing jump immediately returns the character to ordinary gravity.
static func vertical_velocity_for_movement(current: float, on_floor: bool,
		on_wall: bool, jump_pressed: bool, jump_just_pressed: bool,
		crouching: bool, gravity: float, delta: float) -> float:
	if on_wall and not on_floor and jump_pressed and not crouching:
		return WALL_CLIMB_SPEED
	if not on_floor:
		return current - gravity * delta
	if jump_just_pressed and not crouching:
		return JUMP_VELOCITY
	return current


## Hold-to-confirm keeps an accidental key tap from abandoning a good hiding
## spot. Frozen players cannot use this to leave the seeker waiting area.
func _update_unstuck(delta: float) -> bool:
	_unstuck_cooldown = maxf(0.0, _unstuck_cooldown - delta)
	var allowed := not eliminated and not frozen and not ui_blocked \
			and _unstuck_cooldown <= 0.0
	if not allowed or not Input.is_action_pressed("unstuck"):
		_unstuck_hold = 0.0
		return false
	_unstuck_hold += delta
	if _unstuck_hold < UNSTUCK_HOLD_SECONDS:
		return false
	_unstuck_hold = 0.0
	_unstuck_cooldown = UNSTUCK_COOLDOWN_SECONDS
	recover_to_spawn()
	return true


func _fly_move(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up_down := 0.0
	if Input.is_action_pressed("jump"):
		up_down += 1.0
	if Input.is_action_pressed("crouch"):
		up_down -= 1.0
	var dir := (_camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	dir.y += up_down
	velocity = dir.normalized() * FLY_SPEED if dir.length() > 0.1 else Vector3.ZERO
	move_and_slide()


func _ragdoll_fly_camera(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up_down := 0.0
	if Input.is_action_pressed("jump"):
		up_down += 1.0
	if Input.is_action_pressed("crouch"):
		up_down -= 1.0
	var dir := _camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	dir += Vector3.UP * up_down
	if dir.length_squared() > 0.01:
		_rig.global_position += dir.normalized() * FLY_SPEED * delta


func _local_footsteps(delta: float) -> void:
	_footstep_timer -= delta
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 1.0 and _footstep_timer <= 0.0:
		_footstep_timer = 0.38
		_play_footstep()


func _remote_footsteps(delta: float) -> void:
	_footstep_timer -= delta
	var moved := position.distance_to(_last_foot_pos)
	if moved > 0.02 and _footstep_timer <= 0.0 and not eliminated:
		_footstep_timer = 0.38
		_play_footstep()
	_last_foot_pos = position


func _play_footstep() -> void:
	_snd_foot.stream = _footsteps[randi() % _footsteps.size()]
	_snd_foot.play()


# --- painting ---------------------------------------------------------------

func _can_paint() -> bool:
	return (
		role == MatchState.Role.HIDER and not eliminated
		and (phase == MatchState.Phase.PAINT or phase == MatchState.Phase.SEEK)
	)


func _can_shoot() -> bool:
	return (
		role == MatchState.Role.SEEKER and not eliminated
		and phase == MatchState.Phase.SEEK
		and shot_cooldown_left <= 0.0 and ammo > 0
	)


func _can_ragdoll() -> bool:
	return role == MatchState.Role.HIDER and not eliminated and not frozen \
			and (phase == MatchState.Phase.PAINT or phase == MatchState.Phase.SEEK)


func toggle_ragdoll() -> void:
	if ragdolled:
		set_ragdoll(false)
	elif _can_ragdoll():
		set_ragdoll(true)


func set_ragdoll(active: bool) -> void:
	if ragdolled == active or body == null:
		return
	# Capture motion before the CharacterBody stops. Every released segment gets
	# the same translational velocity plus the point velocity created by turning.
	var inherited_velocity := velocity if active and is_local() else Vector3.ZERO
	var inherited_angular_velocity := (
			Vector3.UP * _yaw_rate if active and is_local() else Vector3.ZERO)
	ragdolled = active
	body.scale = Vector3.ONE
	velocity = Vector3.ZERO
	if _collision != null:
		_collision.set_deferred("disabled", active)
	body.set_ragdoll(active, is_local(), inherited_velocity, inherited_angular_velocity)
	if is_local():
		if active:
			if paint_mode:
				_enter_ragdoll_orbit_camera()
			else:
				_enter_ragdoll_fly_camera()
		else:
			_restore_follow_camera()


func _enter_ragdoll_fly_camera() -> void:
	# Collapse the spring arm without moving the view. From here the camera rig
	# itself is translated by WASD/Space/C, independently of the player root.
	var view_transform := _camera.global_transform
	_spring.spring_length = 0.0
	# SpringArm moves direct children to its hit distance. Reset its child to
	# the zero-length offset now so our preserved-view calculation also matches
	# the transform it will have on the next physics tick.
	_camera.position = CAMERA_LOCAL_OFFSET
	var camera_offset := _spring.position + _spring.transform.basis * _camera.position
	_rig.global_position = view_transform.origin - view_transform.basis * camera_offset


func _enter_ragdoll_orbit_camera() -> void:
	_spring.spring_length = ORBIT_SPRING_LENGTH
	_rig.global_position = body.center_of_mass_global()


func _restore_follow_camera() -> void:
	_spring.spring_length = ORBIT_SPRING_LENGTH
	_rig.position = NORMAL_CAMERA_PIVOT


## Sample the brush under a screen point (cursor or crosshair) every frame
## while LMB is held. Consecutive hits are joined into a stroke: stamps fill
## the segment between them, so fast drags paint lines instead of dots.
func _paint_sample(screen_point: Vector2) -> void:
	var hit := _screen_ray(screen_point, PAINT_RANGE, PaintableBody.PAINT_LAYER, [])
	if hit.is_empty():
		_stroke_active = false
		return
	var collider: Object = hit["collider"]
	if not collider.has_meta("peer_id") or int(collider.get_meta("peer_id")) != peer_id:
		_stroke_active = false
		return  # you can only paint yourself
	var local_pos: Vector3 = body.global_transform.affine_inverse() * Vector3(hit["position"])
	if not _stroke_active:
		_stroke_active = true
		_stroke_last = local_pos
		rpc(&"apply_stroke", local_pos, local_pos, current_color, brush_radius)
		return
	var gap := _stroke_last.distance_to(local_pos)
	if gap < brush_radius * PAINT_MIN_STEP:
		return  # holding still: nothing new to paint, no RPC spam
	# Big jumps (cursor flicked across the body, or skimmed off an edge and
	# back on) get a fresh stamp, not a line drawn through the torso.
	var from := _stroke_last if gap <= PAINT_MAX_GAP else local_pos
	rpc(&"apply_stroke", from, local_pos, current_color, brush_radius)
	_stroke_last = local_pos


## On-screen pixel radius of the brush at the cursor: measured against the
## surface under the cursor, or the body's center mass when off-body.
func brush_cursor_px(screen_point: Vector2) -> float:
	var hit := _screen_ray(screen_point, PAINT_RANGE, PaintableBody.PAINT_LAYER, [])
	var ref: Vector3 = (
		Vector3(hit["position"]) if not hit.is_empty()
		else body.center_of_mass_global() if ragdolled
		else body.global_transform * Vector3(0, 1.0, 0)
	)
	var right: Vector3 = _camera.global_transform.basis.x
	return _camera.unproject_position(ref).distance_to(
			_camera.unproject_position(ref + right * brush_radius))


@rpc("authority", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector3, yaw: float, look: Vector3, crouching: bool,
		rigidbody_active: bool, ragdoll_pose: Array) -> void:
	_target_pos = pos
	_target_yaw = yaw
	look_dir = look
	_target_crouch = crouching
	if ragdolled != rigidbody_active:
		set_ragdoll(rigidbody_active)
	if rigidbody_active:
		body.set_remote_pose(ragdoll_pose)


@rpc("authority", "call_local", "reliable")
func apply_stroke(from_pos: Vector3, to_pos: Vector3, color: Color, radius: float) -> void:
	body.stroke(from_pos, to_pos, color, radius)
	if _paint_sound_timer <= 0.0:
		_paint_sound_timer = 0.15
		_snd_paint.pitch_scale = randf_range(0.9, 1.15)
		_snd_paint.play()


## Sample the actual rendered pixel at the crosshair (or under the cursor in
## paint mode) — matches whatever you see, lighting included.
func _eyedrop() -> void:
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		return
	var pt := vp.get_mouse_position() if paint_mode else vp.get_visible_rect().size / 2.0
	var uv := pt / vp.get_visible_rect().size
	var c := img.get_pixel(
			clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1),
			clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
	c.a = 1.0
	current_color = c
	_snd_eyedrop.play()


# --- shooting ---------------------------------------------------------------

func _try_shoot() -> void:
	shot_cooldown_left = App.settings["shot_cooldown"]
	ammo -= 1  # local prediction; server broadcast is authoritative for effects
	var origin := _camera.project_ray_origin(get_viewport().get_visible_rect().size / 2.0)
	var dir := _camera.project_ray_normal(get_viewport().get_visible_rect().size / 2.0)
	Net.request_shot(origin, dir)


func _screen_ray(screen_point: Vector2, range_m: float, mask: int, exclude: Array) -> Dictionary:
	var origin := _camera.project_ray_origin(screen_point)
	var dir := _camera.project_ray_normal(screen_point)
	var params := PhysicsRayQueryParameters3D.create(
			origin, origin + dir * range_m, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(params)
