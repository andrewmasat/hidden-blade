# LoadGameScreen.gd
extends Control

const SaveSlotEntryScene = preload("res://ui/save_load/SaveSlotEntry.tscn")
const START_SCREEN_PATH = "res://scenes/StartScreen.tscn"

@onready var save_list_container = $SaveListContainer # Adjust path
@onready var back_button = $BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	populate_save_list()


func populate_save_list() -> void:
	# Clear existing entries
	for child in save_list_container.get_children():
		child.queue_free()

	# Get metadata for all saves
	var all_metadata = SaveManager.get_all_save_metadata()

	if all_metadata.is_empty():
		# Display "No saves found" message
		var label = Label.new()
		label.text = "No Save Files Found"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_list_container.add_child(label)
	else:
		# Create an entry for each save
		for metadata in all_metadata:
			var entry = SaveSlotEntryScene.instantiate() as SaveSlotEntry # Cast
			if entry:
				# 1. Add to tree FIRST
				save_list_container.add_child(entry)
				# 2. THEN call set_data - NOW @onready vars will be valid
				entry.set_data(metadata)
				# 3. Connect signals
				entry.load_requested.connect(_on_slot_load_requested)
				entry.delete_requested.connect(_on_slot_delete_requested)


func _on_slot_load_requested(slot_index: int) -> void:
	print("LoadGameScreen: Load requested for slot", slot_index)
	# Disable UI? Show loading indicator?
	SaveManager.load_game(slot_index)
	# Game will transition via SceneManager


func _on_slot_delete_requested(slot_index: int) -> void:
	print("LoadGameScreen: Delete requested for slot", slot_index)
	# TODO: Add confirmation dialog popup! "Are you sure?"
	var success = SaveManager.delete_save_slot(slot_index)
	if success:
		# Refresh the list after deletion
		populate_save_list()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(START_SCREEN_PATH) # Go back to start menu
