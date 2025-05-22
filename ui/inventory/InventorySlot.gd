# InventorySlot.gd
# Represents a single slot UI element within an inventory grid or hotbar.
# Handles displaying item info, user interaction (clicks, right-clicks),
# and initiating/receiving drag-and-drop operations related to the Inventory singleton.
extends Button # Inheriting Button provides click signals and focus handling

class_name InventorySlot

# Time threshold in milliseconds to detect a double-click.
const DOUBLE_CLICK_THRESHOLD_MSEC: int = 300

# --- Node References ---
# Assumes ItemIcon and QuantityLabel are direct children named this way in the scene.
@onready var icon_rect: TextureRect = $ItemIcon
@onready var quantity_label: Label = $QuantityLabel
# Assuming the direct parent is always the GridContainer managing this slot.
# Becomes unreliable if the hierarchy changes. Consider alternatives if needed.
@onready var grid_container: Container = get_parent() as Container
# Optional: Get HUD reference if needed for context checks (like panel visibility).
# Use get_tree().get_first_node_in_group("HUD") for reliability across scenes.
@onready var hud = get_tree().get_first_node_in_group("HUD") if get_tree() else null


# --- Exported Variables ---
# Currently unused as we removed the official drag preview. Keep if needed later.
# @export var drag_preview_size := Vector2(40, 40)


# --- Slot State ---
# Index of this slot within its inventory area. Must be set externally.
var slot_index: int = -1
# The area this slot belongs to (e.g., MAIN inventory or HOTBAR). Must be set externally.
var inventory_area: Inventory.InventoryArea = Inventory.InventoryArea.MAIN
# Timestamp of the last potential first click for double-click detection.
var last_click_time_msec: int = 0


# Called when the node is ready. Connects signals.
func _ready() -> void:
	# Connect the Button's built-in signal for completed clicks.
	self.pressed.connect(_on_InventorySlot_pressed)

	# Optional safety check for HUD reference if needed by _handle_double_click
	if not hud and inventory_area == Inventory.InventoryArea.HOTBAR:
		print("InventorySlot Warning [Hotbar ", slot_index, "]: HUD node not found. Double-click transfer to main inventory might not work.")


# Updates the slot's visual display based on ItemData.
func display_item(item_data: ItemData) -> void:
	if item_data != null and item_data is ItemData:
		# Display item texture
		if is_instance_valid(icon_rect):
			icon_rect.texture = item_data.texture
			icon_rect.visible = true
		# Display quantity label only if item stacks and quantity > 1
		if is_instance_valid(quantity_label):
			if item_data.max_stack_size > 1 and item_data.quantity > 1:
				quantity_label.text = str(item_data.quantity)
				quantity_label.visible = true
			else:
				quantity_label.text = ""
				quantity_label.visible = false
	else:
		# Clear display if item_data is null
		clear()


# Clears the item texture and quantity label.
func clear() -> void:
	if is_instance_valid(icon_rect):
		icon_rect.texture = null
		icon_rect.visible = false
	if is_instance_valid(quantity_label):
		quantity_label.text = ""
		quantity_label.visible = false


# Handles specific GUI input events, primarily right-clicks and the first part of double-clicks.
func _gui_input(event: InputEvent) -> void:
	# Handle Right-Click for splitting stacks
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if Inventory.get_cursor_item() == null:
			print(" -> Slot [", slot_index, "] Right-click detected for split.") # Debug
			Inventory.split_stack_to_cursor(inventory_area, slot_index)
			accept_event()
		return

	# Handle Left-Click Press ONLY for immediate placement if cursor has item
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Inventory.get_cursor_item() != null:
			print("  -> Slot [", slot_index, "] Processing immediate place click (pressed) from _gui_input.") # DEBUG
			Inventory.place_cursor_item_on_slot(inventory_area, slot_index)
			accept_event() # Consume the placement press
			return
		# If cursor empty, DO NOTHING HERE on press. Let the 'pressed' signal handle it.


