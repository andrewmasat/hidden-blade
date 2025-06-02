# Inventory.gd - Autoload Singleton
extends Node

enum InventoryArea { HOTBAR, MAIN }

signal inventory_changed(slot_index: int, item_data: ItemData)
signal main_inventory_changed(slot_index: int, item_data: ItemData)
signal selected_slot_changed(new_index: int, old_index: int, item_data: ItemData)
signal cursor_item_changed(item_data: ItemData)

# Constants
const HOTBAR_SIZE = 9
const INVENTORY_COLS = 9 # Example: 8 columns wide
const INVENTORY_ROWS = 4 # Example: 4 rows high
const INVENTORY_SIZE = INVENTORY_COLS * INVENTORY_ROWS

# Data storage
var hotbar_slots: Array = [] # Array[ItemData] - ItemData can be Resource, Dictionary, or path string for now
var selected_slot_index: int = 0 : set = set_selected_slot
var inventory_slots: Array = [] # Array[ItemData] - Main inventory slots
var cursor_item_data: ItemData = null
var is_dragging_selected_slot: bool = false

func _ready():
	# Initialize hotbar
	hotbar_slots.resize(HOTBAR_SIZE)
	hotbar_slots.fill(null)
	# Initialize main inventory
	inventory_slots.resize(INVENTORY_SIZE)
	inventory_slots.fill(null)
	print("Inventory initialized. Hotbar:", hotbar_slots.size(), "Main:", inventory_slots.size())


# --- Item Management ---
# Add item: Tries to stack first, then find empty
func add_item(item_data_to_add: ItemData) -> bool:
	if not item_data_to_add is ItemData:
		printerr("Inventory.add_item: Invalid item_data provided.")
		return false

	var item_id = item_data_to_add.item_id

	# --- Try stacking in Hotbar ---
	var target_index = find_first_stackable_slot(InventoryArea.HOTBAR, item_id)
	if target_index != -1:
		return _try_add_quantity_to_slot(InventoryArea.HOTBAR, target_index, item_data_to_add)

	# --- Try stacking in Main Inventory ---
	target_index = find_first_stackable_slot(InventoryArea.MAIN, item_id)
	if target_index != -1:
		return _try_add_quantity_to_slot(InventoryArea.MAIN, target_index, item_data_to_add)

	# --- Try empty slot in Hotbar ---
	target_index = find_first_empty_slot(InventoryArea.HOTBAR)
	if target_index != -1:
		# Important: Duplicate the resource if adding the full amount to prevent shared references
		var new_item_instance = item_data_to_add.duplicate()
		_set_item_data(InventoryArea.HOTBAR, target_index, new_item_instance)
		_emit_change_signal(InventoryArea.HOTBAR, target_index, new_item_instance)
		return true

	# --- Try empty slot in Main Inventory ---
	target_index = find_first_empty_slot(InventoryArea.MAIN)
	if target_index != -1:
		var new_item_instance = item_data_to_add.duplicate()
		_set_item_data(InventoryArea.MAIN, target_index, new_item_instance)
		_emit_change_signal(InventoryArea.MAIN, target_index, new_item_instance)
		return true

	print("All inventories full/no stackable slots, cannot add item:", item_id)
	return false

func _try_add_quantity_to_slot(area: InventoryArea, index: int, item_data_to_add: ItemData) -> bool:
	var target_item: ItemData = get_item_data(area, index)
	if not target_item or target_item.item_id != item_data_to_add.item_id:
		printerr("_try_add_quantity: Target slot mismatch or empty!")
		return false # Should not happen if find_stackable worked

	var can_add = target_item.max_stack_size - target_item.quantity
	var amount_to_add = min(item_data_to_add.quantity, can_add)

	if amount_to_add > 0:
		target_item.quantity += amount_to_add
		item_data_to_add.quantity -= amount_to_add # Decrease quantity from source item data

		_emit_change_signal(area, index, target_item) # Signal target update

		# If source quantity remains, try adding the rest recursively (might be complex)
		# For now, let's assume add_item handles adding the remainder if quantity > 0
		if item_data_to_add.quantity > 0:
			print("Partial add to stack, remaining:", item_data_to_add.quantity)
			# Trigger add_item again to handle the remainder
			return add_item(item_data_to_add)

		return true # All quantity was added

	return false # Couldn't add any more


