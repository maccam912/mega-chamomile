extends Node
## Networking singleton: ENet host/join, replicated player registry, and every
## match-orchestration RPC. Living on an autoload means RPC node paths always
## match on every peer, regardless of which scene is loaded.

signal players_changed
signal join_failed(msg: String)
signal joined_ok
signal player_left(peer_id: int)
signal all_peers_scene_ready          ## server only
signal all_peers_match_ready          ## server only
signal shot_requested(shooter_id: int, origin: Vector3, dir: Vector3)  ## server only
signal match_setup(payload: Dictionary)
signal phase_changed(phase: int, duration: float, extra: Dictionary)
signal player_eliminated_sig(victim_id: int, shooter_id: int)
signal shot_fired_sig(shooter_id: int, origin: Vector3, hit_pos: Vector3)
signal spotted_changed(is_spotted: bool)
signal scores_updated(scores: Array, winner: int)
signal player_despawned(peer_id: int)
signal replay_readiness_changed(ready_ids: Array, player_count: int)
signal hiding_readiness_changed(hidden_count: int, hider_count: int, my_hidden: bool)
signal hidden_ready_requested(peer_id: int, hidden: bool)  ## server only
signal start_seeking_requested  ## server only
signal settings_changed(settings: Dictionary)
signal lan_games_changed(games: Array)

const SessionStateScript := preload("res://scripts/session_state.gd")
const DISCOVERY_PORT := 24566
const DISCOVERY_REQUEST := "PAINT_N_SEEK_DISCOVER_V1"
const DISCOVERY_PROTOCOL := 1
const DISCOVERY_PROBE_INTERVAL := 1.0
const DISCOVERY_STALE_SECONDS := 3.5

var players := {}  ## peer_id -> {"name": String, "avatar": String, "preference": String}
var my_name := "Painter"

var _ready_peers := {}
var _match_ready_peers := {}
var session: RefCounted = SessionStateScript.new()
var _accepting_replay_ready := false
var lobby_settings := {}
var _lan_server: UDPServer
var _lan_client: PacketPeerUDP
var _lan_games := {}  ## address -> advertised row + last_seen
var _lan_probe_left := 0.0


func _ready() -> void:
	set_process(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func host_game() -> Error:
	stop_lan_discovery()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(App.PORT, 16)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": my_name, "avatar": App.selected_avatar,
			"preference": App.selected_role_preference}}
	lobby_settings = App.settings.duplicate(true)
	session.reset([])
	session.add_player(1, App.lobby_identity)
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0
	players_changed.emit()
	_start_lan_advertising()
	return OK


func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, App.PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	lobby_settings.clear()
	session.reset([])
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0
	return OK


func leave() -> void:
	_stop_lan_advertising()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	lobby_settings.clear()
	_ready_peers.clear()
	_match_ready_peers.clear()
	session.reset([])
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0


func _process(delta: float) -> void:
	_poll_lan_advertising()
	_poll_lan_discovery(delta)


func _start_lan_advertising() -> void:
	_stop_lan_advertising()
	_lan_server = UDPServer.new()
	var err := _lan_server.listen(DISCOVERY_PORT)
	if err != OK:
		print("[net] LAN discovery advertising unavailable: ", error_string(err))
		_lan_server = null


func _stop_lan_advertising() -> void:
	if _lan_server != null:
		_lan_server.stop()
		_lan_server = null


func _poll_lan_advertising() -> void:
	if _lan_server == null or App.in_match:
		return
	_lan_server.poll()
	while _lan_server.is_connection_available():
		var peer := _lan_server.take_connection()
		if peer == null or peer.get_available_packet_count() == 0:
			continue
		var request := peer.get_packet().get_string_from_utf8()
		if request != DISCOVERY_REQUEST:
			continue
		var payload := {
			"protocol": DISCOVERY_PROTOCOL,
			"host": my_name,
			"players": players.size(),
			"capacity": 16,
			"port": App.PORT,
		}
		peer.put_packet(JSON.stringify(payload).to_utf8_buffer())


func start_lan_discovery() -> void:
	stop_lan_discovery()
	_lan_client = PacketPeerUDP.new()
	var err := _lan_client.bind(0)
	if err != OK:
		print("[net] LAN discovery unavailable: ", error_string(err))
		_lan_client = null
		return
	_lan_client.set_broadcast_enabled(true)
	_lan_games.clear()
	_lan_probe_left = 0.0
	lan_games_changed.emit([])


func stop_lan_discovery() -> void:
	if _lan_client != null:
		_lan_client.close()
		_lan_client = null
	_lan_games.clear()


