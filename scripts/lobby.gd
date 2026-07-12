extends Control
## Lobby: shows connected players; the host picks seeker count and starts.

var _player_list: VBoxContainer
var _start_btn: Button
var _seeker_spin: SpinBox
var _map_option: OptionButton
var _hint: Label


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
	ip_hint.text = "friends join with your LAN IP, port %d" % App.PORT
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

	if Net.is_server():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var lbl := Label.new()
		lbl.text = "Seekers:"
		row.add_child(lbl)
		_seeker_spin = SpinBox.new()
		_seeker_spin.min_value = 1
		_seeker_spin.max_value = 8
		_seeker_spin.value = App.settings["seeker_count"]
		_seeker_spin.value_changed.connect(
			func(v: float) -> void: App.settings["seeker_count"] = int(v))
		row.add_child(_seeker_spin)

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


func _refresh() -> void:
	for c in _player_list.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id: int in ids:
		var row := Label.new()
		var tag := "  (host)" if id == 1 else ""
		var me := "  <- you" if id == multiplayer.get_unique_id() else ""
		row.text = "%s%s%s" % [Net.players[id]["name"], tag, me]
		row.add_theme_color_override("font_color", Color("d8dce6"))
		_player_list.add_child(row)
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
