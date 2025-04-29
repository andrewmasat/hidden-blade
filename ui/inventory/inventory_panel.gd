# InventoryPanel.gd
extends Control

class_name InventoryPanel

signal close_requested

const InventorySlotScene = preload("res://ui/inventory/inventory_slot.tscn") # ADJUST PATH

@onready var grid_container = $MarginContainer/PanelLayout/InventoryGrid
@onready var close_button = $MarginContainer/PanelLayout/CloseButton

var slot_instances: Array[Control] = [] # Holds the instantiated InventorySlot scenes

func _ready():
	close_button.pressed.connect(_on_close_button_pressed)
	_populate_grid()
	# Connect AFTER populating grid
	Inventory.main_inventory_changed.connect(_on_main_inventory_changed)
	# Display initial state
	_update_all_slots()


func _populate_grid():
	# Clear any existing slots first (safety measure)
	for child in grid_container.get_children():
		child.queue_free()
	slot_instances.clear()

	# Instantiate and add slots
	for i in range(Inventory.INVENTORY_SIZE):
		var slot = InventorySlotScene.instantiate() as Control
		# Set the crucial info for DnD
		if slot.has_method("set"): # Check if script variables exist
			slot.set("slot_index", i)
			slot.set("inventory_area", Inventory.InventoryArea.MAIN)
		else:
			printerr("Inventory Panel slot", i, " instance missing script variables (slot_index/inventory_area)")

		grid_container.add_child(slot)
		slot_instances.append(slot)
		# Optional: Connect click signal if needed for panel interaction later
		# Connect slot signals if needed (e.g., slot.pressed.connect(_on_slot_clicked.bind(i)))


func _update_all_slots():
	for i in range(slot_instances.size()):
		var slot_node = slot_instances[i]
		if slot_node.has_method("display_item"):
			# Pass ItemData or null from inventory
			slot_node.display_item(Inventory.get_item_data(Inventory.InventoryArea.MAIN, i))


func _on_main_inventory_changed(slot_index: int, item_data: ItemData): # Add ItemData type hint
	if slot_index >= 0 and slot_index < slot_instances.size():
		var slot_node = slot_instances[slot_index]
		if slot_node and slot_node.has_method("display_item"):
			slot_node.display_item(item_data) # Pass ItemData or null


func show_panel():
	_update_all_slots() # Ensure visuals are fresh before showing
	visible = true

func hide_panel():
	visible = false

func _on_close_button_pressed():
	emit_signal("close_requested")
