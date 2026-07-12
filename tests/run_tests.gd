extends SceneTree
## Headless test suite for the pure match logic.
## Run from the project root:  godot --headless -s tests/run_tests.gd
## Exits 0 on success, 1 on any failure.

const MatchStateScript := preload("res://scripts/match_state.gd")
const SessionStateScript := preload("res://scripts/session_state.gd")
const PaintableBodyScript := preload("res://scripts/paintable_body.gd")
const AppScript := preload("res://autoload/app.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	test_role_assignment()
	test_full_match_hiders_survive()
	test_sweep_seekers_win()
	test_ammo_and_cooldown()
	test_bold_scoring()
	test_score_breakdown()
	test_session_scoring_and_replay()
	test_disconnect_wins()
	test_solo_mode()
	test_paint_splat()
	test_paint_stroke()
	test_articulated_ragdoll()
	test_hud_passes_mouse_through()
	test_travel_facing()
	test_wall_climb()
	test_unstuck_action()
	test_fall_recovery()
	test_map_selection()

	print("")
	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _checks)
	else:
		print("%d FAILURE(S) out of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  ok  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _make(n_players: int, seeker_count: int, cfg := {}) -> MatchState:
	var ms: MatchState = MatchStateScript.new()
	var defaults := {"paint_time": 5.0, "seek_time": 10.0, "results_time": 2.0}
	defaults.merge(cfg, true)
	ms.configure(defaults)
	for i in n_players:
		ms.add_player(i + 1, "P%d" % (i + 1))
	ms.assign_roles(seeker_count, 42)
	return ms


func _tick_until(ms: MatchState, phase: int, max_seconds := 300.0) -> bool:
	var t := 0.0
	while ms.phase != phase and t < max_seconds:
		ms.tick(0.1)
		t += 0.1
	return ms.phase == phase


func test_role_assignment() -> void:
	print("role assignment:")
	var ms := _make(5, 2)
	check(ms.seekers().size() == 2, "2 of 5 players become seekers")
	check(ms.hiders().size() == 3, "3 of 5 players stay hiders")
	var ms2 := _make(5, 2)
	check(ms2.seekers() == ms.seekers(), "same seed gives same roles")
	var ms3 := _make(4, 99)
	check(ms3.seekers().size() == 3, "seeker count clamps to players-1")


func test_full_match_hiders_survive() -> void:
	print("full match, timer expiry (hiders win):")
	var ms := _make(4, 1)
	ms.start()
	check(ms.phase == MatchState.Phase.PAINT, "starts in PAINT")
	check(_tick_until(ms, MatchState.Phase.SEEK), "PAINT rolls into SEEK")
	var ammo_expected: int = ms.cfg["ammo_per_hider"] * 3
	check(ms.ammo_of(ms.seekers()[0]) == ammo_expected, "seeker ammo = 3x hiders")
	check(_tick_until(ms, MatchState.Phase.RESULTS), "SEEK times out into RESULTS")
	check(ms.winner == MatchState.Team.HIDERS, "hiders win on timeout")
	var hider_id: int = ms.hiders()[0]
	var score: int = 0
	for row: Dictionary in ms.scores_snapshot():
		if row["id"] == hider_id:
			score = row["score"]
	# ~10s survival @1/s + 75 survive bonus = ~85
	check(score >= 84 and score <= 86, "hider score = survival + bonus (got %d)" % score)
	check(_tick_until(ms, MatchState.Phase.DONE), "RESULTS rolls into DONE")


func test_sweep_seekers_win() -> void:
	print("sweep (seekers find everyone):")
	var ms := _make(4, 1)
	ms.start()
	_tick_until(ms, MatchState.Phase.SEEK)
	var seeker: int = ms.seekers()[0]
	var victims: Array = ms.hiders()
	for v: int in victims:
		ms.tick(1.0)  # let the cooldown clear between shots
		check(ms.consume_shot(seeker), "shot allowed at hider %d" % v)
		check(ms.report_hit(seeker, v), "hit eliminates hider %d" % v)
	check(ms.phase == MatchState.Phase.RESULTS, "round ends when last hider falls")
	check(ms.winner == MatchState.Team.SEEKERS, "seekers win the sweep")
	var seeker_score: int = ms.scores_snapshot()[0]["score"]
	# 3 kills * 100 + 50 sweep bonus
	check(seeker_score == 350, "seeker score = kills + sweep bonus (got %d)" % seeker_score)
	check(ms.report_hit(seeker, victims[0]) == false, "dead hiders can't die twice")


func test_ammo_and_cooldown() -> void:
	print("ammo + cooldown:")
	var ms := _make(2, 1, {"ammo_per_hider": 2, "shot_cooldown": 1.0})
	ms.start()
	_tick_until(ms, MatchState.Phase.SEEK)
	var seeker: int = ms.seekers()[0]
	check(ms.consume_shot(seeker), "first shot fires")
	check(not ms.consume_shot(seeker), "second shot blocked by cooldown")
	ms.tick(1.1)
	check(ms.consume_shot(seeker), "shot fires after cooldown")
	ms.tick(1.1)
	check(not ms.consume_shot(seeker), "out of ammo (2 per hider, 1 hider)")
	var hider: int = ms.hiders()[0]
	check(not ms.consume_shot(hider), "hiders can never shoot")


func test_bold_scoring() -> void:
	print("bold (line-of-sight) scoring:")
	var ms := _make(2, 1, {"seek_time": 100.0})
	ms.start()
	_tick_until(ms, MatchState.Phase.SEEK)
	var hider: int = ms.hiders()[0]
	for i in 10:  # 1s hidden
		ms.tick(0.1)
	ms.set_in_sight(hider, true)
	for i in 10:  # 1s in sight
		ms.tick(0.1)
	ms.set_in_sight(hider, false)
	var raw: float = ms.score_of(hider)
	# 2s * 1/s survival + 1s * 3/s bold = 5
	check(absf(raw - 5.0) < 0.11, "1s spotted of 2s = 5 points (got %.2f)" % raw)


func test_score_breakdown() -> void:
	print("score breakdown:")
	# 1 seeker, 2 hiders: spot one hider for 1s, eliminate the other, then let
	# the timer expire so the surviving hider also collects the survive bonus.
	var ms := _make(3, 1, {"seek_time": 10.0})
	ms.start()
	_tick_until(ms, MatchState.Phase.SEEK)
	var seeker: int = ms.seekers()[0]
	var survivor: int = ms.hiders()[0]
	var victim: int = ms.hiders()[1]
	ms.set_in_sight(survivor, true)
	for i in 10:  # 1s in sight
		ms.tick(0.1)
	ms.set_in_sight(survivor, false)
	ms.consume_shot(seeker)
	ms.report_hit(seeker, victim)
	check(_tick_until(ms, MatchState.Phase.RESULTS), "round times out into RESULTS")
	check(ms.winner == MatchState.Team.HIDERS, "one hider survived: hiders win")
	for row: Dictionary in ms.scores_snapshot():
		var component_sum: int = row["survival"] + row["bold"] + row["kill_points"] + row["bonus"]
		check(absi(component_sum - row["score"]) <= 1,
				"%s breakdown sums to total (%d ~ %d)" % [row["name"], component_sum, row["score"]])
		if row["id"] == seeker:
			check(row["kills"] == 1 and row["kill_points"] == 100,
					"seeker breakdown shows 1 find worth 100")
			check(row["bonus"] == 0, "no sweep bonus when a hider survives")
		elif row["id"] == survivor:
			check(row["bold"] == 3, "survivor earned 1s of bold points (got %d)" % row["bold"])
			check(row["survival"] == 10, "survivor earned 10s of survival (got %d)" % row["survival"])
			check(row["bonus"] == 75, "survivor got the survive bonus")
		elif row["id"] == victim:
			check(row["bonus"] == 0 and not row["alive"], "found hider gets no bonus")


func test_session_scoring_and_replay() -> void:
	print("session scoring + replay readiness:")
	var session: RefCounted = SessionStateScript.new()
	session.reset([1, 2])
	var first: Array = session.record_round([
		{"id": 1, "score": 20},
		{"id": 2, "score": 10},
	])
	check(first[0]["round_score"] == 20 and first[0]["session_score"] == 20,
			"first results include round and session totals")
	var second: Array = session.record_round([
		{"id": 1, "score": 5},
		{"id": 2, "score": 30},
	])
	check(second[0]["id"] == 2 and second[0]["session_score"] == 40,
			"later rounds accumulate and sort by session total")
	check(second[1]["session_score"] == 25 and session.rounds_played == 2,
			"session total preserves earlier round points")

	session.begin_replay_vote([1, 2])
	check(not session.all_replay_ready([1, 2]), "replay begins with everyone unready")
	check(session.set_replay_ready(1, true), "connected player can ready up")
	check(not session.all_replay_ready([1, 2]), "one ready player cannot start a full replay")
	session.set_replay_ready(2, true)
	check(session.all_replay_ready([1, 2]), "replay unlocks when every player is ready")
	session.remove_player(2)
	check(not session.totals.has(2), "disconnect removes score identity instead of allowing inheritance")


func test_disconnect_wins() -> void:
	print("disconnect handling:")
	var ms := _make(3, 1)
	ms.start()
	_tick_until(ms, MatchState.Phase.SEEK)
	var seeker: int = ms.seekers()[0]
	ms.remove_player(seeker)
	check(ms.phase == MatchState.Phase.RESULTS and ms.winner == MatchState.Team.HIDERS,
			"all seekers leaving hands hiders the win")

	var ms2 := _make(3, 1)
	ms2.start()
	_tick_until(ms2, MatchState.Phase.SEEK)
	for h: int in ms2.hiders():
		ms2.remove_player(h)
	check(ms2.phase == MatchState.Phase.RESULTS and ms2.winner == MatchState.Team.SEEKERS,
			"all hiders leaving hands seekers the win")


func test_solo_mode() -> void:
	print("solo test mode (1 player, 0 seekers):")
	var ms := _make(1, 1)
	check(ms.seekers().size() == 0, "solo player is never a seeker")
	ms.start()
	check(_tick_until(ms, MatchState.Phase.SEEK), "solo reaches SEEK")
	check(_tick_until(ms, MatchState.Phase.RESULTS), "solo reaches RESULTS")
	check(ms.winner == MatchState.Team.HIDERS, "solo survivor wins")


func test_paint_splat() -> void:
	print("paintable body splats:")
	var body: PaintableBody = PaintableBodyScript.new()
	body.build(1, Color.WHITE)
	check(body.part_meshes.size() == 11, "humanoid has 11 articulated paintable parts")
	var paint_material := body.part_meshes[0].material_override as StandardMaterial3D
	check(paint_material.vertex_color_is_srgb,
			"paint vertex colors use sRGB so eyedropped colors do not render brighter")
	var total := 0
	for i in body.part_meshes.size():
		total += body._part_positions[i].size()
	check(total > 1000, "subdivided body has real vertex density (%d verts)" % total)

	# Splat red on the front of the head along the camera ray. The cylindrical
	# footprint must reach matching vertices on the hidden back face.
	var head_idx := body.part_index("Head")
	var head_center: Vector3 = PaintableBodyScript.PARTS[head_idx]["pos"]
	var front := head_center + Vector3(0, 0, -0.18)
	body.splat_at(front, Color.RED, 0.1, Vector3.BACK)
	var painted := _count_painted(body, head_idx, Color.RED)
	var back_painted := 0
	var back_outside_footprint := 0
	var colors: PackedColorArray = body._part_colors[head_idx]
	var verts: PackedVector3Array = body._part_positions[head_idx]
	for i in verts.size():
		if colors[i].r > 0.9 and colors[i].g < 0.5 and verts[i].z > 0.1:
			back_painted += 1  # back of the head, part-local space
		elif colors[i].is_equal_approx(Color.WHITE) and verts[i].z > 0.1 \
				and Vector2(verts[i].x, verts[i].y).length() > 0.12:
			back_outside_footprint += 1
	check(painted > 0, "splat painted vertices near the hit (%d)" % painted)
	check(back_painted > 0, "through-body splat painted the hidden back face")
	check(back_outside_footprint > 0,
			"back-face vertices outside the brush footprint stayed white")
	check(_count_painted(body, body.part_index("LowerLegL"), Color.RED) == 0,
			"through-body splat did not spill onto an unrelated part")

	body.fill_all(Color.BLUE)
	check(body._part_colors[0][0].is_equal_approx(Color.BLUE), "fill_all recolors everything")
	body.free()


func _count_painted(body: PaintableBody, part_idx: int, color: Color) -> int:
	var n := 0
	for c: Color in body._part_colors[part_idx]:
		if _colors_close(c, color):
			n += 1
	return n


func _colors_close(a: Color, b: Color, tolerance := 0.3) -> bool:
	return Vector4(a.r, a.g, a.b, a.a).distance_to(
			Vector4(b.r, b.g, b.b, b.a)) < tolerance


func test_paint_stroke() -> void:
	print("paint strokes:")
	var body: PaintableBody = PaintableBodyScript.new()
	body.build(1, Color.WHITE)

	# Drag across the torso front: endpoints 0.4m apart with a 0.06 brush.
	# Only stroke interpolation can reach the midpoint.
	var torso_idx := body.part_index("Torso")
	var arm_idx := body.part_index("UpperArmR")
	var torso: Vector3 = PaintableBodyScript.PARTS[torso_idx]["pos"]
	body.stroke(torso + Vector3(-0.2, 0.1, -0.14), torso + Vector3(0.2, 0.1, -0.14),
			Color.RED, 0.06, Vector3.BACK)
	var colors: PackedColorArray = body._part_colors[torso_idx]
	var verts: PackedVector3Array = body._part_positions[torso_idx]
	var mid_painted := 0
	for i in verts.size():
		if _colors_close(colors[i], Color.RED) and absf(verts[i].x) < 0.05 \
				and verts[i].z < -0.1:
			mid_painted += 1
	check(mid_painted > 0, "stroke filled in between the endpoints (%d mid verts)" % mid_painted)

	# A stamp at the torso/arm boundary paints both parts — no seams.
	body.splat_at(Vector3(0.26, 1.15, -0.11), Color.GREEN, 0.08, Vector3.BACK)
	check(_count_painted(body, torso_idx, Color.GREEN) > 0, "boundary stamp reached the torso")
	check(_count_painted(body, arm_idx, Color.GREEN) > 0, "boundary stamp reached the right arm")
	body.free()


func test_articulated_ragdoll() -> void:
	print("articulated ragdoll:")
	var body: PaintableBody = PaintableBodyScript.new()
	body.build(7, Color.WHITE)
	check(body.joints.size() == 10, "rig connects 11 pieces with 10 joints")
	for joint_name in ["ElbowL", "ElbowR", "KneeL", "KneeR", "Waist"]:
		check(body.get_node_or_null(joint_name) != null, "%s joint exists" % joint_name)
	body.set_ragdoll(true, false)
	check(body.ragdolled, "ragdoll mode activates")
	check(body.part_bodies[0].top_level, "ragdoll pieces use world-space poses")
	var pose := body.capture_pose()
	check(pose.size() == body.part_bodies.size(), "network pose contains every body piece")
	body.set_ragdoll(false, false)
	check(not body.ragdolled and not body.part_bodies[0].top_level,
			"standing up restores the authored hierarchy")
	body.free()


func test_hud_passes_mouse_through() -> void:
	print("hud mouse filters:")
	# A STOP control at screen center (the crosshair) eats captured-mouse
	# motion before it reaches the player, killing camera orbit.
	var hud: CanvasLayer = load("res://scripts/hud.gd").new()
	# SceneTree's _initialize runs before newly attached nodes receive _ready,
	# so build the code-created HUD explicitly for this synchronous test.
	hud._ready()
	var bad: Array = []
	_collect_stop_controls(hud, bad)
	check(bad.is_empty(), "non-interactive HUD controls ignore mouse (offenders: %s)" % [bad])
	check(hud._ragdoll_button.mouse_filter == Control.MOUSE_FILTER_STOP,
			"ragdoll HUD button remains clickable")
	hud.set_paint_mode(true)
	hud.set_brush_cursor(Vector2(120, 80), 14.0, Color.CORAL)
	check(hud._brush_ring.visible, "paint mode shows the brush ring")
	check(hud._ring_pos == Vector2(120, 80) and is_equal_approx(hud._ring_px, 14.0),
			"brush ring tracks cursor position and projected radius")
	var rows := [
		{"id": 1, "name": "Hider", "role": MatchStateScript.Role.HIDER, "score": 88,
			"survival": 10, "bold": 3, "kills": 0, "kill_points": 0, "bonus": 75, "alive": true},
		{"id": 2, "name": "Seeker", "role": MatchStateScript.Role.SEEKER, "score": 100,
			"survival": 0, "bold": 0, "kills": 1, "kill_points": 100, "bonus": 0, "alive": true},
	]
	hud.show_results(rows, MatchStateScript.Team.HIDERS, 1, true)
	check(hud._score_breakdown(rows[0]) == "survival +10   bold +3   survived +75",
			"hider results row explains its score")
	check(hud._score_breakdown(rows[1]) == "found 1  +100",
			"seeker results row explains its score")
	check(hud._replay_ready_button != null and hud._replay_start_button != null,
			"results offer replay readiness and a host start action")
	hud.set_replay_readiness([1], 1, 2)
	check(hud._replay_start_button.disabled, "host cannot replay before everyone opts in")
	hud.set_replay_readiness([1, 2], 1, 2)
	check(not hud._replay_start_button.disabled, "host can replay once everyone opts in")
	bad.clear()
	_collect_stop_controls(hud, bad)
	check(bad.is_empty(), "results overlay ignores mouse too (offenders: %s)" % [bad])
	# Scores arrive before the RESULTS phase broadcast; the overlay must survive it.
	hud.on_phase(MatchStateScript.Phase.RESULTS, 3.0, MatchStateScript.Role.HIDER, {})
	check(hud._results.visible, "RESULTS phase change keeps the scoreboard visible")
	hud.on_phase(MatchStateScript.Phase.PAINT, 5.0, MatchStateScript.Role.HIDER, {})
	check(not hud._results.visible, "next round's PAINT phase clears the scoreboard")
	hud.free()


func _collect_stop_controls(node: Node, bad: Array) -> void:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and not node.has_meta("interactive_hud"):
		bad.append(node.name)
	for child in node.get_children():
		_collect_stop_controls(child, bad)


func test_travel_facing() -> void:
	print("travel facing:")
	var player_script := load("res://scripts/player.gd")
	for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var yaw: float = player_script.yaw_for_travel(dir)
		var facing := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		check(facing.is_equal_approx(dir),
				"character faces travel direction %s (got %s)" % [dir, facing])


func test_wall_climb() -> void:
	print("wall climb:")
	var player_script := load("res://scripts/player.gd")
	var climbing: float = player_script.vertical_velocity_for_movement(
			-3.0, false, true, true, false, false, 10.0, 0.1)
	check(is_equal_approx(climbing, player_script.WALL_CLIMB_SPEED),
			"holding jump against a wall climbs at the configured speed")
	var released: float = player_script.vertical_velocity_for_movement(
			climbing, false, true, false, false, false, 10.0, 0.1)
	check(is_equal_approx(released, climbing - 1.0),
			"releasing jump at the wall restores gravity")
	var open_air: float = player_script.vertical_velocity_for_movement(
			-3.0, false, false, true, false, false, 10.0, 0.1)
	check(is_equal_approx(open_air, -4.0),
			"holding jump without wall contact cannot climb")
	var jumped: float = player_script.vertical_velocity_for_movement(
			0.0, true, true, true, true, false, 10.0, 0.1)
	check(is_equal_approx(jumped, player_script.JUMP_VELOCITY),
			"Space still performs a normal jump from the floor")


func test_unstuck_action() -> void:
	print("unstuck action:")
	# SceneTree._initialize runs before the App autoload's deferred _ready, so
	# register runtime-created actions explicitly for synthetic input here.
	var app := AppScript.new()
	app._setup_input_map()
	check(InputMap.has_action("unstuck"), "unstuck input action is registered")
	var player = load("res://scripts/player.gd").new()
	player.frozen = false
	player.respawn_position = Vector3(8, 1, -8)
	player.position = Vector3(30, 2, 40)
	player.velocity = Vector3(2, -3, 4)
	player._target_pos = player.position
	Input.action_press("unstuck")
	player._update_unstuck(player.UNSTUCK_HOLD_SECONDS * 0.5)
	check(player.position != player.respawn_position,
			"partial unstuck hold does not teleport")
	player._update_unstuck(player.UNSTUCK_HOLD_SECONDS * 0.5)
	check(player.position == player.respawn_position,
			"full unstuck hold returns to assigned spawn")
	player.position = Vector3(20, 2, 20)
	player._update_unstuck(player.UNSTUCK_HOLD_SECONDS)
	check(player.position != player.respawn_position,
			"unstuck cooldown prevents an immediate repeat")
	Input.action_release("unstuck")
	player.free()
	app.free()


func test_fall_recovery() -> void:
	print("fall recovery:")
	var player: CharacterBody3D = load("res://scripts/player.gd").new()
	player.respawn_position = Vector3(8, 1, -8)
	player.position = Vector3(30, -25, 40)
	player.velocity = Vector3(2, -30, 4)
	player._target_pos = player.position
	player.recover_from_fall()
	check(player.position == player.respawn_position, "fallen player returns to assigned spawn")
	check(player.velocity == Vector3.ZERO, "fall recovery clears momentum")
	check(player._target_pos == player.respawn_position, "network interpolation target also resets")
	player.free()


func test_map_selection() -> void:
	print("map selection:")
	var app := AppScript.new()
	for map_id: String in app.MAPS:
		app.select_map(map_id)
		var scene := load(app.selected_map_scene()) as PackedScene
		check(scene != null, "%s map scene loads" % map_id)
		if scene == null:
			continue
		var instance := scene.instantiate()
		check(instance.has_method("hider_spawns"), "%s provides hider spawns" % map_id)
		check(instance.has_method("seeker_spawns"), "%s provides seeker spawns" % map_id)
		check(instance.has_method("set_seek_open"), "%s provides seek release hook" % map_id)
		check(not instance.hider_spawns().is_empty(), "%s has usable hider spawns" % map_id)
		check(not instance.seeker_spawns().is_empty(), "%s has usable seeker spawns" % map_id)
		if map_id == "empty":
			check(instance.get_node_or_null("Floor") != null, "empty map floor is authored in the scene")
		if map_id == "hallwyl_museum":
			var museum := instance.get_node_or_null("Museum")
			var concave_collision_count := 0
			if museum != null:
				for child in museum.get_children():
					if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
						concave_collision_count += 1
			check(concave_collision_count == 13,
					"Hallwyl Museum has 13 generated concave collision meshes")
		instance.free()
	app.select_map("not-a-map")
	check(app.settings["map_id"] == app.DEFAULT_MAP_ID, "unknown map falls back safely")
	app.free()
