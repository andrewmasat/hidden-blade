# Inventory.gd - Autoload Singleton
extends Node

# Signal emitted when any slot changes content
signal inventory_changed(slot_index: int, item_data)
# Signal emitted when the selected slot changes
signal selected_slot_changed(new_index: int, old_index: int, item_data)

# Constants
const HOTBAR_SIZE = 9

# Data storage
var hotbar_slots: Array = [] # Array to hold item data for each slot
var selected_slot_index: int = 0 : set = set_selected_slot

func _ready():
	# Initialize the hotbar with empty slots
	hotbar_slots.resize(HOTBAR_SIZE)
	hotbar_slots.fill(null) # null represents an empty slot

	print("Inventory initialized with slots:", hotbar_slots.size())


# Attempts to add an item to the first available hotbar slot
# item_data: For now, let's assume this is just the texture path string,
#            later it could be a custom Item Resource or Dictionary.
# Returns: true if added successfully, false otherwise
func add_item(item_data) -> bool:
	for i in range(hotbar_slots.size()):
		if hotbar_slots[i] == null: # Found an empty slot
			hotbar_slots[i] = item_data
			emit_signal("inventory_changed", i, item_data)
			print("Added item", item_data, "to slot", i)
			# If the currently selected slot was empty, automatically select the new item? (Optional)
			# if i == selected_slot_index:
			#     emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, item_data)
			return true
	print("Inventory full, cannot add item", item_data)
	return false

# Removes item from a specific slot (e.g., when used/dropped)
func remove_item(slot_index: int):
	if slot_index >= 0 and slot_index < hotbar_slots.size():
		var removed_item = hotbar_slots[slot_index]
		if removed_item != null:
			hotbar_slots[slot_index] = null
			emit_signal("inventory_changed", slot_index, null)
			print("Removed item from slot", slot_index)
			# If this was the selected slot, update selection signal
			if slot_index == selected_slot_index:
				emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, null)
			return removed_item # Return the data of the removed item
	return null

# Gets the item data from a specific slot
func get_item(slot_index: int):
	if slot_index >= 0 and slot_index < hotbar_slots.size():
		return hotbar_slots[slot_index]
	return null

# --- Selected Slot ---
func set_selected_slot(new_index: int):
	if new_index >= 0 and new_index < hotbar_slots.size() and new_index != selected_slot_index:
		var old_index = selected_slot_index
		selected_slot_index = new_index
		print("Selected slot changed to:", selected_slot_index)
		emit_signal("selected_slot_changed", new_index, old_index, get_item(new_index))

func get_selected_slot_index() -> int:
	return selected_slot_index

func get_selected_item():
	return get_item(selected_slot_index)
