# SceneTransitionArea.gd
extends Area2D
class_name SceneTransitionArea

## Path to the scene file (.tscn) this area transitions TO.
@export_file("*.tscn") var target_scene_path: String = ""

## The unique name of the spawn point (Marker2D) in the target scene
## where the player should appear after transitioning.
@export var target_spawn_name: String = "DefaultSpawn"

func _ready():
	# Ensure monitoring is enabled when the scene loads/reloads
	monitoring = true

func _on_body_entered(body: Node) -> void:
	# Check if the entering body is the player (using a group)
	if body.is_in_group("player"):
		# Check if the player is currently immune due to just transitioning
		if body.has_method("is_currently_transitioning") and body.is_currently_transitioning():
			print("TransitionArea: Ignoring entry, player is currently transitioning.") # Debug
			return # Ignore entry

		print("Player entered transition area. Target:", target_scene_path, "Spawn:", target_spawn_name)
		# Validate paths
		if target_scene_path.is_empty() or target_spawn_name.is_empty():
			printerr("SceneTransitionArea Error: Target scene/spawn not set!")
			return

		# Trigger transition via SceneManager
		if SceneManager and SceneManager.has_method("change_scene"):
			# Disable self deferred to prevent immediate re-trigger and physics errors
			set_deferred("monitoring", false)
			# Call SceneManager deferred
			SceneManager.call_deferred("change_scene", target_scene_path, target_spawn_name)
		else:
			printerr("SceneTransitionArea Error: SceneManager/change_scene not found!")
