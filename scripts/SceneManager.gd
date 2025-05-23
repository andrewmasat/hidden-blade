# SceneManager.gd - Autoload Singleton
# Handles scene transitions between the Start Screen, the Main gameplay scene,
# and different Level scenes loaded within the Main scene. Manages player
# positioning, state changes, and optional fade transitions.
extends Node

# --- Signals ---

## Emitted right before a scene change is initiated (after potential fade starts).
signal scene_change_requested(target_scene_path, target_spawn_name)
## Emitted right before freeing the old scene and loading the new one.
signal scene_load_started(scene_path)
## Emitted after the new scene is loaded, added to the tree, and player is positioned.
## Passes the root node of the newly loaded scene (Main or Level).
signal scene_load_finished(new_scene_root)


# --- Constants ---

## Path to the main gameplay scene structure (adjust if needed).
const MAIN_SCENE_PATH = "res://scenes/Main.tscn"
## Path to the start screen scene (adjust if needed).
const START_SCREEN_PATH = "res://scenes/StartScreen.tscn"
## The collision layer bit number used for scene transition triggers (1-based index).
## Must match the layer set in Project Settings -> Layer Names -> 2D Physics.
const TRIGGER_LAYER_BIT_VALUE : int = 10 # Example: Layer 4 for triggers
## Duration of the grace period after a level transition where player trigger collision is disabled.
const GRACE_PERIOD_DURATION : float = 0.1


# --- Node References (Managed Internally) ---

## Reference to the root node of the persistent Main gameplay scene instance.
var main_scene_root: Node = null
## Reference to the root node of the currently active Level scene instance (child of scene_container_node).
var current_level_root: Node = null
## Reference to the persistent Player node instance (child of Main).
var player_node: CharacterBody2D = null
## Reference to the persistent Node2D container for level scenes (child of Main).
var scene_container_node: Node = null
## Reference to the root node of the currently loaded scene (could be Main, StartScreen, or a Level).
var current_scene_root: Node = null # Used mainly for freeing previous scene

# --- Optional Fade Transition Variables ---
var fade_layer: CanvasLayer = null
var fade_player: AnimationPlayer = null
var fade_layer_initialized: bool = false


# Helper to check if a path likely points to a UI screen (adjust as needed)
func _is_ui_scene(scene_path: String) -> bool:
	# Add paths for LoadGameScreen, CharacterCreation, Settings etc.
	return scene_path == START_SCREEN_PATH \
		or scene_path == "res://scenes/LoadGameScreen.tscn" \
		or scene_path == "res://scenes/CharacterCreation.tscn"
		# Add other UI scene paths here

func _ready(): # Keep empty or just fade init
	pass

# --- Public API ---

## Initiates a scene change. Called by StartScreen or SceneTransitionArea.
func change_scene(target_scene_path: String, target_spawn_name: String) -> void:
	print("SceneManager: change_scene requested to '", target_scene_path, "' at '", target_spawn_name, "'")
	emit_signal("scene_change_requested", target_scene_path, target_spawn_name)

	# Ensure player is in transitioning state IF the player exists (not when called from StartScreen)
	if is_instance_valid(player_node) and player_node.has_method("start_scene_transition"):
		player_node.start_scene_transition()

	# Start the fade-in (to black) process if available
	await _start_fade_in()

	_perform_scene_change(target_scene_path, target_spawn_name)


## Handles quitting the game scene and returning to the Start Screen.
func return_to_start_screen() -> void:
	print("SceneManager: Returning to Start Screen...")
	# Just trigger a normal scene change TO the start screen
	# The _perform_scene_change logic will handle freeing Main and clearing refs.
	change_scene(START_SCREEN_PATH, "") # Use the standard change function


# --- Internal Scene Change Logic ---

