# Forge.gd
extends Node2D
class_name Forge

# We can add specific properties later, like what recipes it unlocks
# or if it requires fuel.
# For now, its existence and type are enough.
@export var station_type: String = "FORGE" # Identifier

func _ready():
	pass
