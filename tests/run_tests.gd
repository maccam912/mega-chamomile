extends SceneTree
## Headless test suite for the pure match logic.
## Run from the project root:  godot --headless -s tests/run_tests.gd
## Exits 0 on success, 1 on any failure.

const MatchStateScript := preload("res://scripts/match_state.gd")
const SessionStateScript := preload("res://scripts/session_state.gd")
const PaintableBodyScript := preload("res://scripts/paintable_body.gd")
const AvatarCatalogScript := preload("res://scripts/avatar_catalog.gd")
const AppScript := preload("res://autoload/app.gd")
const LANAddressScript := preload("res://scripts/lan_address.gd")
const UIThemeScript := preload("res://scripts/ui_theme.gd")
const PaintBackdropScript := preload("res://scripts/paint_backdrop.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	test_role_assignment()
	test_full_match_hiders_survive()
	test_sweep_seekers_win()
	test_ammo_and_cooldown()
	test_ammo_exhaustion_ends_seek()
	test_match_settings()
	test_bold_scoring()
	test_score_breakdown()
	test_session_scoring_and_replay()
	test_role_skill_balancing()
	test_preference_aware_roles()
	test_hidden_readiness()
	test_disconnect_wins()
	test_solo_mode()
	test_avatar_contracts()
	test_balanced_avatar_scaling()
	test_paint_splat()
	test_paint_stroke()
	test_articulated_ragdoll()
	test_results_pose_preservation()
	test_results_mouse_release()
	test_ui_foundation()
	test_hud_passes_mouse_through()
	test_travel_facing()
	test_seek_hider_slowdown()
	test_follow_camera_rules()
	test_wall_climb()
	test_unstuck_action()
	test_fall_recovery()
	test_keep_out_volume()
	test_map_selection()
	test_lan_ip_selection()

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
	var defaults := {"paint_time": 5.0, "seek_time": 10.0, "reveal_time": 1.0}
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
	check(_tick_until(ms, MatchState.Phase.REVEAL), "SEEK times out into REVEAL")
	check(ms.winner == MatchState.Team.HIDERS, "hiders win on timeout")
	var hider_id: int = ms.hiders()[0]
	var score: int = 0
	for row: Dictionary in ms.scores_snapshot():
		if row["id"] == hider_id:
			score = row["score"]
	# ~10s survival @1/s + 75 survive bonus = ~85
	check(score >= 84 and score <= 86, "hider score = survival + bonus (got %d)" % score)
	check(ms.time_left > 0.0 and ms.time_left <= 1.0,
			"REVEAL uses its configured after-round duration")
	check(_tick_until(ms, MatchState.Phase.RESULTS), "REVEAL advances into RESULTS")
	var final_scores := ms.scores_snapshot()
	ms.tick(120.0)
	check(ms.phase == MatchState.Phase.RESULTS,
			"RESULTS remains open well beyond the old timeout")
	check(ms.time_left == 0.0, "RESULTS has no misleading countdown")
	check(ms.scores_snapshot() == final_scores,
			"final scores remain stable while RESULTS stays open")


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
	check(ms.phase == MatchState.Phase.REVEAL, "round reveal begins when last hider falls")
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


func test_ammo_exhaustion_ends_seek() -> void:
	print("ammo exhaustion:")
	var single := _make(2, 1, {"ammo_per_hider": 1, "seek_time": 100.0})
	single.start()
	_tick_until(single, MatchState.Phase.SEEK)
	var seeker: int = single.seekers()[0]
	check(single.consume_shot(seeker), "single seeker's final shot is accepted")
	check(single.phase == MatchState.Phase.SEEK,
			"consuming final ammo waits for the shot result")
	single.complete_shot()
	check(single.phase == MatchState.Phase.REVEAL
			and single.winner == MatchState.Team.HIDERS,
			"final-shot miss ends SEEK immediately with a hider win")

	var multiple := _make(3, 2, {"ammo_per_hider": 1, "shot_cooldown": 0.0})
	multiple.start()
	_tick_until(multiple, MatchState.Phase.SEEK)
	var seekers: Array = multiple.seekers()
	check(multiple.consume_shot(seekers[0]), "first seeker spends their final shot")
	multiple.complete_shot()
	check(multiple.phase == MatchState.Phase.SEEK,
			"one empty seeker does not end while another still has ammo")
	check(multiple.consume_shot(seekers[1]), "second seeker spends the last team shot")
	multiple.complete_shot()
	check(multiple.phase == MatchState.Phase.REVEAL
			and multiple.winner == MatchState.Team.HIDERS,
			"all seekers empty ends the round")

	var last_hit := _make(2, 1, {"ammo_per_hider": 1, "shot_cooldown": 0.0})
	last_hit.start()
	_tick_until(last_hit, MatchState.Phase.SEEK)
	seeker = last_hit.seekers()[0]
	var final_hider: int = last_hit.hiders()[0]
	last_hit.consume_shot(seeker)
	check(last_hit.report_hit(seeker, final_hider), "final shot can eliminate its target")
	last_hit.complete_shot()
	check(last_hit.phase == MatchState.Phase.REVEAL
			and last_hit.winner == MatchState.Team.SEEKERS,
			"final-shot sweep is not overwritten by ammo exhaustion")

	var roster := _make(4, 2, {"ammo_per_hider": 1, "shot_cooldown": 0.0})
	roster.start()
	_tick_until(roster, MatchState.Phase.SEEK)
	seekers = roster.seekers()
	while roster.ammo_of(seekers[0]) > 0:
		roster.consume_shot(seekers[0])
		roster.complete_shot()
	check(roster.phase == MatchState.Phase.SEEK,
			"empty seeker waits while a roster teammate has ammo")
	roster.remove_player(seekers[1])
	check(roster.phase == MatchState.Phase.REVEAL
			and roster.winner == MatchState.Team.HIDERS,
			"seeker disconnect re-evaluates remaining team ammo")


func test_match_settings() -> void:
	print("match settings:")
	var fixed := _make(4, 1, {"ammo_mode": "fixed", "ammo_per_seeker": 7})
	fixed.start()
	_tick_until(fixed, MatchState.Phase.SEEK)
	check(fixed.ammo_of(fixed.seekers()[0]) == 7,
			"fixed-ammo mode ignores the hider count")
	var app := AppScript.new()
	app.apply_match_settings({})
	check(app.settings["reveal_time"] == 10.0,
			"after-round reveal defaults to ten seconds")
	app.apply_match_settings({
		"map_id": "not-a-map", "paint_time": -5, "seek_time": 9999,
		"reveal_time": 999,
		"shot_cooldown": 0, "ammo_mode": "invalid", "ammo_per_seeker": 999,
		"survival_pps": 99, "kill_points": -1,
	})
	check(app.settings["map_id"] == app.DEFAULT_MAP_ID,
			"invalid replicated map falls back safely")
	check(app.settings["paint_time"] == 15.0 and app.settings["seek_time"] == 600.0
			and app.settings["reveal_time"] == 60.0,
			"phase durations clamp to safe limits")
	check(app.settings["shot_cooldown"] == 0.1
			and app.settings["ammo_per_seeker"] == 50,
			"weapon settings clamp to safe limits")
	check(app.settings["ammo_mode"] == "per_hider"
			and app.settings["survival_pps"] == 10.0
			and app.settings["kill_points"] == 0,
			"unknown modes and scoring values are normalized")
	app.apply_match_settings({"paint_time": 4.0, "seek_time": 6.0,
			"reveal_time": 0.25, "_fast_phases": true})
	check(app.settings["paint_time"] == 4.0 and app.settings["seek_time"] == 6.0
			and app.settings["reveal_time"] == 0.5,
			"explicit test-mode snapshots preserve fast phase durations")
	app.reset_match_settings()
	check(app.settings == app.DEFAULT_SETTINGS, "restore defaults resets every match rule")
	app.free()


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


func test_role_skill_balancing() -> void:
	print("role-specific skill ratings + size balancing:")
	var session: RefCounted = SessionStateScript.new()
	session.reset([])
	session.add_player(1, "One")
	session.add_player(2, "Two")

	var first: Array = session.record_round([
		{"id": 1, "score": 0, "role": MatchStateScript.Role.HIDER, "alive": false},
		{"id": 2, "score": 100, "role": MatchStateScript.Role.SEEKER, "alive": true},
	])
	var one: Dictionary = session.rating_snapshot(1)
	var two: Dictionary = session.rating_snapshot(2)
	check(one["hiding"] < session.DEFAULT_RATING and one["seeking"] == session.DEFAULT_RATING,
			"a caught hider loses hiding skill without changing seeking skill")
	check(two["seeking"] > session.DEFAULT_RATING and two["hiding"] == session.DEFAULT_RATING,
			"a successful seeker gains seeking skill without changing hiding skill")
	check(first[0].has("hiding_rating") and first[0].has("seeking_rating"),
			"results expose both updated ratings")
	check(session.balanced_hider_size(1, [2]) < 1.0,
			"a weak hider facing a strong seeker is smaller next round")

	var one_hiding_after_first: int = one["hiding"]
	var two_seeking_after_first: int = two["seeking"]
	session.record_round([
		{"id": 1, "score": 100, "role": MatchStateScript.Role.SEEKER, "alive": true},
		{"id": 2, "score": 0, "role": MatchStateScript.Role.HIDER, "alive": false},
	])
	one = session.rating_snapshot(1)
	two = session.rating_snapshot(2)
	check(one["hiding"] == one_hiding_after_first and one["seeking"] > session.DEFAULT_RATING,
			"switching to seeker updates only that player's seeking estimate")
	check(two["seeking"] == two_seeking_after_first and two["hiding"] < session.DEFAULT_RATING,
			"switching to hider updates only that player's hiding estimate")

	var survivors: RefCounted = SessionStateScript.new()
	survivors.reset([1, 2])
	survivors.record_round([
		{"id": 1, "score": 75, "role": MatchStateScript.Role.HIDER, "alive": true},
		{"id": 2, "score": 0, "role": MatchStateScript.Role.SEEKER, "alive": true},
	])
	check(survivors.balanced_hider_size(1, [2]) > 1.0,
			"a strong hider facing a struggling seeker receives the inverse handicap")

	# Force the estimator's legal extremes to prove even long streaks cannot
	# produce a physics-breaking scale.
	session.skill_ratings["One"]["hiding"] = session.MIN_RATING
	session.skill_ratings["Two"]["seeking"] = session.MAX_RATING
	check(is_equal_approx(session.balanced_hider_size(1, [2]), session.MIN_BALANCED_SIZE),
			"combined shrinking is capped at the safe minimum")
	session.skill_ratings["One"]["hiding"] = session.MAX_RATING
	session.skill_ratings["Two"]["seeking"] = session.MIN_RATING
	check(is_equal_approx(session.balanced_hider_size(1, [2]), session.MAX_BALANCED_SIZE),
			"combined enlargement is capped at the safe maximum")
	check(is_equal_approx(session.balanced_hider_size(1, []), 1.0),
			"solo rounds stay at normal size because there is no opponent to balance")

	session.remove_player(1)
	session.add_player(10, "One")
	check(session.rating_snapshot(10)["hiding"] == int(session.MAX_RATING),
			"reconnecting identity retains its session skill estimates")


func test_preference_aware_roles() -> void:
	print("preference-aware role rotation:")
	var session: RefCounted = SessionStateScript.new()
	session.reset([])
	for id in 4:
		session.add_player(id + 1, "Player%d" % (id + 1))
	var prefs := {1: "seeker", 2: "hider", 3: "none", 4: "none"}
	var selected: Array = session.assign_roles(prefs, 1, 7)
	check(selected == [1], "matching seeker volunteer is served before other pools")

	var one_sided := {1: "seeker", 2: "none", 3: "none", 4: "none"}
	var ignored: Array = session.assign_roles(one_sided, 1, 7)
	check(ignored[0] != 1,
			"one-sided preferences are ignored in favor of least-recent fairness")

	var rotation := SessionStateScript.new()
	rotation.reset([])
	for id in 3:
		rotation.add_player(id + 1, "R%d" % (id + 1))
	var none := {1: "none", 2: "none", 3: "none"}
	var seen := {}
	for round_index in 3:
		rotation.rounds_played = round_index
		seen[rotation.assign_roles(none, 1, 5 + round_index)[0]] = true
	check(seen.size() == 3, "least-recent rotation serves every eligible player")

	var reconnect := SessionStateScript.new()
	reconnect.reset([])
	reconnect.add_player(10, "StableName")
	reconnect.add_player(20, "Other")
	reconnect.assign_roles({10: "none", 20: "none"}, 1, 2)
	var prior_history: Dictionary = reconnect.role_history["StableName"].duplicate()
	reconnect.remove_player(10)
	reconnect.add_player(30, "StableName")
	check(reconnect.role_history["StableName"] == prior_history,
			"reconnect with the same lobby identity preserves role history")
	reconnect.assign_roles({30: "hider", 20: "seeker"}, 1, 3)
	check(reconnect.role_history["StableName"]["seeker"] == prior_history["seeker"],
			"preference changes do not erase recorded role history")


func test_hidden_readiness() -> void:
	print("hidden readiness + early seek:")
	var ms := _make(3, 1, {"paint_time": 100.0})
	ms.start()
	var seeker: int = ms.seekers()[0]
	var hiders: Array = ms.hiders()
	check(not ms.all_hiders_hidden(), "paint phase begins with hiders unready")
	check(not ms.set_hidden(seeker, true), "seekers cannot mark themselves hidden")
	check(ms.set_hidden(hiders[0], true), "active hider can confirm hidden")
	check(ms.hidden_hiders() == [hiders[0]], "readiness tracks the confirming hider")
	check(not ms.start_seek_early(), "host cannot skip while a hider is unready")
	check(ms.set_hidden(hiders[0], false) and ms.hidden_hiders().is_empty(),
			"hider can undo readiness during paint")
	ms.set_hidden(hiders[0], true)
	ms.set_hidden(hiders[1], true)
	check(ms.all_hiders_hidden(), "all active hiders can become ready")
	check(ms.start_seek_early() and ms.phase == MatchState.Phase.SEEK,
			"explicit host action starts seeking before the paint timer")
	check(not ms.set_hidden(hiders[0], false), "readiness locks once seeking begins")

	var ms2 := _make(3, 1, {"paint_time": 100.0})
	ms2.start()
	var remaining: Array = ms2.hiders()
	ms2.set_hidden(remaining[0], true)
	ms2.remove_player(remaining[1])
	check(ms2.hiders().size() == 1 and ms2.all_hiders_hidden(),
			"disconnect updates the required ready count")


func test_disconnect_wins() -> void:
	print("disconnect handling:")
	var ms := _make(3, 1)
	ms.start()
	_tick_until(ms, MatchState.Phase.SEEK)
	var seeker: int = ms.seekers()[0]
	ms.remove_player(seeker)
	check(ms.phase == MatchState.Phase.REVEAL and ms.winner == MatchState.Team.HIDERS,
			"all seekers leaving hands hiders the win")

	var ms2 := _make(3, 1)
	ms2.start()
	_tick_until(ms2, MatchState.Phase.SEEK)
	for h: int in ms2.hiders():
		ms2.remove_player(h)
	check(ms2.phase == MatchState.Phase.REVEAL and ms2.winner == MatchState.Team.SEEKERS,
			"all hiders leaving hands seekers the win")


func test_solo_mode() -> void:
	print("solo test mode (1 player, 0 seekers):")
	var ms := _make(1, 1)
	check(ms.seekers().size() == 0, "solo player is never a seeker")
	ms.start()
	check(_tick_until(ms, MatchState.Phase.SEEK), "solo reaches SEEK")
	check(_tick_until(ms, MatchState.Phase.RESULTS), "solo reaches RESULTS")
	check(ms.winner == MatchState.Team.HIDERS, "solo survivor wins")


func test_avatar_contracts() -> void:
	print("avatar contracts:")
	check(AvatarCatalogScript.ORDER == ["human", "cat", "dog"],
			"launch roster contains human, cat, and dog")
	var authored_heights := {}
	for avatar_id: String in AvatarCatalogScript.ORDER:
		var errors := AvatarCatalogScript.contract_errors(avatar_id)
		check(errors.is_empty(), "%s supplies the complete avatar contract: %s" % [
				avatar_id, errors])
		var avatar: PaintableBody = PaintableBodyScript.new()
		avatar.build(17, Color.WHITE, avatar_id)
		authored_heights[avatar_id] = _authored_avatar_height(avatar)
		check(avatar.part_meshes.size() == avatar.parts.size() and not avatar.parts.is_empty(),
				"%s builds every authored paintable part" % avatar_id)
		check(avatar.joints.size() == avatar.parts.size() - 1,
				"%s builds a connected articulated ragdoll" % avatar_id)
		var first_pos: Vector3 = avatar.parts[0]["pos"]
		avatar.splat_at(first_pos, Color.RED, 0.2, Vector3.BACK)
		check(_count_painted(avatar, 0, Color.RED) > 0,
				"%s parts use the shared through-body painting path" % avatar_id)
		avatar.set_ragdoll(true, false)
		check(avatar.capture_pose().size() == avatar.parts.size(),
				"%s replicates every ragdoll transform" % avatar_id)
		avatar.set_ragdoll(false, false)
		check(avatar.part_bodies[0].transform.is_equal_approx(avatar._authored_transforms[0]),
				"%s restores its authored standing pose" % avatar_id)
		avatar.free()
	check(float(authored_heights["cat"]) < float(authored_heights["dog"]),
			"cat is physically shorter than dog (%0.2fm < %0.2fm)" % [
			authored_heights["cat"], authored_heights["dog"]])
	check(float(authored_heights["dog"]) < float(authored_heights["human"]),
			"dog is physically shorter than human (%0.2fm < %0.2fm)" % [
			authored_heights["dog"], authored_heights["human"]])
	var cat_profile := AvatarCatalogScript.profile("cat")
	var dog_profile := AvatarCatalogScript.profile("dog")
	check(float(cat_profile["scale"]) < float(dog_profile["scale"])
			and float(dog_profile["scale"]) < 1.0,
			"uniform profile scale orders cat < dog < human")
	check(float(cat_profile["collision_shapes"][0]["height"])
			< float(dog_profile["collision_shapes"][0]["height"]),
			"movement collision scales with the visible animal")
	var player_script := load("res://scripts/player.gd")
	check(player_script.default_brush_radius_for_scale(float(cat_profile["scale"]))
			< player_script.default_brush_radius_for_scale(float(dog_profile["scale"])),
			"paint brush radius scales with the visible animal")


func test_balanced_avatar_scaling() -> void:
	print("balanced avatar scaling:")
	var regular := AvatarCatalogScript.profile("human")
	var smaller := AvatarCatalogScript.profile("human", 0.8)
	check(is_equal_approx(float(smaller["scale"]), float(regular["scale"]) * 0.8),
			"balance multiplier composes with the authored avatar scale")
	check(Vector3(smaller["parts"][0]["size"]).is_equal_approx(
			Vector3(regular["parts"][0]["size"]) * 0.8),
			"visible body parts receive the balance multiplier")
	check(is_equal_approx(float(smaller["collision_shapes"][0]["height"]),
			float(regular["collision_shapes"][0]["height"]) * 0.8),
			"movement collision receives the balance multiplier")
	check(Vector3(smaller["camera_pivot"]).is_equal_approx(
			Vector3(regular["camera_pivot"]) * 0.8),
			"camera and gameplay anchors stay aligned with the resized body")
	var body: PaintableBody = PaintableBodyScript.new()
	body.build(22, Color.WHITE, "human", 0.8)
	check(Vector3(body.parts[0]["size"]).is_equal_approx(
			Vector3(regular["parts"][0]["size"]) * 0.8),
			"paint and ragdoll geometry build at the balanced size")
	body.free()
	var minimum_body: PaintableBody = PaintableBodyScript.new()
	minimum_body.build(23, Color.WHITE, "human", 0.25)
	check(Vector3(minimum_body.parts[0]["size"]).is_equal_approx(
			Vector3(regular["parts"][0]["size"]) * 0.25),
			"the full avatar contract supports the 25% minimum size")
	minimum_body.free()


func _authored_avatar_height(body: PaintableBody) -> float:
	var low := INF
	var high := -INF
	for part_idx in body.parts.size():
		var half_size: Vector3 = body.parts[part_idx]["size"] * 0.5
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var corner: Vector3 = body.part_bodies[part_idx].transform \
							* Vector3(half_size.x * x, half_size.y * y, half_size.z * z)
					low = minf(low, corner.y)
					high = maxf(high, corner.y)
	return high - low


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
	var head_center: Vector3 = body.parts[head_idx]["pos"]
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
	var torso: Vector3 = body.parts[torso_idx]["pos"]
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


func test_results_pose_preservation() -> void:
	print("results pose preservation:")
	var body: PaintableBody = PaintableBodyScript.new()
	body.build(8, Color.WHITE)
	body.set_ragdoll(true, false)
	var pose_before := body.capture_pose()
	body.freeze_ragdoll_pose()
	check(body.ragdolled, "results freeze keeps the articulated ragdoll active")
	check(body.capture_pose() == pose_before, "results freeze preserves every part transform")
	var all_frozen := true
	var all_noncolliding := true
	for part: RigidBody3D in body.part_bodies:
		all_frozen = all_frozen and part.freeze
		all_noncolliding = all_noncolliding and part.collision_mask == 0
	check(all_frozen, "survivor ragdoll no longer simulates during inspection")
	check(all_noncolliding, "inspection movement cannot disturb survivor parts")
	body.resume_ragdoll_pose()
	var all_resumed := true
	for part: RigidBody3D in body.part_bodies:
		all_resumed = all_resumed and not part.freeze and part.collision_mask == 1
	check(all_resumed, "temporary follow-camera freeze can resume the same ragdoll pose")
	body.free()


func test_results_mouse_release() -> void:
	print("results mouse release:")
	var player = load("res://scripts/player.gd").new()
	player.name = "1"
	get_root().add_child(player)
	player.role = MatchStateScript.Role.HIDER
	player.phase = MatchStateScript.Phase.RESULTS
	player.paint_mode = true

	# Exercise the local part of the production phase handler directly because
	# SceneTree._initialize runs before this test has a multiplayer interface.
	player._apply_local_phase({})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(not player.paint_mode, "RESULTS synchronously exits hider paint mode")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"results can unlock the cursor after hider phase cleanup")
	player.free()


