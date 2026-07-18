extends Node3D
## Luma Living Room Gaussian splat map contract.
##
## GDGS centers the imported points. The scene applies its standard 180-degree
## Z correction plus a 4x dollhouse-scale enlargement, then lifts the scanned
## floor to world Y=0. The only authored collision is a flat floor; furniture
## and walls remain non-solid.

const ROOM_SCALE := 4.0
const SPAWN_Y := 1.0


func hider_spawns() -> Array:
	return [
		_spawn(-2.5, -1.6), _spawn(-1.0, -1.6),
		_spawn(0.5, -1.6), _spawn(2.0, -1.6),
		_spawn(-2.5, 0.0), _spawn(-1.0, 0.0),
		_spawn(0.5, 0.0), _spawn(2.0, 0.0),
		_spawn(-2.0, 1.6), _spawn(0.0, 1.6),
		_spawn(2.0, 1.6), _spawn(3.0, 0.8),
	]


func seeker_spawns() -> Array:
	return [
		_spawn(-3.2, 2.2), _spawn(-2.4, 2.2),
		_spawn(-1.6, 2.2), _spawn(-0.8, 2.2),
		_spawn(0.0, 2.2), _spawn(0.8, 2.2),
		_spawn(1.6, 2.2), _spawn(2.4, 2.2),
	]


func set_seek_open(_open: bool) -> void:
	# Seekers are immobilized and blinded by the phase logic, so this preview
	# map does not need a physical release gate.
	pass


func _spawn(source_x: float, source_z: float) -> Vector3:
	return Vector3(source_x * ROOM_SCALE, SPAWN_Y, source_z * ROOM_SCALE)
