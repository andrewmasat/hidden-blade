# SceneManager.gd - Autoload Singleton
extends Node

signal scene_change_requested(target_scene_path, target_spawn_name)
signal scene_load_started(scene_path)
signal scene_load_finished(new_scene_root)

var main_scene_root: Node = null
var current_scene_root: Node = null
var current_level_root: Node = null
var player_node: CharacterBody2D = null
var scene_container_node: Node = null

# Optional: For fade transitions
var fade_layer: CanvasLayer = null
var fade_player: AnimationPlayer = null
var fade_layer_initialized = false

const TRIGGER_LAYER_BIT_VALUE = 10
const MAIN_SCENE_PATH = "res://scenes/Main.tscn"
const START_SCREEN_PATH = "res://scenes/StartScreen.tscn"

func _ready():
	# Don't search here anymore
	pass

func initialize_fade_layer():
	# Allow re-initialization if main scene reloads
	# if fade_layer_initialized: return
	print("SceneManager: Attempting fade layer initialization...")

	# Search within the CURRENT main_scene_root if it's valid
	var search_root = main_scene_root if is_instance_valid(main_scene_root) else get_tree().get_root()
	var potential_fade_layer = search_root.find_child("FadeLayer", true, false) # Use find_child if group fails sometimes
	# Fallback to group search if needed
	# if not is_instance_valid(potential_fade_layer):
	#     potential_fade_layer = get_tree().get_first_node_in_group("FadeLayer")

	if potential_fade_layer is CanvasLayer:
		print("  -> Found potential fade layer node:", potential_fade_layer.name)
		var potential_anim_player = potential_fade_layer.find_child("AnimationPlayer", false) # Find direct child
		if potential_anim_player is AnimationPlayer:
			fade_layer = potential_fade_layer
			fade_player = potential_anim_player
			print("  -> Found AnimationPlayer:", fade_player.name)
			print("  -> Fade layer setup SUCCESSFUL.")
			if not fade_player.has_animation("Fade_In"): print("    WARNING: Missing Fade_In animation!")
			if not fade_player.has_animation("Fade_Out"): print("    WARNING: Missing Fade_Out animation!")
			fade_layer_initialized = true # Mark as initialized (maybe reset this on return_to_start_screen?)
		else:
			printerr("  -> Found FadeLayer but MISSING AnimationPlayer child!")
			fade_layer = null; fade_player = null; fade_layer_initialized = false;
	else:
		printerr("SceneManager: FadeLayer node not found or is not a CanvasLayer.")
		fade_layer = null; fade_player = null; fade_layer_initialized = false;

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
		fade_layer.visible = true
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
	var node_to_free: Node = null
	if is_loading_main_scene:
		# We are loading Main, so the 'current' root IS the previous scene (StartScreen)
		node_to_free = current_scene_root
		print("  -> Preparing to free previous top-level scene:", node_to_free.name if is_instance_valid(node_to_free) else "None")
		# Clear main scene refs as they are about to be found again
		main_scene_root = null
		player_node = null
		scene_container_node = null
		current_level_root = null
	else:
		# We are loading a Level, so free the previous LEVEL scene
		node_to_free = current_level_root
		print("  -> Preparing to free previous LEVEL scene:", node_to_free.name if is_instance_valid(node_to_free) else "None")
		# Keep main_scene_root, player_node, scene_container_node references

	if is_loading_main_scene and is_instance_valid(node_to_free) and node_to_free == main_scene_root:
		print("  -> Clearing potentially stale fade refs because Main scene was freed.")
		fade_layer = null
		fade_player = null
		# Also clear player/container refs that belonged to old Main
		player_node = null
		scene_container_node = null

	# Actually free the identified node if it's valid
	if is_instance_valid(node_to_free):
		# Important: Check parent relationship before removing!
		# Levels are under scene_container_node. Main/Start are under root.
		var expected_parent = get_tree().get_root() if is_loading_main_scene else scene_container_node
		if is_instance_valid(node_to_free.get_parent()) and node_to_free.get_parent() == expected_parent:
			expected_parent.remove_child(node_to_free)
			print("  -> Removed from parent:", expected_parent.name)
		elif is_instance_valid(node_to_free.get_parent()):
			# Parent mismatch - might indicate structural issue, but try removing anyway
			printerr("SceneManager Warning: Node to free had unexpected parent:", node_to_free.get_parent().name, "Expected:", expected_parent.name if expected_parent else "N/A")
			node_to_free.get_parent().remove_child(node_to_free) # Attempt removal
		# else: Node had no parent already?

		node_to_free.queue_free() # Free it
		print("  -> queue_free() called on old scene.")
	else:
		print("  -> No valid previous scene/level node found to free.")

	# Clear the specific reference that was just freed
	if is_loading_main_scene:
		current_scene_root = null # Clear the general reference too
	else:
		current_level_root = null

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
		parent_node_for_new_scene = get_tree().get_root()
		main_scene_root = new_scene_instance # Store ref to Main
		current_scene_root = main_scene_root # Update general ref
		current_level_root = null # No level loaded yet
	else:
		# Loading a level
		if not is_instance_valid(scene_container_node): # Check container valid BEFORE adding
			printerr("SceneManager Fatal Error: Cannot add level, scene_container_node is invalid!")
			new_scene_instance.queue_free()
			return
		parent_node_for_new_scene = scene_container_node
		current_level_root = new_scene_instance
		current_scene_root = current_level_root

	parent_node_for_new_scene.add_child(new_scene_instance)
	print("  -> New scene added to tree under:", parent_node_for_new_scene.name)

	# --- Post-Load Setup ---
	if is_loading_main_scene:
		# --- Main Scene Loaded ---
		print("  -> Main scene loaded. Finding persistent nodes immediately...")
		player_node = main_scene_root.find_child("Player", true, false) as CharacterBody2D
		scene_container_node = main_scene_root.find_child("Environments", true, false)
		current_level_root = scene_container_node.get_child(0) if scene_container_node and scene_container_node.get_child_count() > 0 else null

		# Validate nodes found
		if not is_instance_valid(player_node): printerr("SceneManager Error: Player node not found within loaded Main scene!")
		if not is_instance_valid(scene_container_node): printerr("SceneManager Error: Environments node not found within loaded Main scene!")

		initialize_fade_layer()

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
		fade_layer.visible = true
		fade_player.play("Fade_Out")
		await fade_player.animation_finished
		fade_layer.visible = false
	else:
		# Provide more specific reason if possible
		if not is_instance_valid(fade_player):
			print("SceneManager: Cannot play Fade_Out, fade_player reference is invalid.") # DEBUG
		elif not fade_player.has_animation("Fade_Out"):
			print("SceneManager: Cannot play Fade_Out, animation missing.") # DEBUG
		else:
			print("SceneManager: Cannot play Fade_Out (Unknown reason).") # DEBUG

