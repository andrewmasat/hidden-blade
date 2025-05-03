# SaveManager.gd - Autoload Singleton
extends Node

const SAVE_DIR = "user://saves/"
const SAVE_FILE_NAME = "savegame.json" # Or use ConfigFile: "savegame.cfg"

# Signal emitted after a save operation completes
signal save_completed(success: bool)
# Signal emitted after data is loaded (before applying) - might not be needed
# signal load_data_read(data: Dictionary)

func _ready() -> void:
	# Ensure save directory exists
	DirAccess.make_dir_absolute(SAVE_DIR)


# --- Saving ---

func save_game() -> void:
	print("SaveManager: Starting save game...")
	# 1. Ensure necessary components exist
	if not is_instance_valid(SceneManager) or not is_instance_valid(Inventory) or not is_instance_valid(SceneManager.player_node):
		printerr("SaveManager Error: Required nodes (SceneManager, Inventory, Player) not found/valid.")
		emit_signal("save_completed", false)
		return

	# 2. Clear cursor item before saving inventory
	Inventory.clear_cursor_item()

	# 3. Gather data
	var player_data = SceneManager.player_node.get_save_data()
	var inventory_data = Inventory.get_save_data()
	# Add other data sources here (e.g., quests, world state)
	# var quest_data = QuestManager.get_save_data()

	# 4. Combine into one dictionary
	var combined_data = {
		"player": player_data,
		"inventory": inventory_data,
		"scene": { # Save scene info separately from player now
			"current_level_path": SceneManager.current_level_root.scene_file_path if is_instance_valid(SceneManager.current_level_root) else "",
			"main_scene_path": SceneManager.main_scene_root.scene_file_path if is_instance_valid(SceneManager.main_scene_root) else SceneManager.MAIN_SCENE_PATH # Save path to main structure
		}
		# "quests": quest_data,
		# Add version number? game_version": "1.0"
	}

	# 5. Save to file (using JSON)
	var save_path = SAVE_DIR.path_join(SAVE_FILE_NAME)
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if FileAccess.get_open_error() != OK:
		printerr("SaveManager Error: Failed to open save file for writing at path: ", save_path, " Error code: ", FileAccess.get_open_error())
		emit_signal("save_completed", false)
		return

	# Convert Dictionary to JSON string
	var json_string = JSON.stringify(combined_data, "\t") # Use tab for indentation (optional)
	file.store_string(json_string)
	file.close() # Close file (implicitly stores/flushes)

	print("SaveManager: Game saved successfully to ", save_path)
	emit_signal("save_completed", true)


# --- Loading ---

# Checks if a save file exists
func has_save_file() -> bool:
	var save_path = SAVE_DIR.path_join(SAVE_FILE_NAME)
	return FileAccess.file_exists(save_path)


# Loads data from file but doesn't apply it yet. Returns loaded data or null.
func read_load_data():
	var save_path = SAVE_DIR.path_join(SAVE_FILE_NAME)
	if not FileAccess.file_exists(save_path):
		printerr("SaveManager: No save file found at: ", save_path)
		return null

	var file = FileAccess.open(save_path, FileAccess.READ)
	if FileAccess.get_open_error() != OK:
		printerr("SaveManager Error: Failed to open save file for reading at path: ", save_path)
		return null

	var json_string = file.get_as_text()
	file.close()

	# Parse JSON string
	var parse_result = JSON.parse_string(json_string)
	# Check type AFTER parsing, before returning
	if parse_result is Dictionary:
		print("SaveManager: Save data read and parsed successfully.")
		return parse_result
	else:
		printerr("SaveManager Error: Failed to parse JSON or result is not a Dictionary.")
		return null


# Main function to trigger loading and applying data
func load_game() -> void:
	print("SaveManager: Starting load game...")

	# 1. Read data from file
	var loaded_data = read_load_data()
	if loaded_data == null:
		printerr("SaveManager: Load failed - could not read data.")
		# TODO: Show error message to player?
		return

	# 2. Extract necessary info (scene to load)
	var scene_data = loaded_data.get("scene", {})
	# We need to load the MAIN scene structure first
	var main_scene_to_load = scene_data.get("main_scene_path", SceneManager.MAIN_SCENE_PATH)
	# Get the specific level path and spawn position from player data
	var player_data = loaded_data.get("player", {})
	var target_level_path = player_data.get("scene_path", "") # Scene player was IN
	var target_pos = Vector2(player_data.get("position_x", 0), player_data.get("position_y", 0))

	if main_scene_to_load.is_empty():
		printerr("SaveManager Error: Save data missing main scene path!")
		return
	if target_level_path.is_empty():
		printerr("SaveManager Error: Save data missing target level path for player!")
		# Maybe default to initial spawn? Risky.
		return

	print("SaveManager: Requesting scene load - Main='", main_scene_to_load, "', Level='", target_level_path, "', Pos=", target_pos)

	# 3. Use SceneManager to load the MAIN scene first
	#    We don't use a spawn point name, we'll set position manually after load.
	#    We might need a specific SceneManager function for loading saves.
	if SceneManager and SceneManager.has_method("load_saved_game_scene"):
		SceneManager.load_saved_game_scene(main_scene_to_load, target_level_path, target_pos, loaded_data)
	else:
		printerr("SaveManager Error: SceneManager missing load_saved_game_scene method!")


# Register as Autoload (`SaveManager.gd`, Name: `SaveManager`)
