# Forge.gd
extends Node2D
class_name Forge

@export var station_type: String = "FORGE" # Make sure this matches what ItemData expects

func _ready():
	# Ensure its InteractionArea is on the correct collision layers/masks
	# to be detected by the player's pickup/interaction area.
	var interaction_area = $InteractionArea 
	if is_instance_valid(interaction_area):
		interaction_area.add_to_group("crafting_station_area") 
		# Ensure its collision layer/mask allows detection by player's Area2D
