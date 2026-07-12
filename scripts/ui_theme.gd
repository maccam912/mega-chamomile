class_name PaintSeekUITheme
extends RefCounted
## Shared UI palette, typography, spacing, and control states. Every menu/HUD
## attaches this theme at its root so the 1280x720 logical canvas scales as one
## coherent interface on standard- and high-DPI displays.

const INK := Color("17202b")
const SURFACE := Color("252c39")
const SURFACE_RAISED := Color("303949")
const TEXT := Color("f7f1e8")
const MUTED := Color("aab4c5")
const MINT := Color("77e0a1")
const MINT_BRIGHT := Color("9af0b8")
const CORAL := Color("ff735d")
const GOLD := Color("f3c85b")
const BLUE := Color("63b9ff")

static var _shared: Theme


static func shared() -> Theme:
	if _shared != null:
		return _shared
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/Kenney Future.ttf")
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.28))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)

	_style_buttons(theme)
	_style_fields(theme)
	_style_panels(theme)

	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", MINT_BRIGHT)
	theme.set_color("font_pressed_color", "CheckButton", MINT)
	theme.set_constant("h_separation", "CheckButton", 10)
	theme.set_font_size("font_size", "CheckButton", 14)

	theme.set_stylebox("separator", "HSeparator", _line(Color(1, 1, 1, 0.12), 1))
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	_shared = theme
	return _shared


static func _style_buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _box(SURFACE_RAISED, 10, 1, Color(1, 1, 1, 0.08), 12))
	theme.set_stylebox("hover", "Button", _box(Color("3b4658"), 10, 2, MINT, 11))
	theme.set_stylebox("pressed", "Button", _box(Color("202733"), 10, 2, MINT_BRIGHT, 11))
	theme.set_stylebox("focus", "Button", _outline(MINT_BRIGHT, 10, 2))
	theme.set_stylebox("disabled", "Button", _box(Color("252b36"), 10, 1, Color(1, 1, 1, 0.04), 12))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", MINT_BRIGHT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.35))
	theme.set_font_size("font_size", "Button", 15)

	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _box(MINT, 12, 0, Color.TRANSPARENT, 14))
	theme.set_stylebox("hover", "PrimaryButton", _box(MINT_BRIGHT, 12, 2, Color.WHITE, 12))
	theme.set_stylebox("pressed", "PrimaryButton", _box(Color("57c982"), 12, 2, INK, 12))
	theme.set_stylebox("focus", "PrimaryButton", _outline(Color.WHITE, 12, 2))
	theme.set_stylebox("disabled", "PrimaryButton", _box(Color("4f6c5d"), 12, 0, Color.TRANSPARENT, 14))
	theme.set_color("font_color", "PrimaryButton", INK)
	theme.set_color("font_hover_color", "PrimaryButton", INK)
	theme.set_color("font_pressed_color", "PrimaryButton", INK)
	theme.set_color("font_focus_color", "PrimaryButton", INK)
	theme.set_color("font_disabled_color", "PrimaryButton", Color(INK, 0.5))
	theme.set_font_size("font_size", "PrimaryButton", 17)

	theme.set_type_variation("QuietButton", "Button")
	theme.set_stylebox("normal", "QuietButton", _box(Color(1, 1, 1, 0.035), 8, 1, Color(1, 1, 1, 0.08), 9))
	theme.set_stylebox("hover", "QuietButton", _box(Color(MINT, 0.12), 8, 1, Color(MINT, 0.55), 9))
	theme.set_stylebox("pressed", "QuietButton", _box(Color(MINT, 0.2), 8, 1, MINT, 9))
	theme.set_stylebox("focus", "QuietButton", _outline(MINT, 8, 2))
	theme.set_font_size("font_size", "QuietButton", 13)


static func _style_fields(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _box(Color("1d2430"), 9, 1, Color(1, 1, 1, 0.12), 12))
	theme.set_stylebox("focus", "LineEdit", _box(Color("1d2430"), 9, 2, MINT, 11))
	theme.set_stylebox("read_only", "LineEdit", _box(Color("242b36"), 9, 1, Color(1, 1, 1, 0.06), 12))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.62))
	theme.set_color("caret_color", "LineEdit", MINT_BRIGHT)
	theme.set_color("selection_color", "LineEdit", Color(MINT, 0.28))
	theme.set_font_size("font_size", "LineEdit", 16)
	theme.set_constant("minimum_character_width", "LineEdit", 4)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _box(SURFACE, 16, 1, Color(1, 1, 1, 0.09), 0))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, 16, 1, Color(1, 1, 1, 0.09), 18))
	theme.set_type_variation("GlassPanel", "PanelContainer")
	theme.set_stylebox("panel", "GlassPanel", _box(Color(0.10, 0.13, 0.17, 0.94), 22, 1, Color(1, 1, 1, 0.14), 26))
	theme.set_type_variation("AccentPanel", "PanelContainer")
	theme.set_stylebox("panel", "AccentPanel", _box(Color(MINT, 0.12), 99, 1, Color(MINT, 0.4), 8))


static func _box(color: Color, radius: int, border: int, border_color: Color,
		padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border)
	style.border_color = border_color
	style.set_content_margin_all(padding)
	style.anti_aliasing = true
	return style


static func _outline(color: Color, radius: int, width: int) -> StyleBoxFlat:
	return _box(Color.TRANSPARENT, radius, width, color, 0)


static func _line(color: Color, width: int) -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = color
	style.thickness = width
	return style