func can_player_add_item_check(item_data_to_check: ItemData) -> bool:
	if not item_data_to_check is ItemData or item_data_to_check.quantity <= 0:
		printerr("Inventory: can_player_add_item_check - Invalid item_data provided.")
		return false # Cannot add invalid item

	var item_id = item_data_to_check.item_id
	var quantity_remaining_to_add = item_data_to_check.quantity

	# --- Try stacking in Hotbar ---
	for item_slot_data in hotbar_slots:
		if item_slot_data is ItemData and \
		   item_slot_data.item_id == item_id and \
		   not item_slot_data.is_stack_full():
			var can_stack_amount = item_slot_data.max_stack_size - item_slot_data.quantity
			quantity_remaining_to_add -= min(quantity_remaining_to_add, can_stack_amount)
			if quantity_remaining_to_add <= 0: return true # Can fit it all

	# --- Try stacking in Main Inventory ---
	for item_slot_data in inventory_slots:
		if item_slot_data is ItemData and \
		   item_slot_data.item_id == item_id and \
		   not item_slot_data.is_stack_full():
			var can_stack_amount = item_slot_data.max_stack_size - item_slot_data.quantity
			quantity_remaining_to_add -= min(quantity_remaining_to_add, can_stack_amount)
			if quantity_remaining_to_add <= 0: return true # Can fit it all

	# If quantity still remains, try finding empty slots
	# --- Try empty slot in Hotbar ---
	if quantity_remaining_to_add > 0: # Only if we still need to place items
		for item_slot_data in hotbar_slots:
			if item_slot_data == null:
				quantity_remaining_to_add -= item_data_to_check.max_stack_size # Assume full stack can go here
				if quantity_remaining_to_add <= 0: return true # Can fit it all

	# --- Try empty slot in Main Inventory ---
	if quantity_remaining_to_add > 0:
		for item_slot_data in inventory_slots:
			if item_slot_data == null:
				quantity_remaining_to_add -= item_data_to_check.max_stack_size
				if quantity_remaining_to_add <= 0: return true # Can fit it all

	# If after all checks, quantity_remaining_to_add is still > 0, then it won't fit
	return quantity_remaining_to_add <= 0


func decrease_item_quantity(area: InventoryArea, index: int, amount_to_decrease: int = 1) -> bool:
	if amount_to_decrease <= 0: return false # Cannot decrease by zero or less

	var item_data: ItemData = get_item_data(area, index)

	if item_data != null and item_data.quantity >= amount_to_decrease:
		item_data.quantity -= amount_to_decrease
		print("Inventory: Decreased quantity for ", item_data.item_id, " in ", InventoryArea.keys()[area], "[", index, "]. New Qty:", item_data.quantity)

		# Check if stack is now empty
		if item_data.quantity <= 0:
			print("  -> Item stack empty, removing.")
			_set_item_data(area, index, null) # Remove the item resource entirely
			_emit_change_signal(area, index, null) # Signal removal

			# Check if this was the selected hotbar item
			if area == InventoryArea.HOTBAR and index == selected_slot_index:
				emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, null)
		else:
			# Just emit signal with updated item data
			_emit_change_signal(area, index, item_data)

		return true # Quantity was decreased
	else:
		# Item not found or not enough quantity
		if item_data: print("Inventory: Cannot decrease quantity, not enough items. Have:", item_data.quantity, "Need:", amount_to_decrease)
		else: print("Inventory: Cannot decrease quantity, slot is empty.")
		return false

# Removes item from a specific slot (e.g., when used/dropped)
func remove_item_from_hotbar(slot_index: int):
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

# Remove from Main Inventory
func remove_item_from_main_inventory(slot_index: int):
	if slot_index >= 0 and slot_index < inventory_slots.size():
		var removed_item = inventory_slots[slot_index]
		if removed_item != null:
			inventory_slots[slot_index] = null
			emit_signal("main_inventory_changed", slot_index, null)
			return removed_item
	return null

