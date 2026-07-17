extends Node
## Networking singleton: selectable ENet/Iroh transport, replicated player
## registry, and every match-orchestration RPC. Living on an autoload means RPC
## node paths always match on every peer, regardless of the active scene.

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
signal waiting_for_round_changed(waiting: bool)
signal hidden_ready_requested(peer_id: int, hidden: bool)  ## server only
signal start_seeking_requested  ## server only
signal settings_changed(settings: Dictionary)
signal lan_games_changed(games: Array)

const SessionStateScript := preload("res://scripts/session_state.gd")
const IrohRoomCode := preload("res://scripts/iroh_room_code.gd")
const IROH_BRIDGE_PATH := "res://scripts/iroh_bridge.gd"
const TRANSPORT_OFFLINE := "offline"
const TRANSPORT_ENET := "enet"
const TRANSPORT_IROH := "iroh"
const DISCOVERY_PORT := 24566
const DISCOVERY_REQUEST := "PAINT_N_SEEK_DISCOVER_V1"
const DISCOVERY_PROTOCOL := 1
const DISCOVERY_PROBE_INTERVAL := 1.0
const DISCOVERY_STALE_SECONDS := 3.5
const DISCOVERY_PEER_STALE_SECONDS := 10.0

var players := {}  ## peer_id -> {"name": String, "avatar": String, "preference": String}
var my_name := "Painter"
var active_transport := TRANSPORT_OFFLINE
## Frozen at the instant a round load begins. Players who connect afterward
## remain in `players` but do not participate until the next round load.
var round_player_ids: Array[int] = []
var waiting_for_next_round := false

var _ready_peers := {}
var _match_ready_peers := {}
var session: RefCounted = SessionStateScript.new()
var _accepting_replay_ready := false
var lobby_settings := {}
var _lan_server: UDPServer
var _lan_server_peers: Array[Dictionary] = []  ## retained UDP peer + last_seen
var _lan_client: PacketPeerUDP
var _lan_games := {}  ## session ID (or legacy address) -> advertised row + last_seen
var _lan_probe_left := 0.0
var _lan_session_id := ""
var _host_room_code := ""


