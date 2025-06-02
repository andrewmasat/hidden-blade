# Main.gd (Attach to root node 'Main')
extends Node

const PlayerScene = preload("res://player/Player.tscn")
const DroppedItemScene = preload("res://world/DroppedItem.tscn")

@onready var player_spawner: MultiplayerSpawner = $WorldYSort/PlayerSpawner
@onready var dropped_item_spawner: MultiplayerSpawner = $WorldYSort/Environments/DroppedItemSpawner
@onready var environments_container: Node2D = $WorldYSort/Environments
@onready var hud = $HUD
@onready var pause_menu = $PauseMenu
# We need a way to know which child of 'Environments' is the starting level
# You could hardcode the name, or find the first child, or use a specific group.
# Let's assume the first child IS the starting level for simplicity here.
@onready var initial_level: Node = environments_container.get_child(0) if environments_container.get_child_count() > 0 else null

var local_player_node: CharacterBody2D = null
var previous_mouse_mode_before_pause = Input.MOUSE_MODE_CAPTURED
var _next_dropped_item_game_id: int = 1

func generate_unique_dropped_item_id() -> String:
	# ... (implementation) ...
	var id_str = "item_" + str(_next_dropped_item_game_id)
	_next_dropped_item_game_id += 1
	return id_str

func _ready() -> void:
	print("Main.gd _ready: My Peer ID:", multiplayer.get_unique_id(), "Is Server:", multiplayer.is_server())

	# --- Validate Initial Setup ---
	if not is_instance_valid(environments_container):
		printerr("Main Error: Environments node not found!")
		return
	if not is_instance_valid(initial_level):
		printerr("Main Error: No initial level found under Environments node!")
		return

	if is_instance_valid(player_spawner):
		# Callable takes the object and the method name
		player_spawner.spawn_function = Callable(self, "_custom_player_spawn_function")
		print("Main: Set custom spawn function on PlayerSpawner.")
	else:
		printerr("Main Error: PlayerSpawner node not found, cannot set spawn_function!")

	if is_instance_valid(dropped_item_spawner):
		# The custom function can be the same if data differentiates, or a new one.
		# Let's assume you have a dedicated one or will adapt _custom_dropped_item_spawn_function
		dropped_item_spawner.spawn_function = Callable(self, "_custom_dropped_item_spawn_function") # Ensure this function exists and handles dropped items
		print("Main: Set custom spawn function on DroppedItemSpawner.")
	else:
		printerr("Main Error: DroppedItemSpawner node not found! Cannot set spawn_function!")
		# This might not be critical to STOP if game can run without dropped items initially

	# --- Initialize SceneManager ---
	if SceneManager:
		SceneManager.scene_container_node = environments_container
		SceneManager.main_scene_root = self
		# --- SET INITIAL LEVEL ROOT EARLIER ---
		var initial_level_node: Node = null
		if is_instance_valid(environments_container):
			for child in environments_container.get_children():
				if child is Node2D and not child is MultiplayerSpawner: # Be more specific if needed
					initial_level_node = child
					break # Found the first actual level node

		if is_instance_valid(initial_level_node):
			SceneManager.current_level_root = initial_level_node
			print("Main: Set SceneManager.current_level_root to initial level:", SceneManager.current_level_root.name)
		else:
			printerr("Main Error: No suitable initial level node found under Environments!")
			# Potentially stop game here or load a default empty level
		# ------------------------------------
		SceneManager.initialize_fade_layer()
		print("Main: Initialized SceneManager structural references.")
	else:
		printerr("Main Error: SceneManager Autoload not found!")
		return # Critical error

	# --- Network Dependent Initialization ---
	if multiplayer.get_unique_id() == 0: # Not connected yet (shouldn't happen if Main is loaded via SceneManager after connection)
		print("Main: WARNING - Main loaded but not connected. Waiting for network signals.")
		# This path is less likely now if StartScreen waits for connection before loading Main
		NetworkManager.connection_succeeded.connect(_on_client_connected_for_spawn, CONNECT_ONE_SHOT)
		NetworkManager.player_connected.connect(_on_host_self_connected_for_spawn, CONNECT_ONE_SHOT)
	elif multiplayer.is_server(): # We are the server/host
		print("Main (Host): Network active. Spawning self.")
		spawn_player_for_peer(multiplayer.get_unique_id()) # Spawn host's player
	else: # We are a client
		print("Main (Client): Network active. Requesting spawn from server.")
		NetworkManager.rpc_id(1, "client_ready_in_main_scene")
		call_deferred("_wait_and_setup_local_player_client")

	# Listen for future player disconnections to despawn them
	NetworkManager.player_disconnected.connect(_on_player_left)

	# Connect signals from PauseMenu
	if is_instance_valid(pause_menu):
		pause_menu.resume_game_requested.connect(resume_game)
		pause_menu.quit_to_menu_requested.connect(quit_to_menu)
	else:
		printerr("Main Error: PauseMenu instance not found!")


