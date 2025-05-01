# InventoryPanel.gd
# Manages the main inventory grid UI, displaying items and handling hover effects.
extends PanelContainer

class_name InventoryPanel

# Signal emitted when the user clicks the close button.
signal close_requested

# Preload the scene for individual inventory slots. Adjust path if necessary.
const InventorySlotScene = preload("res://ui/inventory/InventorySlot.tscn")

# --- Node References ---
# Using shorter paths assumes this script is attached to InventoryPanel node
# and the children have these names. Adjust if structure differs.
# Consider using Godot 4's %UniqueName syntax if nodes have unique names set in the scene.
@onready var grid_container: GridContainer = $MarginContainer/PanelLayout/Inventory/InventoryGrid
@onready var close_button: Button = $MarginContainer/PanelLayout/CloseButton
@onready var hover_indicator: TextureRect = $MarginContainer/PanelLayout/Inventory/HoverIndicator # Path to indicator (sibling of grid)

# --- State Variables ---
# Holds references to the instantiated InventorySlot scenes within the grid.
var slot_instances: Array[InventorySlot] = [] # Use specific type hint if InventorySlot has class_name
# Index of the currently hovered slot (-1 means no slot is hovered).
var highlighted_index: int = -1

# Called when the node is added to the scene tree.
func _ready() -> void:
	# Ensure the slot scene is loaded correctly
	if not InventorySlotScene:
		printerr("InventoryPanel Error: InventorySlotScene could not be preloaded!")
		return # Prevent further errors

	# Connect signals from UI elements and global Inventory
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_button_pressed)
	else:
		printerr("InventoryPanel Error: CloseButton node not found or invalid!")

	# Connect grid mouse exit AFTER populating grid
	if is_instance_valid(grid_container):
		grid_container.mouse_exited.connect(_on_grid_mouse_exited)
	else:
		printerr("InventoryPanel Error: GridContainer node not found or invalid!")

	_populate_grid()

	# Connect AFTER populating grid
	# Assuming Inventory autoload exists and has this signal
	if Inventory.has_signal("main_inventory_changed"):
		Inventory.main_inventory_changed.connect(_on_main_inventory_changed)
	else:
		printerr("InventoryPanel Warning: Inventory autoload or 'main_inventory_changed' signal not found.")

	# Display initial item state from the Inventory singleton
	_update_all_slots()
	# Ensure indicator starts hidden
	_update_highlight_visuals()

# Creates and populates the grid with InventorySlot instances.
func _populate_grid() -> void:
	if not is_instance_valid(grid_container): return # Safety check

	# Clear any existing slots from the grid container BEFORE adding new ones.
	# This is safer than iterating and checking types. Assumes HoverIndicator is NOT a child.
	for child in grid_container.get_children():
		child.queue_free() # Remove old slots if any exist
	slot_instances.clear() # Clear the reference array

	# Instantiate and configure slots based on Inventory size constants
	for i in range(Inventory.INVENTORY_SIZE):
		var slot_instance = InventorySlotScene.instantiate()
		# Check if instantiation worked and if it's the expected type (Control or InventorySlot)
		if slot_instance is Control: # Basic check, use 'is InventorySlot' if class_name is set
			var slot = slot_instance as Control # Cast for setting properties if needed

			# Set the crucial info for the slot's internal logic (index and area)
			if slot.has_method("set"): # Use has_method for safety before calling set
				slot.set("slot_index", i)
				slot.set("inventory_area", Inventory.InventoryArea.MAIN)
			else:
				# This indicates the InventorySlot script might be missing or changed.
				printerr("Inventory Panel: Instantiated slot", i, " missing script or 'set' method.")

			grid_container.add_child(slot)
			slot_instances.append(slot) # Store reference

			# Connect mouse signals for hover effect
			# Use bind() to pass the slot index 'i' to the callback functions
			# Check if signals exist before connecting for robustness
			if slot.has_signal("mouse_entered"):
				slot.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
			if slot.has_signal("mouse_exited"):
				slot.mouse_exited.connect(_on_slot_mouse_exited.bind(i))
		else:
			printerr("Inventory Panel: Failed to instantiate InventorySlotScene for index", i)


