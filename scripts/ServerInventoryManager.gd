# ServerInventoryManager.gd
extends Node

# Dictionary to hold inventories for each player
# Structure: { peer_id: {"hotbar": Array[ItemData], "main": Array[ItemData]} }
var player_inventories: Dictionary = {}

# Constants from your Inventory.gd (or reference Inventory.gd directly if preferred and safe)
const HOTBAR_SIZE = 9 # Or Inventory.HOTBAR_SIZE if Inventory.gd is also an autoload on server
const INVENTORY_SIZE = 32 # Or Inventory.INVENTORY_SIZE (COLS * ROWS)

# Signal that the server can emit if other server systems need to know about an inventory change.
# This is for server-internal communication, not for clients directly from here.
signal server_player_inventory_updated(peer_id: int, area: Inventory.InventoryArea, slot_index: int, item_data: ItemData)


func _ready():
	if multiplayer.is_server():
		print("ServerInventoryManager: Initialized on server.")
		if NetworkManager:
			NetworkManager.player_connected.connect(_on_player_connected)
			NetworkManager.player_disconnected.connect(_on_player_disconnected)
		else:
			printerr("ServerInventoryManager (Server): NetworkManager Autoload not found!")
	else:
		print("ServerInventoryManager: Initialized on client. Will not manage inventories.")
		# Clients might still use this for helper functions if any are made common,
		# but core data management is server-side.

# --- Player Inventory Management ---

func _on_player_connected(peer_id: int):
	if not multiplayer.is_server(): return # Guard
	if not player_inventories.has(peer_id):
		print("ServerInventoryManager: Initializing inventory for new player: ", peer_id)
		player_inventories[peer_id] = {
			"hotbar": [],
			"main": []
		}
		player_inventories[peer_id]["hotbar"].resize(HOTBAR_SIZE)
		player_inventories[peer_id]["hotbar"].fill(null)
		player_inventories[peer_id]["main"].resize(INVENTORY_SIZE)
		player_inventories[peer_id]["main"].fill(null)
		# TODO: Here you would load the player's saved inventory from a database if implementing persistence.
		# For now, they start with an empty inventory.
	else:
		print("ServerInventoryManager: Player ", peer_id, " reconnected (inventory should already exist or be loaded).")


func _on_player_disconnected(peer_id: int):
	if not multiplayer.is_server(): return # Guard
	if player_inventories.has(peer_id):
		print("ServerInventoryManager: Player ", peer_id, " disconnected.")
		# TODO: Here you would save the player's inventory to a database.
		# For now, we might keep it in memory if they could reconnect to same session,
		# or clear it if sessions are not persistent across disconnects.
		# Let's clear it for simplicity in a non-persistent setup for now.
		# player_inventories.erase(peer_id) 
		# print("ServerInventoryManager: Inventory for player ", peer_id, " cleared from memory.")
		# OR, if you want it to persist for a server session:
		print("ServerInventoryManager: Inventory for player ", peer_id, " remains in memory on disconnect.")


func get_player_inventory_area_slots(peer_id: int, area: Inventory.InventoryArea) -> Array:
	if not multiplayer.is_server(): # This function is for server to get server-authoritative data
		printerr("ServerInventoryManager: get_player_inventory_area_slots called on client. This is likely an error.")
		return []
	if not player_inventories.has(peer_id):
		printerr("ServerInventoryManager: No inventory found for peer_id: ", peer_id)
		return [] # Return empty array to prevent crashes

	var p_inv = player_inventories[peer_id]
	if area == Inventory.InventoryArea.HOTBAR:
		return p_inv["hotbar"]
	elif area == Inventory.InventoryArea.MAIN:
		return p_inv["main"]
	
	printerr("ServerInventoryManager: Invalid inventory area specified for peer_id: ", peer_id)
	return []


