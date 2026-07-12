extends Control
## Lobby: shows connected players; the host picks seeker count and starts.

const LANAddress := preload("res://scripts/lan_address.gd")
const UITheme := preload("res://scripts/ui_theme.gd")

var _player_list: VBoxContainer
var _start_btn: Button
var _seeker_spin: SpinBox
var _map_option: OptionButton
var _hint: Label
var _avatar_option: OptionButton
var _role_option: OptionButton
var _preview_root: Node3D
var _preview_camera: Camera3D
var _preview_body: PaintableBody
var _settings_summary: Label


func _ready() -> void:
	_build_ui()
	Net.players_changed.connect(_refresh)
	Net.settings_changed.connect(_refresh_settings_summary)
	_refresh()


func _build_ui() -> void:
	theme = UITheme.shared()
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# The complete host settings list is taller than 720p. Keep it centered when
	# space allows and scroll it within a logical safe area when it does not.
	var safe_area := MarginContainer.new()
	safe_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe_area.add_theme_constant_override(side, 24)
	add_child(safe_area)
	var scroll := ScrollContainer.new()
	scroll.name = "LobbyScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	safe_area.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(560, 0)
	scroll.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UITheme.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var ip_hint := Label.new()
	if Net.is_server():
		var lan_ip := LANAddress.preferred(IP.get_local_addresses())
		ip_hint.text = (
				"Friends can join at %s" % lan_ip
				if not lan_ip.is_empty()
				else "Could not find a LAN IP")
	else:
		ip_hint.text = "Connected to host"
	ip_hint.add_theme_font_size_override("font_size", 13)
	ip_hint.add_theme_color_override("font_color", UITheme.MUTED)
	ip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ip_hint)

	var panel := PanelContainer.new()
	box.add_child(panel)

	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 6)
	_player_list.custom_minimum_size = Vector2(0, 180)
	panel.add_child(_player_list)

	_build_avatar_picker(box)
	_build_role_preference(box)

	if Net.is_server():
		_seeker_spin = _add_setting_spin(box, "Seekers:", "seeker_count", 1, 8, 1)
		_add_setting_spin(box, "Hiding time:", "paint_time", 15, 300, 5, "s")
		_add_setting_spin(box, "Seeking time:", "seek_time", 30, 600, 15, "s")
		_add_setting_spin(box, "Shot cooldown:", "shot_cooldown", 0.1, 3.0, 0.1, "s")

		var ammo_mode_row := HBoxContainer.new()
		ammo_mode_row.add_theme_constant_override("separation", 10)
		box.add_child(ammo_mode_row)
		var ammo_mode_label := Label.new()
		ammo_mode_label.text = "Ammo mode:"
		ammo_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ammo_mode_row.add_child(ammo_mode_label)
		var ammo_mode := OptionButton.new()
		ammo_mode.add_item("Per hider")
		ammo_mode.set_item_metadata(0, "per_hider")
		ammo_mode.add_item("Fixed per seeker")
		ammo_mode.set_item_metadata(1, "fixed")
		ammo_mode.select(1 if App.settings["ammo_mode"] == "fixed" else 0)
		ammo_mode.item_selected.connect(func(index: int) -> void:
			App.settings["ammo_mode"] = str(ammo_mode.get_item_metadata(index))
			Net.update_lobby_settings())
		ammo_mode_row.add_child(ammo_mode)
		_add_setting_spin(box, "Ammo per hider:", "ammo_per_hider", 1, 10, 1)
		_add_setting_spin(box, "Fixed ammo per seeker:", "ammo_per_seeker", 1, 50, 1)
		_add_setting_spin(box, "Survival points/sec:", "survival_pps", 0, 10, 0.5)
		_add_setting_spin(box, "Visible-risk points/sec:", "bold_pps", 0, 20, 0.5)
		_add_setting_spin(box, "Points per find:", "kill_points", 0, 500, 25)
		_add_setting_spin(box, "Survivor bonus:", "survive_bonus", 0, 500, 25)
		_add_setting_spin(box, "Seeker sweep bonus:", "sweep_bonus", 0, 500, 25)

		var map_row := HBoxContainer.new()
		map_row.add_theme_constant_override("separation", 10)
		box.add_child(map_row)
		var map_label := Label.new()
		map_label.text = "Map:"
		map_row.add_child(map_label)
		_map_option = OptionButton.new()
		_map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for map_id: String in App.MAPS:
			var index := _map_option.item_count
			_map_option.add_item(str(App.MAPS[map_id]["label"]))
			_map_option.set_item_metadata(index, map_id)
			if map_id == str(App.settings["map_id"]):
				_map_option.select(index)
		_map_option.item_selected.connect(func(index: int) -> void:
			App.select_map(str(_map_option.get_item_metadata(index))))
		map_row.add_child(_map_option)
		_map_option.item_selected.connect(func(_index: int) -> void:
			Net.update_lobby_settings())

		var defaults_btn := Button.new()
		defaults_btn.text = "RESTORE DEFAULT SETTINGS"
		defaults_btn.pressed.connect(func() -> void:
			App.reset_match_settings()
			Net.update_lobby_settings()
			get_tree().reload_current_scene())
		box.add_child(defaults_btn)

		_start_btn = Button.new()
		_start_btn.text = "START MATCH"
		_start_btn.theme_type_variation = "PrimaryButton"
		_start_btn.custom_minimum_size = Vector2(0, 48)
		_start_btn.pressed.connect(_on_start_pressed)
		box.add_child(_start_btn)

	else:
		_settings_summary = Label.new()
		_settings_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_settings_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_settings_summary.add_theme_font_size_override("font_size", 13)
		_settings_summary.add_theme_color_override("font_color", Color("b8bfce"))
		box.add_child(_settings_summary)
		_refresh_settings_summary(Net.lobby_settings)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("e0b34d"))
	_hint.text = "" if Net.is_server() else "waiting for the host to start..."
	box.add_child(_hint)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
	leave_btn.theme_type_variation = "QuietButton"
	leave_btn.custom_minimum_size = Vector2(0, 40)
	leave_btn.pressed.connect(_on_leave_pressed)
	box.add_child(leave_btn)

	if not App.last_scores.is_empty():
		var last := Label.new()
		var winner_txt := "hiders" if App.last_winner == MatchState.Team.HIDERS else "seekers"
		last.text = "last round: %s won" % winner_txt
		last.add_theme_font_size_override("font_size", 13)
		last.add_theme_color_override("font_color", Color("8a92a6"))
		last.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(last)
