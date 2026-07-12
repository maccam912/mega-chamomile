extends CanvasLayer
## In-match HUD, built in code. The game scene drives it via plain method
## calls; it keeps its own display countdown between phase broadcasts.

const MOVE_HINT := "F paint mode    wheel brush size"
const PAINT_HINT := "LMB paint yourself    RMB sample color    MMB drag orbit    F done"

signal ragdoll_toggled

var _phase_label: Label
var _timer_label: Label
var _role_label: Label
var _alive_label: Label
var _swatch: ColorRect
var _brush_preview: Control
var _brush_label: Label
var _ammo_label: Label
var _spotted_label: Label
var _center_banner: Label
var _blindfold: Control
var _blindfold_timer: Label
var _results: Control
var _bottom_hider: HBoxContainer
var _hint_label: Label
var _cross: ColorRect
var _paint_mode_label: Label
var _brush_ring: Control
var _ragdoll_button: Button

var _time_left := 0.0
var _counting := false
var _spot_pulse := 0.0
var _paint_mode := false
var _brush_radius := 0.09
var _brush_color := Color.WHITE
var _ring_pos := Vector2.ZERO
var _ring_px := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Blindfold sits under the other HUD elements.
	_blindfold = Control.new()
	_blindfold.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blindfold.visible = false
	root.add_child(_blindfold)
	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.05, 0.07, 0.97)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blindfold.add_child(dark)
	var bf_box := VBoxContainer.new()
	bf_box.set_anchors_preset(Control.PRESET_CENTER)
	bf_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bf_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_blindfold.add_child(bf_box)
	var bf := Label.new()
	bf.text = "the hiders are painting themselves..."
	bf.add_theme_font_size_override("font_size", 28)
	bf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bf_box.add_child(bf)
	_blindfold_timer = Label.new()
	_blindfold_timer.add_theme_font_size_override("font_size", 48)
	_blindfold_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bf_box.add_child(_blindfold_timer)

	# Top bar.
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 12
	root.add_child(top)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 22)
	top.add_child(_phase_label)
	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 40)
	top.add_child(_timer_label)
	_spotted_label = Label.new()
	_spotted_label.text = "SPOTTED  +bold points"
	_spotted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spotted_label.add_theme_font_size_override("font_size", 20)
	_spotted_label.add_theme_color_override("font_color", Color("ff5a4d"))
	_spotted_label.visible = false
	top.add_child(_spotted_label)
	_paint_mode_label = Label.new()
	_paint_mode_label.text = "PAINT MODE"
	_paint_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paint_mode_label.add_theme_font_size_override("font_size", 18)
	_paint_mode_label.add_theme_color_override("font_color", Color("8fd18a"))
	_paint_mode_label.visible = false
	top.add_child(_paint_mode_label)

	# Role card, top-left.
	_role_label = Label.new()
	_role_label.position = Vector2(16, 12)
	_role_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_role_label)
	_hint_label = Label.new()
	_hint_label.position = Vector2(16, 40)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	root.add_child(_hint_label)

	# Alive counter, top-right.
	_alive_label = Label.new()
	_alive_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_alive_label.position = Vector2(-180, 12)
	_alive_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_alive_label)

	# Crosshair (hidden in paint mode, where the OS cursor takes over).
	_cross = ColorRect.new()
	_cross.color = Color(1, 1, 1, 0.85)
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.size = Vector2(5, 5)
	_cross.position = Vector2(-2.5, -2.5)
	root.add_child(_cross)

	# Brush ring: follows the cursor in paint mode at true projected size.
	_brush_ring = Control.new()
	_brush_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brush_ring.visible = false
	_brush_ring.draw.connect(_draw_brush_ring)
	root.add_child(_brush_ring)

	# Bottom-center: hider palette info.
	_bottom_hider = HBoxContainer.new()
	_bottom_hider.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom_hider.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom_hider.position.y = -56
	_bottom_hider.add_theme_constant_override("separation", 12)
	root.add_child(_bottom_hider)
	var sw_frame := PanelContainer.new()
	var sw_style := StyleBoxFlat.new()
	sw_style.bg_color = Color(0, 0, 0, 0.5)
	sw_style.set_corner_radius_all(6)
	sw_style.set_content_margin_all(4)
	sw_frame.add_theme_stylebox_override("panel", sw_style)
	_bottom_hider.add_child(sw_frame)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(40, 40)
	_swatch.color = Color.WHITE
	sw_frame.add_child(_swatch)
	var br_frame := PanelContainer.new()
	br_frame.add_theme_stylebox_override("panel", sw_style)
	_bottom_hider.add_child(br_frame)
	_brush_preview = Control.new()
	_brush_preview.custom_minimum_size = Vector2(40, 40)
	_brush_preview.draw.connect(_draw_brush_preview)
	br_frame.add_child(_brush_preview)
	_brush_label = Label.new()
	_brush_label.add_theme_font_size_override("font_size", 14)
	_brush_label.text = MOVE_HINT
	_bottom_hider.add_child(_brush_label)

	# Bottom-center: seeker ammo.
	_ammo_label = Label.new()
	_ammo_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ammo_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ammo_label.position.y = -56
	_ammo_label.add_theme_font_size_override("font_size", 26)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo_label.visible = false
	root.add_child(_ammo_label)

	# Bottom-right ragdoll control. R is always available; the button is also
	# clickable whenever the cursor is visible (notably while painting).
	_ragdoll_button = Button.new()
	_ragdoll_button.text = "R  RAGDOLL"
	_ragdoll_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ragdoll_button.position = Vector2(-176, -64)
	_ragdoll_button.size = Vector2(160, 42)
	_ragdoll_button.set_meta("interactive_hud", true)
	_ragdoll_button.pressed.connect(func() -> void:
		App.play_ui_click()
		ragdoll_toggled.emit())
	root.add_child(_ragdoll_button)

	# Big center banner (eliminated, etc.).
	_center_banner = Label.new()
	_center_banner.set_anchors_preset(Control.PRESET_CENTER)
	_center_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_banner.position.y = -80
	_center_banner.add_theme_font_size_override("font_size", 42)
	_center_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_banner.visible = false
	root.add_child(_center_banner)

	# Results overlay, above everything.
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	root.add_child(_results)

	_pass_mouse_through(root)
	_ragdoll_button.mouse_filter = Control.MOUSE_FILTER_STOP


