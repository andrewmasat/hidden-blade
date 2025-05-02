# Main.gd (Attach to root node 'Main')
extends Node

# Adjust paths based on your exact node names in Main.tscn
@onready var environments_container: Node2D = $Environments
@onready var player: CharacterBody2D = $WorldYSort/Player
# We need a way to know which child of 'Environments' is the starting level
# You could hardcode the name, or find the first child, or use a specific group.
# Let's assume the first child IS the starting level for simplicity here.
@onready var initial_level: Node = environments_container.get_child(0) if environments_container.get_child_count() > 0 else null

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
