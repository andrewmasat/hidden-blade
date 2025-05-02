# StartScreen.gd
extends Control

# --- Node References ---
# Use %UniqueName if you set unique names in the scene tree (recommended in Godot 4)
# Otherwise, use get_node() or @onready var with the path.
@onready var new_game_button: Button = $MenuOptionsContainer/NewGameButton
@onready var load_game_button: Button = $MenuOptionsContainer/LoadGameButton
@onready var settings_button: Button = $MenuOptionsContainer/SettingsButton
@onready var quit_button: Button = $MenuOptionsContainer/QuitButton

# --- Paths (Configure These!) ---
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
	else:
		printerr("StartScreen Error: LoadGameButton node not found!")

	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_pressed)
	else:
		printerr("StartScreen Error: SettingsButton node not found!")

	if is_instance_valid(quit_button):
		quit_button.pressed.connect(_on_quit_pressed)
	else:
		printerr("StartScreen Error: QuitButton node not found!")

	# Ensure cursor is visible on the start screen
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# --- Signal Callbacks ---

func _on_new_game_pressed() -> void:
	print("New Game button pressed.")
	# Disable buttons to prevent double clicks during transition
	_set_buttons_disabled(true)

	# Ensure SceneManager exists before calling
	if SceneManager:
		# Use the SceneManager to handle the transition
		# Pass the path to the main scene and the desired spawn point name
		SceneManager.change_scene(MAIN_GAME_SCENE_PATH, INITIAL_SPAWN_NAME)
		# Note: SceneManager's change_scene might need adjustments
		# to handle loading the main scene (which then loads level 1)
		# instead of directly loading a level scene.
	else:
		printerr("StartScreen Error: SceneManager autoload not found! Cannot start game.")
		# Re-enable buttons if scene manager failed
		_set_buttons_disabled(false)


func _on_load_game_pressed() -> void:
	print("Load Game button pressed. (Not Implemented)")
	# TODO: Implement save game loading logic
	# 1. Show a loading screen or file selector UI
	# 2. Load save data from file (e.g., player stats, position, current scene path, inventory)
	# 3. Call SceneManager.change_scene (or a dedicated load function)
	#    passing the loaded scene path and spawn name/position.
	# 4. After scene loads, apply loaded player stats, inventory etc.


func _on_settings_pressed() -> void:
	print("Settings button pressed. (Not Implemented)")
	# TODO: Implement settings menu
	# 1. Instantiate and show a separate Settings scene/panel (as child of this screen?).
	# 2. Or transition to a dedicated Settings scene using get_tree().change_scene_to_file(...)
	#    Remember to provide a way back to the StartScreen.


func _on_quit_pressed() -> void:
	print("Quit button pressed.")
	get_tree().quit() # Quit the application


# Helper to enable/disable all menu buttons
func _set_buttons_disabled(disabled: bool) -> void:
	if is_instance_valid(new_game_button): new_game_button.disabled = disabled
	if is_instance_valid(load_game_button): load_game_button.disabled = disabled # Keep disabled state if feature not ready
	if is_instance_valid(settings_button): settings_button.disabled = disabled # Keep disabled state if feature not ready
	# Optionally keep Quit enabled? Or disable during transition too?
	# if is_instance_valid(quit_button): quit_button.disabled = disabled
