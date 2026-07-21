extends CanvasLayer
## Escape menu. The match keeps running (it's multiplayer — nothing actually
## pauses); this just frees the mouse and offers resume / leave / quit.

const UITheme := preload("res://scripts/ui_theme.gd")

signal opened
signal resumed

var _room_code_field: LineEdit
var _room_code_status: Label
var _regenerate_code_button: Button


func _ready() -> void:
	layer = 20
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks under the menu
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = UITheme.shared()
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.12, 0.95)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := Label.new()
	note.text = "the match keeps running"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	if Net.is_server() and Net.is_iroh_session():
		_build_iroh_room_controls(box)

	box.add_child(_button("Resume", close))
	box.add_child(_button("Leave Match", func() -> void:
		Net.leave()
		App.to_main_menu()))
	box.add_child(_button("Quit Game", func() -> void: get_tree().quit()))


func _build_iroh_room_controls(parent: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "LATE-JOIN ROOM CODE"
	heading.add_theme_font_size_override("font_size", 11)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(heading)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	parent.add_child(code_row)
	_room_code_field = LineEdit.new()
	_room_code_field.name = "PauseRoomCode"
	_room_code_field.text = Net.host_room_code()
	_room_code_field.editable = false
	_room_code_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_room_code_field)
	var copy_button := _button("Copy", func() -> void:
		DisplayServer.clipboard_set(Net.host_room_code())
		_room_code_status.text = "Room code copied.")
	copy_button.name = "CopyRoomCode"
	copy_button.custom_minimum_size.x = 86
	code_row.add_child(copy_button)

	_regenerate_code_button = _button("Generate New Code", _regenerate_room_code)
	_regenerate_code_button.name = "RegenerateRoomCode"
	parent.add_child(_regenerate_code_button)
	_room_code_status = Label.new()
	_room_code_status.name = "RoomCodeStatus"
	_room_code_status.text = "Generate a fresh code when this one expires."
	_room_code_status.add_theme_font_size_override("font_size", 11)
	_room_code_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(_room_code_status)


func _regenerate_room_code() -> void:
	_regenerate_code_button.disabled = true
	_room_code_status.text = "Generating a fresh code…"
	var err: Error = await Net.regenerate_iroh_room_code()
	_regenerate_code_button.disabled = false
	if err != OK:
		_room_code_status.text = (
				Net.last_iroh_error()
				if not Net.last_iroh_error().is_empty()
				else "Could not generate a new code (%s)." % error_string(err)
		)
		return
	_room_code_field.text = Net.host_room_code()
	DisplayServer.clipboard_set(Net.host_room_code())
	_room_code_status.text = "New code %s copied." % Net.host_room_code()


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 40)
	b.pressed.connect(func() -> void:
		App.play_ui_click()
		on_press.call())
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close() -> void:
	visible = false
	resumed.emit()