func _set_player_slot_item(peer_id: int, area: Inventory.InventoryArea, slot_index: int, item_data: ItemData):
	if not multiplayer.is_server(): return false # Guard
	var slots = get_player_inventory_area_slots(peer_id, area)
	if slot_index >= 0 and slot_index < slots.size():
		slots[slot_index] = item_data
		# Emit server-internal signal if needed by other server systems
		emit_signal("server_player_inventory_updated", peer_id, area, slot_index, item_data)
		# Server will then need to RPC this change to the specific client (peer_id)
		_notify_client_of_slot_update(peer_id, area, slot_index, item_data)
		return true
	printerr("ServerInventoryManager: Invalid slot_index ", slot_index, " for area ", area, " for peer ", peer_id)
	return false

# --- Core Authoritative Inventory Operations (called by other server scripts) ---

func add_item_to_player_inventory(peer_id: int, item_data_to_add: ItemData) -> bool:
	if not multiplayer.is_server(): return false # Guard
	if not player_inventories.has(peer_id) or not item_data_to_add is ItemData:
		printerr("ServerInventoryManager: Cannot add item. No inventory for peer ", peer_id, " or invalid item_data.")
		return false

	var item_id = item_data_to_add.item_id
	var p_inv = player_inventories[peer_id]

	# --- Try stacking in Hotbar ---
	var hotbar_slots_ref = p_inv["hotbar"]
	var target_index = _find_first_stackable_slot_in_array(hotbar_slots_ref, item_id)
	if target_index != -1:
		return _try_add_quantity_to_player_slot(peer_id, Inventory.InventoryArea.HOTBAR, target_index, item_data_to_add)

	# --- Try stacking in Main Inventory ---
	var main_slots_ref = p_inv["main"]
	target_index = _find_first_stackable_slot_in_array(main_slots_ref, item_id)
	if target_index != -1:
		return _try_add_quantity_to_player_slot(peer_id, Inventory.InventoryArea.MAIN, target_index, item_data_to_add)

	# --- Try empty slot in Hotbar ---
	target_index = _find_first_empty_slot_in_array(hotbar_slots_ref)
	if target_index != -1:
		var new_item_instance = item_data_to_add.duplicate() # Server gets its own instance
		_set_player_slot_item(peer_id, Inventory.InventoryArea.HOTBAR, target_index, new_item_instance)
		return true

	# --- Try empty slot in Main Inventory ---
	target_index = _find_first_empty_slot_in_array(main_slots_ref)
	if target_index != -1:
		var new_item_instance = item_data_to_add.duplicate()
		_set_player_slot_item(peer_id, Inventory.InventoryArea.MAIN, target_index, new_item_instance)
		return true

	print("ServerInventoryManager: All inventories full for peer ", peer_id, ", cannot add item: ", item_id)
	return false