# Performs the core steps of freeing old scene, loading new, adding, and setting up.
func _perform_scene_change(target_scene_path: String, target_spawn_name: String) -> void: # Mark async
	print("SceneManager: Performing scene change to:", target_scene_path)
	emit_signal("scene_load_started", target_scene_path)

	var is_loading_main_scene = (target_scene_path == MAIN_SCENE_PATH)
	var is_loading_ui_scene = _is_ui_scene(target_scene_path)

	# Start Fade In (can happen before freeing)
	await _start_fade_in()

	# --- 1. Free the PREVIOUS Scene Root ---
	# current_scene_root always holds the scene to be replaced.
	print("  -> Checking node to free (current_scene_root): ", current_scene_root.name if is_instance_valid(current_scene_root) else "None")
	if is_instance_valid(current_scene_root):
		var old_scene_parent = current_scene_root.get_parent()
		if is_instance_valid(old_scene_parent):
			old_scene_parent.remove_child(current_scene_root)
		current_scene_root.queue_free()
		print("  -> queue_free() called on old scene.")
	# else: print("  -> No valid previous scene found in current_scene_root to free.")

	# --- Clear References based on WHAT WE ARE LOADING ---
	if is_loading_main_scene or is_loading_ui_scene:
		# If loading Main OR another UI scene, clear potentially stale gameplay refs.
		# If loading Main, main_scene_root will be set below.
		# If loading UI, main_scene_root should become null.
		print("  -> Loading Main/UI, clearing gameplay references.")
		main_scene_root = null
		current_level_root = null
		player_node = null
		scene_container_node = null
		fade_layer = null # Assume fade layer lives in Main, clear ref too
		fade_player = null
		fade_layer_initialized = false
	# else: # Loading a level, only clear the old level ref (done implicitly below)
		# print("  -> Loading Level, keeping Main/Player references.")
		pass

	# Always clear the general current_scene_root ref before loading the new one
	current_scene_root = null

	# --- 2. Load and Instantiate New Scene ---
	var new_scene_instance = await _load_scene_instance(target_scene_path)
	if not is_instance_valid(new_scene_instance): return

	# --- 3. Add new scene to tree & Set References ---
	var parent_node_for_new_scene = null
	if is_loading_main_scene:
		parent_node_for_new_scene = get_tree().get_root()
		main_scene_root = new_scene_instance # Store ref to Main
		current_scene_root = main_scene_root
		# Find gameplay nodes immediately after adding Main
		_setup_main_scene(target_spawn_name) # Setup finds player, container, initial level, fade
	elif is_loading_ui_scene:
		parent_node_for_new_scene = get_tree().get_root()
		current_scene_root = new_scene_instance # UI scene is now the current root
		# Make sure gameplay refs stay null
		main_scene_root = null
		current_level_root = null
		player_node = null
		scene_container_node = null
		fade_layer = null # Fade layer reference belongs to Main scene normally
		fade_player = null
		fade_layer_initialized = false
	else: # Loading a Level
		if not is_instance_valid(scene_container_node): # Container MUST exist
			printerr("SceneManager Fatal Error: Cannot add level, scene_container_node invalid!")
			new_scene_instance.queue_free(); return
		parent_node_for_new_scene = scene_container_node
		current_level_root = new_scene_instance
		current_scene_root = current_level_root # Level is now the current root

	# Add the child if parent is valid
	if is_instance_valid(parent_node_for_new_scene):
		parent_node_for_new_scene.add_child(new_scene_instance)
		print("  -> New scene '", new_scene_instance.name, "' added under '", parent_node_for_new_scene.name, "'")
		# --- DEBUG: List children ---
		# print("  -> Children of parent:", parent_node_for_new_scene.get_children())
	else:
		# Should not happen with root fallback, but safety check
		printerr("SceneManager Error: Failed to determine parent node for new scene!")
		new_scene_instance.queue_free()
		return

	# --- 4. Post-Load Setup (Only needed for Levels) ---
	if not is_loading_main_scene and not is_loading_ui_scene:
		# Setup level transition (includes grace period await)
		await _setup_level_transition(target_spawn_name)

	# --- Final Steps ---
	emit_signal("scene_load_finished", current_scene_root)
	print("SceneManager: Scene change complete.")
	await _start_fade_out()


