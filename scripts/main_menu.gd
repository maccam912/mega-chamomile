extends Control
## Main menu: pick a name, host, or join by IP. UI is built in code.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _lan_list: VBoxContainer


func _ready() -> void:
	_build_ui()
	Net.leave()
	Net.join_failed.connect(_on_join_failed)
	Net.joined_ok.connect(_on_joined_ok)
	Net.lan_games_changed.connect(_on_lan_games_changed)
	Net.start_lan_discovery()
	if App.status_message != "":
		_status.text = App.status_message
		App.status_message = ""
	_handle_cli()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("232733")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAINT-N-SEEK"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("f5f0e6"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "paint yourself. blend in. don't get found."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("8fd18a"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_spacer(12))

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = "Painter%03d" % (randi() % 1000)
	_name_edit.max_length = 20
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name_edit)

	var host_btn := _button("HOST GAME")
	host_btn.pressed.connect(_on_host_pressed)
	box.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Host IP"
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)

	var join_btn := _button("JOIN")
	join_btn.custom_minimum_size = Vector2(120, 0)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

	var lan_heading := Label.new()
	lan_heading.text = "GAMES ON YOUR NETWORK"
	lan_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan_heading.add_theme_font_size_override("font_size", 13)
	lan_heading.add_theme_color_override("font_color", Color("8fd18a"))
	box.add_child(lan_heading)
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 6)
	box.add_child(_lan_list)
	_on_lan_games_changed([])

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("e0b34d"))
	_status.text = ""
	box.add_child(_status)

	var quit_btn := _button("QUIT")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit_btn)

	var footer := Label.new()
	footer.text = (
		"art & audio: kenney.nl (CC0)\n"
		+ "Hallwyl Museum: Thomas Flynn / Erik Lernestål (CC BY 4.0)"
	)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color("5a6172"))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.position += Vector2(-470, -50)
	add_child(footer)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	_buttons.append(b)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy


func _on_host_pressed() -> void:
	App.play_ui_click()
	Net.my_name = _name_edit.text.strip_edges()
	var err := Net.host_game()
	if err != OK:
		_status.text = "Could not host (port %d busy?)" % App.PORT
		return
	App.goto_scene(App.LOBBY_SCENE)


func _on_join_pressed() -> void:
	Net.stop_lan_discovery()
	App.play_ui_click()
	Net.my_name = _name_edit.text.strip_edges()
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_status.text = "Enter the host's IP first."
		return
	_set_busy(true)
	_status.text = "Connecting to %s..." % ip
	var err := Net.join_game(ip)
	if err != OK:
		_set_busy(false)
		_status.text = "Invalid address."


func _on_joined_ok() -> void:
	App.goto_scene(App.LOBBY_SCENE)


func _on_join_failed(msg: String) -> void:
	_set_busy(false)
	_status.text = msg
	Net.start_lan_discovery()


func _on_lan_games_changed(games: Array) -> void:
	if _lan_list == null:
		return
	for child in _lan_list.get_children():
		child.queue_free()
	if games.is_empty():
		var searching := Label.new()
		searching.text = "Searching… (manual IP still works)"
		searching.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		searching.add_theme_color_override("font_color", Color("747d91"))
		_lan_list.add_child(searching)
		return
	for game: Dictionary in games:
		var button := Button.new()
		var compatible := bool(game.get("compatible", false))
		button.text = "%s  •  %d/%d players%s" % [
				str(game.get("host", "LAN game")), int(game.get("players", 0)),
				int(game.get("capacity", 16)), "" if compatible else "  •  incompatible"]
		button.disabled = not compatible
		button.pressed.connect(func() -> void:
			_ip_edit.text = str(game["address"])
			_on_join_pressed())
		_lan_list.add_child(button)


func _handle_cli() -> void:
	if App.cli.has("name"):
		_name_edit.text = str(App.cli["name"])
	if App.cli.has("host"):
		_on_host_pressed.call_deferred()
	elif App.cli.has("join"):
		_ip_edit.text = str(App.cli["join"])
		_on_join_pressed.call_deferred()
