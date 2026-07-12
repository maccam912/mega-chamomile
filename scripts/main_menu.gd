extends Control
## Main menu: playful paint-led presentation with responsive, keyboard-friendly
## host/join controls. Nearby LAN games remain one click away.

const UITheme := preload("res://scripts/ui_theme.gd")
const PaintBackdrop := preload("res://scripts/paint_backdrop.gd")

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _lan_list: VBoxContainer
var _hero: VBoxContainer
var _content: HBoxContainer
var _menu_panel: PanelContainer
var _backdrop: Control


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
	theme = UITheme.shared()

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UITheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_backdrop = PaintBackdrop.new()
	_backdrop.name = "PaintBackdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.set_reduce_motion(App.reduce_motion)
	add_child(_backdrop)

	var safe_area := MarginContainer.new()
	safe_area.name = "SafeArea"
	safe_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe_area.add_theme_constant_override(side, 38)
	add_child(safe_area)

	_content = HBoxContainer.new()
	_content.name = "ResponsiveContent"
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 64)
	safe_area.add_child(_content)

	_build_hero(_content)
	_build_join_panel(_content)
	resized.connect(_update_responsive_layout)
	_update_responsive_layout.call_deferred()


func _build_hero(parent: HBoxContainer) -> void:
	_hero = VBoxContainer.new()
	_hero.name = "Hero"
	_hero.custom_minimum_size = Vector2(500, 0)
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero.add_theme_constant_override("separation", 4)
	parent.add_child(_hero)

	var eyebrow := Label.new()
	eyebrow.text = "A GAME OF CAMOUFLAGE & NERVE"
	eyebrow.add_theme_font_size_override("font_size", 15)
	eyebrow.add_theme_color_override("font_color", UITheme.MINT)
	_hero.add_child(eyebrow)

	_hero.add_child(_hero_word("PAINT.", UITheme.TEXT))
	_hero.add_child(_hero_word("BLEND.", UITheme.BLUE))
	_hero.add_child(_hero_word("VANISH.", UITheme.CORAL))

	var pitch := Label.new()
	pitch.text = "Steal colors from the room, paint your body,\nand become part of the scenery before the seekers arrive."
	pitch.add_theme_font_size_override("font_size", 17)
	pitch.add_theme_color_override("font_color", UITheme.MUTED)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size = Vector2(480, 58)
	pitch.add_theme_constant_override("line_spacing", 5)
	_hero.add_child(pitch)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(_chip("PAINT YOURSELF", UITheme.CORAL))
	chips.add_child(_chip("HIDE TOGETHER", UITheme.MINT))
	chips.add_child(_chip("FIND THEM ALL", UITheme.BLUE))
	_hero.add_child(chips)

	var credits := Label.new()
	credits.text = (
		"ART & AUDIO  KENNEY.NL (CC0)\n"
		+ "HALLWYL MUSEUM  THOMAS FLYNN / ERIK LERNESTÅL (CC BY 4.0)"
	)
	credits.add_theme_font_size_override("font_size", 10)
	credits.add_theme_color_override("font_color", Color(UITheme.MUTED, 0.58))
	credits.custom_minimum_size.y = 48
	credits.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hero.add_child(credits)


