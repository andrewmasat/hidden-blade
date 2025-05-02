# SceneManager.gd - Autoload Singleton
extends Node

signal scene_change_requested(target_scene_path, target_spawn_name)
signal scene_load_started(scene_path)
signal scene_load_finished(new_scene_root)

var main_scene_root: Node = null
var current_level_root: Node = null
var player_node: CharacterBody2D = null
var scene_container_node: Node = null

# Optional: For fade transitions
var fade_layer: CanvasLayer = null
var fade_player: AnimationPlayer = null
var fade_layer_initialized = false

const TRIGGER_LAYER_BIT_VALUE = 10
const MAIN_SCENE_PATH = "res://scenes/Main.tscn"

func _ready():
	# Don't search here anymore
	pass

func initialize_fade_layer():
	if fade_layer_initialized: return # Don't initialize twice
	print("SceneManager: Attempting fade layer initialization...") # DEBUG

	var potential_fade_layer = get_tree().get_first_node_in_group("FadeLayer")
	print("SceneManager Ready: Searching for FadeLayer group...") # DEBUG
	if potential_fade_layer is CanvasLayer:
		print("  -> Found potential fade layer node:", potential_fade_layer.name) # DEBUG
		if potential_fade_layer.has_node("AnimationPlayer"):
			fade_layer = potential_fade_layer
			fade_player = fade_layer.get_node("AnimationPlayer")
			print("  -> Found AnimationPlayer:", fade_player.name) # DEBUG
			print("  -> Fade layer setup SUCCESSFUL.") # DEBUG
			# Check if animations exist
			if not fade_player.has_animation("Fade_In"): print("    WARNING: Missing Fade_In animation!")
			if not fade_player.has_animation("Fade_Out"): print("    WARNING: Missing Fade_Out animation!")
			# Optional: Ensure initial state is faded out if needed (might interfere)
			# fade_player.play("Fade_Out", -1, 1.0, true) # Play backwards instantly? Risky.
			# fade_layer.visible = true # Ensure layer itself is visible
			# var color_rect = fade_layer.get_node_or_null("ColorRect") # Assuming name is ColorRect
			# if color_rect: color_rect.modulate.a = 0.0 # Start transparent
		else:
			printerr("  -> Found FadeLayer but MISSING AnimationPlayer child!")
	else:
		printerr("SceneManager Ready: FadeLayer node not found in group 'FadeLayer' or is not a CanvasLayer.")
		# Clear refs just in case they were partially set
		fade_layer = null
		fade_player = null

	if fade_player != null:
		fade_layer_initialized = true

# Called externally (e.g., by SceneTransitionArea) to initiate a change.
func change_scene(target_scene_path: String, target_spawn_name: String) -> void:
	print("SceneManager: change_scene requested to", target_scene_path, "at", target_spawn_name)
	emit_signal("scene_change_requested", target_scene_path, target_spawn_name)

	# --- Tell Player to Stop Moving IF player exists ---
	# Player might not exist when called from StartScreen
	if is_instance_valid(player_node) and player_node.has_method("start_scene_transition"):
		player_node.start_scene_transition()

	# --- Start Fade Out ---
	if fade_player and fade_player.has_animation("Fade_In"):
		print("SceneManager: Playing Fade_In...") # DEBUG
		fade_player.play("Fade_In")
		await fade_player.animation_finished
		print("SceneManager: Fade_In finished.") # DEBUG
		_perform_scene_change(target_scene_path, target_spawn_name)
	else:
		print("SceneManager: No fade player or Fade_In animation found, changing instantly.") # DEBUG
		_perform_scene_change(target_scene_path, target_spawn_name)