## HUD chrome must never eat input. Controls default to MOUSE_FILTER_STOP, and
## while the mouse is captured every motion event lands at dead center — right
## on the crosshair — so a STOP control there consumes the event before it can
## reach the player's _unhandled_input, killing camera orbit entirely.
func _pass_mouse_through(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_pass_mouse_through(child)


func _process(delta: float) -> void:
	if _counting:
		_time_left = maxf(0.0, _time_left - delta)
		var txt := "%d:%02d" % [int(_time_left) / 60, int(_time_left) % 60]
		_timer_label.text = txt
		_blindfold_timer.text = txt
	if _spotted_label.visible:
		_spot_pulse += delta * 6.0
		_spotted_label.modulate.a = 0.6 + 0.4 * sin(_spot_pulse)


func setup(role: int) -> void:
	if role == MatchState.Role.SEEKER:
		_role_label.text = "SEEKER"
		_role_label.add_theme_color_override("font_color", Color("ff8a5c"))
		_hint_label.text = "find the painted hiders. LMB to shoot. Esc menu."
	else:
		_role_label.text = "HIDER"
		_role_label.add_theme_color_override("font_color", Color("8fd18a"))
		_hint_label.text = "press F, then paint yourself to match the world.\nR ragdoll, WASD fly cam, Esc menu."
	_ragdoll_button.visible = role == MatchState.Role.HIDER


func set_ragdoll(active: bool) -> void:
	_ragdoll_button.text = "R  STAND UP" if active else "R  RAGDOLL"


func on_phase(phase: int, duration: float, role: int, extra: Dictionary) -> void:
	_time_left = duration
	_counting = true
	# The server broadcasts the RESULTS scores before the phase change, so the
	# already-visible scoreboard must survive this call.
	if phase != MatchState.Phase.RESULTS:
		_results.visible = false
	match phase:
		MatchState.Phase.PAINT:
			_phase_label.text = "PAINT PHASE — blend in"
			_blindfold.visible = role == MatchState.Role.SEEKER
			_bottom_hider.visible = role == MatchState.Role.HIDER
		MatchState.Phase.SEEK:
			_phase_label.text = "SEEK PHASE — they're coming"
			_blindfold.visible = false
			if role == MatchState.Role.SEEKER and extra.has("ammo"):
				set_ammo(int(extra["ammo"]))
		MatchState.Phase.RESULTS:
			_phase_label.text = "RESULTS"
			_blindfold.visible = false
			_spotted_label.visible = false


func set_swatch(color: Color, brush: float) -> void:
	_swatch.color = color
	if brush != _brush_radius or color != _brush_color:
		_brush_radius = brush
		_brush_color = color
		_brush_preview.queue_redraw()


func set_paint_mode(on: bool) -> void:
	if on == _paint_mode:
		return
	_paint_mode = on
	_cross.visible = not on
	_brush_ring.visible = on
	_paint_mode_label.visible = on
	_brush_label.text = PAINT_HINT if on else MOVE_HINT


## Called every frame while paint mode is on: cursor position in viewport
## pixels plus the brush's projected on-screen radius.
func set_brush_cursor(pos: Vector2, radius_px: float, color: Color) -> void:
	_ring_pos = pos
	_ring_px = maxf(radius_px, 3.0)
	_brush_color = color
	_brush_ring.queue_redraw()


func _draw_brush_ring() -> void:
	var c := _brush_color
	c.a = 1.0
	# Dark halo first so the ring reads against bright walls too.
	_brush_ring.draw_arc(_ring_pos, _ring_px, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 3.5, true)
	_brush_ring.draw_arc(_ring_pos, _ring_px, 0.0, TAU, 48, c, 1.8, true)
	# Keep the exact cursor pixel transparent: the eyedropper samples that pixel
	# from the rendered viewport, so drawing a center dot makes it resample the
	# current brush color instead of the surface underneath.


func _draw_brush_preview() -> void:
	var center := _brush_preview.size / 2.0
	# brush_radius spans 0.05..0.25 m (see player.gd); map onto the 40px box.
	var px := remap(_brush_radius, 0.05, 0.25, 4.0, 19.0)
	_brush_preview.draw_circle(center, px, _brush_color)
	_brush_preview.draw_arc(center, px, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 1.5)


func set_ammo(n: int) -> void:
	_ammo_label.visible = true
	_ammo_label.text = "AMMO  %d" % n


func set_alive(n: int, total: int) -> void:
	_alive_label.text = "hiders  %d / %d" % [n, total]


func set_spotted(spotted: bool) -> void:
	_spotted_label.visible = spotted


func show_banner(text: String, color := Color.WHITE) -> void:
	_center_banner.text = text
	_center_banner.add_theme_color_override("font_color", color)
	_center_banner.visible = true
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func() -> void: _center_banner.visible = false)