# --- Helper Functions ---
# Loads and instantiates a scene resource. Returns null on failure.
func _load_scene_instance(scene_path: String) -> Node:
	var scene_res = load(scene_path)
	if not scene_res is PackedScene:
		printerr("SceneManager Error: Failed load or invalid resource type: ", scene_path)
		await _start_fade_out() # Fade back if possible
		return null

	var scene_instance = scene_res.instantiate()
	if not is_instance_valid(scene_instance):
		printerr("SceneManager Error: Failed to instantiate scene: ", scene_path)
		await _start_fade_out()
		return null

	print("  -> New scene instantiated: ", scene_instance.name)
	return scene_instance


# Adds the new scene instance to the correct parent and updates root references.
func _add_new_scene_to_tree(scene_instance: Node, is_main: bool) -> void:
	var parent_node: Node = null
	if is_main:
		parent_node = get_tree().get_root()
		main_scene_root = scene_instance
		current_scene_root = main_scene_root
		current_level_root = null # Reset level ref when loading main
	else:
		# Loading a level, container must be valid
		if not is_instance_valid(scene_container_node):
			printerr("SceneManager Fatal Error: Cannot add level, scene_container_node invalid!")
			scene_instance.queue_free() # Clean up orphan
			# Consider error handling - maybe force return_to_start_screen()?
			return
		parent_node = scene_container_node
		current_level_root = scene_instance
		current_scene_root = current_level_root # Update general ref

	parent_node.add_child(scene_instance)
	print("  -> New scene '", scene_instance.name, "' added under '", parent_node.name, "'")


# Finds persistent nodes after Main scene loads, finds initial level/spawn, positions player.
func _setup_main_scene(_initial_spawn_name: String) -> void:
	print("  -> SceneManager: _setup_main_scene called for Main scene.")
	if not is_instance_valid(main_scene_root):
		printerr("    Error: main_scene_root invalid during _setup_main_scene!")
		return

	scene_container_node = main_scene_root.find_child("Environments", true, false)
	initialize_fade_layer()

	if is_instance_valid(scene_container_node):
		var initial_level_node: Node = null
		for child in scene_container_node.get_children():
			if child is Node2D and not child is MultiplayerSpawner: # Example find logic
				initial_level_node = child
				break
		current_level_root = initial_level_node # Set based on find
		if is_instance_valid(current_level_root):
			print("    -> SceneManager: Initial level set to:", current_level_root.name)
		else:
			printerr("    Error: SceneManager could not find initial level in _setup_main_scene!")


# Finds spawn point in the newly loaded level, positions player, handles grace period.
func _setup_level_transition(target_spawn_name: String) -> void: # Mark as async for await
	print("  -> Setting up Level transition...")
	if not is_instance_valid(player_node) or not is_instance_valid(current_level_root):
		printerr("    Error: Player or current_level_root invalid during level setup!")
		return

	# Find spawn point in NEW level (current_level_root)
	var spawn_point = current_level_root.find_child(target_spawn_name, true, false) as Node2D
	var target_pos = spawn_point.global_position if is_instance_valid(spawn_point) else current_level_root.global_position # Fallback
	if not is_instance_valid(spawn_point): printerr("    Warning: Target spawn '", target_spawn_name, "' not found.")

	# Position player
	player_node.global_position = target_pos
	print("    -> Player positioned at: ", target_pos)

	# --- Grace Period ---
	var needs_disable = player_node.get_collision_layer_value(TRIGGER_LAYER_BIT_VALUE)
	if needs_disable:
		print("    -> Disabling player trigger collision layer bit: ", TRIGGER_LAYER_BIT_VALUE)
		player_node.set_collision_layer_value(TRIGGER_LAYER_BIT_VALUE, false)

	print("    -> Starting grace period wait...")
	await get_tree().create_timer(GRACE_PERIOD_DURATION).timeout
	print("    -> Grace period finished.")

	# Restore Collision & Player State (Deferred)
	if is_instance_valid(player_node): # Check player validity AFTER await
		if needs_disable:
			print("    -> Scheduling restore player collision layer bit.")
			player_node.call_deferred("set_collision_layer_value", TRIGGER_LAYER_BIT_VALUE, true)

		if player_node.has_method("end_scene_transition"):
			player_node.call_deferred("end_scene_transition")
			print("    -> Called player.end_scene_transition (deferred).")
	else:
		printerr("    Error: Player node became invalid AFTER grace period await!")


