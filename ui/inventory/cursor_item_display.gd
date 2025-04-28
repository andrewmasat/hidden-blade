# CursorItemDisplay.gd
extends Control

@onready var icon_rect = $ItemIcon
@onready var quantity_label = $QuantityLabel

func _ready():
	# Hide initially, Inventory signal will show it
	visible = false
	# Connect to the central inventory signal
	Inventory.cursor_item_changed.connect(_on_cursor_item_changed)
	# Ensure initial state matches inventory (likely null)
	_on_cursor_item_changed(Inventory.get_cursor_item())


func _process(delta):
	# Follow the mouse cursor
	if visible:
		global_position = get_global_mouse_position()


func _on_cursor_item_changed(item_data: ItemData):
	if item_data != null and item_data is ItemData:
		icon_rect.texture = item_data.texture
		if item_data.quantity > 1:
			quantity_label.text = str(item_data.quantity)
			quantity_label.visible = true
		else:
			quantity_label.text = ""
			quantity_label.visible = false
		visible = true # Show the display
	else:
		visible = false # Hide the display
		icon_rect.texture = null
		quantity_label.text = ""