func show_results(scores: Array, winner: int, my_id: int) -> void:
	for c in _results.get_children():
		c.queue_free()
	_results.visible = true

	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.05, 0.08, 0.85)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dark)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)

	var banner := Label.new()
	if winner == MatchState.Team.HIDERS:
		banner.text = "HIDERS WIN"
		banner.add_theme_color_override("font_color", Color("8fd18a"))
	elif winner == MatchState.Team.SEEKERS:
		banner.text = "SEEKERS WIN"
		banner.add_theme_color_override("font_color", Color("ff8a5c"))
	else:
		banner.text = "ROUND OVER"
	banner.add_theme_font_size_override("font_size", 46)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(banner)

	for row: Dictionary in scores:
		var l := Label.new()
		var role_txt := "seeker" if row["role"] == MatchState.Role.SEEKER else "hider"
		var state := "" if row["alive"] else "  [eliminated]"
		var me := "  <- you" if row["id"] == my_id else ""
		l.text = "%-18s %-7s %5d%s%s" % [row["name"], role_txt, row["score"], state, me]
		l.add_theme_font_size_override("font_size", 20)
		box.add_child(l)
		var detail := Label.new()
		detail.text = "        " + _score_breakdown(row)
		detail.add_theme_font_size_override("font_size", 13)
		detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		box.add_child(detail)

	var back := Label.new()
	back.text = "back to lobby shortly..."
	back.add_theme_font_size_override("font_size", 14)
	back.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(back)

	_pass_mouse_through(_results)


## One line per player explaining where the total came from.
func _score_breakdown(row: Dictionary) -> String:
	var parts: Array[String] = []
	if row["role"] == MatchState.Role.SEEKER:
		parts.append("found %d  +%d" % [row["kills"], row["kill_points"]])
		if row["bonus"] > 0:
			parts.append("sweep bonus +%d" % row["bonus"])
	else:
		parts.append("survival +%d" % row["survival"])
		parts.append("bold +%d" % row["bold"])
		if row["bonus"] > 0:
			parts.append("survived +%d" % row["bonus"])
	return "   ".join(parts)