# Clears all managed node references.
func _clear_all_refs() -> void:
	main_scene_root = null
	current_level_root = null
	player_node = null
	scene_container_node = null
	current_scene_root = null
	fade_layer = null
	fade_player = null
	fade_layer_initialized = false


# --- Optional Fade Helpers ---

# Plays fade-in animation and waits for completion. Returns true if fade ran/completed.
func _start_fade_in() -> bool:
	if fade_player and fade_player.has_animation("Fade_In"):
		print("SceneManager: Playing Fade_In...")
		if is_instance_valid(fade_layer): fade_layer.visible = true # Ensure layer visible
		fade_player.play("Fade_In")
		await fade_player.animation_finished
		print("SceneManager: Fade_In finished.")
		return true # Indicate fade completed
	else:
		# No fade available or animation missing
		if not is_instance_valid(fade_player): print("SceneManager: No fade player for Fade_In.")
		elif not fade_player.has_animation("Fade_In"): print("SceneManager: Fade_In animation missing.")
		return false # Indicate fade did not run


# Plays fade-out animation and waits. Also hides layer after. Returns true if ran/completed.
func _start_fade_out() -> bool:
	if fade_player and fade_player.has_animation("Fade_Out"):
		print("SceneManager: Playing Fade_Out...")
		if is_instance_valid(fade_layer): fade_layer.visible = true # Ensure layer visible for fade out
		fade_player.play("Fade_Out")
		await fade_player.animation_finished
		print("SceneManager: Fade_Out finished.")
		if is_instance_valid(fade_layer): fade_layer.visible = false # Hide layer after fade
		return true
	else:
		# No fade available or animation missing
		if not is_instance_valid(fade_player): print("SceneManager: No fade player for Fade_Out.")
		elif not fade_player.has_animation("Fade_Out"): print("SceneManager: Fade_Out animation missing.")
		return false

# --- Initialization ---

# Finds fade layer nodes. Can be called again if Main scene reloads.
func initialize_fade_layer() -> void:
	# Reset flag to allow re-initialization
	fade_layer_initialized = false
	fade_layer = null
	fade_player = null
	print("SceneManager: Attempting fade layer initialization...")

	# Search within the CURRENT main_scene_root first
	var search_root = main_scene_root if is_instance_valid(main_scene_root) else get_tree().get_root()
	var potential_fade_layer = search_root.find_child("FadeLayer", true, false) # Prefer finding within Main

	# Fallback to group search if not found as direct child (less reliable)
	if not is_instance_valid(potential_fade_layer):
		print("  -> FadeLayer not found as child of Main, searching group...")
		potential_fade_layer = get_tree().get_first_node_in_group("FadeLayer")

	if potential_fade_layer is CanvasLayer:
		var potential_anim_player = potential_fade_layer.find_child("AnimationPlayer", false) # Direct child only
		if potential_anim_player is AnimationPlayer:
			fade_layer = potential_fade_layer
			fade_player = potential_anim_player
			fade_layer_initialized = true
			print("  -> Fade layer setup SUCCESSFUL (Node: '", fade_layer.name, "', Player: '", fade_player.name, "')")
			# Optional: Check animation existence here too
		else:
			printerr("  -> Found FadeLayer '", potential_fade_layer.name, "' but MISSING AnimationPlayer child!")
	else:
		printerr("SceneManager: FadeLayer node not found or is not a CanvasLayer.")
