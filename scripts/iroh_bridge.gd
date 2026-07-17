extends RefCounted
## Loaded only after Net confirms that the native godot-iroh classes exist.
## Keeping those identifiers out of Net.gd lets unsupported exports fail
## gracefully while ENet and LAN discovery continue to work.


static func start_server() -> MultiplayerPeer:
	return IrohServer.start()


static func connect_client(room_code: String) -> MultiplayerPeer:
	return IrohClient.connect(room_code)