func test_ui_foundation() -> void:
	print("shared UI foundation:")
	var shared_theme := UIThemeScript.shared()
	check(shared_theme.default_font_size == 16,
			"shared theme defines a readable logical base font")
	check(shared_theme.get_stylebox("normal", "PrimaryButton") != null,
			"shared theme exposes a consistent primary action style")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1280
			and ProjectSettings.get_setting("display/window/size/viewport_height") == 720,
			"UI renders from the 1280x720 logical canvas")
	check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items"
			and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand",
			"logical UI scales and expands without distorting its aspect")

	var backdrop: Control = PaintBackdropScript.new()
	backdrop.set_reduce_motion(true)
	check(backdrop.reduce_motion and not backdrop.is_processing(),
			"menu motion has an accessible opt-out")
	backdrop.set_reduce_motion(false)
	check(backdrop.is_processing(), "menu backdrop can restore restrained motion")
	backdrop.free()


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
	hud.set_balance_size(MatchStateScript.Role.HIDER, 0.92)
	check(hud._balance_label.visible and "92% SIZE" in hud._balance_label.text,
			"hiders can see their skill-balance size")
	hud.set_balance_size(MatchStateScript.Role.SEEKER, 1.0)
	check(not hud._balance_label.visible,
			"seekers stay normal-sized and do not receive a size readout")
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
	check(not hud._counting and hud._timer_label.text.is_empty(),
			"RESULTS phase hides and stops the HUD countdown")
	hud.toggle_results_inspection()
	check(not hud._results.visible,
			"inspection toggle hides scores for mouse-look without ending results")
	hud.toggle_results_inspection()
	check(hud._results.visible,
			"inspection toggle restores the scoreboard and cursor")
	hud.on_phase(MatchStateScript.Phase.REVEAL, 10.0, MatchStateScript.Role.HIDER, {})
	check(hud._counting and hud._phase_label.text.begins_with("AFTER-ROUND REVEAL"),
			"timed reveal is distinct from the untimed results screen")
	check(not hud._bottom_hider.visible and not hud._ammo_label.visible \
			and not hud._ragdoll_button.visible,
			"reveal clears active-round controls so hiding spots stay visible")
	hud.set_follow_camera("Seeker Two", 2, 3)
	check(hud._follow_label.visible and "2 / 3" in hud._follow_label.text,
			"follow-camera HUD identifies the seeker and cycle position")
	hud.set_follow_camera("")
	check(not hud._follow_label.visible, "returning to the hider hides the follow status")
	hud.on_phase(MatchStateScript.Phase.PAINT, 5.0, MatchStateScript.Role.HIDER, {})
	check(not hud._results.visible, "next round's PAINT phase clears the scoreboard")
	hud.setup(MatchStateScript.Role.HIDER, true)
	hud.set_hiding_readiness(1, 2, true)
	check(hud._hidden_status.text == "HIDERS READY  1 / 2" and hud._start_seek_button.disabled,
			"paint HUD shows readiness progress without unlocking early seek")
	hud.set_hiding_readiness(2, 2, true)
	check(not hud._start_seek_button.disabled,
			"host early-seek action unlocks when every hider is ready")
	var app := AppScript.new()
	app._setup_input_map()
	check(InputMap.has_action("toggle_hidden") and InputMap.has_action("start_seeking_early")
			and InputMap.has_action("toggle_results")
			and InputMap.has_action("cycle_seeker_camera"),
			"readiness keyboard actions are registered")
	app.free()
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


