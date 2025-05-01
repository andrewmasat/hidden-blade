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

	# --- Start Fade Out (if available) ---
	if fade_player and fade_player.has_animation("Fade_In"):
		fade_player.play("Fade_In")
		await fade_player.animation_finished # Wait for fade to complete
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

	# 5. Add the new scene to the tree (as a child of the main root, e.g., /root/Main)
	scene_container_node.add_child(current_scene_root)
	print("  -> New scene added to container:", scene_container_node.name)

	# 7. Find the spawn point in the NEW scene
	var spawn_point: Node2D = current_scene_root.find_child(target_spawn_name, true, false) as Node2D
	var target_position: Vector2

	if not is_instance_valid(spawn_point):
		printerr("SceneManager Warning: Target spawn '", target_spawn_name, "' not found. Using scene origin.")
		# Fallback: Place player at the origin of the new scene root (relative to container)
		target_position = current_scene_root.global_position
	else:
		print("  -> Spawn point '", spawn_point.name, "' found.")
		target_position = spawn_point.global_position # Get spawn's global position

	# 8. Position the player (Player is likely still child of Main, not Environments)
	player_node.call("set_transitioning_state", true) # Tell player it's transitioning
	player_node.global_position = target_position
	print("  -> Player positioned at:", target_position)

	# 9. Wait briefly before clearing transition state
	await get_tree().create_timer(0.1).timeout # Wait 0.1 sec
	# Check if player node still valid before calling method
	if is_instance_valid(player_node):
		player_node.call("set_transitioning_state", false) # Clear flag after delay

	emit_signal("scene_load_finished", current_scene_root)
	print("SceneManager: Scene change complete.")

	# --- Start Fade Out ---
	if fade_player and fade_player.has_animation("Fade_Out"):
		fade_player.play("Fade_Out")
