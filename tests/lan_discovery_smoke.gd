extends Node
## Loopback integration check for the real Net LAN advertiser and browser.
## Run from the project root:
##   godot --headless tests/lan_discovery_smoke.tscn

const TIMEOUT_SECONDS := 5.0
var _elapsed := 0.0
var _matching_updates := 0


func _ready() -> void:
	Net.my_name = "LAN Smoke Host"
	Net.players = {1: {"name": Net.my_name}}
	Net.lan_games_changed.connect(_on_games_changed)
	Net._start_lan_advertising()
	Net.start_lan_discovery()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= TIMEOUT_SECONDS:
		_finish(false, "timed out waiting for the loopback advertisement")


func _on_games_changed(games: Array) -> void:
	for game: Dictionary in games:
		if game.get("host") == "LAN Smoke Host" and bool(game.get("compatible", false)):
			_matching_updates += 1
			if _matching_updates >= 2:
				_finish(true, "discovered and refreshed the compatible loopback host")
			return


func _finish(success: bool, message: String) -> void:
	Net.stop_lan_discovery()
	Net._stop_lan_advertising()
	if success:
		print("LAN DISCOVERY PASSED: ", message)
	else:
		printerr("LAN DISCOVERY FAILED: ", message)
	get_tree().quit(0 if success else 1)