func test_seek_hider_slowdown() -> void:
	print("seek-phase hider slowdown:")
	var player_script := load("res://scripts/player.gd")
	var hider := MatchStateScript.Role.HIDER
	var seeker := MatchStateScript.Role.SEEKER
	var paint := MatchStateScript.Phase.PAINT
	var seek := MatchStateScript.Phase.SEEK
	check(is_equal_approx(
			player_script.horizontal_speed_for_state(hider, paint, false, false),
			player_script.SPEED), "hiders keep normal speed throughout PAINT")
	check(is_equal_approx(
			player_script.horizontal_speed_for_state(hider, seek, false, false),
			player_script.SPEED * 0.2), "living hiders move at one-fifth speed in SEEK")
	check(is_equal_approx(
			player_script.horizontal_speed_for_state(hider, seek, false, true),
			player_script.CROUCH_SPEED * 0.2), "crouching cannot bypass the slowdown")
	check(is_equal_approx(
			player_script.horizontal_speed_for_state(seeker, seek, false, false),
			player_script.SPEED), "seekers retain full movement speed")
	check(is_equal_approx(
			player_script.horizontal_speed_for_state(hider, seek, true, false),
			player_script.SPEED), "eliminated hiders do not inherit the movement penalty")
	check(is_equal_approx(
			player_script.horizontal_speed_for_state(hider, paint, false, true),
			player_script.CROUCH_SPEED), "replay PAINT restores full crouched speed")

	var ms := _make(3, 1, {"paint_time": 100.0})
	ms.start()
	for id: int in ms.hiders():
		ms.set_hidden(id, true)
	check(ms.start_seek_early(), "early-seek transition activates the SEEK speed state")
	check(is_equal_approx(player_script.horizontal_speed_for_state(
			hider, ms.phase, false, false), player_script.SPEED * 0.2),
			"early SEEK uses the same one-fifth hider speed")
	var entry_velocity: Vector3 = player_script.velocity_for_phase_entry(
			Vector3(player_script.SPEED, 1.0, 0.0), hider, seek, false, false)
	check(is_equal_approx(Vector2(entry_velocity.x, entry_velocity.z).length(),
			player_script.SPEED * 0.2), "SEEK entry clamps carried paint-phase momentum")
	check(is_equal_approx(entry_velocity.y, 1.0),
			"SEEK entry does not change vertical momentum")