func place_item_onto_slot_from_cursor_like_source(peer_id: int, item_from_cursor_source: ItemData, 
												 target_area: Inventory.InventoryArea, target_index: int):
	if not multiplayer.is_server(): return
	if not player_inventories.has(peer_id) or not is_instance_valid(item_from_cursor_source):
		printerr("SIM: Invalid args for place_item_onto_slot_from_cursor_like_source for peer ", peer_id)
		return

	print("SIM: Peer [", peer_id, "] placing '", item_from_cursor_source.item_id, "' Qty ", item_from_cursor_source.quantity, " onto ", Inventory.InventoryArea.keys()[target_area], "[", target_index, "]")

	var target_slots = get_player_inventory_area_slots(peer_id, target_area)
	if target_index < 0 or target_index >= target_slots.size():
		printerr("  -> SIM: Invalid target_index ", target_index)
		# TODO: Notify client of failure (e.g. item "returns" to cursor or original spot)
		return

	var item_in_target_slot = target_slots[target_index] # This is a reference to the ItemData in server's array

	# Case 1: Target slot is empty
	if item_in_target_slot == null:
		print("  -> SIM: Target empty. Placing directly.")
		_set_player_slot_item(peer_id, target_area, target_index, item_from_cursor_source.duplicate()) # Server places a duplicate
		# The "cursor item" on client is now considered placed. Server doesn't have a cursor item.
		# We need to tell the client its cursor is now empty.
		_notify_client_of_cursor_item_update(peer_id, null) # New RPC needed
		return

	# Case 2: Target slot has SAME item type (try merging)
	if item_in_target_slot.item_id == item_from_cursor_source.item_id:
		print("  -> SIM: Target same type. Attempting merge.")
		var can_add_to_target = item_in_target_slot.max_stack_size - item_in_target_slot.quantity
		var amount_to_transfer = mini(item_from_cursor_source.quantity, can_add_to_target)

		if amount_to_transfer > 0:
			item_in_target_slot.quantity += amount_to_transfer
			item_from_cursor_source.quantity -= amount_to_transfer
			_set_player_slot_item(peer_id, target_area, target_index, item_in_target_slot) # Update target slot
			
			if item_from_cursor_source.quantity <= 0: # Cursor source fully merged
				_notify_client_of_cursor_item_update(peer_id, null)
			else: # Cursor source still has items
				_notify_client_of_cursor_item_update(peer_id, item_from_cursor_source)
			return
		else:
			print("  -> SIM: Target stack full. No merge possible (item remains on conceptual cursor).")
			# Item remains on "cursor". Client's cursor item doesn't change yet.
			# Or, if no swap, server tells client placement failed.
			# For now, assume no swap if types are same but stack is full.
			return

	# Case 3: Target slot has DIFFERENT item type (swap)
	print("  -> SIM: Target different type. Swapping.")
	var item_that_was_in_slot = item_in_target_slot.duplicate() # Duplicate for the "new cursor"
	_set_player_slot_item(peer_id, target_area, target_index, item_from_cursor_source.duplicate()) # Place cursor item in slot
	_notify_client_of_cursor_item_update(peer_id, item_that_was_in_slot) # Put old slot item on client's cursor


func split_player_stack_to_cursor_like_destination(peer_id: int, source_area: Inventory.InventoryArea, source_index: int):
	if not multiplayer.is_server(): return
	if not player_inventories.has(peer_id): return

	var source_slots = get_player_inventory_area_slots(peer_id, source_area)
	if source_index < 0 or source_index >= source_slots.size():
		printerr("SIM: Invalid source_index for split for peer ", peer_id)
		return

	var item_in_source_slot = source_slots[source_index]
	if not is_instance_valid(item_in_source_slot) or item_in_source_slot.quantity <= 1:
		print("  -> SIM: Cannot split. Slot empty or quantity <= 1 for peer ", peer_id)
		# No change, so no client notification needed unless to explicitly deny.
		return

	print("SIM: Peer [", peer_id, "] splitting '", item_in_source_slot.item_id, "' from ", Inventory.InventoryArea.keys()[source_area], "[", source_index, "]")

	var quantity_to_move_to_cursor = ceili(float(item_in_source_slot.quantity) / 2.0)
	var quantity_remaining_in_slot = item_in_source_slot.quantity - quantity_to_move_to_cursor

	var new_cursor_item_instance = item_in_source_slot.duplicate()
	new_cursor_item_instance.quantity = quantity_to_move_to_cursor

	if quantity_remaining_in_slot > 0:
		item_in_source_slot.quantity = quantity_remaining_in_slot
		_set_player_slot_item(peer_id, source_area, source_index, item_in_source_slot) # Update source slot
	else: # Should not happen if original quantity > 1 and ceili(q/2) is used.
		_set_player_slot_item(peer_id, source_area, source_index, null) # Source slot becomes empty
		
	_notify_client_of_cursor_item_update(peer_id, new_cursor_item_instance) # Tell client about new cursor item


