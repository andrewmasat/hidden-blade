# Main.gd (Attach to root node 'Main')
extends Node

const PlayerScene = preload("res://player/Player.tscn")

@onready var player_spawner: MultiplayerSpawner = $WorldYSort/PlayerSpawner
@onready var environments_container: Node2D = $WorldYSort/Environments
@onready var hud = $HUD
@onready var pause_menu = $PauseMenu
# We need a way to know which child of 'Environments' is the starting level
# You could hardcode the name, or find the first child, or use a specific group.
# Let's assume the first child IS the starting level for simplicity here.
@onready var initial_level: Node = environments_container.get_child(0) if environments_container.get_child_count() > 0 else null

var local_player_node: CharacterBody2D = null
var previous_mouse_mode_before_pause = Input.MOUSE_MODE_CAPTURED

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

	# --- Initialize SceneManager ---
	if SceneManager:
		SceneManager.scene_container_node = environments_container
		SceneManager.main_scene_root = self # 'self' is the Main scene instance
		# Player node ref is set later by _setup_local_player_references
		# Initial level ref is set later by _setup_local_player_references for new game
		# or by SceneManager for loaded game
		await SceneManager.initialize_fade_layer() # Call this once main structural nodes are set in SM
		print("Main: Initialized SceneManager structural references (container, main_root, fade).")
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


func _custom_player_spawn_function(peer_id_to_spawn_for: Variant) -> Node:
	var peer_id = int(peer_id_to_spawn_for)

	print("Main (Server - _custom_player_spawn_function): Spawning player for peer ID:", peer_id)

	if not PlayerScene:
		printerr("Main (_custom_player_spawn_function): PlayerScene not preloaded!")
		return null

	var player_instance = PlayerScene.instantiate()
	if not is_instance_valid(player_instance):
		printerr("Main (_custom_player_spawn_function): Failed to instantiate PlayerScene!")
		return null

	player_instance.name = str(peer_id)
	player_instance.set_multiplayer_authority(peer_id)

	var spawn_marker_name = "InitialSpawn" # Default for new game start
	var spawn_position = Vector2.ZERO # Fallback

	if is_instance_valid(SceneManager.current_level_root):
		var spawn_marker = SceneManager.current_level_root.find_child(spawn_marker_name, true, false) as Node2D
		if is_instance_valid(spawn_marker):
			spawn_position = spawn_marker.global_position
			print("  -> CustomSpawn: Found '", spawn_marker_name, "' at ", spawn_position, " for player ", peer_id)
		else:
			printerr("  -> CustomSpawn: '", spawn_marker_name, "' not found in current level '", SceneManager.current_level_root.name, "'. Player ", peer_id, " at origin of level.")
			spawn_position = SceneManager.current_level_root.global_position # Spawn at level origin
	else:
		printerr("  -> CustomSpawn: SceneManager.current_level_root is invalid. Player ", peer_id, " at global origin.")
		# This is a critical error if current_level_root isn't set when spawning.

	player_instance.global_position = spawn_position # Set authoritative position
	# ---------------------------------

	print("Main (_custom_player_spawn_function): Player instance '", player_instance.name, "' created, configured, and positioned at ", spawn_position)
	return player_instance


func _wait_and_setup_local_player_client():
	if multiplayer.is_server(): return # Only for clients

	var local_peer_id_str = str(multiplayer.get_unique_id())
	var spawner_spawn_path_node = get_node_or_null(player_spawner.spawn_path)
	if not is_instance_valid(spawner_spawn_path_node):
		printerr("Main (Client): Spawner path invalid while waiting for player.")
		return

	# Wait up to a few seconds for the node to appear
	var attempts = 0
	while not is_instance_valid(spawner_spawn_path_node.get_node_or_null(local_peer_id_str)) and attempts < 100: # Approx 1.6s
		await get_tree().process_frame
		attempts += 1

	if is_instance_valid(spawner_spawn_path_node.get_node_or_null(local_peer_id_str)):
		_setup_local_player_references(local_peer_id_str)
	else:
		printerr("Main (Client): Timed out waiting for local player node '", local_peer_id_str, "' to be spawned.")


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
		SceneManager.player_node = local_player_node
		print("Main: Local player node '", local_player_node.name, "' reference SET.")

		# --- ALWAYS NEW GAME POSITIONING LOGIC NOW ---
		# (As server handles restoring position for returning players)
		print("Main: New connection setup for player '", local_player_node.name, "'.")
		var initial_level_node = SceneManager.current_level_root # Get from SM
		if not is_instance_valid(initial_level_node):
			initial_level_node = environments_container.get_child(0) if environments_container.get_child_count() > 0 else null
			if is_instance_valid(initial_level_node): SceneManager.current_level_root = initial_level_node
			else: printerr("Main Error: No initial level for new game spawn!"); return

		var initial_spawn_marker_name = "InitialSpawn" # Get from SM if stored, e.g., SceneManager.target_spawn_name
		var initial_spawn = initial_level_node.find_child(initial_spawn_marker_name, true, false) as Node2D

		if is_instance_valid(initial_spawn):
			local_player_node.global_position = initial_spawn.global_position
			print("Main: Local player '", local_player_node.name, "' positioned at '", initial_spawn_marker_name, "'.")
		else:
			print("Main Warning: '", initial_spawn_marker_name, "' not found. Player at origin.")
			local_player_node.global_position = Vector2.ZERO

		if local_player_node.has_method("end_scene_transition"): # Reset to IDLE_RUN
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
