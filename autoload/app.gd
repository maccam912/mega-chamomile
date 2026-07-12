extends Node
## App-level singleton: settings, scene transitions, input map, CLI args, UI sounds.

const PORT := 24565
const GAME_SCENE := "res://scenes/game.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_MAP_ID := "basic"
const MAPS := {
	"basic": {
		"label": "Basic Arena",
		"scene": "res://maps/map_basic.tscn",
	},
	"empty": {
		"label": "Empty Map",
		"scene": "res://maps/map_empty.tscn",
	},
	"hallwyl_museum": {
		"label": "Hallwyl Museum",
		"scene": "res://maps/hallwyl_museum.tscn",
	},
}

## Host-configured match settings. The host's copy is authoritative; relevant
## values reach clients inside match/phase broadcasts.
var settings := {
	"map_id": DEFAULT_MAP_ID,
	"seeker_count": 1,
	"paint_time": 90.0,
	"seek_time": 180.0,
	"shot_cooldown": 0.8,
	"ammo_per_hider": 3,
}

var status_message := ""  ## shown on the main menu after disconnects/errors
var last_scores: Array = []
var last_winner: int = 0
var in_match := false
var selected_avatar := AvatarCatalog.DEFAULT_ID
var cli := {}  ## parsed user args: name/host/join/autostart/fast-phases/quit-after

var _ui_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_map()
	_parse_cli()
	if cli.has("avatar"):
		select_avatar(str(cli["avatar"]))
	_ui_player = AudioStreamPlayer.new()
	_ui_player.stream = load("res://assets/audio/ui_click.ogg")
	add_child(_ui_player)
	if cli.has("fast-phases"):
		settings["paint_time"] = 4.0
		settings["seek_time"] = 6.0
	if cli.has("screenshot"):
		var st := Timer.new()
		st.wait_time = float(cli.get("screenshot-at", "8"))
		st.one_shot = true
		st.timeout.connect(func() -> void:
			var img := get_viewport().get_texture().get_image()
			img.save_png(str(cli["screenshot"]))
			print("[app] screenshot saved to ", cli["screenshot"]))
		add_child(st)
		st.start()
	if cli.has("quit-after"):
		var t := Timer.new()
		t.wait_time = float(cli["quit-after"])
		t.one_shot = true
		t.timeout.connect(func() -> void:
			print("[app] --quit-after reached, quitting")
			get_tree().quit())
		add_child(t)
		t.start()


func goto_scene(path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", path)


func to_main_menu(msg := "") -> void:
	status_message = msg
	in_match = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	goto_scene(MENU_SCENE)


func play_ui_click() -> void:
	_ui_player.play()


func select_map(map_id: String) -> void:
	settings["map_id"] = map_id if MAPS.has(map_id) else DEFAULT_MAP_ID


func select_avatar(avatar_id: String) -> void:
	selected_avatar = AvatarCatalog.normalize(avatar_id)


func selected_map_scene() -> String:
	var map_id := str(settings.get("map_id", DEFAULT_MAP_ID))
	if not MAPS.has(map_id):
		map_id = DEFAULT_MAP_ID
	return str(MAPS[map_id]["scene"])


func _parse_cli() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i].trim_prefix("--")
		var val := "true"
		if i + 1 < args.size() and not args[i + 1].begins_with("--"):
			val = args[i + 1]
			i += 1
		cli[a] = val
		i += 1
	if not cli.is_empty():
		print("[app] cli args: ", cli)


func _setup_input_map() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("crouch", KEY_C)
	_add_key("pause", KEY_ESCAPE)
	_add_key("toggle_paint_mode", KEY_F)
	_add_key("toggle_ragdoll", KEY_R)
	_add_key("unstuck", KEY_U)
	_add_key("toggle_hidden", KEY_H)
	_add_key("start_seeking_early", KEY_ENTER)
	_add_mouse("primary_action", MOUSE_BUTTON_LEFT)   # paint (hider) / shoot (seeker)
	_add_mouse("eyedrop", MOUSE_BUTTON_RIGHT)
	_add_mouse("brush_grow", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse("brush_shrink", MOUSE_BUTTON_WHEEL_DOWN)


func _add_key(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