func _unhandled_input(event: InputEvent) -> void:
	# Use the Input singleton for global state checks like pause toggle
	if Input.is_action_just_pressed("toggle_pause"): # Check global Input state
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		# Consume the input event that likely triggered this state check
		# Check if the EVENT itself matches too, for safer consumption
		if event.is_action("toggle_pause"): # Check the event itself before consuming
			get_viewport().set_input_as_handled()


# --- Multiplayer ---
func _on_client_connected_for_spawn(): # If Main loaded before client fully connected
	print("Main (Client): Connection now succeeded. Requesting spawn.")
	NetworkManager.rpc_id(1, "client_ready_in_main_scene")


func _on_host_self_connected_for_spawn(peer_id: int): # If Main loaded before host "self-connect"
	if peer_id == 1 and multiplayer.is_server():
		print("Main (Host): Self-connection processed. Spawning self.")
		spawn_player_for_peer(1)


func _custom_player_spawn_function(peer_id_to_spawn_for_variant: Variant) -> Node:
	var peer_id = int(peer_id_to_spawn_for_variant)
	print("CustomPlayerSpawn (Peer:", multiplayer.get_unique_id(), "): Spawning player for peer ID:", peer_id)

	if not PlayerScene:
		printerr("CustomPlayerSpawn: PlayerScene not preloaded!")
		return null
	var player_instance = PlayerScene.instantiate()
	if not is_instance_valid(player_instance):
		printerr("CustomPlayerSpawn: Failed to instantiate PlayerScene!")
		return null

	player_instance.name = str(peer_id)
	player_instance.set_multiplayer_authority(peer_id)

	# --- SERVER sets its OWN initial position directly ---
	if peer_id == multiplayer.get_unique_id(): # If spawning for self (the server/host)
		print("  -> CustomPlayerSpawn (Server Logic for SELF ID:", peer_id, "): Setting initial position directly.")
		var char_name = "Player_" + str(peer_id)
		var spawn_marker_name = "InitialSpawn"
		var spawn_pos = Vector2.ZERO

		if is_instance_valid(SceneManager.current_level_root):
			var marker = SceneManager.current_level_root.find_child(spawn_marker_name, true, false) as Node2D
			if marker: spawn_pos = marker.global_position
			else: spawn_pos = SceneManager.current_level_root.global_position

		if player_instance.has_method("initialize_networked_data"):
			player_instance.initialize_networked_data(char_name, spawn_pos)
		else:
			# Fallback direct set (less ideal as it bypasses setter logic if not careful)
			player_instance.player_name = char_name
			player_instance.global_position = spawn_pos
		print("  -> CustomPlayerSpawn (Server Logic for ID:", peer_id, "): Initialized with name '", char_name, "' and position ", spawn_pos)
		#player_instance.global_position = spawn_pos
		#print("  -> CustomPlayerSpawn (Server for SELF): Position set to ", spawn_pos)

	return player_instance


@rpc("any_peer", "call_local", "reliable") # Client calls this on Server (ID 1)
func client_player_node_ready_for_init(client_peer_id_arg: int):
	if not multiplayer.is_server(): return

	print("Main (Server): Client [", client_peer_id_arg, "] reported its player node is ready. Setting initial pos via RPC.")

	# Find the server's instance of the client's player
	var spawner_spawn_path_node = get_node_or_null(player_spawner.spawn_path) # Get correct parent
	if not is_instance_valid(spawner_spawn_path_node): return # Error

	var client_player_on_server = spawner_spawn_path_node.get_node_or_null(str(client_peer_id_arg)) as Player
	if is_instance_valid(client_player_on_server):
		# Determine initial spawn position (same logic as in _custom_player_spawn_function for host)
		var spawn_marker_name = "InitialSpawn"
		var spawn_pos = Vector2.ZERO
		if is_instance_valid(SceneManager.current_level_root):
			var marker = SceneManager.current_level_root.find_child(spawn_marker_name, true, false) as Node2D
			if marker: spawn_pos = marker.global_position
			else: spawn_pos = SceneManager.current_level_root.global_position
		# Call RPC on the client's player node to set its position
		client_player_on_server.rpc("set_initial_network_position", spawn_pos)
		print("  -> Main (Server): Sent set_initial_network_position RPC to Player [", client_peer_id_arg, "] with pos ", spawn_pos)