func _ready() -> void:
	set_process(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func is_iroh_available() -> bool:
	return ClassDB.class_exists("IrohServer") and ClassDB.class_exists("IrohClient")


func is_iroh_session() -> bool:
	return active_transport == TRANSPORT_IROH


func host_room_code() -> String:
	return _host_room_code if is_server() and is_iroh_session() else ""


func host_game() -> Error:
	stop_lan_discovery()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(App.PORT, 16)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active_transport = TRANSPORT_ENET
	_host_room_code = ""
	_prepare_host_session()
	_start_lan_advertising()
	return OK


func host_iroh_game() -> Error:
	stop_lan_discovery()
	if not is_iroh_available():
		return ERR_UNAVAILABLE
	var bridge = load(IROH_BRIDGE_PATH)
	if bridge == null:
		return ERR_CANT_OPEN
	var peer: MultiplayerPeer = bridge.start_server()
	if peer == null:
		return FAILED
	multiplayer.multiplayer_peer = peer
	active_transport = TRANSPORT_IROH
	_host_room_code = str(peer.call("connection_string"))
	if not IrohRoomCode.is_valid(_host_room_code):
		peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		active_transport = TRANSPORT_OFFLINE
		_host_room_code = ""
		return FAILED
	_prepare_host_session()
	print("[net] iroh room code: ", _host_room_code)
	return OK


func _prepare_host_session() -> void:
	players = {1: {"name": my_name, "avatar": App.selected_avatar,
			"preference": App.selected_role_preference, "waiting": false}}
	round_player_ids.clear()
	waiting_for_next_round = false
	lobby_settings = App.settings.duplicate(true)
	session.reset([])
	session.add_player(1, App.lobby_identity)
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0
	players_changed.emit()


func join_game(ip: String) -> Error:
	stop_lan_discovery()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, App.PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active_transport = TRANSPORT_ENET
	_host_room_code = ""
	_prepare_join_session()
	return OK


func join_iroh_game(room_code: String) -> Error:
	stop_lan_discovery()
	var normalized := IrohRoomCode.normalize(room_code)
	if not IrohRoomCode.is_valid(normalized):
		return ERR_INVALID_PARAMETER
	if not is_iroh_available():
		return ERR_UNAVAILABLE
	var bridge = load(IROH_BRIDGE_PATH)
	if bridge == null:
		return ERR_CANT_OPEN
	var peer: MultiplayerPeer = bridge.connect_client(normalized)
	if peer == null:
		return FAILED
	multiplayer.multiplayer_peer = peer
	active_transport = TRANSPORT_IROH
	_host_room_code = ""
	_prepare_join_session()
	return OK


func _prepare_join_session() -> void:
	lobby_settings.clear()
	round_player_ids.clear()
	waiting_for_next_round = false
	session.reset([])
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0


func leave() -> void:
	_stop_lan_advertising()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active_transport = TRANSPORT_OFFLINE
	_host_room_code = ""
	players.clear()
	lobby_settings.clear()
	round_player_ids.clear()
	waiting_for_next_round = false
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
	_lan_session_id = App.lobby_identity
	_lan_server = UDPServer.new()
	_lan_server.max_pending_connections = 64
	# Discovery is intentionally IPv4: limited broadcast and the advertised
	# ENet addresses are IPv4. An explicit bind avoids platform-dependent
	# dual-stack behavior that can swallow IPv4 replies.
	var err := _lan_server.listen(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		print("[net] LAN discovery advertising unavailable: ", error_string(err))
		_lan_server = null


func _stop_lan_advertising() -> void:
	if _lan_server != null:
		_lan_server.stop()
		_lan_server = null
	_lan_server_peers.clear()
	_lan_session_id = ""


func _poll_lan_advertising() -> void:
	if _lan_server == null:
		return
	var poll_error := _lan_server.poll()
	if poll_error != OK:
		print("[net] LAN discovery poll failed: ", error_string(poll_error))
		_stop_lan_advertising()
		return
	var now := Time.get_ticks_msec() / 1000.0
	while _lan_server.is_connection_available():
		var peer := _lan_server.take_connection()
		if peer != null:
			# UDPServer routes future datagrams for this address/port to the same
			# PacketPeerUDP. Godot requires us to retain that peer after accepting
			# it; dropping the reference was the LAN discovery regression.
			_lan_server_peers.append({"peer": peer, "last_seen": now})
	var payload := JSON.stringify({
		"protocol": DISCOVERY_PROTOCOL,
		"session_id": _lan_session_id,
		"host": my_name,
		"players": players.size(),
		"capacity": 16,
		"port": App.PORT,
		"in_progress": App.in_match,
	}).to_utf8_buffer()
	for entry: Dictionary in _lan_server_peers:
		var peer: PacketPeerUDP = entry["peer"]
		while peer.get_available_packet_count() > 0:
			var request := peer.get_packet().get_string_from_utf8()
			entry["last_seen"] = now
			if request == DISCOVERY_REQUEST:
				peer.put_packet(payload)
	# Browsers keep one source port for their menu lifetime. Expiring old peers
	# prevents an endless list after many clients have come and gone.
	for index in range(_lan_server_peers.size() - 1, -1, -1):
		if now - float(_lan_server_peers[index]["last_seen"]) > DISCOVERY_PEER_STALE_SECONDS:
			_lan_server_peers.remove_at(index)


func start_lan_discovery() -> void:
	stop_lan_discovery()
	_lan_client = PacketPeerUDP.new()
	var err := _lan_client.bind(0, "0.0.0.0")
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
		if not parsed is Dictionary or not parsed.has("protocol") or not parsed.has("port"):
			continue
		var row: Dictionary = parsed.duplicate()
		row["address"] = address
		row["compatible"] = (
				int(row["protocol"]) == DISCOVERY_PROTOCOL
				and int(row["port"]) == App.PORT
		)
		row["last_seen"] = Time.get_ticks_msec() / 1000.0
		var session_id := str(row.get("session_id", "")).strip_edges()
		var game_key := (
				"session:%s" % session_id
				if not session_id.is_empty()
				else "%s:%d" % [address, int(row["port"])]
		)
		var is_new := not _lan_games.has(game_key)
		if not is_new:
			var previous: Dictionary = _lan_games[game_key]
			# The loopback probe and the LAN broadcast can both find the same
			# local host. Keep its routable LAN address instead of showing a
			# duplicate or replacing it with 127.0.0.1.
			if (
					not str(previous.get("address", "")).begins_with("127.")
					and address.begins_with("127.")
			):
				previous["last_seen"] = row["last_seen"]
				changed = true
				continue
		_lan_games[game_key] = row
		if is_new:
			print("[net] discovered LAN game %s at %s" % [row.get("host", "?"), address])
		changed = true
	var now := Time.get_ticks_msec() / 1000.0
	for game_key: String in _lan_games.keys():
		if now - float(_lan_games[game_key]["last_seen"]) > DISCOVERY_STALE_SECONDS:
			_lan_games.erase(game_key)
			changed = true
	if changed:
		var rows := _lan_games.values()
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("host", "")) < str(b.get("host", "")))
		lan_games_changed.emit(rows)


