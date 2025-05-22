# UIInputHandler.gd
# Attached to a full-screen Control node (e.g., UIContainer).
# Handles detecting drops outside inventory slots (world drops)
# and clicks outside slots when holding a cursor item (e.g., after right-click split).
extends Control

var _world_drop_action_pending: bool = false
var _item_for_pending_world_drop: ItemData = null

# --- Drag and Drop Handling ---

# Determines if the dragged 'data' (originating from an InventorySlot)
# can be dropped onto this background control.
func _can_drop_data(at_position: Vector2, data) -> bool:
	return data is Dictionary and data.get("drag_type") == "inventory_item_on_cursor"


# Executes when an inventory item drag is released (dropped) onto this background control.
func _drop_data(at_position: Vector2, data) -> void: # For DRAG operations ending on background
	print("UIInputHandler: _drop_data triggered (World drop from DRAG).")

	# This IS the primary handler for drag-to-world.
	# Item was put on cursor by InventorySlot._get_drag_data
	var item_to_drop_now = Inventory.get_cursor_item() # This should be the item dragged

	if item_to_drop_now != null:
		# Set up for world drop, clear cursor, and mark action as handled
		_item_for_pending_world_drop = item_to_drop_now
		_world_drop_action_pending = true # Mark that a world drop needs to happen
		Inventory.clear_cursor_item() # Clear the client's cursor immediately
		print("UIInputHandler _drop_data: Local cursor cleared. World drop action is pending.")
	else:
		printerr("UIInputHandler _drop_data: Cursor was already empty at DnD drop!")

	accept_event() # Consume the DnD drop event fully

	# Let _process or a timer handle the pending drop to avoid re-entrancy
	# For simplicity, let's try _process first.
	# If _process doesn't work well, a short one-shot timer is an option.
	# No, _process is bad for input-triggered things. Let's try deferred call.
	if _world_drop_action_pending:
		call_deferred("_execute_pending_world_drop")


func _execute_pending_world_drop():
	if not _world_drop_action_pending or not is_instance_valid(_item_for_pending_world_drop):
		_world_drop_action_pending = false # Reset if item became invalid
		_item_for_pending_world_drop = null
		return

	print("UIInputHandler: Executing deferred world drop for:", _item_for_pending_world_drop.item_id)
	var local_player = SceneManager.player_node
	if is_instance_valid(local_player) and local_player.is_multiplayer_authority():
		if local_player.has_method("handle_world_drop"):
			local_player.handle_world_drop(_item_for_pending_world_drop, DroppedItem.DropMode.GLOBAL, 0)
		# else: printerr(...)
	# else: printerr(...)

	_world_drop_action_pending = false # Reset flag
	_item_for_pending_world_drop = null

# --- Input Handling ---

# Handles input events, primarily for detecting clicks outside slots
# when holding an item from a non-drag source (like right-click split).
func _input(event: InputEvent) -> void:
	# This _input now ONLY handles NON-DRAG world drops (e.g., after right-click split)
	if _world_drop_action_pending: # If a DnD drop is being processed, ignore other clicks
		# print("UIInputHandler _input: Ignoring input, world drop action pending from DnD.")
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var item_on_cursor = Inventory.get_cursor_item()
		var drag_data_at_release = get_viewport().gui_get_drag_data() # Check if Godot DnD just ended

		# This path is for clicking on world with item from SPLIT (drag_data_at_release should be null)
		if item_on_cursor != null and drag_data_at_release == null:
			var release_pos = get_global_mouse_position()
			var control_under_mouse = _find_control_at_position(release_pos)
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
				print("UIInputHandler _input: World Drop from CURSOR item (Non-Drag/Split Release) detected.")
				var local_player = SceneManager.player_node # ... (get local player with authority) ...
				if is_instance_valid(local_player) and local_player.is_multiplayer_authority():
					var data_for_drop = item_on_cursor
					Inventory.clear_cursor_item() # Clear LOCAL cursor
					local_player.handle_world_drop(data_for_drop, DroppedItem.DropMode.GLOBAL, 0)
					get_viewport().set_input_as_handled()
				else:
					printerr("UIInputHandler _input: Could not find valid LOCAL player node for cursor item world drop!")
					Inventory.clear_cursor_item()
					get_viewport().set_input_as_handled()
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