# Called AFTER a full Press+Release click completes on this Button node.
# Handles placing items from cursor or double-click actions.
func _on_InventorySlot_pressed() -> void:
	print("Slot [", slot_index, "] _on_InventorySlot_pressed signal triggered.") # Debug

	# Check cursor state first. If an item is held, this click places it.
	var item_on_cursor = Inventory.get_cursor_item()
	if item_on_cursor != null:
		print("  -> Slot [", slot_index, "] Processing place click via pressed signal.") # Debug
		Inventory.place_cursor_item_on_slot(inventory_area, slot_index)
		# Placement complete, ensure last click time is reset so next click isn't double
		last_click_time_msec = 0
		return # Action completed

	# --- Double-Click / Single Click Logic ---
	# Cursor is empty, process single/double click on the slot itself
	var current_time_msec = Time.get_ticks_msec()
	var time_diff = current_time_msec - last_click_time_msec
	var item_in_this_slot = Inventory.get_item_data(inventory_area, slot_index)

	# Check if it's the SECOND click (time difference is small)
	if item_in_this_slot != null and time_diff < DOUBLE_CLICK_THRESHOLD_MSEC:
		# Make sure the first click was actually recorded (last_click_time_msec != 0)
		if last_click_time_msec != 0:
			print("  -> Slot [", slot_index, "] Double-click completed. Handling transfer.") # DEBUG
			_handle_double_click() # Call the transfer logic
			last_click_time_msec = 0 # Reset time after handling double-click
		# else: # First click ever, time diff is huge negative, ignore
			# print("  -> Slot [", slot_index, "] Ignoring potential double click on first ever click.")

	else:
		# --- This is the FIRST completed click (or second was too slow) ---
		print("  -> Slot [", slot_index, "] Recording time for potential double-click.") # DEBUG
		# Record the time of THIS click completion
		last_click_time_msec = current_time_msec
		# If this slot is in the hotbar, select it on the first click.
		if inventory_area == Inventory.InventoryArea.HOTBAR:
			print("  -> Slot [", slot_index, "] Single click on Hotbar slot - Selecting.") # Debug
			Inventory.set_selected_slot(slot_index)
		# else: # Single click on main inventory slot - no specific action besides recording time
			# print("  -> Slot [", slot_index, "] Single click completed (Main Inv / Slow Double / Empty).") # Debug


# Handles the logic for transferring items on double-click.
func _handle_double_click() -> void:
	var item_data: ItemData = Inventory.get_item_data(inventory_area, slot_index)
	if not item_data is ItemData: return

	print("Handling double click transfer for slot:", slot_index, "Area:", inventory_area) # Debug

	if inventory_area == Inventory.InventoryArea.MAIN:
		Inventory.transfer_to_hotbar(inventory_area, slot_index)
	elif inventory_area == Inventory.InventoryArea.HOTBAR:
		var is_panel_open = hud and hud.has_method("is_inventory_open") and hud.is_inventory_open()
		if is_panel_open:
			Inventory.transfer_to_main_inventory(inventory_area, slot_index)
		# else: print(" -> Cannot transfer from hotbar, panel closed")


# --- Drag and Drop Methods ---

# Called by the engine when a drag is initiated FROM this control.
func _get_drag_data(_at_position: Vector2):
	# Prevent starting a drag if an item is already held on the cursor.
	if Inventory.get_cursor_item() != null:
		print("Slot [", slot_index, "] _get_drag_data: Cannot start drag, item on cursor.") # Debug
		return null

	# Get the item currently in this slot.
	var item_in_slot = Inventory.get_item_data(inventory_area, slot_index)

	# Only proceed if there's an item to drag.
	if item_in_slot != null:
		print("Slot [", slot_index, "] _get_drag_data: Starting drag.") # Debug
		# Move the item from the slot to the inventory's cursor state immediately.
		var item_put_on_cursor = Inventory.remove_item_and_put_on_cursor(inventory_area, slot_index)

		# If moving to cursor failed for some reason, abort the drag.
		if item_put_on_cursor == null:
			printerr("Slot [", slot_index, "] _get_drag_data: Failed to move item to cursor.")
			return null

		# Return minimal data just to initiate the drag state.
		# The actual item state is now managed via the cursor.
		# Rely on CursorItemDisplay for visual feedback during drag.
		return { "drag_type": "inventory_item_on_cursor" }
	else:
		# Cannot drag an empty slot.
		# print("Slot [", slot_index, "] _get_drag_data: Slot is empty, cannot drag.") # Debug
		return null


# Called by the engine to check if data from a drag operation can be dropped ONTO this control.
func _can_drop_data(_at_position: Vector2, data) -> bool:
	# Accept the drop only if an item is currently held on the cursor
	# AND the drag data payload indicates it's the correct type of drag operation.
	var can_drop = Inventory.get_cursor_item() != null and \
				   data is Dictionary and \
				   data.get("drag_type") == "inventory_item_on_cursor"
	# print("Slot [", slot_index, "] _can_drop_data: Check result:", can_drop) # Debug
	return can_drop


# Called by the engine when a drag operation successfully drops data ONTO this control.
func _drop_data(_at_position: Vector2, _data) -> void:
	# The item to be placed is already on the cursor (moved there by _get_drag_data).
	# Call the Inventory function to handle placing/swapping/merging at this slot's location.
	print("Slot [", slot_index, "] _drop_data: Calling place_cursor_item_on_slot.") # Debug
	Inventory.place_cursor_item_on_slot(inventory_area, slot_index)
	# The Inventory function handles clearing the cursor and emitting necessary signals.
	accept_event() # Consume the drop event so it doesn't propagate further.