func test_follow_camera_rules() -> void:
	print("living-hider follow camera rules:")
	var player_script := load("res://scripts/player.gd")
	var hider := MatchStateScript.Role.HIDER
	var seeker := MatchStateScript.Role.SEEKER
	var seek := MatchStateScript.Phase.SEEK
	check(player_script.follow_camera_allowed(hider, seek, false, false),
			"living hider outside paint mode can follow during SEEK")
	check(not player_script.follow_camera_allowed(hider, MatchStateScript.Phase.PAINT,
			false, false), "follow view cannot expose the seeker during PAINT")
	check(not player_script.follow_camera_allowed(hider, seek, false, true),
			"paint mode must be exited before following")
	check(not player_script.follow_camera_allowed(hider, seek, true, false),
			"eliminated hiders keep their separate spectator behavior")
	check(not player_script.follow_camera_allowed(seeker, seek, false, false),
			"seekers cannot enter the hider-only follow mode")


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


func test_keep_out_volume() -> void:
	print("keep-out volume:")
	var scene := load("res://scenes/objects/keep_out_volume.tscn") as PackedScene
	check(scene != null, "reusable keep-out volume scene loads")
	if scene == null:
		return
	var volume := scene.instantiate() as Area3D
	check(volume.collision_layer == 0, "keep-out volume does not physically block players")
	check(volume.collision_mask == 6,
			"keep-out volume monitors standing players and ragdoll parts")
	var collision := volume.get_node_or_null("CollisionShape3D") as CollisionShape3D
	check(collision != null and collision.shape is BoxShape3D,
			"keep-out volume has an editor-scalable box shape")
	var preview := volume.get_node_or_null("EditorPreview") as MeshInstance3D
	check(preview != null and preview.mesh is BoxMesh,
			"keep-out volume has a prominent editor preview")
	check(not volume.preview_through_geometry,
			"keep-out preview is occluded by map geometry by default")
	volume.preview_through_geometry = true
	var preview_material := preview.material_override as StandardMaterial3D
	check(preview_material != null and preview_material.no_depth_test,
			"keep-out preview can be toggled to show through geometry")
	volume.preview_through_geometry = false
	check(not preview_material.no_depth_test,
			"keep-out preview can be toggled back to normal occlusion")

	var player = load("res://scripts/player.gd").new()
	var ragdoll_part := RigidBody3D.new()
	player.add_child(ragdoll_part)
	check(volume.recovery_target_for(player) == player,
			"standing player resolves to the recovery target")
	check(volume.recovery_target_for(ragdoll_part) == player,
			"ragdoll part resolves to its owning player")
	var unrelated_body := Node3D.new()
	check(volume.recovery_target_for(unrelated_body) == null,
			"unrelated physics bodies are ignored")
	unrelated_body.free()
	player.free()
	volume.free()


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
			check(instance.get_node_or_null("KeepOutVolumes/KeepOutVolume") != null,
					"Hallwyl Museum includes a duplicable keep-out volume")
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


func test_lan_ip_selection() -> void:
	print("LAN IP selection:")
	check(LANAddressScript.preferred(PackedStringArray([
			"127.0.0.1", "10.0.0.8", "192.168.1.42", "fe80::1"
	])) == "192.168.1.42", "192.168 address is preferred for hosting")
	check(LANAddressScript.preferred(PackedStringArray([
			"127.0.0.1", "169.254.1.2", "10.20.30.40"
	])) == "10.20.30.40", "other private LAN ranges are supported")
	check(LANAddressScript.preferred(PackedStringArray([
			"127.0.0.1", "169.254.1.2", "fe80::1"
	])).is_empty(), "loopback, link-local, and IPv6 addresses are not advertised")
