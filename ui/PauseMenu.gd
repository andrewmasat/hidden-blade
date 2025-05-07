# PauseMenu.gd
# Controls the pause overlay UI.
extends CanvasLayer

# Signal emitted when the resume button is pressed.
signal resume_game_requested
signal quit_to_menu_requested

# --- Node References ---
@onready var main_pause_buttons: Container = $MenuPanel/MarginContainer/MainPauseButtons
@onready var quit_confirm_container: Container = $MenuPanel/MarginContainer/QuitConfirmContainer
@onready var resume_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/ResumeButton
@onready var settings_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/SettingsButton
@onready var save_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/SettingsButton
@onready var quit_to_menu_button: Button = $MenuPanel/MarginContainer/MainPauseButtons/QuitToMenuButton

@onready var confirm_label: Label = $MenuPanel/MarginContainer/QuitConfirmContainer/ConfirmLabel
@onready var save_and_quit_button: Button = $MenuPanel/MarginContainer/QuitConfirmContainer/SaveAndQuitButton
@onready var quit_only_button: Button = $MenuPanel/MarginContainer/QuitConfirmContainer/QuitOnlyButton
@onready var cancel_quit_button: Button = $MenuPanel/MarginContainer/QuitConfirmContainer/CancelQuitButton

# Path to the start screen scene (used when quitting)
const START_SCREEN_PATH = "res://scenes/StartScreen.tscn" # ADJUST PATH

var is_saving_and_quitting = false

func _ready() -> void:
	# Hide the pause menu initially
	hide_menu()

	# Connect Main Pause Buttons
	if is_instance_valid(resume_button): resume_button.pressed.connect(_on_resume_button_pressed)
	if is_instance_valid(settings_button): settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(save_button): save_button.pressed.connect(_on_save_button_pressed)
	if is_instance_valid(quit_to_menu_button): quit_to_menu_button.pressed.connect(_show_quit_confirmation) # Changed target

	# Connect Confirmation Buttons
	if is_instance_valid(save_and_quit_button): save_and_quit_button.pressed.connect(_on_save_and_quit_pressed)
	if is_instance_valid(quit_only_button): quit_only_button.pressed.connect(_on_quit_only_pressed)
	if is_instance_valid(cancel_quit_button): cancel_quit_button.pressed.connect(_on_cancel_quit_pressed)

	# Connect SaveManager signal if needed for Save & Quit feedback
	if SaveManager and SaveManager.has_signal("save_completed"):
		# Check connection using the method directly
		if not SaveManager.is_connected("save_completed", _on_save_completed): # Use method name directly
			SaveManager.save_completed.connect(_on_save_completed) # Connect using method name directly
	# else: SaveManager or signal doesn't exist


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
	if is_instance_valid(quit_confirm_container): quit_confirm_container.visible = false
	# Ensure buttons are enabled
	_set_buttons_disabled(false) # Disables ALL buttons initially
	is_saving_and_quitting = false # Reset flag
	# Grab focus for first button
	if is_instance_valid(resume_button): resume_button.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_menu() -> void:
	visible = false
	is_saving_and_quitting = false


# --- Button Callbacks ---

func _on_resume_button_pressed() -> void:
	if is_saving_and_quitting: return
	print("PauseMenu: Resume button pressed.")
	emit_signal("resume_game_requested")
	hide_menu()


func _on_settings_button_pressed() -> void:
	if is_saving_and_quitting: return
	print("PauseMenu: Settings button pressed. (Not Implemented)")


func _on_save_button_pressed() -> void:
	if not SaveManager: # Check SaveManager exists
		printerr("PauseMenu: SaveManager not found!")
		return

	if SaveManager:
		print("PauseMenu: Requesting save (using current slot)...")
		save_button.disabled = true # Disable only save button
		# Consider disabling other buttons too? Maybe not needed for simple save.
		SaveManager.save_game() # Uses current slot implicitly
		# Feedback happens via _on_save_completed
	else:
		printerr("PauseMenu: SaveManager not found!")