func remove_item_and_put_on_cursor(area: InventoryArea, index: int) -> ItemData:
	var slots = _get_slot_array(area)
	if index < 0 or index >= slots.size():
		printerr("remove_item_and_put_on_cursor: Invalid index ", index)
		return null

	var item_to_move: ItemData = slots[index]

	if item_to_move == null:
		print("remove_item_and_put_on_cursor: Slot already empty.")
		return null # Nothing to move

	if area == InventoryArea.HOTBAR and index == selected_slot_index:
		is_dragging_selected_slot = true
		print("Inventory: Started dragging selected slot.") # DEBUG

	# Clear the source slot FIRST internally
	if not _set_item_data(area, index, null):
		printerr("remove_item_and_put_on_cursor: Failed to clear source slot.")
		return null # Abort if clearing failed

	# Put the item onto the cursor
	# IMPORTANT: Use the actual ItemData removed, not a duplicate here.
	set_cursor_item(item_to_move) # This emits cursor_item_changed

	# Emit signal for the source slot becoming empty
	_emit_change_signal(area, index, null)

	# Return the item that was moved to the cursor
	return item_to_move

func remove_item_from_area(area: InventoryArea, index: int) -> ItemData:
	var slots = _get_slot_array(area)
	if index < 0 or index >= slots.size(): return null

	var removed_item = slots[index]
	if removed_item != null:
		print("Removing item from", area, "[", index, "]")
		_set_item_data(area, index, null)
		_emit_change_signal(area, index, null)
		# Check if it was selected hotbar slot
		if area == InventoryArea.HOTBAR and index == selected_slot_index:
			emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, null)
		return removed_item
	return null

func find_first_empty_slot(area: InventoryArea) -> int:
	var slots = _get_slot_array(area)
	for i in range(slots.size()):
		if slots[i] == null: # Found an empty one
			return i
	return -1 # No empty slot found

func find_first_stackable_slot(area: InventoryArea, item_id_to_stack: String) -> int:
	var slots = _get_slot_array(area)
	for i in range(slots.size()):
		var existing_item: ItemData = slots[i]
		if existing_item != null and \
		   existing_item.item_id == item_id_to_stack and \
		   not existing_item.is_stack_full():
			return i # Found a suitable stack
	return -1 # No stackable slot found

# Get from Hotbar
func get_item_from_hotbar(slot_index: int):
	if slot_index >= 0 and slot_index < hotbar_slots.size():
		return hotbar_slots[slot_index]
	return null

# Get from Main Inventory
func get_item_from_main_inventory(slot_index: int):
	if slot_index >= 0 and slot_index < inventory_slots.size():
		return inventory_slots[slot_index]
	return null

func select_next_slot():
	# Calculate next index with wrap-around using modulo
	var next_index = (selected_slot_index + 1) % HOTBAR_SIZE
	set_selected_slot(next_index) # Use setter to handle signal emission

func select_previous_slot():
	# Calculate previous index with wrap-around
	# Adding HOTBAR_SIZE before modulo handles negative results correctly
	var prev_index = (selected_slot_index - 1 + HOTBAR_SIZE) % HOTBAR_SIZE
	set_selected_slot(prev_index) # Use setter to handle signal emission

# --- Selected Slot ---
func set_selected_slot(new_index: int):
	if new_index >= 0 and new_index < HOTBAR_SIZE and new_index != selected_slot_index:
		var old_index = selected_slot_index
		selected_slot_index = new_index
		emit_signal("selected_slot_changed", new_index, old_index, get_item_from_hotbar(new_index))

func get_selected_slot_index() -> int:
	return selected_slot_index

func get_selected_item() -> ItemData: # Ensure ItemData type hint
	return get_item_data(InventoryArea.HOTBAR, selected_slot_index)

func get_item_quantity_by_id(item_id_to_find: String) -> int:
	if item_id_to_find.is_empty():
		return 0

	var total_quantity: int = 0

	# Check Hotbar
	for item_data in hotbar_slots:
		if item_data is ItemData and item_data.item_id == item_id_to_find:
			total_quantity += item_data.quantity
	
	# Check Main Inventory
	for item_data in inventory_slots:
		if item_data is ItemData and item_data.item_id == item_id_to_find:
			total_quantity += item_data.quantity
			
	return total_quantity

