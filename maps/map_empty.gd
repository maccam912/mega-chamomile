extends Node3D
## Blank editor-built map scaffold. This script only fulfils the game map
## contract; it intentionally does not create or place any scene objects.


func hider_spawns() -> Array:
	return [
		Vector3(0, 1, 0), Vector3(3, 1, 0), Vector3(-3, 1, 0),
		Vector3(0, 1, 3), Vector3(0, 1, -3), Vector3(6, 1, 0),
		Vector3(-6, 1, 0), Vector3(0, 1, 6), Vector3(0, 1, -6),
		Vector3(6, 1, 6), Vector3(-6, 1, 6), Vector3(6, 1, -6),
	]


func seeker_spawns() -> Array:
	return [
		Vector3(-7, 1, 18), Vector3(-5, 1, 18), Vector3(-3, 1, 18),
		Vector3(-1, 1, 18), Vector3(1, 1, 18), Vector3(3, 1, 18),
		Vector3(5, 1, 18), Vector3(7, 1, 18),
	]


func set_seek_open(_open: bool) -> void:
	pass