func _wait_and_setup_local_player_client():
	if multiplayer.is_server(): return # Only for clients

	var local_peer_id_str = str(multiplayer.get_unique_id())

	if not is_instance_valid(player_spawner): # Ensure spawner ref is valid
		printerr("Main (Client) _wait: PlayerSpawner ref is invalid!")
		return

	var spawner_spawn_path_node_path = player_spawner.spawn_path
	var actual_spawn_parent_node: Node
	if spawner_spawn_path_node_path.is_empty() or spawner_spawn_path_node_path == NodePath("."):
		actual_spawn_parent_node = player_spawner
	else:
		actual_spawn_parent_node = player_spawner.get_node_or_null(spawner_spawn_path_node_path)

	if not is_instance_valid(actual_spawn_parent_node):
		printerr("Main (Client) _wait: Spawner's actual_spawn_parent_node ('", spawner_spawn_path_node_path, "' relative to '", player_spawner.name, "') is invalid.")
		return

	print("Main (Client) _wait: Waiting for player '", local_peer_id_str, "' under '", actual_spawn_parent_node.name, "' (Path: ", actual_spawn_parent_node.get_path(), ")") # DEBUG

	var attempts = 0
	var found_node = actual_spawn_parent_node.get_node_or_null(local_peer_id_str)
	while not is_instance_valid(found_node) and attempts < 120: # ~2 seconds
		await get_tree().process_frame
		found_node = actual_spawn_parent_node.get_node_or_null(local_peer_id_str)
		attempts += 1

	if is_instance_valid(found_node):
		var local_player_instance = found_node as Player
		_setup_local_player_references(local_peer_id_str)

		print("Main (Client): Local player node '", local_peer_id_str, "' found. Notifying server for initial position.")
		rpc_id(1, "client_player_node_ready_for_init", multiplayer.get_unique_id())
	else:
		printerr("Main (Client): Timed out waiting for local player node '", local_peer_id_str, "' to be spawned under '", actual_spawn_parent_node.name, "'. Final Children of '", actual_spawn_parent_node.name, "': ", actual_spawn_parent_node.get_children())


func spawn_player_for_peer(peer_id_to_spawn_for: int):
	if not multiplayer.is_server():
		print("Main: Ignoring spawn_player_for_peer, not server.")
		return

	var player_node_name = str(peer_id_to_spawn_for)
	# Check if player already exists UNDER THE SPAWNER'S SPAWN PATH
	var spawner_spawn_path_node = get_node_or_null(player_spawner.spawn_path)
	if not is_instance_valid(spawner_spawn_path_node):
		printerr("Main: PlayerSpawner spawn_path node is invalid:", player_spawner.spawn_path)
		return

	if not is_instance_valid(spawner_spawn_path_node.get_node_or_null(player_node_name)):
		print("Main (Server): Calling player_spawner.spawn() for peer ID:", peer_id_to_spawn_for)
		# We pass the peer_id as the custom data.
		if is_instance_valid(player_spawner):
			print("Main (Server): About to call spawn for ID [", peer_id_to_spawn_for, "]. Spawner's spawn_function is valid:", player_spawner.spawn_function.is_valid())
			if player_spawner.spawn_function.is_valid():
				print("  -> Target object for spawn_function:", player_spawner.spawn_function.get_object().name if is_instance_valid(player_spawner.spawn_function.get_object()) else "Invalid Object")
				print("  -> Target method for spawn_function:", player_spawner.spawn_function.get_method())
		else:
			printerr("Main (Server): player_spawner is NULL before calling spawn!")
			return

		# The spawner will call _custom_player_spawn_function with this peer_id.
		player_spawner.spawn(peer_id_to_spawn_for)

		if peer_id_to_spawn_for == multiplayer.get_unique_id():
			call_deferred("_setup_local_player_references", player_node_name)
	else:
		print("Main (Server): Player already spawned for peer ID:", peer_id_to_spawn_for)