func remove_item_by_id_and_quantity(item_id_to_remove: String, quantity_to_remove: int) -> bool:
	if item_id_to_remove.is_empty() or quantity_to_remove <= 0:
		return false # Invalid request

	var quantity_actually_removed: int = 0
	var target_quantity_to_remove = quantity_to_remove

	# --- Pass 1: Decrease from Hotbar slots ---
	for i in range(hotbar_slots.size()):
		var item_data = hotbar_slots[i]
		if item_data is ItemData and item_data.item_id == item_id_to_remove:
			var amount_in_this_stack = item_data.quantity
			var amount_to_take_from_stack = min(target_quantity_to_remove - quantity_actually_removed, amount_in_this_stack)
			
			if amount_to_take_from_stack > 0:
				item_data.quantity -= amount_to_take_from_stack
				quantity_actually_removed += amount_to_take_from_stack
				
				if item_data.quantity <= 0:
					_set_item_data(InventoryArea.HOTBAR, i, null) # Remove item if stack depleted
					_emit_change_signal(InventoryArea.HOTBAR, i, null)
					# If this was the selected slot, ensure player unequips
					if i == selected_slot_index:
						emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, null)
				else:
					_emit_change_signal(InventoryArea.HOTBAR, i, item_data) # Update existing slot

			if quantity_actually_removed >= target_quantity_to_remove:
				return true # All required items removed

	# --- Pass 2: Decrease from Main Inventory slots ---
	for i in range(inventory_slots.size()):
		var item_data = inventory_slots[i]
		if item_data is ItemData and item_data.item_id == item_id_to_remove:
			var amount_in_this_stack = item_data.quantity
			var amount_to_take_from_stack = min(target_quantity_to_remove - quantity_actually_removed, amount_in_this_stack)

			if amount_to_take_from_stack > 0:
				item_data.quantity -= amount_to_take_from_stack
				quantity_actually_removed += amount_to_take_from_stack

				if item_data.quantity <= 0:
					_set_item_data(InventoryArea.MAIN, i, null)
					_emit_change_signal(InventoryArea.MAIN, i, null)
				else:
					_emit_change_signal(InventoryArea.MAIN, i, item_data)
			
			if quantity_actually_removed >= target_quantity_to_remove:
				return true # All required items removed

	if quantity_actually_removed < target_quantity_to_remove:
		# This case means we couldn't find enough items.
		# For robust transactional behavior, one might implement a rollback here,
		# but for now, it means the operation failed to meet the full request.
		# The items that *were* removed are still gone.
		printerr("Inventory: Failed to remove full quantity of '", item_id_to_remove, "'. Requested: ", target_quantity_to_remove, ", Removed: ", quantity_actually_removed)
		# Depending on game design, you might want to add back the `quantity_actually_removed` if partial removal is not allowed.
		# For now, we'll assume partial removal up to what's available is okay if the pre-check failed.
		return false 
		
	return true # Should have returned earlier if successful

