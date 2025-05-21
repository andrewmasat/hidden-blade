# StartScreen.gd
extends Control

# --- Node References ---
# Use %UniqueName if you set unique names in the scene tree (recommended in Godot 4)
# Otherwise, use get_node() or @onready var with the path.
@onready var new_game_button: Button = $MenuOptionsContainer/NewGameButton
@onready var settings_button: Button = $MenuOptionsContainer/SettingsButton
@onready var quit_button: Button = $MenuOptionsContainer/QuitButton
@onready var ip_address_edit: LineEdit = $MenuOptionsContainer/HBoxContainer/IPAddressEdit
@onready var host_button: Button = $MenuOptionsContainer/HBoxContainer/HostButton
@onready var join_button: Button = $MenuOptionsContainer/HBoxContainer/JoinButton

const CHARACTER_CREATION_PATH = "res://scenes/CharacterCreation.tscn"

# Path to your main gameplay scene that loads levels etc.
const MAIN_GAME_SCENE_PATH = "res://scenes/Main.tscn"
# Name of the Marker2D within the *first level* loaded by Main.tscn
const INITIAL_SPAWN_NAME = "InitialSpawn"

func _on_host_button_pressed():
	if NetworkManager.host_game():
		# Successfully hosted, now transition to the main game scene
		# The host also needs to spawn their player character.
		# This scene change will trigger Main.gd _ready which can handle spawning.
		#_set_buttons_disabled(true)
		SceneManager.change_scene(MAIN_GAME_SCENE_PATH, INITIAL_SPAWN_NAME)
	else:
		# Show error: Failed to host
		pass

func _on_join_button_pressed():
	var ip = ip_address_edit.text
	if ip.is_empty(): ip = "127.0.0.1" # Default to localhost
	if NetworkManager.join_game(ip):
		# Attempting to join. Wait for connection_succeeded signal from NetworkManager
		# Disable buttons while attempting to connect
		#_set_buttons_disabled(true)
		# SceneManager.change_scene could be called after connection_succeeded
		# Or we can change to a "Connecting..." screen first
		pass
	else:
		# Show error: Failed to initiate join
		#_set_buttons_disabled(false)
		pass


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Connect button signals to functions
	if is_instance_valid(new_game_button):
		new_game_button.pressed.connect(_on_new_game_pressed)
	else:
		printerr("StartScreen Error: NewGameButton node not found!")

	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_pressed)
	else:
		printerr("StartScreen Error: SettingsButton node not found!")

	if is_instance_valid(quit_button):
		quit_button.pressed.connect(_on_quit_pressed)
	else:
		printerr("StartScreen Error: QuitButton node not found!")

	if NetworkManager:
		NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
		NetworkManager.connection_failed.connect(_on_connection_failed_ui_reset)
	else:
		printerr("StartScreen Error: NetworkManager not found!")

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
func _on_connection_succeeded():
	print("StartScreen: Connection succeeded! Changing to Main scene.")
	#_set_buttons_disabled(true)
	SceneManager.change_scene(MAIN_GAME_SCENE_PATH, INITIAL_SPAWN_NAME)


func _on_connection_failed_ui_reset():
	print("StartScreen: Connection failed. Re-enabling UI.")
	#_set_buttons_disabled(false) # Re-enable buttons


func _on_new_game_pressed() -> void:
	print("StartScreen: New Game pressed, requesting scene change to Character Creation.")
	if SceneManager:
		# Use "" or a specific spawn name if Character Creation needs one (unlikely)
		SceneManager.change_scene(CHARACTER_CREATION_PATH, "")
	else:
		printerr("StartScreen Error: SceneManager not found!")


func _on_settings_pressed() -> void:
	print("Settings button pressed. (Not Implemented)")
	# TODO: Implement settings menu
	# 1. Instantiate and show a separate Settings scene/panel (as child of this screen?).
	# 2. Or transition to a dedicated Settings scene using get_tree().change_scene_to_file(...)
	#    Remember to provide a way back to the StartScreen.


func _on_quit_pressed() -> void:
	print("Quit button pressed.")
	get_tree().quit() # Quit the application