func _find_and_setup_local_player():
	var local_peer_id_str = str(multiplayer.get_unique_id())
	var spawner_spawn_path_node = get_node_or_null(player_spawner.spawn_path)
	if not is_instance_valid(spawner_spawn_path_node): return

	# Wait a frame for spawner to potentially add child if called too early
	await get_tree().process_frame

	local_player_node = spawner_spawn_path_node.get_node_or_null(local_peer_id_str) as CharacterBody2D
	_setup_local_player_references(local_peer_id_str) # Call the common setup


func _setup_local_player_references(player_node_name_is_peer_id_str: String) -> void:
	if not is_instance_valid(player_spawner):
		printerr("Main Error (_setup_local_player_references): player_spawner node is invalid!")
		return

	var actual_spawn_parent_node: Node
	if player_spawner.spawn_path.is_empty() or player_spawner.spawn_path == NodePath("."):
		actual_spawn_parent_node = player_spawner
	else:
		actual_spawn_parent_node = player_spawner.get_node_or_null(player_spawner.spawn_path)

	if not is_instance_valid(actual_spawn_parent_node):
		printerr("Main Error (_setup_local_player_references): Node at PlayerSpawner.spawn_path ('", player_spawner.spawn_path, "') is invalid or not found relative to spawner!")
		printerr("  Spawner is at:", player_spawner.get_path())
		return

	print("Main (_setup_local_player_references): Waiting for player '", player_node_name_is_peer_id_str, "' under '", actual_spawn_parent_node.name, "' (Path:", actual_spawn_parent_node.get_path(), ")")

	# --- Wait for the node to appear ---
	var attempts = 0
	var found_player_node = actual_spawn_parent_node.get_node_or_null(player_node_name_is_peer_id_str)
	# Increase wait time, especially for client
	var max_attempts = 120 # Approx 2 seconds if 60fps
	if multiplayer.is_server() and multiplayer.get_unique_id() == player_node_name_is_peer_id_str.to_int():
		max_attempts = 10 # Host can expect it sooner

	while not is_instance_valid(found_player_node) and attempts < max_attempts:
		await get_tree().process_frame
		found_player_node = actual_spawn_parent_node.get_node_or_null(player_node_name_is_peer_id_str)
		attempts += 1
	# ----------------------------------

	local_player_node = found_player_node as CharacterBody2D

	if is_instance_valid(local_player_node):
		print("Main: Local player node '", local_player_node.name, "' reference SET for SceneManager.")
		SceneManager.player_node = local_player_node

		if is_instance_valid(hud) and hud.has_method("assign_player_and_connect_signals"):
			hud.assign_player_and_connect_signals(local_player_node)
		if local_player_node.has_method("end_scene_transition"):
			local_player_node.call_deferred("end_scene_transition")
	else:
		printerr("Main Error: Failed to get local player node '", player_node_name_is_peer_id_str, "' under '", actual_spawn_parent_node.name, "' after waiting. Children are:", actual_spawn_parent_node.get_children())


func _on_player_left(peer_id: int):
	var player_node_name = str(peer_id)
	var spawner_spawn_path_node = get_node_or_null(player_spawner.spawn_path)
	if not is_instance_valid(spawner_spawn_path_node): return

	var player_to_remove = spawner_spawn_path_node.get_node_or_null(player_node_name)
	if is_instance_valid(player_to_remove):
		print("Main: Despawning player for peer ID:", peer_id)
		player_to_remove.queue_free()
		if local_player_node == player_to_remove: # Should not happen if server disconnected properly
			local_player_node = null
			SceneManager.player_node = null

