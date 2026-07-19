extends Node3D
## Violets Room map contract. The scan is enlarged so regular game avatars
## feel like large dolls in the real-world room.


func hider_spawns() -> Array:
	return [
		Vector3(-4, 1, -1), Vector3(-1, 1, -1), Vector3(2, 1, -1),
		Vector3(5, 1, -1), Vector3(-4, 1, 2), Vector3(-1, 1, 2),
		Vector3(2, 1, 2), Vector3(5, 1, 2), Vector3(-4, 1, 5),
		Vector3(-1, 1, 5), Vector3(2, 1, 5), Vector3(5, 1, 5),
	]


func seeker_spawns() -> Array:
	return [
		Vector3(-6, 1, -7), Vector3(-4, 1, -7), Vector3(-2, 1, -7),
		Vector3(0, 1, -7), Vector3(2, 1, -7), Vector3(4, 1, -7),
		Vector3(6, 1, -7), Vector3(-6, 1, -5),
	]


func set_seek_open(_open: bool) -> void:
	# Phase logic already immobilizes and blinds seekers during painting.
	pass
