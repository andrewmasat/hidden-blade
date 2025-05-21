# CharacterCreation.gd
extends Control

@onready var name_edit: LineEdit = $CreateContainer/NameEdit # Adjust path
@onready var confirm_button: Button = $CreateContainer/ConfirmButton
@onready var back_button: Button = $BackButton

const START_SCREEN_PATH = "res://scenes/StartScreen.tscn" # Path back to start
const INITIAL_LEVEL_SCENE_PATH = "res://scenes/City.tscn"

func _ready() -> void:
	# --- Tell SceneManager this IS the current scene ---
	if SceneManager:
		print("CharacterCreation: Setting self as SceneManager.current_scene_root") # DEBUG
		SceneManager.current_scene_root = self
		# Clear other refs
		SceneManager.main_scene_root = null
		SceneManager.current_level_root = null
		SceneManager.player_node = null
		SceneManager.scene_container_node = null
	else:
		printerr("CharacterCreation Error: SceneManager not found!")
	# --------------------------------------------------

	if is_instance_valid(confirm_button): confirm_button.pressed.connect(_on_confirm_pressed)
	if is_instance_valid(back_button): back_button.pressed.connect(_on_back_pressed)
	if is_instance_valid(name_edit): name_edit.grab_focus()


func _on_confirm_pressed() -> void:
	var char_name = name_edit.text.strip_edges() # Remove leading/trailing whitespace

	if char_name.is_empty():
		# TODO: Show error message to user (e.g., popup or label)
		print("CharacterCreation Error: Name cannot be empty.")
		return
	# Optional: Add more validation (length, allowed characters)

	print("Character name confirmed:", char_name)
	_start_new_game(char_name)


func _start_new_game(player_name: String) -> void:
	# Disable UI
	confirm_button.disabled = true
	back_button.disabled = true
	name_edit.editable = false

	# For now, let's assume player name is handled by server on first true connection.
	if SceneManager:
		# "InitialSpawn" is still relevant for where the player appears
		# when Main.tscn and its first level are loaded.
		SceneManager.change_scene(SceneManager.MAIN_SCENE_PATH, "InitialSpawn")
		# Store name for server to pick up?
		# TempNameHolder.character_name = player_name # Example with another Autoload
	else:
		printerr("CharacterCreation Error: SceneManager not found!")
		# Re-enable UI
		confirm_button.disabled = false; back_button.disabled = false; name_edit.editable = true


func _on_back_pressed() -> void:
	print("CharacterCreation: Back button pressed, requesting scene change to Start Screen.")
	if SceneManager:
		SceneManager.change_scene(START_SCREEN_PATH, "") # Use SceneManager
	else:
		printerr("CharacterCreation Error: SceneManager not found!")
		# Fallback? get_tree().change_scene_to_file(START_SCREEN_PATH)