# --- Dropped Item ---
func _custom_dropped_item_spawn_function(data: Dictionary) -> Node:
	var item_identifier = data.get("item_identifier", "")
	var item_quantity = data.get("item_quantity", 1)
	var drop_mode_enum = data.get("drop_mode_int", DroppedItem.DropMode.GLOBAL) as DroppedItem.DropMode
	var owner_peer_id = data.get("owner_peer_id", 0)
	var unique_id_for_instance = data.get("item_unique_id", "")
	var position = Vector2(data.get("position_x", 0), data.get("position_y", 0))
	print("CustomDroppedItemSpawn (Peer:", multiplayer.get_unique_id(), "): Spawning '", item_identifier, "' UniqueID:", unique_id_for_instance)

	if not DroppedItemScene:
		printerr("CustomDroppedItemSpawn: DroppedItemScene not preloaded!")
		return null
	var dropped_item = DroppedItemScene.instantiate() as DroppedItem
	if not is_instance_valid(dropped_item):
		printerr("CustomDroppedItemSpawn: Failed to instantiate DroppedItemScene!")
		return null

	if multiplayer.is_server():
		print("  -> CustomDroppedItemSpawn (Server Logic for ID:", unique_id_for_instance, "): Setting initial data.")
		var item_base_res: ItemData = null
		if item_identifier.begins_with("res://"): item_base_res = load(item_identifier)
		else:
			if ItemDatabase: item_base_res = ItemDatabase.get_item_base(item_identifier)

		if not item_base_res is ItemData:
			printerr("  -> CustomDroppedItemSpawn (Server): Could not get ItemData for '", item_identifier, "'")
			dropped_item.queue_free() # Clean up bad instance
			return null

		var item_data_instance = item_base_res.duplicate()
		item_data_instance.quantity = item_quantity

		# This function sets properties that will be synced
		dropped_item.initialize_server_data(item_data_instance, drop_mode_enum, owner_peer_id, unique_id_for_instance, position)
	# --------------------------------------------
	# Clients will receive these properties (item_data, drop_mode, owner_peer_id, item_unique_id, global_position)
	# via the DroppedItem's MultiplayerSynchronizer.
	# DroppedItem._ready() calls _update_visuals_and_interaction() which uses these synced properties.

	print("CustomDroppedItemSpawn (Peer:", multiplayer.get_unique_id(), "): DroppedItem instance created for '", unique_id_for_instance, "'")
	return dropped_item


@rpc("any_peer", "call_local", "reliable")
func server_handle_debug_add_item_to_inventory(item_id_to_add: String, quantity: int):
	if not multiplayer.is_server(): return

	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1: requesting_peer_id = 1
	
	print("Main (Server): Received debug_add_item request from peer [", requesting_peer_id, "] for item '", item_id_to_add, "' qty ", quantity)

	var item_base_res = ItemDatabase.get_item_base(item_id_to_add)
	if not is_instance_valid(item_base_res):
		printerr("  -> Server: Debug item '", item_id_to_add, "' not found in ItemDatabase.")
		# Optionally RPC failure back to client's player
		return

	var item_instance_for_server = item_base_res.duplicate()
	item_instance_for_server.quantity = quantity

	if ServerInventoryManager.add_item_to_player_inventory(requesting_peer_id, item_instance_for_server):
		print("  -> Server: Debug item '", item_id_to_add, "' added to ServerInventoryManager for peer [", requesting_peer_id, "]")
		# ServerInventoryManager will call _notify_client_of_slot_update, which RPCs client Inventory.gd
	else:
		printerr("  -> Server: FAILED to add debug item '", item_id_to_add, "' to ServerInventoryManager for peer [", requesting_peer_id, "] (Inventory full?).")
		# Optionally RPC failure back to client's player


@rpc("any_peer", "call_local", "reliable")
func server_handle_place_cursor_item_request(cursor_item_path: String, cursor_item_id: String, cursor_item_qty: int, 
										  target_area_enum_val: int, target_index: int):
	if not multiplayer.is_server(): return
	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1: requesting_peer_id = 1
	
	print("Main (Server): Peer [", requesting_peer_id, "] requests to place cursor item (ID '", cursor_item_id, "', Qty ", cursor_item_qty, ") onto Area ", target_area_enum_val, " Slot ", target_index)

	# Reconstruct the ItemData for the cursor item on server
	var cursor_item_on_server: ItemData = null
	if not cursor_item_path.is_empty():
		var res = load(cursor_item_path)
		if res is ItemData:
			cursor_item_on_server = res.duplicate()
			cursor_item_on_server.quantity = cursor_item_qty
	elif not cursor_item_id.is_empty(): # Fallback to ID
		var base_res = ItemDatabase.get_item_base(cursor_item_id)
		if base_res is ItemData:
			cursor_item_on_server = base_res.duplicate()
			cursor_item_on_server.quantity = cursor_item_qty
			
	if not is_instance_valid(cursor_item_on_server):
		printerr("  -> Server: Could not reconstruct cursor item '", cursor_item_id, "'. Aborting place request.")
		# TODO: RPC failure to client
		return

	var target_area = target_area_enum_val as Inventory.InventoryArea
	
	# Call a new method in ServerInventoryManager
	if ServerInventoryManager.has_method("place_item_onto_slot_from_cursor_like_source"):
		ServerInventoryManager.place_item_onto_slot_from_cursor_like_source(requesting_peer_id, cursor_item_on_server, target_area, target_index)
	else:
		printerr("  -> Server: ServerInventoryManager missing 'place_item_onto_slot_from_cursor_like_source' method.")


