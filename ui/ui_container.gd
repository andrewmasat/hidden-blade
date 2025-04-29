# UIInputHandler.gd
extends Control # Make sure it inherits from Control

# We might still need access to the HUD script for things like is_inventory_open()
@onready var hud = get_node("/root/Main/HUD") # Adjust path as needed, or use groups/signals

func _input(event):
	# Check for left mouse button release
	if event is InputEventMouseButton and \
	   event.button_index == MOUSE_BUTTON_LEFT and \
	   not event.pressed:

		var item_on_cursor = Inventory.get_cursor_item()
		if item_on_cursor != null:
			# Get the control directly under the mouse at the release point
			var release_pos = get_global_mouse_position() # This works in Control node

			# Use the recursive function to find the topmost Control under the mouse
			# Start search from the viewport's root Control node for broad coverage
			# Note: get_viewport().get_gui_focus_owner() might be too narrow if nothing has focus
			# A safer starting point might be the HUD node itself or this container node.
			var control_under_mouse = _find_control_recursive(self, release_pos) # Start search from this container
			
			print(control_under_mouse)
			if control_under_mouse != null:
				print("DEBUG: Control found under mouse: Name=", control_under_mouse.name, ", Type=", control_under_mouse.get_class(), ", Is Slot=", control_under_mouse is InventorySlot)
			else:
				print("DEBUG: No control found under mouse.")

			# Check if the control found (if any) is an InventorySlot
			var drop_target_is_slot_or_panel = false # Flag if drop is on valid UI target
			if control_under_mouse != null:
				var current_control = control_under_mouse
				while current_control != null:
					if current_control is InventorySlot:
						drop_target_is_slot_or_panel = true
						print("DEBUG: Drop target is InventorySlot") # Debug
						break
					# OPTIONAL: Allow dropping onto the panel background itself to cancel/do nothing?
					# Requires reference to inventory_panel node (e.g., via hud reference)
					if hud and current_control == hud.inventory_panel:
						drop_target_is_slot_or_panel = true
						print("DEBUG: Drop target is InventoryPanel background") # Debug
						break

					# Stop checking if we hit the main UI container or HUD base
					if current_control == self or current_control == hud: break

					current_control = current_control.get_parent_control()

			# If the drop did NOT land on a slot (or the panel background, if enabled)...
			if not drop_target_is_slot_or_panel:
				print("UIInputHandler detected drop outside valid UI target while holding:", item_on_cursor.item_id)
				# Tell the player to handle the world drop
				var player = get_tree().get_first_node_in_group("player")
				if player and player.has_method("handle_world_drop"):
					player.handle_world_drop(item_on_cursor)
					Inventory.clear_cursor_item()
					get_viewport().set_input_as_handled() # Consume event
				else:
					printerr("UIInputHandler: Could not find player or handle_world_drop method!")
					Inventory.clear_cursor_item() # Clear cursor anyway
					get_viewport().set_input_as_handled() # Still consume
			else:
				# Optional Debug: Log if drop was handled by UI
				print("DEBUG: Drop likely handled by UI target:", control_under_mouse.name if control_under_mouse else "None")
				pass # Let the InventorySlot's _drop_data handle it


# Recursive helper to find topmost visible control at position
# Note: This is still potentially complex. Consider simpler checks first.
func _find_control_recursive(node: Node, global_pos: Vector2) -> Control:
	if not is_instance_valid(node): return null # Check if node is valid

	var found_control: Control = null

	# Check children first (topmost visually)
	var children = node.get_children()
	# CORRECTED LOOPING ON REVERSED ARRAY:
	children.reverse() # Reverse in-place
	for child in children: # Now iterate on the reversed array
		var found_in_child = _find_control_recursive(child, global_pos)
		if found_in_child:
			found_control = found_in_child
			break # Found in child, stop searching siblings lower in reversed list

	# If not found in children, check the node itself
	if not found_control and node is Control:
		var control_node = node as Control
		# Check visibility AND mouse filter AND if point is inside
		if control_node.visible and \
		   control_node.get_global_rect().has_point(global_pos) and \
		   control_node.get_mouse_filter() != Control.MOUSE_FILTER_IGNORE:
			found_control = control_node

	return found_control


func _ready():
	# Make this control cover the whole screen and process input
	mouse_filter = MOUSE_FILTER_PASS # Allow input to pass through unless handled
	# Ensure it processes input when inventory is open - maybe link visibility to panel?
	# Or just let it always run and check cursor item != null inside _input
	# Ensure the UI Container itself fills the rect
	anchor_right = 1.0
	anchor_bottom = 1.0