# --- connection lifecycle -------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_server() and App.in_match:
		print("[net] peer %d connected during a round; queueing for the next one" % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	var was_in_round := round_player_ids.has(id)
	round_player_ids.erase(id)
	players.erase(id)
	session.remove_player(id)
	_ready_peers.erase(id)
	_match_ready_peers.erase(id)
	rpc(&"_sync_players", players)
	players_changed.emit()
	if was_in_round:
		player_left.emit(id)
	if _accepting_replay_ready:
		_broadcast_replay_readiness()
	_check_barriers()


func _on_connected_ok() -> void:
	rpc_id(1, &"_register_player", my_name, App.selected_avatar,
			App.selected_role_preference, App.lobby_identity)
	joined_ok.emit()


func _on_connection_failed() -> void:
	var message := "Could not connect to host."
	var peer := multiplayer.multiplayer_peer
	if active_transport == TRANSPORT_IROH and peer != null and peer.has_method("connection_error"):
		var detail := str(peer.call("connection_error")).strip_edges()
		if not detail.is_empty():
			message = "Could not join that room: %s" % detail.substr(0, 160)
	leave()
	join_failed.emit(message)


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
	var waiting := App.in_match
	players[id] = {
		"name": pname.substr(0, 20),
		"avatar": AvatarCatalog.normalize(avatar_id),
		"preference": _normalize_preference(preference),
		"waiting": waiting,
	}
	rpc_id(id, &"_sync_settings", App.settings)
	rpc_id(id, &"_receive_waiting_for_round", waiting)
	session.add_player(id, lobby_identity.substr(0, 80))
	rpc(&"_sync_players", players)
	players_changed.emit()
	if _accepting_replay_ready:
		_broadcast_replay_readiness()


@rpc("authority", "call_remote", "reliable")
func _sync_players(new_players: Dictionary) -> void:
	players = new_players
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_waiting_for_round(waiting: bool) -> void:
	waiting_for_next_round = waiting
	waiting_for_round_changed.emit(waiting)


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
	if not players.has(id) or (App.in_match and round_player_ids.has(id)):
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
	if not players.has(id) or (App.in_match and round_player_ids.has(id)):
		return
	players[id]["preference"] = _normalize_preference(preference)
	rpc(&"_sync_players", players)
	players_changed.emit()


func _normalize_preference(preference: String) -> String:
	return preference if preference in ["none", "seeker", "hider"] else "none"


func assign_session_roles(seeker_count: int) -> Array:
	var preferences := {}
	for id: int in round_player_ids:
		if not players.has(id):
			continue
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


## Readiness is an informational signal during the between-round break. The
## host may start the next round at any time; every connected player at that
## instant is promoted into the frozen round roster.
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
	_begin_game_load()
	return true


func _begin_game_load() -> void:
	round_player_ids.clear()
	for id: int in players:
		round_player_ids.append(id)
		players[id]["waiting"] = false
	round_player_ids.sort()
	rpc(&"_sync_players", players)
	players_changed.emit()
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
	# Target only the frozen roster. A peer connected but not yet registered is
	# intentionally left on the waiting screen until the following break.
	for id: int in round_player_ids:
		if id == 1:
			_load_game(snapshot)
		else:
			rpc_id(id, &"_load_game", snapshot)


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
	for id: int in round_player_ids:
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
	waiting_for_next_round = false
	waiting_for_round_changed.emit(false)
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
	if not round_player_ids.has(id):
		return
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
	if not round_player_ids.has(id):
		return
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
	for id: int in round_player_ids:
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
