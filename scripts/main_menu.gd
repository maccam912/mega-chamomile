extends Control
## Main menu: pick a name, host, or join by IP. UI is built in code.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	_build_ui()
	Net.leave()
	Net.join_failed.connect(_on_join_failed)
	Net.joined_ok.connect(_on_joined_ok)
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
	title.text = "MEGA CHAMOMILE"
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
	_name_edit.text = "Chamomile%03d" % (randi() % 1000)
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


func _handle_cli() -> void:
	if App.cli.has("name"):
		_name_edit.text = str(App.cli["name"])
	if App.cli.has("host"):
		_on_host_pressed.call_deferred()
	elif App.cli.has("join"):
		_ip_edit.text = str(App.cli["join"])
		_on_join_pressed.call_deferred()