# --- Highlight Management ---

# Sets the currently highlighted slot index and updates the visual indicator.
func set_highlighted_index(new_index: int) -> void:
	# Clamp index to valid range (-1 for none, 0 to size-1 for slots)
	new_index = clamp(new_index, -1, Inventory.INVENTORY_SIZE - 1)

	# Update only if the index has actually changed
	if new_index != highlighted_index:
		highlighted_index = new_index
		_update_highlight_visuals()


# Updates the position and visibility of the hover indicator based on highlighted_index.
func _update_highlight_visuals() -> void:
	if not is_instance_valid(hover_indicator): return # Safety check

	if highlighted_index != -1 and highlighted_index < slot_instances.size():
		var target_slot = slot_instances[highlighted_index]
		# Ensure the target slot node is still valid before accessing it
		if is_instance_valid(target_slot):
			# Position the indicator over the target slot using global coordinates
			var offset = Vector2.ZERO # Adjust if visual offset is needed
			hover_indicator.global_position = target_slot.global_position + offset
			hover_indicator.visible = true
			# Z Index (set in editor) handles drawing order
		else:
			# Target slot became invalid unexpectedly, hide indicator
			printerr("InventoryPanel: Target slot instance [", highlighted_index, "] is invalid for highlighting!")
			hover_indicator.visible = false
			highlighted_index = -1 # Reset highlighted index
	else:
		# Hide indicator if index is -1 (no hover) or invalid
		hover_indicator.visible = false


# --- UI Control ---

# Makes the inventory panel visible.
func show_panel() -> void:
	_update_all_slots() # Refresh items before showing
	visible = true      # Set root visibility (should cascade to children)
	set_highlighted_index(-1) # Start with no slot highlighted
	# Use call_deferred for positioning in case layout needs to settle
	call_deferred("_update_highlight_visuals")


# Hides the inventory panel.
func hide_panel() -> void:
	visible = false     # Set root visibility
	set_highlighted_index(-1) # Ensure highlight is cleared


# --- Signal Callbacks ---

# Called when the Inventory singleton signals a change in the main inventory data.
func _on_main_inventory_changed(slot_index: int, item_data: ItemData) -> void:
	# Update the specific slot that changed
	if slot_index >= 0 and slot_index < slot_instances.size():
		var slot_node = slot_instances[slot_index]
		# Check node validity and method existence before calling
		if is_instance_valid(slot_node) and slot_node.has_method("display_item"):
			slot_node.display_item(item_data)
			# slot_node.queue_redraw() # Removed - Add back ONLY if visual updates lag


# Called when the mouse cursor enters the bounding box of an InventorySlot.
func _on_slot_mouse_entered(index: int) -> void:
	set_highlighted_index(index) # Highlight the slot the mouse is over


# Called when the mouse cursor exits the bounding box of an InventorySlot.
func _on_slot_mouse_exited(index: int) -> void:
	# Only clear the highlight if the mouse is exiting the *currently* highlighted slot.
	# This prevents flickering if the mouse moves quickly between adjacent slots.
	if highlighted_index == index:
		set_highlighted_index(-1)


# Called when the mouse cursor exits the bounding box of the entire GridContainer.
func _on_grid_mouse_exited() -> void:
	# Clear the highlight regardless of which slot was highlighted before.
	set_highlighted_index(-1)


# Called when the close button is pressed.
func _on_close_button_pressed() -> void:
	emit_signal("close_requested") # Notify parent (HUD) to close the panel


# --- Helper Functions ---

# Updates the display of all slots, fetching data from the Inventory singleton.
func _update_all_slots() -> void:
	if Inventory == null:
		printerr("InventoryPanel Error: Inventory singleton not available!")
		return
	for i in range(slot_instances.size()):
		var slot_node = slot_instances[i]
		if is_instance_valid(slot_node) and slot_node.has_method("display_item"):
			# Get data for the corresponding slot in the MAIN inventory area
			var item_data = Inventory.get_item_data(Inventory.InventoryArea.MAIN, i)
			slot_node.display_item(item_data)