func _poll_lan_discovery(delta: float) -> void:
	if _lan_client == null:
		return
	_lan_probe_left -= delta
	if _lan_probe_left <= 0.0:
		_lan_probe_left = DISCOVERY_PROBE_INTERVAL
		_lan_client.set_dest_address("255.255.255.255", DISCOVERY_PORT)
		_lan_client.put_packet(DISCOVERY_REQUEST.to_utf8_buffer())
		# Also supports two-instance testing on one computer; LAN hosts still
		# arrive through the broadcast above.
		_lan_client.set_dest_address("127.0.0.1", DISCOVERY_PORT)
		_lan_client.put_packet(DISCOVERY_REQUEST.to_utf8_buffer())
	var changed := false
	while _lan_client.get_available_packet_count() > 0:
		var bytes := _lan_client.get_packet()
		var address := _lan_client.get_packet_ip()
		var parsed = JSON.parse_string(bytes.get_string_from_utf8())
		if not parsed is Dictionary or not parsed.has("protocol"):
			continue
		var row: Dictionary = parsed
		row["address"] = address
		row["compatible"] = int(row["protocol"]) == DISCOVERY_PROTOCOL
		row["last_seen"] = Time.get_ticks_msec() / 1000.0
		var is_new := not _lan_games.has(address)
		_lan_games[address] = row
		if is_new:
			print("[net] discovered LAN game %s at %s" % [row.get("host", "?"), address])
		changed = true
	var now := Time.get_ticks_msec() / 1000.0
	for address: String in _lan_games.keys():
		if now - float(_lan_games[address]["last_seen"]) > DISCOVERY_STALE_SECONDS:
			_lan_games.erase(address)
			changed = true
	if changed:
		var rows := _lan_games.values()
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("host", "")) < str(b.get("host", "")))
		lan_games_changed.emit(rows)


# --- connection lifecycle -------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_server() and App.in_match:
		# No late joins mid-match in the MVP.
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	players.erase(id)
	session.remove_player(id)
	_ready_peers.erase(id)
	_match_ready_peers.erase(id)
	rpc(&"_sync_players", players)
	players_changed.emit()
	player_left.emit(id)
	if _accepting_replay_ready:
		_broadcast_replay_readiness()
	_check_barriers()


func _on_connected_ok() -> void:
	rpc_id(1, &"_register_player", my_name, App.selected_avatar,
			App.selected_role_preference, App.lobby_identity)
	joined_ok.emit()


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Could not connect to host.")


func _on_server_disconnected() -> void:
	leave()
	App.to_main_menu("Host disconnected.")


# --- player registry ------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register_player(pname: String, avatar_id: String, preference: String,
		lobby_identity: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {
		"name": pname.substr(0, 20),
		"avatar": AvatarCatalog.normalize(avatar_id),
		"preference": _normalize_preference(preference),
	}
	rpc_id(id, &"_sync_settings", App.settings)
	session.add_player(id, lobby_identity.substr(0, 80))
	rpc(&"_sync_players", players)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_players(new_players: Dictionary) -> void:
	players = new_players
	players_changed.emit()


## Lobby customization is server-authoritative and becomes part of the match
## setup payload. Keeping it in the player registry also preserves replays.
func request_avatar(avatar_id: String) -> void:
	var normalized := AvatarCatalog.normalize(avatar_id)
	App.select_avatar(normalized)
	if is_server():
		_set_player_avatar(1, normalized)
	else:
		rpc_id(1, &"_request_avatar", normalized)


@rpc("any_peer", "call_remote", "reliable")
func _request_avatar(avatar_id: String) -> void:
	if is_server():
		_set_player_avatar(multiplayer.get_remote_sender_id(), avatar_id)


func _set_player_avatar(id: int, avatar_id: String) -> void:
	if App.in_match or not players.has(id):
		return
	players[id]["avatar"] = AvatarCatalog.normalize(avatar_id)
	rpc(&"_sync_players", players)
	players_changed.emit()


func request_role_preference(preference: String) -> void:
	var normalized := _normalize_preference(preference)
	App.select_role_preference(normalized)
	if is_server():
		_set_role_preference(1, normalized)
	else:
		rpc_id(1, &"_request_role_preference", normalized)


@rpc("any_peer", "call_remote", "reliable")
func _request_role_preference(preference: String) -> void:
	if is_server():
		_set_role_preference(multiplayer.get_remote_sender_id(), preference)