func _notify_client_of_cursor_item_update(peer_id_to_notify: int, cursor_item_data: ItemData):
	if not multiplayer.is_server(): return

	if not multiplayer.has_multiplayer_peer():
		printerr("SIM: No multiplayer peer, cannot send RPC for cursor update.")
		return

	# Check if the target peer is currently connected
	var is_target_connected = false
	if peer_id_to_notify == multiplayer.get_unique_id(): # Target is self (server/host)
		is_target_connected = true 
	else:
		var connected_peers = multiplayer.get_peers() # Gets an array of connected peer IDs
		if connected_peers.has(peer_id_to_notify):
			is_target_connected = true

	if is_target_connected:
		print("SIM: Notifying client ", peer_id_to_notify, " of cursor item update.")

		var item_path = ""
		var item_id = ""
		var item_qty = 0
		if is_instance_valid(cursor_item_data):
			item_path = cursor_item_data.resource_path
			item_id = cursor_item_data.item_id
			item_qty = cursor_item_data.quantity
		
		var inventory_node_path = "/root/Inventory" # Client's Inventory.gd
		var local_inv_ref = get_node_or_null(inventory_node_path) # Server's local ref to its own Inventory Autoload
		if is_instance_valid(local_inv_ref):
			local_inv_ref.rpc_id(
				peer_id_to_notify, 
				"client_receive_cursor_item_update", 
				item_path, 
				item_id, 
				item_qty
			)
		else:
			printerr("SIM: Could not find local /root/Inventory to initiate cursor RPC.")
	else:
		print("SIM: Peer ", peer_id_to_notify, " not connected for cursor update RPC.")

func _try_add_quantity_to_player_slot(peer_id: int, area: Inventory.InventoryArea, index: int, item_data_to_add: ItemData) -> bool:
	if not multiplayer.is_server(): return false # Guard
	var slots = get_player_inventory_area_slots(peer_id, area)
	if index < 0 or index >= slots.size(): return false
	
	var target_item: ItemData = slots[index]
	if not target_item or target_item.item_id != item_data_to_add.item_id:
		printerr("ServerInventoryManager _try_add_quantity: Target slot mismatch or empty for peer ", peer_id)
		return false

	var can_add = target_item.max_stack_size - target_item.quantity
	var amount_to_add = mini(item_data_to_add.quantity, can_add)

	if amount_to_add > 0:
		target_item.quantity += amount_to_add
		item_data_to_add.quantity -= amount_to_add 
		
		_set_player_slot_item(peer_id, area, index, target_item) # Update and notify client

		if item_data_to_add.quantity > 0: # If source quantity remains
			return add_item_to_player_inventory(peer_id, item_data_to_add) # Try adding the rest

		return true
	return false


func get_player_item_quantity_by_id(peer_id: int, item_id_to_find: String) -> int:
	if not multiplayer.is_server(): # Server-side query of authoritative data
		# Client should query its own local Inventory.gd for display purposes
		printerr("ServerInventoryManager: get_player_item_quantity_by_id called on client. This is likely an error.")
		return 0

	if not player_inventories.has(peer_id) or item_id_to_find.is_empty():
		return 0

	var total_quantity: int = 0
	var p_inv = player_inventories[peer_id]

	for item_data in p_inv["hotbar"]:
		if item_data is ItemData and item_data.item_id == item_id_to_find:
			total_quantity += item_data.quantity
	for item_data in p_inv["main"]:
		if item_data is ItemData and item_data.item_id == item_id_to_find:
			total_quantity += item_data.quantity
			
	return total_quantity