func _build_join_panel(parent: HBoxContainer) -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "JoinPanel"
	_menu_panel.theme_type_variation = "GlassPanel"
	_menu_panel.custom_minimum_size = Vector2(500, 0)
	parent.add_child(_menu_panel)

	var box := VBoxContainer.new()
	box.name = "MenuActions"
	box.add_theme_constant_override("separation", 9)
	_menu_panel.add_child(box)

	var brand := Label.new()
	brand.text = "PAINT-N-SEEK"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 34)
	brand.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(brand)

	var subtitle := Label.new()
	subtitle.text = "HOST A ROOM OR DROP INTO A NEARBY GAME"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", UITheme.MINT)
	box.add_child(subtitle)

	box.add_child(_field_label("YOUR PAINTER NAME"))
	_name_edit = LineEdit.new()
	_name_edit.name = "PlayerName"
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = "Painter%03d" % (randi() % 1000)
	_name_edit.max_length = 20
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size.y = 46
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_host_pressed())
	box.add_child(_name_edit)

	var host_btn := _button("HOST A GAME", "PrimaryButton")
	host_btn.name = "HostButton"
	host_btn.custom_minimum_size.y = 52
	host_btn.pressed.connect(_on_host_pressed)
	box.add_child(host_btn)

	var divider := HBoxContainer.new()
	divider.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 2:
		var line := HSeparator.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		divider.add_child(line)
		if i == 0:
			var or_label := Label.new()
			or_label.text = "OR JOIN BY ADDRESS"
			or_label.add_theme_font_size_override("font_size", 10)
			or_label.add_theme_color_override("font_color", UITheme.MUTED)
			divider.add_child(or_label)
	box.add_child(divider)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)

	_ip_edit = LineEdit.new()
	_ip_edit.name = "HostAddress"
	_ip_edit.placeholder_text = "Host IP or address"
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size.y = 46
	_ip_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	join_row.add_child(_ip_edit)

	var join_btn := _button("JOIN", "")
	join_btn.name = "JoinButton"
	join_btn.custom_minimum_size = Vector2(122, 46)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

	var lan_heading := Label.new()
	lan_heading.text = "GAMES ON YOUR NETWORK"
	lan_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan_heading.add_theme_font_size_override("font_size", 11)
	lan_heading.add_theme_color_override("font_color", UITheme.MINT)
	box.add_child(lan_heading)

	var lan_scroll := ScrollContainer.new()
	lan_scroll.name = "LanGamesScroll"
	lan_scroll.custom_minimum_size = Vector2(0, 82)
	lan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lan_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(lan_scroll)
	_lan_list = VBoxContainer.new()
	_lan_list.name = "LanGames"
	_lan_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_list.add_theme_constant_override("separation", 6)
	lan_scroll.add_child(_lan_list)
	_on_lan_games_changed([])

	_status = Label.new()
	_status.name = "ConnectionStatus"
	_status.custom_minimum_size.y = 24
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UITheme.GOLD)
	_status.text = ""
	box.add_child(_status)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	box.add_child(footer)
	var motion_toggle := CheckButton.new()
	motion_toggle.name = "ReduceMotion"
	motion_toggle.text = "REDUCE MOTION"
	motion_toggle.button_pressed = App.reduce_motion
	motion_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	motion_toggle.toggled.connect(_on_reduce_motion_toggled)
	footer.add_child(motion_toggle)
	var quit_btn := _button("QUIT", "QuietButton")
	quit_btn.name = "QuitButton"
	quit_btn.custom_minimum_size = Vector2(108, 38)
	quit_btn.pressed.connect(_on_quit_pressed)
	footer.add_child(quit_btn)


func _hero_word(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 62)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.2))
	return label


func _chip(text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AccentPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.13)
	style.border_color = Color(color, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(99)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	return panel


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	return label


func _button(text: String, variation: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	if not variation.is_empty():
		button.theme_type_variation = variation
	_buttons.append(button)
	return button


func _update_responsive_layout() -> void:
	if _hero == null or _menu_panel == null:
		return
	var show_hero := size.x >= 1040.0
	_hero.visible = show_hero
	_menu_panel.custom_minimum_size.x = 500.0 if show_hero else minf(560.0, size.x - 76.0)
	_content.add_theme_constant_override("separation", 64 if size.x >= 1280.0 else 30)


func _set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy


func _on_host_pressed() -> void:
	App.play_ui_click()
	Net.my_name = _name_edit.text.strip_edges()
	var err := Net.host_game()
	if err != OK:
		_status.text = "Could not host — is port %d already in use?" % App.PORT
		return
	App.goto_scene(App.LOBBY_SCENE)


func _on_join_pressed() -> void:
	Net.stop_lan_discovery()
	App.play_ui_click()
	Net.my_name = _name_edit.text.strip_edges()
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_status.text = "Enter the host's address first."
		return
	_set_busy(true)
	_status.text = "Connecting to %s…" % ip
	var err := Net.join_game(ip)
	if err != OK:
		_set_busy(false)
		_status.text = "That address isn't valid."


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
		searching.text = "Searching nearby… manual joining still works"
		searching.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		searching.add_theme_font_size_override("font_size", 12)
		searching.add_theme_color_override("font_color", Color(UITheme.MUTED, 0.72))
		_lan_list.add_child(searching)
		return
	for game: Dictionary in games:
		var button := Button.new()
		button.theme_type_variation = "QuietButton"
		var compatible := bool(game.get("compatible", false))
		button.text = "%s  •  %d/%d PLAYERS%s" % [
				str(game.get("host", "LAN game")), int(game.get("players", 0)),
				int(game.get("capacity", 16)), "" if compatible else "  •  INCOMPATIBLE"]
		button.disabled = not compatible
		button.pressed.connect(func() -> void:
			_ip_edit.text = str(game["address"])
			_on_join_pressed())
		_lan_list.add_child(button)


func _on_reduce_motion_toggled(reduced: bool) -> void:
	App.set_reduce_motion(reduced)
	_backdrop.set_reduce_motion(reduced)


func _on_quit_pressed() -> void:
	App.play_ui_click()
	get_tree().quit()


func _handle_cli() -> void:
	if App.cli.has("name"):
		_name_edit.text = str(App.cli["name"])
	if App.cli.has("host"):
		_on_host_pressed.call_deferred()
	elif App.cli.has("join"):
		_ip_edit.text = str(App.cli["join"])
		_on_join_pressed.call_deferred()
