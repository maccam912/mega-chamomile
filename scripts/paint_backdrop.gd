extends Control
## Lightweight, code-drawn menu art. It keeps the title screen lively without
## loading a 3D map or adding a large bitmap to every build.

var reduce_motion := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(not reduce_motion)
	queue_redraw()


func set_reduce_motion(reduced: bool) -> void:
	reduce_motion = reduced
	set_process(not reduced)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var drift := 0.0 if reduce_motion else sin(_time * 0.38) * 14.0
	var sway := 0.0 if reduce_motion else cos(_time * 0.25) * 10.0

	# Broad brush trails create depth while preserving a quiet center for text.
	draw_line(Vector2(-80, h * 0.82 + drift), Vector2(w * 0.63, h * 0.20 + drift),
			Color(1.0, 0.35, 0.27, 0.16), 128.0, true)
	draw_line(Vector2(w * 0.18, h + 70 + sway), Vector2(w * 0.76, -80 + sway),
			Color(0.31, 0.77, 1.0, 0.11), 92.0, true)
	draw_line(Vector2(w * 0.57, h + 80 - drift), Vector2(w + 90, h * 0.32 - drift),
			Color(0.47, 0.88, 0.63, 0.12), 112.0, true)

	# Uneven clusters read as paint splashes instead of generic circles.
	_blob(Vector2(w * 0.08 + sway, h * 0.18), 58.0, Color(1.0, 0.45, 0.36, 0.28))
	_blob(Vector2(w * 0.46 - drift, h * 0.88), 50.0, Color(0.95, 0.77, 0.25, 0.20))
	_blob(Vector2(w * 0.92 + drift, h * 0.12), 70.0, Color(0.39, 0.73, 1.0, 0.20))
	_blob(Vector2(w * 0.82 - sway, h * 0.78), 42.0, Color(0.47, 0.88, 0.63, 0.22))

	# Small droplets supply restrained motion and a playful edge treatment.
	for drop in [
		[Vector2(0.14, 0.10), 9.0, Color("ff735d")],
		[Vector2(0.32, 0.91), 7.0, Color("f3c85b")],
		[Vector2(0.76, 0.12), 6.0, Color("77e0a1")],
		[Vector2(0.94, 0.62), 10.0, Color("63b9ff")],
		[Vector2(0.58, 0.08), 5.0, Color("ff735d")],
	]:
		var p: Vector2 = drop[0]
		var bob := 0.0 if reduce_motion else sin(_time * 0.7 + p.x * 9.0) * 6.0
		draw_circle(Vector2(p.x * w, p.y * h + bob), drop[1], Color(drop[2], 0.55))


func _blob(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)
	draw_circle(center + Vector2(radius * 0.72, radius * 0.10), radius * 0.48, color)
	draw_circle(center + Vector2(-radius * 0.58, radius * 0.26), radius * 0.38, color)
	draw_circle(center + Vector2(radius * 0.15, -radius * 0.64), radius * 0.32, color)
