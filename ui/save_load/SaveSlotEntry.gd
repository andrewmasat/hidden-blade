extends Button
class_name SaveSlotEntry

signal load_requested(slot_index)
signal delete_requested(slot_index)

@onready var name_label: Label = $Container/CharacterNameLabel
@onready var level_label: Label = $Container/LevelNameLabel
@onready var time_label: Label = $Container/SaveTimeLabel

var slot_index: int = -1

func _ready():
	self.pressed.connect(_on_load_pressed)

func set_data(metadata: Dictionary):
	if not metadata: return
	slot_index = metadata.get("slot_index", -1)

	if is_instance_valid(name_label):
		name_label.text = metadata.get("character_name", "???")
	else:
		printerr("SaveSlotEntry Error: name_label node not found/invalid!")

	if is_instance_valid(level_label):
		level_label.text = "Level: " + metadata.get("current_level_name", "Unknown")
	else:
		printerr("SaveSlotEntry Error: level_label node not found/invalid!")

	if is_instance_valid(time_label):
		var save_time = metadata.get("save_time_unix", 0)
		# Add check for valid time?
		if save_time > 0:
			var datetime = Time.get_datetime_dict_from_unix_time(save_time)
			time_label.text = "%04d-%02d-%02d %02d:%02d" % [datetime.year, datetime.month, datetime.day, datetime.hour, datetime.minute]
		else:
			time_label.text = "--:--" # Placeholder for invalid time
	else:
		printerr("SaveSlotEntry Error: time_label node not found/invalid!")

func _on_load_pressed():
	if slot_index != -1:
		emit_signal("load_requested", slot_index)

func _on_delete_pressed():
	if slot_index != -1:
		emit_signal("delete_requested", slot_index)
