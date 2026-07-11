extends Node3D
## Basic blockout arena. Geometry is data-driven: each entry in ZONES becomes
## a colored box with collision, so new maps are mostly "edit the arrays".
## Contract every map must fulfil:
##   - hider_spawns() / seeker_spawns() -> Array[Vector3]
##   - set_seek_open(open: bool)  (releases the seeker pen)

const ARENA_HALF := 22.0
const WALL_H := 3.5
const WALL_T := 0.5

# Palette painted around the arena — these are the colors hiders will match.
const C_FLOOR := Color("9a9d9a")
const C_BORDER := Color("4a4e57")
const C_BRICK := Color("b5493a")
const C_BLUE := Color("3a6db5")
const C_HEDGE := Color("4a8f3c")
const C_YELLOW := Color("d9b93b")
const C_ORANGE := Color("d97b2e")
const C_PURPLE := Color("7b4fa0")
const C_WHITE := Color("e8e8e8")
const C_WOOD := Color("8a6742")
const C_PEN := Color("3c4048")

## {size, pos, color} — pos is the box center.
var ZONES := [
	# Big colored walls to hide against (inset from the border walls).
	{"size": Vector3(14, 3.0, 0.6), "pos": Vector3(-4, 1.5, -19.0), "color": C_BRICK},
	{"size": Vector3(10, 3.0, 0.6), "pos": Vector3(14, 1.5, -19.0), "color": C_PURPLE},
	{"size": Vector3(0.6, 3.0, 12), "pos": Vector3(19.0, 1.5, -8), "color": C_BLUE},
	{"size": Vector3(0.6, 3.0, 10), "pos": Vector3(19.0, 1.5, 8), "color": C_YELLOW},
	{"size": Vector3(0.6, 3.0, 14), "pos": Vector3(-19.0, 1.5, -6), "color": C_WHITE},
	{"size": Vector3(0.6, 3.0, 8), "pos": Vector3(-19.0, 1.5, 9), "color": C_WOOD},
	# Free-standing walls to break sightlines.
	{"size": Vector3(6, 2.6, 0.5), "pos": Vector3(-8, 1.3, -6), "color": C_BRICK},
	{"size": Vector3(0.5, 2.6, 6), "pos": Vector3(6, 1.3, -2), "color": C_BLUE},
	{"size": Vector3(6, 2.6, 0.5), "pos": Vector3(9, 1.3, 8), "color": C_PURPLE},
	# Hedge cluster (SW).
	{"size": Vector3(3, 1.8, 1.2), "pos": Vector3(-12, 0.9, 8), "color": C_HEDGE},
	{"size": Vector3(1.2, 1.8, 4), "pos": Vector3(-9, 0.9, 11), "color": C_HEDGE},
	{"size": Vector3(2.2, 1.4, 2.2), "pos": Vector3(-13, 0.7, 13), "color": C_HEDGE},
	# Yellow pillars (NE court).
	{"size": Vector3(1.1, 3.2, 1.1), "pos": Vector3(12, 1.6, -10), "color": C_YELLOW},
	{"size": Vector3(1.1, 3.2, 1.1), "pos": Vector3(15, 1.6, -6), "color": C_YELLOW},
	{"size": Vector3(1.1, 3.2, 1.1), "pos": Vector3(12, 1.6, -2), "color": C_YELLOW},
	# Orange crate stacks (center-east).
	{"size": Vector3(1.4, 1.4, 1.4), "pos": Vector3(2, 0.7, 4), "color": C_ORANGE},
	{"size": Vector3(1.4, 1.4, 1.4), "pos": Vector3(3.6, 0.7, 4.3), "color": C_ORANGE},
	{"size": Vector3(1.4, 1.4, 1.4), "pos": Vector3(2.8, 2.1, 4.15), "color": C_ORANGE},
	# Wood platform (west).
	{"size": Vector3(5, 1.0, 5), "pos": Vector3(-14, 0.5, 0), "color": C_WOOD},
	# White blocks near the white wall — the "easy start" corner.
	{"size": Vector3(2, 2.4, 2), "pos": Vector3(-16, 1.2, -10), "color": C_WHITE},
]

var _barrier: StaticBody3D


func _ready() -> void:
	_build_environment()
	_build_floor_and_border()
	for z: Dictionary in ZONES:
		add_child(_make_box(z["size"], z["pos"], z["color"]))
	_build_seeker_pen()


func hider_spawns() -> Array:
	return [
		Vector3(0, 1, 0), Vector3(3, 1, -3), Vector3(-3, 1, -3), Vector3(3, 1, 3),
		Vector3(-3, 1, 3), Vector3(6, 1, 0), Vector3(-6, 1, 0), Vector3(0, 1, -6),
		Vector3(0, 1, 6), Vector3(8, 1, -8), Vector3(-8, 1, 8), Vector3(8, 1, 8),
	]


func seeker_spawns() -> Array:
	return [
		Vector3(-2, 1, 26), Vector3(0, 1, 26), Vector3(2, 1, 26), Vector3(-2, 1, 28),
		Vector3(0, 1, 28), Vector3(2, 1, 28), Vector3(-2, 1, 24), Vector3(2, 1, 24),
	]


## Opens the pen when the SEEK phase begins. Deterministic from phase
## broadcasts, so every client flips it locally — no extra RPC needed.
func set_seek_open(open: bool) -> void:
	_barrier.visible = not open
	_barrier.get_node("Col").disabled = open


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a8d0e6")
	# Strong ambient so rendered pixel colors sit close to material albedo —
	# the eyedropper samples the screen, and paint should match what you see.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.25
	sun.shadow_enabled = true
	add_child(sun)


func _build_floor_and_border() -> void:
	add_child(_make_box(Vector3(ARENA_HALF * 2 + 14, 1, ARENA_HALF * 2 + 22),
			Vector3(0, -0.5, 3), C_FLOOR))
	var s := ARENA_HALF
	add_child(_make_box(Vector3(s * 2 + WALL_T, WALL_H, WALL_T), Vector3(0, WALL_H / 2, -s), C_BORDER))
	add_child(_make_box(Vector3(WALL_T, WALL_H, s * 2 + WALL_T), Vector3(-s, WALL_H / 2, 3), C_BORDER))
	add_child(_make_box(Vector3(WALL_T, WALL_H, s * 2 + WALL_T), Vector3(s, WALL_H / 2, 3), C_BORDER))
	# South wall sits past the seeker pen.
	add_child(_make_box(Vector3(s * 2 + WALL_T, WALL_H, WALL_T), Vector3(0, WALL_H / 2, 30), C_BORDER))


func _build_seeker_pen() -> void:
	# Pen walls flanking the release gate at z=22.
	add_child(_make_box(Vector3(16, WALL_H, WALL_T), Vector3(-13, WALL_H / 2, 22), C_PEN))
	add_child(_make_box(Vector3(16, WALL_H, WALL_T), Vector3(13, WALL_H / 2, 22), C_PEN))
	# The removable gate.
	_barrier = _make_box(Vector3(10, WALL_H, WALL_T), Vector3(0, WALL_H / 2, 22), Color("6e3d3d"))
	add_child(_barrier)


## A colored box with collision on the world layer (1).
func _make_box(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	col.name = "Col"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body
