# SceneTransitionArea.gd
extends Area2D
class_name SceneTransitionArea

## Path to the scene file (.tscn) this area transitions TO.
@export_file("*.tscn") var target_scene_path: String = ""

## The unique name of the spawn point (Marker2D) in the target scene
## where the player should appear after transitioning.
@export var target_spawn_name: String = "DefaultSpawn"

# Connect this signal in the editor:
# Select SceneTransitionArea -> Node Dock -> Signals -> body_entered -> Connect...
func _on_body_entered(body: Node) -> void:
	# Check if the entering body is the player (using a group)
	if body.is_in_group("player"):
		if body.has_method("is_currently_transitioning") and body.is_currently_transitioning():
			print("TransitionArea: Ignoring entry, player is currently transitioning.") # Debug
			return # Ignore entry if player just spawned

		print("Player entered transition area. Target:", target_scene_path, "Spawn:", target_spawn_name) # Debug

		# Basic validation
		if target_scene_path.is_empty():
			printerr("SceneTransitionArea Error: Target scene path is not set!")
			return
		if target_spawn_name.is_empty():
			printerr("SceneTransitionArea Error: Target spawn name is not set!")
			# Could default to a standard name, but better to require it.
			return

		# --- Call the Scene Manager to handle the transition ---
		# Check if SceneManager autoload exists and has the function
		if SceneManager and SceneManager.has_method("change_scene"):
			# Prevent triggering multiple times if player lingers
			set_deferred("monitoring", false)
			# Use call_deferred to avoid issues during physics step
			SceneManager.call_deferred("change_scene", target_scene_path, target_spawn_name)
		else:
			printerr("SceneTransitionArea Error: SceneManager autoload or change_scene method not found!")