func return_to_start_screen() -> void:
	print("SceneManager: Returning to Start Screen...")

	# 1. Tell player state is ending (optional, might not matter if Main is freed)
	if is_instance_valid(player_node) and player_node.has_method("start_scene_transition"):
		player_node.start_scene_transition() # Put in transitioning state

	# 2. Optional Fade to Black
	if fade_player and fade_player.has_animation("Fade_In"):
		fade_layer.visible = true
		fade_player.play("Fade_In")
		await fade_player.animation_finished
	# else: proceed immediately

	# 3. Free the ENTIRE Main Scene Instance
	if is_instance_valid(main_scene_root):
		print("  -> Freeing entire Main scene:", main_scene_root.name)
		if is_instance_valid(main_scene_root.get_parent()):
			main_scene_root.get_parent().remove_child(main_scene_root)
		main_scene_root.queue_free()
	else:
		printerr("SceneManager: Cannot free Main scene, reference invalid!")

	# 4. Clear internal references that are no longer valid
	main_scene_root = null
	current_level_root = null
	player_node = null
	scene_container_node = null
	current_scene_root = null # Clear this too
	fade_layer = null
	fade_player = null
	fade_layer_initialized = false
	print("  -> SceneManager references cleared.")

	# 5. Load and instantiate the StartScreen scene
	var start_scene_res = load(START_SCREEN_PATH)
	if not start_scene_res is PackedScene:
		printerr("SceneManager Error: Failed to load StartScreen scene!")
		# Critical error - maybe quit application?
		get_tree().quit()
		return

	var start_scene_instance = start_scene_res.instantiate()
	if not is_instance_valid(start_scene_instance):
		printerr("SceneManager Error: Failed to instantiate StartScreen!")
		get_tree().quit()
		return

	# 6. Add StartScreen under the root
	get_tree().get_root().add_child(start_scene_instance)
	# Update current_scene_root to point to the StartScreen now
	current_scene_root = start_scene_instance
	print("  -> StartScreen added and set as current scene root.")

	# 7. Optional Fade back in (if using fade layer independent of Main scene)
	#    If FadeLayer was child of Main, it was freed. Need independent FadeLayer.
	#    If FadeLayer is setup standalone (e.g., separate Autoload or child of root), fade out here.
	if fade_player and fade_player.has_animation("Fade_Out"):
		fade_player.play("Fade_Out")
		await fade_player.animation_finished
		fade_layer.visible = false