# Server calls this on the client's /root/Inventory node to tell it about a slot update.
@rpc("any_peer", "call_local", "reliable") # Server (any_peer technically, but targeted by rpc_id) calls, client executes locally
func client_receive_slot_update(area_enum_val: int, slot_index: int, item_data_resource_path: String, item_id_from_server: String, quantity_from_server: int):
	# This function executes on the CLIENT that was targeted by the server's rpc_id.
	# We need to ensure this client is actually the one who should be processing this.
	# However, since the server uses rpc_id to target the specific client, this RPC
	# will only arrive at the correct client's Inventory.gd instance.
	# A check like 'if multiplayer.get_unique_id() != TARGETED_PEER_ID' is tricky here
	# because the RPC itself doesn't carry who it was *intended* for beyond the rpc_id mechanism.
	# We trust that rpc_id delivered it correctly.

	print("Inventory (Client ", multiplayer.get_unique_id(), "): Received slot update from server. Area: ", area_enum_val, ", Slot: ", slot_index, ", Path: '", item_data_resource_path, "', ID: '", item_id_from_server, "', Qty: ", quantity_from_server)

	var target_area = area_enum_val as InventoryArea # Cast int back to enum

	var new_item_instance: ItemData = null
	if not item_data_resource_path.is_empty(): # If server sent a resource path
		var loaded_res = load(item_data_resource_path)
		if loaded_res is ItemData:
			new_item_instance = loaded_res.duplicate() # Client gets its own instance
			new_item_instance.quantity = quantity_from_server
			# Sanity check if item_id also matches, though path should be king
			if new_item_instance.item_id != item_id_from_server and not item_id_from_server.is_empty():
				printerr("Inventory (Client): Item ID mismatch for loaded resource! Path gave '", new_item_instance.item_id, "', server also sent ID '", item_id_from_server, "'. Using path's item.")
		else:
			printerr("Inventory (Client): Failed to load ItemData from path: ", item_data_resource_path)
			# Fallback: Try to construct from item_id if path failed but id is valid
			if not item_id_from_server.is_empty():
				var base_res_by_id = ItemDatabase.get_item_base(item_id_from_server)
				if base_res_by_id is ItemData:
					new_item_instance = base_res_by_id.duplicate()
					new_item_instance.quantity = quantity_from_server
					print("  -> Fallback: Reconstructed item '", item_id_from_server, "' from ItemDatabase.")
				else:
					printerr("Inventory (Client): Fallback failed. Could not find item '", item_id_from_server, "' in ItemDatabase.")
	elif not item_id_from_server.is_empty(): # No path, but got an ID (e.g., non-resource items, or if server prefers ID)
		var base_res_by_id = ItemDatabase.get_item_base(item_id_from_server)
		if base_res_by_id is ItemData:
			new_item_instance = base_res_by_id.duplicate()
			new_item_instance.quantity = quantity_from_server
		else:
			printerr("Inventory (Client): Could not find item '", item_id_from_server, "' in ItemDatabase.")
	# If both path and ID are empty, new_item_instance remains null (empty slot)

	# Update the local inventory array
	var slots_array_ref = _get_slot_array(target_area) # Get local hotbar_slots or inventory_slots
	if slot_index >= 0 and slot_index < slots_array_ref.size():
		slots_array_ref[slot_index] = new_item_instance
		print("  -> Client Inventory: Slot ", InventoryArea.keys()[target_area], "[", slot_index, "] updated locally.")
		
		# Emit the local signals so UI updates
		_emit_change_signal(target_area, slot_index, new_item_instance)
		
		# If the hotbar's selected slot was updated, also emit selected_slot_changed
		if target_area == InventoryArea.HOTBAR and slot_index == selected_slot_index:
			emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, new_item_instance)
	else:
		printerr("Inventory (Client): Received invalid slot_index ", slot_index, " for area ", target_area)

@rpc("any_peer", "call_local", "reliable") # Server calls this on client
func client_receive_cursor_item_update(item_data_path: String, item_id_from_server: String, quantity_from_server: int):
	print("Inventory (Client ", multiplayer.get_unique_id(), "): Received cursor update from server. Path: '", item_data_path, "', ID: '", item_id_from_server, "', Qty: ", quantity_from_server)

	var new_cursor_item: ItemData = null
	if not item_data_path.is_empty():
		var res = load(item_data_path)
		if res is ItemData:
			new_cursor_item = res.duplicate()
			new_cursor_item.quantity = quantity_from_server
	elif not item_id_from_server.is_empty(): # Fallback to ID
		var base_res = ItemDatabase.get_item_base(item_id_from_server)
		if base_res is ItemData:
			new_cursor_item = base_res.duplicate()
			new_cursor_item.quantity = quantity_from_server
			
	set_cursor_item(new_cursor_item) # This existing function emits "cursor_item_changed" for UI

# Internal helper to get the correct array based on area
func _get_slot_array(area: InventoryArea) -> Array:
	if area == InventoryArea.HOTBAR:
		return hotbar_slots
	elif area == InventoryArea.MAIN:
		return inventory_slots
	else:
		printerr("Inventory._get_slot_array: Invalid area provided!")
		return [] # Return empty array to avoid crash, signal error

# Internal helper to get item data
func get_item_data(area: InventoryArea, index: int) -> ItemData:
	var slots = _get_slot_array(area)
	if index >= 0 and index < slots.size():
		return slots[index] # Direct return
	return null

