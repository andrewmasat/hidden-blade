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

	# 1. Find an empty save slot
	var save_slot = SaveManager.find_next_empty_slot()
	if save_slot == -1:
		# TODO: Handle "No empty save slots" error - show message? Allow overwrite?
		printerr("CharacterCreation Error: No empty save slots available!")
		# Re-enable UI
		confirm_button.disabled = false; back_button.disabled = false; name_edit.editable = true
		return

	# 2. Create INITIAL save data (minimal needed to start)
	#    Player position will be set by SceneManager using InitialSpawn.
	var initial_player_data = {
		"character_name": player_name,
		"scene_path": INITIAL_LEVEL_SCENE_PATH,
		"position_x": 0.0,
		"position_y": 0.0,
		"current_health": 100.0,
		"current_dashes": 3,
		"last_direction_x": 0.0,
		"last_direction_y": 1.0
	}

	var initial_hotbar = []
	initial_hotbar.resize(Inventory.HOTBAR_SIZE)
	initial_hotbar.fill(null)

	var initial_main_inv = []
	initial_main_inv.resize(Inventory.INVENTORY_SIZE)
	initial_main_inv.fill(null)

	var initial_inventory_data = {
		"hotbar": initial_hotbar, # Use the created array
		"main": initial_main_inv, # Use the created array
		"selected_index": 0
	}
	var initial_scene_data = {
		"current_level_path": INITIAL_LEVEL_SCENE_PATH,
		"main_scene_path": SceneManager.MAIN_SCENE_PATH
	}
	var initial_metadata = {
		"save_time_unix": Time.get_unix_time_from_system(),
		"character_name": player_name,
		"current_level_name": INITIAL_LEVEL_SCENE_PATH.get_file().get_basename(),
		"version": "1.0"
	}
	var initial_save_data = {
		"metadata": initial_metadata,
		"player": initial_player_data,
		"inventory": initial_inventory_data,
		"scene": initial_scene_data
	}

	# 3. Save this initial data to the chosen slot
	var save_path = SaveManager.get_save_file_path(save_slot)
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if FileAccess.get_open_error() == OK:
		file.store_string(JSON.stringify(initial_save_data, "\t"))
		file.close()
		print("Initial save data created for slot", save_slot)

		# 4. NOW, load the game using this new save slot
		#    This ensures the game starts in a state consistent with saving/loading
		SaveManager.load_game(save_slot)
		# load_game will call SceneManager to load Main.tscn, then the initial level,
		# apply the initial data, and set player position.
	else:
		printerr("CharacterCreation Error: Failed to create initial save file for slot", save_slot)
		# Re-enable UI
		confirm_button.disabled = false; back_button.disabled = false; name_edit.editable = true


func _on_back_pressed() -> void:
	print("CharacterCreation: Back button pressed, requesting scene change to Start Screen.")
	if SceneManager:
		SceneManager.change_scene(START_SCREEN_PATH, "") # Use SceneManager
	else:
		printerr("CharacterCreation Error: SceneManager not found!")
		# Fallback? get_tree().change_scene_to_file(START_SCREEN_PATH)