func _set_role_preference(id: int, preference: String) -> void:
	if App.in_match or not players.has(id):
		return
	players[id]["preference"] = _normalize_preference(preference)
	rpc(&"_sync_players", players)
	players_changed.emit()


func _normalize_preference(preference: String) -> String:
	return preference if preference in ["none", "seeker", "hider"] else "none"


func assign_session_roles(seeker_count: int) -> Array:
	var preferences := {}
	for id: int in players:
		preferences[id] = _normalize_preference(str(players[id].get("preference", "none")))
	return session.assign_roles(preferences, seeker_count)


func update_lobby_settings() -> void:
	if not is_server() or App.in_match:
		return
	App.apply_match_settings(App.settings)
	lobby_settings = App.settings.duplicate(true)
	rpc(&"_sync_settings", lobby_settings)
	settings_changed.emit(lobby_settings)


@rpc("authority", "call_remote", "reliable")
func _sync_settings(snapshot: Dictionary) -> void:
	App.apply_match_settings(snapshot)
	lobby_settings = App.settings.duplicate(true)
	settings_changed.emit(lobby_settings)


# --- match orchestration (host -> everyone) --------------------------------

## Host calls this from the lobby to move everyone into the game scene.
func request_start() -> void:
	if is_server():
		_begin_game_load()


## Every player opts in from the results screen. Once all connected players
## are ready, the host may reload the game scene for the next round.
func begin_replay_readiness() -> void:
	if not is_server():
		return
	_accepting_replay_ready = true
	session.begin_replay_vote(players.keys())
	_broadcast_replay_readiness()


func request_replay_ready(ready: bool) -> void:
	if is_server():
		_set_replay_ready(1, ready)
	else:
		rpc_id(1, &"_request_replay_ready", ready)


@rpc("any_peer", "call_remote", "reliable")
func _request_replay_ready(ready: bool) -> void:
	if is_server():
		_set_replay_ready(multiplayer.get_remote_sender_id(), ready)


func _set_replay_ready(id: int, ready: bool) -> void:
	if not _accepting_replay_ready or not players.has(id):
		return
	if session.set_replay_ready(id, ready):
		_broadcast_replay_readiness()


func request_replay_start() -> bool:
	if not is_server() or not _accepting_replay_ready:
		return false
	if session.all_replay_ready(players.keys()):
		_begin_game_load()
		return true
	return false


func _begin_game_load() -> void:
	_stop_lan_advertising()
	var snapshot: Dictionary = App.settings.duplicate(true)
	var fast_phases := App.cli.has("fast-phases")
	if fast_phases:
		snapshot["_fast_phases"] = true
	App.apply_match_settings(snapshot)
	snapshot = App.settings.duplicate(true)
	if fast_phases:
		snapshot["_fast_phases"] = true
	_accepting_replay_ready = false
	_ready_peers.clear()
	_match_ready_peers.clear()
	rpc(&"_load_game", snapshot)


func _broadcast_replay_readiness() -> void:
	rpc(&"_receive_replay_readiness", session.ready_ids(), players.size())


@rpc("authority", "call_local", "reliable")
func _receive_replay_readiness(ready_ids: Array, player_count: int) -> void:
	replay_readiness_changed.emit(ready_ids, player_count)


## Hiding readiness is personalized: everyone receives only the aggregate
## count plus their own state, never the identities of ready hiders.
func broadcast_hiding_readiness(hidden_ids: Array, hider_count: int) -> void:
	if not is_server():
		return
	var hidden_count := hidden_ids.size()
	for id: int in players:
		var my_hidden := hidden_ids.has(id)
		if id == 1:
			_receive_hiding_readiness(hidden_count, hider_count, my_hidden)
		else:
			rpc_id(id, &"_receive_hiding_readiness", hidden_count, hider_count, my_hidden)


@rpc("authority", "call_remote", "reliable")
func _receive_hiding_readiness(hidden_count: int, hider_count: int, my_hidden: bool) -> void:
	hiding_readiness_changed.emit(hidden_count, hider_count, my_hidden)


func request_hidden_ready(hidden: bool) -> void:
	if is_server():
		hidden_ready_requested.emit(1, hidden)
	else:
		rpc_id(1, &"_request_hidden_ready", hidden)


@rpc("any_peer", "call_remote", "reliable")
func _request_hidden_ready(hidden: bool) -> void:
	if is_server():
		hidden_ready_requested.emit(multiplayer.get_remote_sender_id(), hidden)


func request_start_seeking() -> void:
	if is_server():
		start_seeking_requested.emit()