@rpc("any_peer", "call_local", "reliable")
func server_handle_split_stack_request(source_area_enum_val: int, source_index: int):
	if not multiplayer.is_server(): return
	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1: requesting_peer_id = 1

	var source_area = source_area_enum_val as Inventory.InventoryArea
	print("Main (Server): Peer [", requesting_peer_id, "] requests to split stack from Area ", source_area, " Slot ", source_index)

	if ServerInventoryManager.has_method("split_player_stack_to_cursor_like_destination"):
		ServerInventoryManager.split_player_stack_to_cursor_like_destination(requesting_peer_id, source_area, source_index)
	else:
		printerr("  -> Server: ServerInventoryManager missing 'split_player_stack_to_cursor_like_destination' method.")


@rpc("any_peer", "call_local", "reliable") # Client (any_peer) calls this, server (ID 1) executes it locally
func server_process_gather_request(node_path_from_level: NodePath):
	if not multiplayer.is_server(): return # Should only run on server

	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0: # This can happen if host calls it on self before fully "connected"
		if multiplayer.get_unique_id() == 1:
			requesting_peer_id = 1 
		else: # Should not happen for actual remote clients
			printerr("Main (Server): server_process_gather_request from invalid sender_id 0")
			return

	print("Main (Server): Received gather request from peer [", requesting_peer_id, "] for node path '", node_path_from_level, "'")

	# 1. Find the ResourceNode instance on the server
	if not is_instance_valid(SceneManager.current_level_root):
		printerr("  -> Server Error: current_level_root is invalid. Cannot find ResourceNode.")
		return

	var resource_node = SceneManager.current_level_root.get_node_or_null(node_path_from_level) as ResourceNode

	if not is_instance_valid(resource_node):
		printerr("  -> Server Error: ResourceNode not found at path '", node_path_from_level, "' relative to '", SceneManager.current_level_root.name, "'.")
		return

	if not resource_node.is_multiplayer_authority(): # Server should have authority over these nodes
		printerr("  -> Server Warning: Server does not have authority over ResourceNode '", resource_node.name, "'. Interaction might fail or be unsynced.")
		# This usually means the node wasn't set up correctly for server ownership,
		# or it's not being spawned by a server-controlled MultiplayerSpawner.

	if resource_node.is_depleted:
		print("  -> Node '", resource_node.name, "' is already depleted. No action.")
		# Optionally, RPC back to client: "action_failed_depleted"
		return

	# 2. Find the Player node instance for the requesting client ON THE SERVER
	var actual_player_parent_node: Node
	if player_spawner.spawn_path.is_empty() or player_spawner.spawn_path == NodePath("."):
		actual_player_parent_node = player_spawner
	else:
		actual_player_parent_node = player_spawner.get_node_or_null(player_spawner.spawn_path)

	if not is_instance_valid(actual_player_parent_node):
		printerr("  -> Server Error: Could not find the actual parent node for players based on PlayerSpawner's spawn_path: '", player_spawner.spawn_path, "'")
		return

	# Now use actual_player_parent_node to find the player:
	var requesting_player_node_on_server = actual_player_parent_node.get_node_or_null(str(requesting_peer_id)) as Player
	if not is_instance_valid(requesting_player_node_on_server):
		printerr("  -> Server Error: Could not find player node '", str(requesting_peer_id), "' under '", actual_player_parent_node.name, "'. Children are: ", actual_player_parent_node.get_children())
		return

	# 3. Server-side tool check (Authoritative)
	var required_tool_type_for_node = resource_node.required_tool_type # Renamed for clarity
	var player_has_correct_tool = false

	if required_tool_type_for_node == ItemData.ItemType.MISC:
		player_has_correct_tool = true
	else:
		# Use the synced_equipped_item_id from the server's instance of the player node
		var currently_equipped_id_on_server = requesting_player_node_on_server.synced_equipped_item_id

		if not currently_equipped_id_on_server.is_empty():
			var equipped_item_base_on_server = ItemDatabase.get_item_base(currently_equipped_id_on_server)
			if is_instance_valid(equipped_item_base_on_server):
				if equipped_item_base_on_server.item_type == required_tool_type_for_node:
					player_has_correct_tool = true
				else:
					print("  -> Server: Peer [", requesting_peer_id, "] has item '", currently_equipped_id_on_server, "' (type ", ItemData.ItemType.keys()[equipped_item_base_on_server.item_type] ,") but needs type ", ItemData.ItemType.keys()[required_tool_type_for_node])
			else:
				print("  -> Server: Peer [", requesting_peer_id, "] has unknown item_id '", currently_equipped_id_on_server, "' equipped according to sync.")
		else:
			print("  -> Server: Peer [", requesting_peer_id, "] has nothing equipped according to sync.")
			
	if not player_has_correct_tool:
		print("  -> Server: Peer [", requesting_peer_id, "] tool requirement not met for '", resource_node.name, "'. Needs type: ", ItemData.ItemType.keys()[required_tool_type_for_node])
		return # Stop processing if tool check fails

	# 4. Server performs the gather action on the resource node
	var yielded_item_info: Dictionary = resource_node.on_gather_interaction() # This runs on server's instance

	# 5. If items were yielded, send them to the specific client
	if yielded_item_info.has("item_id") and yielded_item_info.has("quantity"):
		var item_id_to_give = yielded_item_info.get("item_id")
		var quantity_to_give = yielded_item_info.get("quantity")
		
		print("  -> Server: Node yielded ", quantity_to_give, "x ", item_id_to_give, ". For peer [", requesting_peer_id, "]")

		# --- THIS IS THE NEW CORE LOGIC ---
		# Add item to the ServerInventoryManager for the requesting_peer_id
		var item_base_res = ItemDatabase.get_item_base(item_id_to_give)
		if is_instance_valid(item_base_res):
			var item_instance_for_server_inv = item_base_res.duplicate()
			item_instance_for_server_inv.quantity = quantity_to_give
			
			if ServerInventoryManager.add_item_to_player_inventory(requesting_peer_id, item_instance_for_server_inv):
				print("    -> Item added to ServerInventoryManager for peer [", requesting_peer_id, "]")
				# ServerInventoryManager.add_item_to_player_inventory will internally call
				# _notify_client_of_slot_update, which sends the RPC to the client's (or host's client-side) Inventory.gd.
				# So, the client_receive_gathered_items RPC on Player.gd is no longer strictly needed for inventory update.
				# It can be used for other feedback like sounds or messages if desired.
			else:
				printerr("    -> FAILED to add item to ServerInventoryManager for peer [", requesting_peer_id, "] (Inventory full on server?). Item might be lost.")
				# TODO: Handle item dropping on ground if server inventory is full.
		else:
			printerr("    -> Server Error: Could not find ItemData for '", item_id_to_give, "' in ItemDatabase. Cannot give to player.")


