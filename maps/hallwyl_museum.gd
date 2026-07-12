extends Node3D
## Hallwyl Museum map contract and verified walkable spawn points.


func hider_spawns() -> Array:
	return [
		Vector3(1, 4.72, 19), Vector3(-2, 4.72, 19), Vector3(4, 4.70, 19),
		Vector3(9, 4.63, 11), Vector3(-1, 4.61, 11), Vector3(-8, 5.47, 2),
		Vector3(-9, 4.55, 5), Vector3(-7, 4.59, 0), Vector3(-6, 4.58, 9),
		Vector3(9, 4.54, 1), Vector3(11, 4.59, 6),
	]


func seeker_spawns() -> Array:
	return [
		Vector3(-8, 4.52, -5), Vector3(-6, 4.52, -5), Vector3(-7, 4.53, -6),
		Vector3(9, 4.50, -5), Vector3(11, 4.50, -5), Vector3(9, 4.50, -3),
		Vector3(11, 4.50, -3), Vector3(12, 4.51, -5),
	]


func set_seek_open(_open: bool) -> void:
	# The player phase logic immobilizes and blinds seekers during painting, so
	# this historic interior does not need a removable release gate.
	pass
