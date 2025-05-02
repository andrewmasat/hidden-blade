# Main.gd (Attach to root node 'Main')
extends Node

# Adjust paths based on your exact node names in Main.tscn
@onready var environments_container: Node2D = $Environments
@onready var player: CharacterBody2D = $WorldYSort/Player
@onready var pause_menu = $PauseMenu
# We need a way to know which child of 'Environments' is the starting level
# You could hardcode the name, or find the first child, or use a specific group.
# Let's assume the first child IS the starting level for simplicity here.
@onready var initial_level: Node = environments_container.get_child(0) if environments_container.get_child_count() > 0 else null

var previous_mouse_mode_before_pause = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	# --- Validate Initial Setup ---
	if not is_instance_valid(environments_container):
		printerr("Main Error: Environments node not found!")
		return
	if not is_instance_valid(player):
		printerr("Main Error: Player node not found!")
		return
	if not is_instance_valid(initial_level):
		printerr("Main Error: No initial level found under Environments node!")
		return

	# --- Initialize SceneManager ---
	if SceneManager:
		# Give SceneManager reference to the player
		SceneManager.player_node = player
		# Give SceneManager reference to the CURRENT scene root node
		SceneManager.current_level_root = initial_level
		# --- Give SceneManager reference to the CONTAINER for levels ---
		SceneManager.scene_container_node = environments_container
		# --- Call fade layer init AFTER main nodes ready ---
		SceneManager.initialize_fade_layer()
		print("Main: Initialized SceneManager. player_node is valid:", is_instance_valid(SceneManager.player_node)) # DEBUG
	else:
		printerr("Main Error: SceneManager autoload not found!")

	# --- Position Player at Initial Spawn ---
	var initial_spawn = initial_level.find_child("InitialSpawn", true, false) as Node2D
	if is_instance_valid(initial_spawn):
		player.global_position = initial_spawn.global_position
		print("Main: Player positioned at InitialSpawn:", player.global_position)
	else:
		printerr("Main Warning: 'InitialSpawn' Marker2D not found in starting level!")
		# Player starts at its default position relative to Main

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