func _show_quit_confirmation() -> void:
	print("PauseMenu: Show quit confirmation requested.")
	if is_instance_valid(main_pause_buttons): main_pause_buttons.visible = false
	if is_instance_valid(quit_confirm_container): quit_confirm_container.visible = true
	# Optionally set focus to one of the confirmation buttons, e.g., Cancel
	if is_instance_valid(cancel_quit_button): cancel_quit_button.grab_focus()


func _on_save_and_quit_pressed() -> void:
	if not SaveManager:
		printerr("PauseMenu: SaveManager not found! Cannot Save & Quit.")
		return

	print("PauseMenu: Save & Quit pressed. Initiating save...")
	is_saving_and_quitting = true # Set flag
	_set_confirmation_buttons_disabled(true) # Disable confirmation buttons
	# Optionally update label: confirm_label.text = "Saving..."

	SaveManager.save_game() # Trigger save
	# The actual quit happens in _on_save_completed ONLY IF successful


func _on_quit_only_pressed() -> void:
	print("PauseMenu: Quit Only pressed.")
	_set_confirmation_buttons_disabled(true) # Disable buttons
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
	if is_instance_valid(quit_confirm_container): quit_confirm_container.visible = false
	# Reset flag
	is_saving_and_quitting = false
	# Set focus back to a main button
	if is_instance_valid(resume_button): resume_button.grab_focus()

# --- SaveManager Signal Callback ---

func _on_save_completed(success: bool, slot_index: int):
	# This handles feedback for BOTH normal save and save-and-quit
	print("PauseMenu: Save completed signal received. Success:", success, "Slot:", slot_index)

	if is_saving_and_quitting:
		if success:
			# Save successful, now proceed with quitting
			print("PauseMenu: Save successful, proceeding with Quit.")
			get_tree().paused = false # Unpause game
			hide_menu() # Hide self
			# Signal or call SceneManager
			if SceneManager and SceneManager.has_method("return_to_start_screen"):
				SceneManager.return_to_start_screen()
			else: # Fallback
				emit_signal("quit_to_menu_requested")
				get_tree().change_scene_to_file(START_SCREEN_PATH)
		else:
			# Save failed during Save & Quit
			printerr("PauseMenu: Save FAILED during Save & Quit!")
			# TODO: Show error message to user on the confirmation panel
			if is_instance_valid(confirm_label): confirm_label.text = "Save Failed! Try again?"
			# Re-enable confirmation buttons ONLY
			_set_confirmation_buttons_disabled(false)
			is_saving_and_quitting = false # Reset flag as process aborted
	else:
		# Normal save completed (not quitting)
		if is_instance_valid(save_button):
			save_button.disabled = false # Re-enable normal save button
		if success:
			# TODO: Show temporary "Game Saved!" message
			pass
		else:
			# TODO: Show "Save Failed!" message
			pass


# --- Helper Functions ---

# Helper to enable/disable MAIN pause buttons
func _set_buttons_disabled(disabled: bool) -> void:
	if is_instance_valid(resume_button): resume_button.disabled = disabled
	# Keep settings/save disabled if they are not implemented or based on context
	var settings_na = not is_instance_valid(settings_button) or settings_button.disabled # Check original disabled state if needed
	var save_na = not is_instance_valid(save_button) or save_button.disabled
	if is_instance_valid(settings_button): settings_button.disabled = settings_na or disabled
	if is_instance_valid(save_button): save_button.disabled = save_na or disabled
	if is_instance_valid(quit_to_menu_button): quit_to_menu_button.disabled = disabled

# Helper to enable/disable CONFIRMATION buttons
func _set_confirmation_buttons_disabled(disabled: bool) -> void:
	if is_instance_valid(save_and_quit_button): save_and_quit_button.disabled = disabled
	if is_instance_valid(quit_only_button): quit_only_button.disabled = disabled
	if is_instance_valid(cancel_quit_button): cancel_quit_button.disabled = disabled