@rpc("any_peer", "call_local", "reliable") # Client (any_peer) calls this, server (ID 1) executes it locally
func server_handle_craft_item_request(item_id_to_craft: String):
	if not multiplayer.is_server(): # Guard: Ensure this only runs on the server
		return

	var requesting_peer_id = multiplayer.get_remote_sender_id()
	# If the host calls this on itself locally (e.g. via a UI that uses the same RPC path),
	# get_remote_sender_id() will be 0. We need to correctly identify the host as peer 1.
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1:
		requesting_peer_id = 1 
	
	if requesting_peer_id == 0: # Still 0 means it's an invalid sender for this context
		printerr("Main (Server): server_handle_craft_item_request from invalid sender_id 0 after check.")
		return

	print("Main (Server): Received craft item request from peer [", requesting_peer_id, "] for item '", item_id_to_craft, "'")

	# Find the parent node where player instances are actually spawned
	var actual_player_parent_node: Node
	if not is_instance_valid(player_spawner): # Ensure player_spawner is valid
		printerr("  -> Main (Server) Error: player_spawner node reference is invalid!")
		# TODO: Notify client of failure if possible (e.g., by finding their player node by peer_id if it exists elsewhere and RPCing a fail message)
		return

	if player_spawner.spawn_path.is_empty() or player_spawner.spawn_path == NodePath("."):
		actual_player_parent_node = player_spawner
	else:
		actual_player_parent_node = player_spawner.get_node_or_null(player_spawner.spawn_path)

	if not is_instance_valid(actual_player_parent_node):
		printerr("  -> Main (Server) Error: Could not find actual player parent node based on PlayerSpawner's spawn_path: '", player_spawner.spawn_path, "'")
		# TODO: Notify client of failure
		return
	
	# Find the specific Player node instance on the server that corresponds to the requesting client
	var requesting_player_node_on_server = actual_player_parent_node.get_node_or_null(str(requesting_peer_id)) as Player
	if not is_instance_valid(requesting_player_node_on_server):
		printerr("  -> Main (Server) Error: Could not find player node '", str(requesting_peer_id), "' under '", actual_player_parent_node.name, "' on server for crafting. Children are: ", actual_player_parent_node.get_children())
		# If you can get the player node by another means to send a failure RPC, do so.
		# Otherwise, the client might time out or not know why crafting isn't happening.
		# For now, we can't RPC back without a player node reference.
		return

	# Call the (non-RPC) processing function on that specific Player node instance on the server
	if requesting_player_node_on_server.has_method("process_server_craft_attempt"):
		requesting_player_node_on_server.process_server_craft_attempt(item_id_to_craft)
	else:
		printerr("  -> Main (Server) Error: Player node '", str(requesting_peer_id), "' missing 'process_server_craft_attempt' method.")
		# If possible, RPC a failure message back to the client via requesting_player_node_on_server.client_crafting_result.rpc(false, item_id_to_craft, "Internal server error: method missing")
		if requesting_player_node_on_server.has_method("client_crafting_result"): # Check before calling
			requesting_player_node_on_server.client_crafting_result(false, item_id_to_craft, "Internal server error: Craft processing method missing.")