func remove_item_from_player_inventory_by_id_and_quantity(peer_id: int, item_id_to_remove: String, quantity_to_remove: int) -> bool:
	if not multiplayer.is_server(): return false # Guard
	if not player_inventories.has(peer_id) or item_id_to_remove.is_empty() or quantity_to_remove <= 0:
		return false

	var quantity_actually_removed: int = 0
	var target_qty_to_remove = quantity_to_remove
	var p_inv = player_inventories[peer_id]

	# Pass 1: Hotbar
	var hotbar_slots_ref = p_inv["hotbar"]
	for i in range(hotbar_slots_ref.size()):
		var item_data = hotbar_slots_ref[i]
		if item_data is ItemData and item_data.item_id == item_id_to_remove:
			var amount_to_take = mini(target_qty_to_remove - quantity_actually_removed, item_data.quantity)
			if amount_to_take > 0:
				item_data.quantity -= amount_to_take
				quantity_actually_removed += amount_to_take
				if item_data.quantity <= 0:
					_set_player_slot_item(peer_id, Inventory.InventoryArea.HOTBAR, i, null)
				else:
					_set_player_slot_item(peer_id, Inventory.InventoryArea.HOTBAR, i, item_data)
			if quantity_actually_removed >= target_qty_to_remove: return true
	
	# Pass 2: Main Inventory
	var main_slots_ref = p_inv["main"]
	for i in range(main_slots_ref.size()):
		var item_data = main_slots_ref[i]
		if item_data is ItemData and item_data.item_id == item_id_to_remove:
			var amount_to_take = mini(target_qty_to_remove - quantity_actually_removed, item_data.quantity)
			if amount_to_take > 0:
				item_data.quantity -= amount_to_take
				quantity_actually_removed += amount_to_take
				if item_data.quantity <= 0:
					_set_player_slot_item(peer_id, Inventory.InventoryArea.MAIN, i, null)
				else:
					_set_player_slot_item(peer_id, Inventory.InventoryArea.MAIN, i, item_data)
			if quantity_actually_removed >= target_qty_to_remove: return true

	if quantity_actually_removed < target_qty_to_remove:
		printerr("ServerInventoryManager: Failed to remove full quantity of '", item_id_to_remove, "' for peer ", peer_id, ". Requested: ", target_qty_to_remove, ", Removed: ", quantity_actually_removed)
		# TODO: Rollback logic for partial removal if strict transactions are needed.
		return false
		
	return true


# --- Helper functions for array operations (could be static in Inventory.gd too) ---
func _find_first_empty_slot_in_array(slots_array: Array) -> int:
	for i in range(slots_array.size()):
		if slots_array[i] == null: return i
	return -1

func _find_first_stackable_slot_in_array(slots_array: Array, item_id_to_stack: String) -> int:
	for i in range(slots_array.size()):
		var existing_item: ItemData = slots_array[i]
		if existing_item != null and \
		   existing_item.item_id == item_id_to_stack and \
		   not existing_item.is_stack_full():
			return i
	return -1


# --- Client Notification (SERVER ONLY LOGIC TO INITIATE) ---
func _notify_client_of_slot_update(peer_id_to_notify: int, area: Inventory.InventoryArea, slot_index: int, item_data: ItemData):
	if not multiplayer.is_server(): return

	if not multiplayer.has_multiplayer_peer():
		printerr("ServerInventoryManager: No multiplayer peer configured for MultiplayerAPI, cannot send RPC for slot update.")
		return

	# Check if the target peer is currently connected
	var is_target_connected = false
	if peer_id_to_notify == multiplayer.get_unique_id(): # Target is self (server/host)
		is_target_connected = true 
	else:
		var connected_peers = multiplayer.get_peers() # Gets an array of connected peer IDs
		if connected_peers.has(peer_id_to_notify):
			is_target_connected = true
			
	if is_target_connected:
		print("ServerInventoryManager: Notifying client ", peer_id_to_notify, " of update to ", Inventory.InventoryArea.keys()[area], "[", slot_index, "]")

		var item_data_path_to_send = ""
		var item_id_to_send = ""
		var quantity_to_send = 0

		if item_data is ItemData:
			item_data_path_to_send = item_data.resource_path
			item_id_to_send = item_data.item_id
			quantity_to_send = item_data.quantity
			if item_data_path_to_send.is_empty() and not item_id_to_send.is_empty():
				print("ServerInventoryManager: Item '", item_id_to_send, "' has no resource_path. Client will reconstruct from ID.")

		var target_node_path_on_client = "/root/Inventory"
		var local_inventory_node_ref = get_node_or_null(target_node_path_on_client) 
		if is_instance_valid(local_inventory_node_ref):
			local_inventory_node_ref.rpc_id(
				peer_id_to_notify, 
				"client_receive_slot_update", 
				area, 
				slot_index, 
				item_data_path_to_send, 
				item_id_to_send, 
				quantity_to_send
			)
		else:
			printerr("ServerInventoryManager: Could not find local /root/Inventory node to initiate RPC. This should not happen for an autoload.")
	else:
		print("ServerInventoryManager: Peer ", peer_id_to_notify, " not connected or invalid state for RPC. Cannot send slot update.")