# Internal function to handle the actual loading and setup.
func _perform_scene_change(target_scene_path: String, target_spawn_name: String) -> void:
	print("SceneManager: Performing scene change...")
	emit_signal("scene_load_started", target_scene_path)

	# --- Determine if loading the main game scene ---
	# This is crucial for setting up initial references
	var is_loading_main_scene = (target_scene_path == MAIN_SCENE_PATH)

	# 1. Free the OLD scene root (if it exists)
	if is_loading_main_scene:
		# If loading Main, free whatever was there before (e.g., StartScreen)
		if is_instance_valid(main_scene_root): # Use main_scene_root for top level
			print("  -> Freeing old MAIN scene:", main_scene_root.name)
			if is_instance_valid(main_scene_root.get_parent()):
				main_scene_root.get_parent().remove_child(main_scene_root)
			main_scene_root.queue_free()
			main_scene_root = null
			player_node = null # Clear refs that belonged to old Main
			scene_container_node = null
			current_level_root = null
	else:
		# If loading a Level, free only the CURRENT LEVEL under Environments
		if is_instance_valid(current_level_root):
			print("  -> Freeing old LEVEL scene:", current_level_root.scene_file_path if current_level_root.scene_file_path else current_level_root.name)
			if is_instance_valid(scene_container_node) and current_level_root.get_parent() == scene_container_node:
				scene_container_node.remove_child(current_level_root)
			else:
				printerr("SceneManager Warning: Old level parent was not the Environments container!")
			current_level_root.queue_free()
			current_level_root = null # Clear level reference
		# Do NOT free main_scene_root or player_node here!

	# 2. Load the new scene resource
	var next_scene_res = load(target_scene_path)
	if not next_scene_res is PackedScene:
		printerr("SceneManager Error: Failed to load scene or invalid resource type at path:", target_scene_path)
		# Handle error: maybe load a default scene or return player to previous? Difficult.
		# For now, just stop and potentially fade out.
		if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
		return

	# 3. Instantiate the new scene
	var new_scene_instance = next_scene_res.instantiate()
	if not is_instance_valid(new_scene_instance):
		printerr("SceneManager Error: Failed to instantiate scene:", target_scene_path)
		new_scene_instance = null # Ensure it's null if instantiation failed
		if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
		return
	print("  -> New scene instantiated:", new_scene_instance.name)

	# 4. Add new scene to tree
	var parent_node_for_new_scene = null
	if is_loading_main_scene:
		parent_node_for_new_scene = get_tree().get_root() # Add Main under root
		main_scene_root = new_scene_instance # Store reference to Main scene
		current_level_root = null # No level loaded yet within Main
	else:
		# Loading a level, container MUST be valid
		if not is_instance_valid(scene_container_node):
			printerr("SceneManager Fatal Error: Cannot add level, scene_container_node is invalid!")
			new_scene_instance.queue_free()
			# Possibly try reloading Main scene? Or quit?
			return
		parent_node_for_new_scene = scene_container_node # Add level under Environments
		current_level_root = new_scene_instance # Store reference to new LEVEL

	parent_node_for_new_scene.add_child(new_scene_instance)
	print("  -> New scene added to tree under:", parent_node_for_new_scene.name)

	# --- Post-Load Setup ---
	if is_loading_main_scene:
		# --- Main Scene Loaded ---
		print("  -> Main scene loaded. Finding persistent nodes...")
		# Find and STORE references to persistent nodes within the loaded Main scene
		player_node = main_scene_root.find_child("Player", true, false) as CharacterBody2D
		scene_container_node = main_scene_root.find_child("Environments", true, false)
		# Find initial level WITHIN the new Main scene's container
		current_level_root = scene_container_node.get_child(0) if scene_container_node and scene_container_node.get_child_count() > 0 else null

		# Validate nodes found
		if not is_instance_valid(player_node): printerr("SceneManager Error: Player node not found within loaded Main scene!")
		if not is_instance_valid(scene_container_node): printerr("SceneManager Error: Environments node not found within loaded Main scene!")

		# Get the initial level (which should be pre-instantiated within Main.tscn)
		var initial_level_node = scene_container_node.get_child(0) if scene_container_node and scene_container_node.get_child_count() > 0 else null
		if not is_instance_valid(initial_level_node):
			printerr("SceneManager Error: Initial level node not found within loaded Main scene!")
		else:
			# Find spawn point within the INITIAL LEVEL and position player
			var spawn_point: Node2D = initial_level_node.find_child(target_spawn_name, true, false) as Node2D
			var target_position: Vector2
			if not is_instance_valid(spawn_point):
				printerr("SceneManager Warning: Initial spawn '", target_spawn_name, "' not found. Using player default pos.")
				target_position = player_node.global_position # Keep player where it started in Main.tscn
			else:
				target_position = spawn_point.global_position

			player_node.global_position = target_position
			print("  -> Player positioned at initial spawn:", target_position)

		if is_instance_valid(current_level_root): # Check if initial level exists
			# Find spawn point within the INITIAL LEVEL
			var spawn_point: Node2D = current_level_root.find_child(target_spawn_name, true, false) as Node2D
			# ... (Position player based on spawn_point or fallback) ...
		else:
			printerr("SceneManager Error: No initial level found to get spawn point from!")
			# Position player at default origin maybe? player_node.global_position = Vector2.ZERO

		# NO grace period needed when loading Main scene itself. Player starts fresh.
		# NO need to call end_scene_transition here, player starts in default state.

	else: # --- Level Scene Loaded (Transitioning between levels) ---
		print("  -> Level scene loaded. Positioning player...")
		# Player and container SHOULD be valid here from previous Main load.
		if not is_instance_valid(player_node) or not is_instance_valid(scene_container_node):
			printerr("SceneManager Error: Persistent nodes invalid during level transition!")
			return # Abort if critical refs lost

		# Find spawn point in the NEW level and get target position
		var spawn_point: Node2D = current_level_root.find_child(target_spawn_name, true, false) as Node2D
		var target_position: Vector2
		if not is_instance_valid(spawn_point):
			printerr("SceneManager Warning: Spawn '", target_spawn_name, "' not found. Using scene origin.")
			target_position = current_level_root.global_position
		else:
			target_position = spawn_point.global_position

		# --- Position Player & Handle Grace Period ---
		var original_player_layer = player_node.get_collision_layer()
		player_node.global_position = target_position
		print("  -> Player positioned at:", target_position)

		# Temporarily Disable Player's Trigger Collision
		var needs_disable = (player_node.get_collision_layer_value(TRIGGER_LAYER_BIT_VALUE))
		if needs_disable:
			print("  -> Disabling player trigger collision layer bit:", TRIGGER_LAYER_BIT_VALUE)
			player_node.set_collision_layer_value(TRIGGER_LAYER_BIT_VALUE, false)
		# else: print("  -> Player layer doesn't include trigger bit.")

		if not is_instance_valid(player_node):
			printerr("SceneManager Error: Player became invalid BEFORE grace period await!")
			# Maybe fade out and stop?
			if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
			return

		# Wait for grace period
		print("SceneManager: Starting grace period wait...")
		await get_tree().create_timer(0.1).timeout
		print("SceneManager: Grace period finished.")

		if not is_instance_valid(player_node):
			printerr("SceneManager Error: Player became invalid AFTER grace period await!")
			# Cannot call deferred methods now. Maybe fade out?
			if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
			return

		# Restore Player Collision Layer (Deferred)
		if needs_disable:
			print("SceneManager: Scheduling restore player collision layer bit:", TRIGGER_LAYER_BIT_VALUE)
			player_node.call_deferred("set_collision_layer_value", TRIGGER_LAYER_BIT_VALUE, true)

		# Tell Player Transition Ended (Deferred)
		if player_node.has_method("end_scene_transition"):
			player_node.call_deferred("end_scene_transition")
			print("SceneManager: Called player.end_scene_transition (deferred).")
		# --------------------------------------------

	emit_signal("scene_load_finished", current_level_root)
	print("SceneManager: Scene change complete.")

	# --- Start Fade Out ---
	if fade_player and fade_player.has_animation("Fade_Out"):
		print("SceneManager: Playing Fade_Out...") # DEBUG
		fade_player.play("Fade_Out")
	else:
		print("SceneManager: No fade player or Fade_Out animation found.") # DEBUG
