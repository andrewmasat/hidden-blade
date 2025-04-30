# UIInputHandler.gd
# Attached to a full-screen Control node (e.g., UIContainer).
# Handles detecting drops outside inventory slots (world drops)
# and clicks outside slots when holding a cursor item (e.g., after right-click split).
extends Control

# Optional: Reference to HUD if needed for context (like checking if panel is open).
# Consider using signals or groups instead of direct node paths for better decoupling.
# @onready var hud = get_node("/root/Main/HUD") # Example path


# --- Drag and Drop Handling ---

# Determines if the dragged 'data' (originating from an InventorySlot)
# can be dropped onto this background control.
func _can_drop_data(at_position: Vector2, data) -> bool:
	# Allow dropping if the data indicates it's an inventory item drag.
	# This prevents the "forbidden" cursor icon when dragging over the background.
	var is_inventory_drag = data is Dictionary and data.get("drag_type") == "inventory_item_on_cursor"
	# print("UIInputHandler _can_drop_data:", is_inventory_drag) # Debug
	return is_inventory_drag


# Executes when an inventory item drag is released (dropped) onto this background control.
func _drop_data(at_position: Vector2, data) -> void:
	# This signifies a "world drop" initiated via drag-and-drop.
	print("UIInputHandler: _drop_data triggered (World drop from drag).") # Debug

	# The actual item being dragged is on the Inventory cursor.
	var item_on_cursor = Inventory.get_cursor_item()

	if item_on_cursor != null:
		# Find the player and tell them to handle the drop action.
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("handle_world_drop"):
			player.handle_world_drop(item_on_cursor)
			Inventory.clear_cursor_item() # Clear cursor after successful drop
		else:
			printerr("UIInputHandler _drop_data: Player/handle_world_drop not found!")
			Inventory.clear_cursor_item() # Clear cursor anyway on error
	else:
		# This indicates a state mismatch - DnD completed but cursor was already empty.
		printerr("UIInputHandler _drop_data: Drop detected but cursor item is null!")

	# No need to call accept_event() here; the DnD system handles it via _drop_data.


# --- Input Handling ---

# Handles input events, primarily for detecting clicks outside slots
# when holding an item from a non-drag source (like right-click split).
func _input(event: InputEvent) -> void:
	# Check for Left Mouse Button RELEASE.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:

		# Check if we are CURRENTLY holding an item (e.g., from a right-click split).
		var item_on_cursor = Inventory.get_cursor_item()
		# Check if a drag operation was JUST completed in this frame.
		# If gui_get_drag_data() returns non-null here, it means a DnD operation
		# likely concluded (either successfully on a slot/background or failed).
		var drag_data_at_release = get_viewport().gui_get_drag_data()

		# --- Handle World Drop from Non-Drag Cursor Item ---
		# Only proceed if:
		# 1. An item IS on the cursor.
		# 2. A drag operation did NOT just conclude (drag_data is null).
		if item_on_cursor != null and drag_data_at_release == null:
			var release_pos = get_global_mouse_position()
			# Check what's under the mouse at release point.
			var control_under_mouse = _find_control_at_position(release_pos) # Use helper

			# Determine if the click landed on a slot or panel background.
			var on_valid_ui_target = false
			if control_under_mouse != null:
				var current = control_under_mouse
				while current != null:
					if current is InventorySlot: # or current == hud.inventory_panel: # Optional check
						on_valid_ui_target = true
						break
					if current == self: break # Stop if we reach this background node
					current = current.get_parent_control()

			# If the release was NOT on a slot/panel, trigger world drop for the cursor item.
			if not on_valid_ui_target:
				print("UIInputHandler _input: World Drop from CURSOR item (Non-Drag Release) detected.") # Debug
				var player = get_tree().get_first_node_in_group("player")
				if player and player.has_method("handle_world_drop"):
					player.handle_world_drop(item_on_cursor)
					Inventory.clear_cursor_item()
					# Consume this specific input event, as we handled it directly.
					get_viewport().set_input_as_handled()
				else:
					printerr("UIInputHandler _input: Player/handle_world_drop not found!")
					Inventory.clear_cursor_item() # Clear cursor on error
					get_viewport().set_input_as_handled() # Consume anyway
			# else: The release was on a slot/panel, let that control handle it via its own input/signals.


# --- Initialization ---

# Called when the node is added to the scene tree.
func _ready() -> void:
	# Ensure this control covers the screen to detect background clicks/drops.
	anchor_right = 1.0
	anchor_bottom = 1.0
	# Allow mouse events to pass through to controls underneath unless handled here.
	mouse_filter = MOUSE_FILTER_PASS


# --- Helper Function ---

# Recursively finds the topmost visible, interactive Control node at a global position.
func _find_control_at_position(global_pos: Vector2) -> Control:
	# Start search from self downwards.
	return _find_control_recursive(self, global_pos)


# Recursive helper implementation.
func _find_control_recursive(node: Node, global_pos: Vector2) -> Control:
	if not is_instance_valid(node): return null

	var potential_hit: Control = null

	# Check children first in reverse visual order
	var children = node.get_children()
	children.reverse() # Modify in-place
	for child in children:
		var found_in_child = _find_control_recursive(child, global_pos)
		if found_in_child:
			# Only consider child hit if it's interactive (not Ignore filter)
			if found_in_child.get_mouse_filter() != Control.MOUSE_FILTER_IGNORE:
				potential_hit = found_in_child
				break # Found topmost interactive child

	# If no interactive child found, check this node itself
	if not potential_hit and node is Control:
		var control_node = node as Control
		# Check visibility, point inside, AND if interactive
		if control_node.visible and \
		   control_node.get_global_rect().has_point(global_pos) and \
		   control_node.get_mouse_filter() != Control.MOUSE_FILTER_IGNORE:
			potential_hit = control_node

	return potential_hit
