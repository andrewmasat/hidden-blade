# NetworkManager.gd - Autoload Singleton
extends Node

const DEFAULT_PORT = 7777 # Or any port you prefer
var peer: ENetMultiplayerPeer = null

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

@rpc("call_remote", "any_peer", "reliable") # Client calls this on Server (ID 1)
func client_ready_in_main_scene():
	var client_peer_id = multiplayer.get_remote_sender_id()
	print("NetworkManager (Server): Client ID [", client_peer_id, "] reported ready in Main scene.")
	# Server now tells its Main.gd (or GameManager) to spawn for this client
	var main_node = get_tree().get_root().get_node_or_null("Main") # Adjust path if Main is elsewhere
	if main_node and main_node.has_method("spawn_player_for_peer"):
		main_node.spawn_player_for_peer(client_peer_id)
	else:
		printerr("NetworkManager (Server): Main node or spawn_player_for_peer method not found!")

func host_game(port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port)
	if error != OK:
		printerr("NetworkManager: Failed to create server. Error:", error)
		peer = null
		return false
	multiplayer.set_multiplayer_peer(peer)
	print("NetworkManager: Server created. My ID:", multiplayer.get_unique_id()) # Should be 1
	emit_signal("player_connected", 1) # Host "connects"
	# Spawn logic moved to Main.gd after scene load
	return true

func join_game(ip_address: String, port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, port)
	if error != OK:
		printerr("NetworkManager: Failed to create client. Error:", error)
		peer = null
		return false
	multiplayer.set_multiplayer_peer(peer)
	print("NetworkManager: Client attempting connection.")
	return true

func close_connection():
	if peer:
		peer.close() # ENet specific close for connections
	multiplayer.set_multiplayer_peer(null) # Essential to reset
	peer = null
	print("NetworkManager: Connection closed/reset.")

# --- Signal Callbacks from MultiplayerAPI ---
func _on_player_connected(id: int): # Called ON SERVER when a client connects
	print("NetworkManager (Server): Player connected - ID:", id)
	emit_signal("player_connected", id)
	# Server will spawn for 'id' when Main scene tells it the new player is ready for spawn

func _on_player_disconnected(id: int):
	print("NetworkManager: Player disconnected - ID:", id)
	emit_signal("player_disconnected", id)

func _on_connection_failed():
	printerr("NetworkManager: Connection failed!")
	close_connection() # Clean up peer
	emit_signal("connection_failed")

func _on_connected_to_server(): # Called ON CLIENT
	print("NetworkManager (Client): Successfully connected! My ID:", multiplayer.get_unique_id())
	emit_signal("connection_succeeded")
	# Client will tell server it's ready via an RPC FROM Main.gd's _ready

func _on_server_disconnected():
	printerr("NetworkManager: Disconnected from server!")
	close_connection() # Clean up peer
	emit_signal("server_disconnected")
