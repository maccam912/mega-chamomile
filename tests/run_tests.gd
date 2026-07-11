extends SceneTree
## Headless test suite for the pure match logic.
## Run from the project root:  godot --headless -s tests/run_tests.gd
## Exits 0 on success, 1 on any failure.

const MatchStateScript := preload("res://scripts/match_state.gd")
const PaintableBodyScript := preload("res://scripts/paintable_body.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	test_role_assignment()
	test_full_match_hiders_survive()
	test_sweep_seekers_win()
	test_ammo_and_cooldown()
	test_bold_scoring()
	test_disconnect_wins()
	test_solo_mode()
	test_paint_splat()

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
	var raw: float = ms.players[hider]["score"]
	# 2s * 1/s survival + 1s * 3/s bold = 5
	check(absf(raw - 5.0) < 0.11, "1s spotted of 2s = 5 points (got %.2f)" % raw)


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
	check(body.part_meshes.size() == 6, "humanoid has 6 paintable parts")
	var total := 0
	for i in 6:
		total += body._part_positions[i].size()
	check(total > 1000, "subdivided body has real vertex density (%d verts)" % total)

	# Splat red on the front of the head (part 5, local body-space point).
	var head_center: Vector3 = PaintableBodyScript.PARTS[5]["pos"]
	var front := head_center + Vector3(0, 0, -0.18)
	body.splat(5, front, Color.RED, 0.1)
	var colors: PackedColorArray = body._part_colors[5]
	var verts: PackedVector3Array = body._part_positions[5]
	var painted := 0
	var back_painted := 0
	for i in verts.size():
		if colors[i].r > 0.9 and colors[i].g < 0.5:
			painted += 1
			if verts[i].z > 0.1:  # back of the head, part-local space
				back_painted += 1
	check(painted > 0, "splat painted vertices near the hit (%d)" % painted)
	check(back_painted == 0, "back of the head stayed white")

	body.fill_all(Color.BLUE)
	check(body._part_colors[0][0].is_equal_approx(Color.BLUE), "fill_all recolors everything")
	body.free()
