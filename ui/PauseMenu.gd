# PauseMenu.gd
# Controls the pause overlay UI.
extends CanvasLayer

# Signal emitted when the resume button is pressed.
signal resume_game_requested
signal quit_to_menu_requested

# --- Node References ---
@onready var main_pause_buttons: Container = $MenuPanel/MarginContainer/MainPauseButtons
@onready var resume_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/ResumeButton
@onready var settings_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/SettingsButton
@onready var confirm_quit_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/ConfirmQuitButton

# Path to the start screen scene (used when quitting)
const START_SCREEN_PATH = "res://scenes/StartScreen.tscn" # ADJUST PATH

func _ready() -> void:
	# Hide the pause menu initially
	hide_menu()

	# Connect Main Pause Buttons
	if is_instance_valid(resume_button): resume_button.pressed.connect(_on_resume_button_pressed)
	if is_instance_valid(settings_button): settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(confirm_quit_button): confirm_quit_button.pressed.connect(_on_confirm_quit_pressed)


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
	# Default view: Show main buttons, hide confirmation
	if is_instance_valid(main_pause_buttons): main_pause_buttons.visible = true
	# Ensure buttons are enabled
	_set_buttons_disabled(false) # Disables ALL buttons initially
	# Grab focus for first button
	if is_instance_valid(resume_button): resume_button.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_menu() -> void:
	visible = false


# --- Button Callbacks ---

func _on_resume_button_pressed() -> void:
	print("PauseMenu: Resume button pressed.")
	emit_signal("resume_game_requested")
	hide_menu()


func _on_settings_button_pressed() -> void:
	print("PauseMenu: Settings button pressed. (Not Implemented)")


func _show_quit_confirmation() -> void:
	print("PauseMenu: Show quit confirmation requested.")
	if is_instance_valid(main_pause_buttons): main_pause_buttons.visible = false


func _on_confirm_quit_pressed() -> void:
	print("PauseMenu: Quit Only pressed.")
	get_tree().paused = false # Unpause game FIRST
	hide_menu() # Hide self
	# Signal Main/GameManager or call SceneManager directly
	if SceneManager and SceneManager.has_method("return_to_start_screen"):
		SceneManager.return_to_start_screen()
	else: # Fallback
		emit_signal("quit_to_menu_requested") # Less ideal, Main needs to handle unpausing etc.
		get_tree().change_scene_to_file(START_SCREEN_PATH)


func _on_cancel_quit_pressed() -> void:
	print("PauseMenu: Cancel Quit pressed.")
	# Switch back to main pause buttons
	if is_instance_valid(main_pause_buttons): main_pause_buttons.visible = true
	# Set focus back to a main button
	if is_instance_valid(resume_button): resume_button.grab_focus()


# --- Helper Functions ---

# Helper to enable/disable MAIN pause buttons
func _set_buttons_disabled(disabled: bool) -> void:
	if is_instance_valid(resume_button): resume_button.disabled = disabled
	var settings_na = not is_instance_valid(settings_button) or settings_button.disabled
	if is_instance_valid(settings_button): settings_button.disabled = settings_na or disabled