# Internal helper to set item data (DOES NOT EMIT SIGNALS - Caller must emit)
func _set_item_data(area: InventoryArea, index: int, item_data: ItemData):
	var slots = _get_slot_array(area)
	if index >= 0 and index < slots.size():
		slots[index] = item_data # Direct assignment
		return true
	return false

func transfer_to_hotbar(source_area: InventoryArea, source_index: int):
	if source_area != InventoryArea.MAIN: print("Invalid source for transfer_to_hotbar"); return # Safety check
	var source_item: ItemData = get_item_data(source_area, source_index)
	if source_item == null: return

	var item_id = source_item.item_id
	var target_area = InventoryArea.HOTBAR
	print("Attempting Transfer: MAIN[", source_index, "] -> HOTBAR") # DEBUG

	# 1. Try to find existing stack in target area
	var stack_index = find_first_stackable_slot(target_area, item_id)
	if stack_index != -1:
		var target_item: ItemData = get_item_data(target_area, stack_index)
		var can_add = target_item.max_stack_size - target_item.quantity
		var transfer_amount = min(source_item.quantity, can_add)

		if transfer_amount > 0:
			target_item.quantity += transfer_amount
			source_item.quantity -= transfer_amount
			# Clear source if empty
			if source_item.quantity <= 0:
				_set_item_data(source_area, source_index, null)
			# Emit signals for both changed slots
			_emit_change_signal(target_area, stack_index, target_item)
			_emit_change_signal(source_area, source_index, get_item_data(source_area, source_index)) # Pass updated source (or null)
			print("Stacked ", transfer_amount, " onto Hotbar[", stack_index, "]")
			# If source still has items, stop here (don't also move to empty slot)
			if get_item_data(source_area, source_index) != null:
				return

	# 2. If no stack found OR source became empty after stacking, find empty slot
	if get_item_data(source_area, source_index) != null: # Check if item still needs moving
		var empty_index = find_first_empty_slot(target_area)
		if empty_index != -1:
			print(" -> Moving to empty Hotbar slot:", empty_index) # DEBUG
			var item_to_move = get_item_data(source_area, source_index)
			_set_item_data(target_area, empty_index, item_to_move)
			_set_item_data(source_area, source_index, null)
			_emit_change_signal(target_area, empty_index, item_to_move)
			_emit_change_signal(source_area, source_index, null)
		else:
			print(" -> Hotbar full, cannot transfer item.") # DEBUG

func transfer_to_main_inventory(source_area: InventoryArea, source_index: int):
	if source_area != InventoryArea.HOTBAR: print("Invalid source for transfer_to_main"); return # Safety check
	var source_item: ItemData = get_item_data(source_area, source_index)
	if source_item == null: return

	var item_id = source_item.item_id
	var target_area = InventoryArea.MAIN
	print("Attempting Transfer: HOTBAR[", source_index, "] -> MAIN") # DEBUG

	# 1. Try to find existing stack in target area
	var stack_index = find_first_stackable_slot(target_area, item_id)
	if stack_index != -1:
		var target_item: ItemData = get_item_data(target_area, stack_index)
		var can_add = target_item.max_stack_size - target_item.quantity
		var transfer_amount = min(source_item.quantity, can_add)

		if transfer_amount > 0:
			target_item.quantity += transfer_amount
			source_item.quantity -= transfer_amount
			if source_item.quantity <= 0:
				_set_item_data(source_area, source_index, null)
			_emit_change_signal(target_area, stack_index, target_item)
			_emit_change_signal(source_area, source_index, get_item_data(source_area, source_index))
			print("Stacked ", transfer_amount, " onto Main[", stack_index, "]")
			if get_item_data(source_area, source_index) != null:
				return # Stop if source still has items

	# 2. If no stack OR source became empty, find empty slot
	if get_item_data(source_area, source_index) != null:
		var empty_index = find_first_empty_slot(target_area)
		if empty_index != -1:
			print(" -> Moving to empty Main slot:", empty_index) # DEBUG
			var item_to_move = get_item_data(source_area, source_index)
			_set_item_data(target_area, empty_index, item_to_move)
			_set_item_data(source_area, source_index, null)
			_emit_change_signal(target_area, empty_index, item_to_move)
			_emit_change_signal(source_area, source_index, null)
		else:
			print(" -> Main Inventory full, cannot transfer item.") # DEBUG

