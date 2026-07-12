extends Control
## Lobby: shows connected players; the host picks seeker count and starts.

const LANAddress := preload("res://scripts/lan_address.gd")

var _player_list: VBoxContainer
var _start_btn: Button
var _seeker_spin: SpinBox
var _map_option: OptionButton
var _hint: Label
var _avatar_option: OptionButton
var _preview_root: Node3D
var _preview_camera: Camera3D
var _preview_body: PaintableBody


func _ready() -> void:
	_build_ui()
	Net.players_changed.connect(_refresh)
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("232733")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("f5f0e6"))
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
	ip_hint.add_theme_color_override("font_color", Color("8a92a6"))
	ip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ip_hint)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2c3140")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)

	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 6)
	_player_list.custom_minimum_size = Vector2(0, 180)
	panel.add_child(_player_list)

	_build_avatar_picker(box)

	if Net.is_server():
		_seeker_spin = _add_setting_spin(box, "Seekers:", "seeker_count", 1, 8, 1)
		_add_setting_spin(box, "Hiding time:", "paint_time", 15, 300, 5, "s")
		_add_setting_spin(box, "Seeking time:", "seek_time", 30, 600, 15, "s")
		_add_setting_spin(box, "Ammo per hider:", "ammo_per_hider", 1, 10, 1)

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

		_start_btn = Button.new()
		_start_btn.text = "START MATCH"
		_start_btn.custom_minimum_size = Vector2(0, 48)
		_start_btn.pressed.connect(_on_start_pressed)
		box.add_child(_start_btn)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("e0b34d"))
	_hint.text = "" if Net.is_server() else "waiting for the host to start..."
	box.add_child(_hint)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
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
		App.settings[key] = int(v) if as_int else v)
	row.add_child(spin)
	return spin


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
		row.text = "%s  —  %s%s%s" % [Net.players[id]["name"],
				AvatarCatalog.label(avatar_id), tag, me]
		row.add_theme_color_override("font_color", Color("d8dce6"))
		_player_list.add_child(row)
		if id == multiplayer.get_unique_id() and _avatar_option != null:
			for index in _avatar_option.item_count:
				if str(_avatar_option.get_item_metadata(index)) == avatar_id:
					_avatar_option.select(index)
					_update_avatar_preview(avatar_id)
					break
	if Net.is_server():
		var n := ids.size()
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
