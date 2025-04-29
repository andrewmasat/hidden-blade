# DroppedItem.gd
extends Area2D
class_name DroppedItem # Optional: for type hints

@onready var sprite = $ItemSprite

var item_data: ItemData = null

# Call this immediately after instantiating the scene
func initialize(data: ItemData):
	if data == null or not data is ItemData:
		printerr("DroppedItem: Invalid ItemData provided during initialization!")
		queue_free() # Remove invalid item immediately
		return

	item_data = data
	# Update sprite based on item data
	if item_data.texture:
		sprite.texture = item_data.texture
	else:
		printerr("DroppedItem: ItemData is missing a texture!")
		# Optional: Set a default placeholder texture if needed
	# TODO: Maybe add quantity label visually if > 1? Or just rely on pickup logic?

	print("DroppedItem initialized with:", item_data.item_id, " Qty:", item_data.quantity)


func get_item_data() -> ItemData:
	return item_data