func get_cursor_item() -> ItemData:
	return cursor_item_data

func set_cursor_item(new_item_data: ItemData) -> ItemData:
	var old_item = cursor_item_data
	cursor_item_data = new_item_data
	if cursor_item_data != null and cursor_item_data.quantity <= 0:
		# If setting an item with zero quantity, clear it instead
		cursor_item_data = null
	emit_signal("cursor_item_changed", cursor_item_data)
	print("Inventory: Cursor item set to: ", cursor_item_data)
	return old_item # Return what was previously held

# Clears the item from the cursor and returns it
func clear_cursor_item() -> ItemData:
	var old_item = cursor_item_data
	if old_item != null:
		cursor_item_data = null
		emit_signal("cursor_item_changed", null)
		print("Inventory: Cursor item cleared.")
	return old_item

# --- Split Stack Logic ---
func split_stack_to_cursor(source_area: InventoryArea, source_index: int):
	if cursor_item_data != null: # Cannot split if client already holding
		print("Inventory: Cannot split, client already holding item on cursor.")
		return

	# Client needs to know what item is in the source slot to potentially show it on cursor optimistically
	var source_item_locally = get_item_data(source_area, source_index)
	if source_item_locally == null or source_item_locally.quantity <= 1:
		print("Inventory: Cannot split empty slot or stack of 1 (client-side check).")
		return

	print("Inventory (Client): Requesting server to split stack from ", InventoryArea.keys()[source_area], "[", source_index, "]")
	var main_node = get_node_or_null("/root/Main")
	if is_instance_valid(main_node):
		main_node.rpc_id(1, "server_handle_split_stack_request", source_area, source_index)
	else:
		printerr("Inventory: Could not find Main node for split_stack RPC.")


# --- Place Cursor Item Logic ---
func place_cursor_item_on_slot(target_area: InventoryArea, target_index: int):
	if cursor_item_data == null:
		printerr("Inventory: client_request_place_cursor_item called with no item on cursor!")
		return

	print("Inventory (Client): Requesting server to place cursor item '", cursor_item_data.item_id, "' onto ", InventoryArea.keys()[target_area], "[", target_index, "]")

	# We need to send enough info for the server to reconstruct the cursor_item_data
	# and know where it's going.
	var item_id_on_cursor = cursor_item_data.item_id
	var qty_on_cursor = cursor_item_data.quantity
	var path_on_cursor = cursor_item_data.resource_path

	var main_node = get_node_or_null("/root/Main")
	if is_instance_valid(main_node):
		# Client tells server: "My cursor item (defined by these properties) wants to go to this target slot."
		main_node.rpc_id(1, "server_handle_place_cursor_item_request", 
						 path_on_cursor, item_id_on_cursor, qty_on_cursor, 
						 target_area, target_index)
	else:
		printerr("Inventory: Could not find Main node for place_cursor_item RPC.")

func force_update_selected_slot_signal():
	# Re-emit the signal with the current state
	print("Inventory: Forcing selected_slot_changed signal update.") # Debug
	var current_selected_item = get_item_data(InventoryArea.HOTBAR, selected_slot_index)
	emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, current_selected_item)