func _build_avatar_picker(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 180)
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(controls)
	var label := Label.new()
	label.text = "Your body:"
	controls.add_child(label)
	_avatar_option = OptionButton.new()
	for avatar_id: String in AvatarCatalog.ORDER:
		var index := _avatar_option.item_count
		_avatar_option.add_item(AvatarCatalog.label(avatar_id))
		_avatar_option.set_item_metadata(index, avatar_id)
		if avatar_id == App.selected_avatar:
			_avatar_option.select(index)
	_avatar_option.item_selected.connect(_on_avatar_selected)
	controls.add_child(_avatar_option)
	var note := Label.new()
	note.text = "All bodies use the same paint and ragdoll systems."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("8a92a6"))
	controls.add_child(note)

	var preview_container := SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(210, 180)
	preview_container.stretch = true
	row.add_child(preview_container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(420, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(viewport)
	_preview_root = Node3D.new()
	viewport.add_child(_preview_root)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("20242f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.65
	environment.environment = env
	_preview_root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.2
	_preview_root.add_child(light)
	_preview_camera = Camera3D.new()
	_preview_root.add_child(_preview_camera)
	_preview_camera.make_current()
	_update_avatar_preview(App.selected_avatar)


func _build_role_preference(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var label := Label.new()
	label.text = "Role preference:"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_role_option = OptionButton.new()
	for item: Dictionary in [
		{"id": "none", "label": "No Preference"},
		{"id": "seeker", "label": "Prefer Seeker"},
		{"id": "hider", "label": "Prefer Hider"},
	]:
		var index := _role_option.item_count
		_role_option.add_item(item["label"])
		_role_option.set_item_metadata(index, item["id"])
		if item["id"] == App.selected_role_preference:
			_role_option.select(index)
	_role_option.item_selected.connect(func(index: int) -> void:
		Net.request_role_preference(str(_role_option.get_item_metadata(index))))
	row.add_child(_role_option)


func _on_avatar_selected(index: int) -> void:
	var avatar_id := str(_avatar_option.get_item_metadata(index))
	Net.request_avatar(avatar_id)
	_update_avatar_preview(avatar_id)


func _update_avatar_preview(avatar_id: String) -> void:
	avatar_id = AvatarCatalog.normalize(avatar_id)
	if _preview_body != null:
		_preview_body.free()
	_preview_body = PaintableBody.new()
	_preview_root.add_child(_preview_body)
	_preview_body.build(0, Color("e7ded0"), avatar_id)
	_preview_body.set_parts_collidable(false)
	var height := float(AvatarCatalog.profile(avatar_id).get("preview_height", 1.8))
	_preview_camera.position = Vector3(2.0, height * 0.72, -2.5)
	_preview_camera.look_at(Vector3(0, height * 0.48, 0))


func _process(delta: float) -> void:
	if _preview_body != null:
		_preview_body.rotation.y += delta * 0.35


## Labeled SpinBox row bound to one App.settings key. The initial value is set
## without emitting value_changed so CLI overrides outside the spinner's range
## (e.g. --fast-phases) are displayed clamped but never written back.
func _add_setting_spin(box: VBoxContainer, text: String, key: String,
		min_v: float, max_v: float, step: float, suffix := "") -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.suffix = suffix
	spin.set_value_no_signal(float(App.settings[key]))
	var as_int: bool = App.settings[key] is int
	spin.value_changed.connect(func(v: float) -> void:
		App.settings[key] = int(v) if as_int else v
		Net.update_lobby_settings())
	row.add_child(spin)
	return spin


func _refresh_settings_summary(snapshot: Dictionary) -> void:
	if _settings_summary == null:
		return
	var cfg := snapshot if not snapshot.is_empty() else App.settings
	var ammo_text := (
			"%d fixed" % int(cfg.get("ammo_per_seeker", 9))
			if cfg.get("ammo_mode", "per_hider") == "fixed"
			else "%d per hider" % int(cfg.get("ammo_per_hider", 3)))
	_settings_summary.text = (
			"MATCH SETTINGS  •  %ds hide  •  %ds seek  •  %d seeker(s)\n"
			+ "%s  •  %.1fs cooldown  •  %s\n"
			+ "Scoring: %.1f survival/s, %.1f visible/s, %d find, %d survivor, %d sweep") % [
			int(cfg.get("paint_time", 90)), int(cfg.get("seek_time", 180)),
			int(cfg.get("seeker_count", 1)),
			str(App.MAPS.get(str(cfg.get("map_id", App.DEFAULT_MAP_ID)),
					App.MAPS[App.DEFAULT_MAP_ID])["label"]),
			float(cfg.get("shot_cooldown", 0.8)), ammo_text,
			float(cfg.get("survival_pps", 1.0)), float(cfg.get("bold_pps", 3.0)),
			int(cfg.get("kill_points", 100)), int(cfg.get("survive_bonus", 75)),
			int(cfg.get("sweep_bonus", 50))]


func _refresh() -> void:
	for c in _player_list.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id: int in ids:
		var row := Label.new()
		var tag := "  (host)" if id == 1 else ""
		var me := "  <- you" if id == multiplayer.get_unique_id() else ""
		var avatar_id := AvatarCatalog.normalize(str(
				Net.players[id].get("avatar", AvatarCatalog.DEFAULT_ID)))
		var preference := str(Net.players[id].get("preference", "none"))
		var preference_label: String = {"none": "no preference", "seeker": "prefers seeker",
				"hider": "prefers hider"}.get(preference, "no preference")
		row.text = "%s  —  %s, %s%s%s" % [Net.players[id]["name"],
				AvatarCatalog.label(avatar_id), preference_label, tag, me]
		row.add_theme_color_override("font_color", Color("d8dce6"))
		_player_list.add_child(row)
		if id == multiplayer.get_unique_id() and _avatar_option != null:
			for index in _avatar_option.item_count:
				if str(_avatar_option.get_item_metadata(index)) == avatar_id:
					_avatar_option.select(index)
					_update_avatar_preview(avatar_id)
					break
		if id == multiplayer.get_unique_id() and _role_option != null:
			for index in _role_option.item_count:
				if str(_role_option.get_item_metadata(index)) == preference:
					_role_option.select(index)
					break
	if Net.is_server():
		var n := ids.size()
		if _seeker_spin != null:
			var max_seekers := maxi(1, n - 1)
			_seeker_spin.max_value = max_seekers
			if n > 1 and int(App.settings["seeker_count"]) > max_seekers:
				App.settings["seeker_count"] = max_seekers
				_seeker_spin.set_value_no_signal(max_seekers)
				Net.update_lobby_settings()
		_hint.text = "solo test mode: you'll hide with no seekers" if n == 1 else ""
		_maybe_autostart(n)


func _maybe_autostart(player_count: int) -> void:
	if App.cli.has("autostart") and player_count >= int(App.cli["autostart"]):
		App.cli.erase("autostart")
		print("[lobby] autostart with %d players" % player_count)
		_on_start_pressed.call_deferred()


func _on_start_pressed() -> void:
	App.play_ui_click()
	Net.request_start()


func _on_leave_pressed() -> void:
	App.play_ui_click()
	Net.leave()
	App.to_main_menu()
