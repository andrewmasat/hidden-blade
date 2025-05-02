# PauseMenu.gd
# Controls the pause overlay UI.
extends CanvasLayer

# Signal emitted when the resume button is pressed.
signal resume_game_requested

# Signal emitted when quitting to the main menu is requested.
signal quit_to_menu_requested

# --- Node References ---
@onready var resume_button: Button = $MenuPanel/MarginContainer/ButtonContainer/ResumeButton # Assumes unique names set in scene
@onready var settings_button: Button = $MenuPanel/MarginContainer/ButtonContainer/SettingsButton
@onready var save_button: Button = $MenuPanel/MarginContainer/ButtonContainer/SaveButton
@onready var quit_to_menu_button: Button = $MenuPanel/MarginContainer/ButtonContainer/QuitToMenuButton

# Path to the start screen scene (used when quitting)
const START_SCREEN_PATH = "res://scenes/StartScreen.tscn" # ADJUST PATH

func _ready() -> void:
	# Hide the pause menu initially
	hide_menu()

	# Connect button signals
	if is_instance_valid(resume_button):
		resume_button.pressed.connect(_on_resume_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(save_button):
		save_button.pressed.connect(_on_save_button_pressed)
	if is_instance_valid(quit_to_menu_button):
		quit_to_menu_button.pressed.connect(_on_quit_to_menu_button_pressed)


# Handle input specific to the pause menu (like pressing Esc again to resume)
func _unhandled_input(event: InputEvent) -> void:
	if not visible: return

	# Check event directly for matching actions, ensure it's the initial press
	var resume_pressed = event.is_action("ui_cancel", true) or event.is_action("toggle_pause", true)
	if resume_pressed and event.is_pressed() and not event.is_echo():
		print("PauseMenu: Resume action detected via input.") # Debug
		_on_resume_button_pressed() # Call the resume function
		get_viewport().set_input_as_handled() # Stop event propagation


# --- Menu Control ---

func show_menu() -> void:
	visible = true
	# Ensure buttons are interactive
	_set_buttons_disabled(false)
	# Optionally grab focus for potential keyboard nav later
	resume_button.grab_focus()
	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_menu() -> void:
	visible = false
	# Optionally hide mouse cursor IF resuming (handled by game manager)
	# Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Or HIDDEN


# --- Button Callbacks ---

func _on_resume_button_pressed() -> void:
	print("PauseMenu: Resume button pressed.") # Debug
	emit_signal("resume_game_requested") # Signal the game manager
	hide_menu() # Hide self immediately


func _on_settings_button_pressed() -> void:
	print("PauseMenu: Settings button pressed. (Not Implemented)")
	# TODO: Open a settings sub-panel or scene


func _on_save_button_pressed() -> void:
	print("PauseMenu: Save Game button pressed. (Not Implemented)")
	# TODO: Implement save game logic
	# 1. Pause might need to stay open while saving?
	# 2. Call a function in a SaveManager autoload?
	# 3. Provide feedback (Saving..., Saved!)


func _on_quit_to_menu_button_pressed() -> void:
	print("PauseMenu: Quit to Menu button pressed.")
	_set_buttons_disabled(true)
	get_tree().paused = false # Unpause before transition
	hide_menu()

	# Option A: Signal a GameManager/Main node
	# emit_signal("quit_to_start_menu_requested")

	# Option B: Call SceneManager directly IF appropriate
	if SceneManager and SceneManager.has_method("return_to_start_screen"):
		SceneManager.return_to_start_screen()
	else:
		# Fallback if SceneManager doesn't handle this specifically yet
		printerr("PauseMenu: SceneManager cannot handle return_to_start_screen. Using fallback change_scene.")
		# This fallback WILL likely cause the original issue if SceneManager isn't adapted
		get_tree().change_scene_to_file(START_SCREEN_PATH)


# Helper to enable/disable menu buttons (e.g., during transitions)
func _set_buttons_disabled(disabled: bool) -> void:
	if is_instance_valid(resume_button): resume_button.disabled = disabled
	if is_instance_valid(settings_button): settings_button.disabled = settings_button.disabled or disabled # Keep disabled if feature N/A
	if is_instance_valid(save_button): save_button.disabled = save_button.disabled or disabled # Keep disabled if feature N/A
	if is_instance_valid(quit_to_menu_button): quit_to_menu_button.disabled = disabled
