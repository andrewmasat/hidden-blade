# StartScreen.gd
extends Control

# --- Node References ---
# Use %UniqueName if you set unique names in the scene tree (recommended in Godot 4)
# Otherwise, use get_node() or @onready var with the path.
@onready var new_game_button: Button = $MenuOptionsContainer/NewGameButton
@onready var load_game_button: Button = $MenuOptionsContainer/LoadGameButton
@onready var settings_button: Button = $MenuOptionsContainer/SettingsButton
@onready var quit_button: Button = $MenuOptionsContainer/QuitButton

const CHARACTER_CREATION_PATH = "res://scenes/CharacterCreation.tscn"
const LOAD_GAME_SCREEN_PATH = "res://scenes/LoadGameScreen.tscn"

# Path to your main gameplay scene that loads levels etc.
const MAIN_GAME_SCENE_PATH = "res://scenes/Main.tscn"
# Name of the Marker2D within the *first level* loaded by Main.tscn
const INITIAL_SPAWN_NAME = "InitialSpawn"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Connect button signals to functions
	if is_instance_valid(new_game_button):
		new_game_button.pressed.connect(_on_new_game_pressed)
	else:
		printerr("StartScreen Error: NewGameButton node not found!")

	if is_instance_valid(load_game_button):
		load_game_button.pressed.connect(_on_load_game_pressed)
		# Disable if no save file exists initially
		if SaveManager:
			load_game_button.disabled = SaveManager.get_all_save_metadata().is_empty()
		else:
			load_game_button.disabled = true # Disable if manager missing

	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_pressed)
	else:
		printerr("StartScreen Error: SettingsButton node not found!")

	if is_instance_valid(quit_button):
		quit_button.pressed.connect(_on_quit_pressed)
	else:
		printerr("StartScreen Error: QuitButton node not found!")

	# --- Tell SceneManager this IS the current scene ---
	if SceneManager:
		print("StartScreen: Setting self as SceneManager.current_scene_root") # DEBUG
		SceneManager.current_scene_root = self
		# Also ensure main scene refs are null initially in manager
		SceneManager.main_scene_root = null
		SceneManager.current_level_root = null
		SceneManager.player_node = null
		SceneManager.scene_container_node = null
	else:
		printerr("StartScreen Error: SceneManager not found!")

	# Ensure cursor is visible on the start screen
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# --- Signal Callbacks ---

func _on_new_game_pressed() -> void:
	print("StartScreen: New Game pressed, changing to Character Creation.")
	get_tree().change_scene_to_file(CHARACTER_CREATION_PATH)


func _on_load_game_pressed() -> void:
	print("StartScreen: Load Game pressed, changing to Load Screen.")
	get_tree().change_scene_to_file(LOAD_GAME_SCREEN_PATH)


func _on_settings_pressed() -> void:
	print("Settings button pressed. (Not Implemented)")
	# TODO: Implement settings menu
	# 1. Instantiate and show a separate Settings scene/panel (as child of this screen?).
	# 2. Or transition to a dedicated Settings scene using get_tree().change_scene_to_file(...)
	#    Remember to provide a way back to the StartScreen.


func _on_quit_pressed() -> void:
	print("Quit button pressed.")
	get_tree().quit() # Quit the application