func move_item(source_area: InventoryArea, source_index: int, target_area: InventoryArea, target_index: int):
	# Prevent dropping onto itself
	if source_area == target_area and source_index == target_index:
		print("  -> Abort: Source and target are the same.") # DEBUG
		return
	# Prevent dropping onto itself (no action needed)
	if source_area == target_area and source_index == target_index:
		return

	var source_item: ItemData = get_item_data(source_area, source_index)
	var target_item: ItemData = get_item_data(target_area, target_index)

	# Cannot drag from an empty slot
	if source_item == null:
		printerr("Inventory.move_item: Source slot is empty.")
		return


	# Case 1: Target slot is empty
	if target_item == null:
		# Simple move: place source item in target, clear source
		if _set_item_data(target_area, target_index, source_item):
			if _set_item_data(source_area, source_index, null): # Clear source
				_emit_change_signal(target_area, target_index, source_item)
				_emit_change_signal(source_area, source_index, null)
				_check_and_update_selected_slot(source_area, source_index, target_area, target_index, null, source_item) # Update selection if needed
			else: printerr("Move Error: Failed to clear source slot.")
		else: printerr("Move Error: Failed to set target slot.")


	# Case 2: Target slot has SAME item type (Attempt stacking)
	elif target_item.item_id == source_item.item_id:
		var can_add_to_target = target_item.max_stack_size - target_item.quantity
		var amount_to_transfer = min(source_item.quantity, can_add_to_target)

		if amount_to_transfer > 0:
			target_item.quantity += amount_to_transfer
			source_item.quantity -= amount_to_transfer

			# Clear source slot if it became empty
			var final_source_item = source_item if source_item.quantity > 0 else null
			_set_item_data(source_area, source_index, final_source_item)

			# Emit signals for both potentially changed slots
			_emit_change_signal(target_area, target_index, target_item)
			_emit_change_signal(source_area, source_index, final_source_item)
			_check_and_update_selected_slot(source_area, source_index, target_area, target_index, final_source_item, target_item) # Update selection if needed

		else:
			# Cannot stack (target full), perform a SWAP instead
			print("  -> Action: Target stack full, swapping instead.")
			_perform_swap(source_area, source_index, source_item, target_area, target_index, target_item)


	# Case 3: Target slot has DIFFERENT item type (Perform swap)
	else:
		print("  -> Action: Different item types, swapping.")
		_perform_swap(source_area, source_index, source_item, target_area, target_index, target_item)

func _perform_swap(area1: InventoryArea, index1: int, item1: ItemData, area2: InventoryArea, index2: int, item2: ItemData):
	if _set_item_data(area2, index2, item1):
		if _set_item_data(area1, index1, item2):
			# Emit signals for both changed slots
			_emit_change_signal(area1, index1, item2)
			_emit_change_signal(area2, index2, item1)
			_check_and_update_selected_slot(area1, index1, area2, index2, item2, item1) # Update selection if needed
		else: printerr("Swap Error: Failed setting slot 1.")
	else: printerr("Swap Error: Failed setting slot 2.")

func _check_and_update_selected_slot(s_area, s_idx, t_area, t_idx, final_s_item, final_t_item):
	print("Checking selection update: s_area=", s_area, " s_idx=", s_idx, " t_area=", t_area, " t_idx=", t_idx, " | current_selected=", selected_slot_index) # DEBUG
	var selection_changed = false
	var new_selected_item = null

	# Check if the original source was the selected hotbar slot
	if s_area == InventoryArea.HOTBAR and s_idx == selected_slot_index:
		selection_changed = true
		new_selected_item = final_s_item # Item that ended up in the source slot (should be null in this case)
		print("  -> Source was selected slot. New item for selected slot:", new_selected_item) # DEBUG

	# Check if the target was the selected hotbar slot (overwrites source check if true)
	if t_area == InventoryArea.HOTBAR and t_idx == selected_slot_index:
		selection_changed = true
		new_selected_item = final_t_item # Item that ended up in the target slot
		print("  -> Target was selected slot. New item for selected slot:", new_selected_item) # DEBUG

	# If the selection was affected, emit the signal
	if selection_changed:
		print("  -> Selection WAS affected. Emitting selected_slot_changed for index", selected_slot_index, " with item:", new_selected_item) # DEBUG
		emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, new_selected_item) # Use index twice as old/new index didn't change
	#else: # Debug
	#	print("  -> Selection NOT affected.") # DEBUG

func _emit_change_signal(area: InventoryArea, index: int, item_data: ItemData): # Ensure ItemData type hint
	print("Emitting change signal for:", area, "[", index, "]") # Debug
	if area == InventoryArea.HOTBAR:
		emit_signal("inventory_changed", index, item_data)
		# --- ADD SELECTION CHECK HERE ---
		# If the change happened TO the currently selected slot, we MUST update the player equip state.
		if index == selected_slot_index:
			print("  -> Change occurred in selected hotbar slot. Re-emitting selected_slot_changed.") # Debug
			# Emit the main signal the player listens to
			emit_signal("selected_slot_changed", selected_slot_index, selected_slot_index, item_data)
		# -------------------------------
	elif area == InventoryArea.MAIN:
		emit_signal("main_inventory_changed", index, item_data)