@rpc("any_peer", "call_local", "reliable")
func server_handle_slot_emptied_for_drag(source_area_enum_val: int, source_index: int):
	if not multiplayer.is_server(): return
	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1: requesting_peer_id = 1
	
	var source_area = source_area_enum_val as Inventory.InventoryArea
	print("Main (Server): Peer [", requesting_peer_id, "] notified slot ", Inventory.InventoryArea.keys()[source_area], "[", source_index, "] was emptied for drag.")

	# Tell ServerInventoryManager to update this slot to null for this player
	# This will also trigger _notify_client_of_slot_update to confirm with the client.
	if ServerInventoryManager.has_method("_set_player_slot_item_authoritative"): # Let's assume a direct setter for this
		ServerInventoryManager._set_player_slot_item_authoritative(requesting_peer_id, source_area, source_index, null)
	else: # Fallback to a more generic remove if needed, or add the method
		# For now, let's ensure SIM has a way to just set a slot to null.
		# The existing _set_player_slot_item in SIM will do this and notify client.
		var current_item_in_slot_on_server = ServerInventoryManager.get_player_inventory_area_slots(requesting_peer_id, source_area)[source_index]
		if is_instance_valid(current_item_in_slot_on_server): # Only update if server thought something was there
			ServerInventoryManager._set_player_slot_item(requesting_peer_id, source_area, source_index, null)


# --- Pause/Resume Logic ---
func pause_game() -> void:
	if get_tree().paused: return # Already paused

	print("Main: Pausing game.") # Debug
	get_tree().paused = true # Pause the main game tree execution
	# Store mouse mode and show cursor
	previous_mouse_mode_before_pause = Input.get_mouse_mode()
	# Let PauseMenu handle showing cursor now Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Show the pause menu
	if is_instance_valid(pause_menu):
		pause_menu.show_menu()


func resume_game() -> void:
	if not get_tree().paused: return # Already running

	print("Main: Resuming game.") # Debug
	get_tree().paused = false # Unpause the game tree
	# Hide the pause menu (it might hide itself, but good practice)
	if is_instance_valid(pause_menu):
		pause_menu.hide_menu()
	# Restore previous mouse mode
	Input.set_mouse_mode(previous_mouse_mode_before_pause)


# --- Quit Logic ---
func quit_to_menu() -> void:
	print("Main: Quitting to start menu.") # Debug
	# Ensure game is unpaused before changing scene
	get_tree().paused = false
	# Reset SceneManager references if needed? Maybe not necessary if reloading Main later.
	# SceneManager.player_node = null
	# SceneManager.scene_container_node = null
	# SceneManager.current_level_root = null
	# SceneManager.main_scene_root = null # Clear main scene ref

	# Change scene back to the start screen
	var err = get_tree().change_scene_to_file(pause_menu.START_SCREEN_PATH) # Use path from PauseMenu
	if err != OK:
		printerr("Main Error: Failed to change scene to Start Screen! Error code:", err)
