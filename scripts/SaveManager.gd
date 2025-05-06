# SaveManager.gd - Autoload Singleton
extends Node

const SAVE_DIR = "user://saves/"
const SAVE_FILE_BASE_NAME = "savegame_"
const SAVE_FILE_EXTENSION = ".json"
const MAX_SAVE_SLOTS = 5

# Signal emitted after a save operation completes
signal save_completed(success: bool)
# Signal emitted after data is loaded (before applying) - might not be needed
# signal load_data_read(data: Dictionary)

var current_slot_index: int = -1

func _ready() -> void:
	# Ensure save directory exists
	DirAccess.make_dir_absolute(SAVE_DIR)

# --- Get Save File Path ---
func get_save_file_path(slot_index: int) -> String:
	# Ensure slot index is valid (adjust range if 0-based or 1-based)
	if slot_index < 0 or slot_index >= MAX_SAVE_SLOTS:
		printerr("SaveManager: Invalid slot index requested:", slot_index)
		return ""
	return SAVE_DIR.path_join(SAVE_FILE_BASE_NAME + str(slot_index) + SAVE_FILE_EXTENSION)

# --- Saving ---
func save_game(slot_index_to_save: int = -1) -> void:
	# If no slot index provided, try using the currently loaded one
	if slot_index_to_save == -1:
		slot_index_to_save = current_slot_index

	# Check if we have a valid slot index now
	if slot_index_to_save == -1:
		printerr("SaveManager Error: Cannot save - No current slot loaded and no slot index provided.")
		# Optionally trigger a "Save As" flow here?
		emit_signal("save_completed", false, -1)
		return

	print("SaveManager: Starting save game to slot", slot_index_to_save)
	var save_path = get_save_file_path(slot_index_to_save)
	if save_path.is_empty():
		emit_signal("save_completed", false, slot_index_to_save)
		return

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
	var current_level_path = SceneManager.current_level_root.scene_file_path if is_instance_valid(SceneManager.current_level_root) else ""
	var main_scene_path = SceneManager.main_scene_root.scene_file_path if is_instance_valid(SceneManager.main_scene_root) else SceneManager.MAIN_SCENE_PATH

	# --- Create Metadata ---
	var metadata = {
		"save_time_unix": Time.get_unix_time_from_system(), # Timestamp
		"character_name": player_data.get("character_name", "Ninja"), # Need to add character_name to player save data
		"current_level_name": current_level_path.get_file().get_basename(), # Get e.g., "City" from path
		"version": "1.0" # Game version for compatibility later
		# Add playtime, thumbnail path etc. later
	}

	# 4. Combine into one dictionary
	var combined_data = {
		"metadata": metadata,
		"player": player_data,
		"inventory": inventory_data,
		"scene": {
			"current_level_path": current_level_path,
			"main_scene_path": main_scene_path
		}
	}

	# 5. Save to file (using JSON)
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if FileAccess.get_open_error() != OK:
		printerr("SaveManager Error: Failed to open save file for writing at path: ", save_path, " Error code: ", FileAccess.get_open_error())
		emit_signal("save_completed", false)
		return

	# Convert Dictionary to JSON string
	var json_string = JSON.stringify(combined_data, "\t")
	file.store_string(json_string)
	file.close()

	print("SaveManager: Game saved successfully to slot", slot_index_to_save)
	emit_signal("save_completed", true, slot_index_to_save)


# --- Loading ---
func get_all_save_metadata() -> Array[Dictionary]:
	var all_metadata: Array[Dictionary] = []
	for i in range(MAX_SAVE_SLOTS):
		var metadata = read_save_metadata(i)
		if metadata != null:
			# We already checked metadata is Dictionary in read_save_metadata
			metadata["slot_index"] = i # Add slot index for identification
			all_metadata.append(metadata) # Append Dictionary to Array[Dictionary]

	# Optional: Sort by save_time_unix descending
	all_metadata.sort_custom(func(a, b): return a.get("save_time_unix", 0) > b.get("save_time_unix", 0)) # Added .get() for safety
	return all_metadata

func read_save_metadata(slot_index: int):
	var save_path = get_save_file_path(slot_index)
	if not FileAccess.file_exists(save_path):
		return null # Slot is empty or file missing

	var file = FileAccess.open(save_path, FileAccess.READ)
	if FileAccess.get_open_error() != OK:
		printerr("SaveManager Meta Read Error: Failed to open file for slot", slot_index)
		return null

	# Optimization: Read only enough to parse metadata? JSON requires full parse usually.
	# If using ConfigFile, could read only specific section.
	var json_string = file.get_as_text()
	file.close()

	var parse_result = JSON.parse_string(json_string)
	if parse_result is Dictionary and parse_result.has("metadata"):
		return parse_result["metadata"]
	else:
		printerr("SaveManager Meta Read Error: Failed parse or no 'metadata' key in slot", slot_index)
		return null


# Loads data from file but doesn't apply it yet. Returns loaded data or null.
func read_load_data(slot_index: int):
	var save_path = get_save_file_path(slot_index)
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
func load_game(slot_index: int) -> void:
	print("SaveManager: Starting load game from slot", slot_index)
	current_slot_index = -1

	# 1. Read data from file
	var loaded_data = read_load_data(slot_index)
	if loaded_data == null:
		printerr("SaveManager: Load failed - could not read data for slot", slot_index)
		return

	# 2. Extract necessary info (scene to load)
	current_slot_index = slot_index
	var scene_data = loaded_data.get("scene", {})
	var player_data = loaded_data.get("player", {})
	var main_scene_to_load = scene_data.get("main_scene_path", SceneManager.MAIN_SCENE_PATH)
	var target_level_path = player_data.get("scene_path", "")
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

func find_next_empty_slot() -> int:
	for i in range(MAX_SAVE_SLOTS):
		if not FileAccess.file_exists(get_save_file_path(i)):
			return i
	return -1 # No empty slots found

func delete_save_slot(slot_index: int) -> bool:
	var save_path = get_save_file_path(slot_index)
	if FileAccess.file_exists(save_path):
		var err = DirAccess.remove_absolute(save_path)
		if err == OK:
			print("SaveManager: Deleted save slot", slot_index)
			return true
		else:
			printerr("SaveManager Error: Failed to delete save file for slot", slot_index, " Error:", err)
			return false
	else:
		print("SaveManager: Save slot", slot_index, "does not exist, cannot delete.")
		return false # File didn't exist anyway
