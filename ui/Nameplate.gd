# Nameplate.gd
extends Control

@onready var name_label: Label = $NameLabel # Adjust if path differs

func update_name(new_name: String) -> void:
	if is_instance_valid(name_label):
		name_label.text = new_name
		# Optional: Resize the control if name is very long?
		# self.custom_minimum_size.x = name_label.get_minimum_size().x + some_padding