@rpc("authority", "call_local", "reliable")
func _load_game(settings_snapshot: Dictionary) -> void:
	App.apply_match_settings(settings_snapshot)
	App.in_match = true
	App.status_message = ""
	App.goto_scene(App.GAME_SCENE)


## Each peer's game scene reports in once its tree is ready.
func notify_scene_ready() -> void:
	if is_server():
		_mark_scene_ready(1)
	else:
		rpc_id(1, &"_peer_scene_ready")


@rpc("any_peer", "call_remote", "reliable")
func _peer_scene_ready() -> void:
	if is_server():
		_mark_scene_ready(multiplayer.get_remote_sender_id())


func _mark_scene_ready(id: int) -> void:
	_ready_peers[id] = true
	_check_barriers()


func notify_match_ready() -> void:
	if is_server():
		_mark_match_ready(1)
	else:
		rpc_id(1, &"_peer_match_ready")


@rpc("any_peer", "call_remote", "reliable")
func _peer_match_ready() -> void:
	if is_server():
		_mark_match_ready(multiplayer.get_remote_sender_id())


func _mark_match_ready(id: int) -> void:
	_match_ready_peers[id] = true
	_check_barriers()


func _check_barriers() -> void:
	if not is_server():
		return
	if not _ready_peers.is_empty() and _all_present(_ready_peers):
		_ready_peers.clear()
		all_peers_scene_ready.emit()
	if not _match_ready_peers.is_empty() and _all_present(_match_ready_peers):
		_match_ready_peers.clear()
		all_peers_match_ready.emit()


func _all_present(marks: Dictionary) -> bool:
	for id: int in players:
		if not marks.has(id):
			return false
	return true


func broadcast_match_setup(payload: Dictionary) -> void:
	rpc(&"_receive_match_setup", payload)


@rpc("authority", "call_local", "reliable")
func _receive_match_setup(payload: Dictionary) -> void:
	match_setup.emit(payload)


func broadcast_phase(phase: int, duration: float, extra := {}) -> void:
	rpc(&"_receive_phase", phase, duration, extra)


@rpc("authority", "call_local", "reliable")
func _receive_phase(phase: int, duration: float, extra: Dictionary) -> void:
	phase_changed.emit(phase, duration, extra)


func broadcast_elimination(victim_id: int, shooter_id: int) -> void:
	rpc(&"_receive_elimination", victim_id, shooter_id)


@rpc("authority", "call_local", "reliable")
func _receive_elimination(victim_id: int, shooter_id: int) -> void:
	player_eliminated_sig.emit(victim_id, shooter_id)


func broadcast_shot(shooter_id: int, origin: Vector3, hit_pos: Vector3) -> void:
	rpc(&"_receive_shot", shooter_id, origin, hit_pos)


@rpc("authority", "call_local", "reliable")
func _receive_shot(shooter_id: int, origin: Vector3, hit_pos: Vector3) -> void:
	shot_fired_sig.emit(shooter_id, origin, hit_pos)


func notify_spotted(peer_id: int, is_spotted: bool) -> void:
	if peer_id == 1:
		_receive_spotted(is_spotted)
	else:
		rpc_id(peer_id, &"_receive_spotted", is_spotted)


@rpc("authority", "call_remote", "reliable")
func _receive_spotted(is_spotted: bool) -> void:
	spotted_changed.emit(is_spotted)


func broadcast_scores(scores: Array, winner: int) -> void:
	rpc(&"_receive_scores", scores, winner)


func record_round_scores(scores: Array) -> Array:
	return session.record_round(scores) if is_server() else []


@rpc("authority", "call_local", "reliable")
func _receive_scores(scores: Array, winner: int) -> void:
	App.last_scores = scores
	App.last_winner = winner
	scores_updated.emit(scores, winner)


func broadcast_despawn(peer_id: int) -> void:
	rpc(&"_receive_despawn", peer_id)


@rpc("authority", "call_local", "reliable")
func _receive_despawn(peer_id: int) -> void:
	player_despawned.emit(peer_id)


# --- gameplay requests (client -> server) -----------------------------------

## Seeker asks the server to fire a shot from their camera ray.
func request_shot(origin: Vector3, dir: Vector3) -> void:
	if is_server():
		shot_requested.emit(1, origin, dir)
	else:
		rpc_id(1, &"_request_shot", origin, dir)


@rpc("any_peer", "call_remote", "reliable")
func _request_shot(origin: Vector3, dir: Vector3) -> void:
	if is_server():
		shot_requested.emit(multiplayer.get_remote_sender_id(), origin, dir)
