# SceneManager.gd - Autoload Singleton
extends Node

signal scene_change_requested(target_scene_path, target_spawn_name)
signal scene_load_started(scene_path)
signal scene_load_finished(new_scene_root)

var current_scene_root: Node = null
var player_node: CharacterBody2D = null
var scene_container_node: Node = null

# Optional: For fade transitions
var fade_layer: CanvasLayer = null
var fade_player: AnimationPlayer = null

const TRIGGER_LAYER_BIT_VALUE = 10

func _ready() -> void:
	# Find the fade layer if using one (assumes it's added elsewhere, e.g., in main scene)
	var potential_fade_layer = get_tree().get_first_node_in_group("FadeLayer")
	if potential_fade_layer is CanvasLayer and potential_fade_layer.has_node("AnimationPlayer"):
		fade_layer = potential_fade_layer
		fade_player = fade_layer.get_node("AnimationPlayer")
		print("SceneManager: Fade layer found.")
		# Ensure it starts faded out (transparent)
		#if fade_player.has_animation("Fade_Out"):
			#fade_player.play("Fade_Out") # Play instantly to set state
			#fade_player.seek(fade_player.get_animation("Fade_Out").length, true) # Go to end
	else:
		print("SceneManager: Fade layer/player not found (group 'FadeLayer'). Transitions will be instant.")


# Called externally (e.g., by SceneTransitionArea) to initiate a change.
func change_scene(target_scene_path: String, target_spawn_name: String) -> void:
	print("SceneManager: change_scene requested to", target_scene_path, "at", target_spawn_name)
	emit_signal("scene_change_requested", target_scene_path, target_spawn_name)

	# --- Tell Player to Stop Moving (using the dedicated method) ---
	if is_instance_valid(player_node) and player_node.has_method("start_scene_transition"):
		player_node.start_scene_transition()
	else:
		printerr("SceneManager: Cannot call player.start_scene_transition()!")
		return # Abort if player state can't be set

	# --- Start Fade Out ---
	if fade_player and fade_player.has_animation("Fade_In"):
		fade_player.play("Fade_In")
		await fade_player.animation_finished
		# Perform actual scene change AFTER fade
		_perform_scene_change(target_scene_path, target_spawn_name)
	else:
		# No fade, change instantly
		_perform_scene_change(target_scene_path, target_spawn_name)


# Internal function to handle the actual loading and setup.
func _perform_scene_change(target_scene_path: String, target_spawn_name: String) -> void:
	print("SceneManager: Performing scene change...")
	emit_signal("scene_load_started", target_scene_path)

	# 1. Validate Player Reference
	if not is_instance_valid(player_node):
		# Try to find the player if reference is lost/not set
		player_node = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(player_node):
			printerr("SceneManager Error: Player node not found or invalid! Aborting scene change.")
			# Optionally fade back out or handle error
			if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
			return

	# 2. Free the old scene root (if it exists)
	if is_instance_valid(current_scene_root):
		print("  -> Freeing old scene:", current_scene_root.scene_file_path)
		if current_scene_root.get_parent() == scene_container_node:
			scene_container_node.remove_child(current_scene_root) # Remove first
		current_scene_root.queue_free() # Then free
		current_scene_root = null
	else:
		print("  -> No previous scene root found to free.")

	# 3. Load the new scene resource
	var next_scene_res = load(target_scene_path)
	if not next_scene_res is PackedScene:
		printerr("SceneManager Error: Failed to load scene or invalid resource type at path:", target_scene_path)
		# Handle error: maybe load a default scene or return player to previous? Difficult.
		# For now, just stop and potentially fade out.
		if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
		return

	# 4. Instantiate the new scene
	current_scene_root = next_scene_res.instantiate()
	if not is_instance_valid(current_scene_root):
		printerr("SceneManager Error: Failed to instantiate scene:", target_scene_path)
		current_scene_root = null # Ensure it's null if instantiation failed
		if fade_player and fade_player.has_animation("Fade_Out"): fade_player.play("Fade_Out")
		return

	print("  -> New scene instantiated:", current_scene_root.name)

	# 5. Add the new scene TO THE CONTAINER NODE
	scene_container_node.add_child(current_scene_root)
	print("  -> New scene added to container:", scene_container_node.name)

	# 6. Find spawn point & position player
	var spawn_point: Node2D = current_scene_root.find_child(target_spawn_name, true, false) as Node2D
	var target_position: Vector2
	if not is_instance_valid(spawn_point):
		printerr("SceneManager Warning: Target spawn '", target_spawn_name, "' not found. Using scene origin.")
		# Fallback: Place player at the origin of the new scene root (relative to container)
		target_position = current_scene_root.global_position
	else:
		print("  -> Spawn point '", spawn_point.name, "' found.")
		target_position = spawn_point.global_position # Get spawn's global position

	player_node.global_position = target_position
	print("  -> Player positioned at:", target_position)
	
	var original_player_layer = player_node.collision_layer
	var disabled_layer = 0 # Set to layer 0 (nothing) temporarily
	if original_player_layer != disabled_layer: # Avoid unnecessary changes
		print("  -> Disabling player trigger collision layer. Original:", original_player_layer) # Debug
		player_node.set_collision_layer(disabled_layer)

	# 7. Wait for grace period (0.1 seconds)
	print("SceneManager: Starting grace period wait...")
	await get_tree().create_timer(0.1).timeout
	print("SceneManager: Grace period finished.")

	# 8. Restore Player Collision Layer & End Transition State (Deferred)
	if is_instance_valid(player_node):
		# Restore deferred to ensure physics server updates after setting layer
		player_node.call_deferred("set_collision_layer", original_player_layer)
		print("SceneManager: Scheduling restore player collision layer to:", original_player_layer) # Debug

		# End transition state deferred
		if player_node.has_method("end_scene_transition"):
			player_node.call_deferred("end_scene_transition")
			print("SceneManager: Called player.end_scene_transition (deferred).")
		else:
			printerr("SceneManager: Cannot call player.end_scene_transition()!")
	else:
			print("SceneManager: Player node invalid before restoring state!")

	emit_signal("scene_load_finished", current_scene_root)
	print("SceneManager: Scene change complete.")

	# --- Start Fade Out ---
	if fade_player and fade_player.has_animation("Fade_Out"):
		fade_player.play("Fade_Out")
