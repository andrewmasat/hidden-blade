# InventorySlot.gd
extends Button

class_name InventorySlot

const DOUBLE_CLICK_THRESHOLD_MSEC = 300

@onready var icon_rect = $ItemIcon
@onready var quantity_label = $QuantityLabel
@onready var hud = get_tree().get_first_node_in_group("HUD") if get_tree() else null

@export var drag_preview_size := Vector2(40, 40)

# Optional: Store the index this slot represents
var slot_index: int = -1
var inventory_area: Inventory.InventoryArea = Inventory.InventoryArea.MAIN
var last_click_time_msec: int = 0

func _ready():
	# Safety check for HUD reference
	if not hud:
		print("InventorySlot Warning: HUD node not found in group 'HUD'. Double-click transfer from hotbar might not work.")

func display_item(item_data: ItemData): # Use ItemData type hint
	if item_data != null and item_data is ItemData: # Check type
		icon_rect.texture = item_data.texture # Get texture from ItemData
		icon_rect.visible = true
		# Display quantity if > 1 (or always if > 0, your choice)
		if item_data.quantity > 1:
			quantity_label.text = str(item_data.quantity)
			quantity_label.visible = true
		else:
			quantity_label.text = ""
			quantity_label.visible = false
	else:
		clear()

func clear():
	icon_rect.texture = null
	icon_rect.visible = false
	quantity_label.text = ""
	quantity_label.visible = false

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		# --- Left Click ---
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if holding an item on cursor FIRST
			if Inventory.get_cursor_item() != null:
				# Try to place the item here
				Inventory.place_cursor_item_on_slot(inventory_area, slot_index)
				accept_event() # Consume the click event
				return # Don't process double-click or drag start

			# --- If not placing cursor item, check for double-click ---
			var current_time_msec = Time.get_ticks_msec()
			var time_diff = current_time_msec - last_click_time_msec
			if time_diff < DOUBLE_CLICK_THRESHOLD_MSEC:
				# Double-click detected!
				_handle_double_click() # Handles transfer logic
				last_click_time_msec = 0 # Reset time
				accept_event() # Consume the event
			else:
				# First click (or too slow), record time for potential double-click later
				last_click_time_msec = current_time_msec
				# DO NOT accept_event() here, let DnD check it

		# --- Right Click ---
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Try to split the stack in this slot
			Inventory.split_stack_to_cursor(inventory_area, slot_index)
			accept_event() # Consume the right-click

func _handle_double_click():
	# Check type just in case
	var item_data: ItemData = Inventory.get_item_data(inventory_area, slot_index)
	if not item_data is ItemData: return # Cannot transfer null or wrong type

	if inventory_area == Inventory.InventoryArea.MAIN:
		Inventory.transfer_to_hotbar(inventory_area, slot_index)
	elif inventory_area == Inventory.InventoryArea.HOTBAR:
		var is_panel_open = false
		if hud and hud.has_method("is_inventory_open"):
			is_panel_open = hud.is_inventory_open()
		if is_panel_open:
			Inventory.transfer_to_main_inventory(inventory_area, slot_index)
		# else: print("Cannot transfer from hotbar, panel closed")

# --- Drag and Drop Methods ---

func _get_drag_data(at_position: Vector2):
	# Prevent drag if holding item on cursor OR if double-click just happened
	if Inventory.get_cursor_item() != null: return null
	var current_time_msec = Time.get_ticks_msec()
	if current_time_msec - last_click_time_msec < 50: return null

	# Get item data from the central inventory
	var item_data = Inventory.get_item_data(inventory_area, slot_index)

	# Only allow dragging if there's an item
	if item_data != null:
		# Prepare data package for drop target
		var drag_data = {
			"source_area": inventory_area,
			"source_index": slot_index,
			"item_data": item_data
		}

		# Create drag preview (simple icon)
		var preview_container = Control.new()
		preview_container.size = drag_preview_size
		preview_container.clip_contents = false

		var preview_icon = TextureRect.new()
		preview_icon.texture = item_data.texture
		preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Let the icon fill the container
		preview_icon.size = preview_container.size
		preview_icon.position = Vector2.ZERO # Position at top-left of container
		preview_container.add_child(preview_icon)

		if item_data.quantity > 1:
			var preview_label = Label.new()
			preview_label.text = str(item_data.quantity)

			# Set label size to match container for alignment purposes
			preview_label.size = preview_container.size

			# Align text to bottom-right within the label's bounds
			preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			preview_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

			# --- Styling (Adjust as needed) ---
			preview_label.add_theme_font_size_override("font_size", 14) # Adjust size as needed
			preview_label.add_theme_color_override("font_color", Color.WHITE)
			preview_label.add_theme_color_override("font_shadow_color", Color.BLACK)
			preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
			preview_label.add_theme_constant_override("outline_offset_y", 2)
			preview_label.add_theme_constant_override("outline_size", 5)
			preview_label.add_theme_constant_override("shadow_outline_size", 1)
			# --- End Styling ---

			preview_container.add_child(preview_label)

		preview_container.z_index = 100
		set_drag_preview(preview_container)
		return drag_data
	else:
		print("Cannot drag empty slot: ", Inventory.InventoryArea.keys()[inventory_area], "[", slot_index, "]")
		return null # No drag starts if slot is empty

func _can_drop_data(at_position: Vector2, data) -> bool:
	# Check if data includes ItemData resource
	return data is Dictionary and \
		   data.has("source_area") and \
		   data.has("source_index") and \
		   data.has("item_data") and \
		   data["item_data"] is ItemData # Verify type

func _drop_data(at_position: Vector2, data):
	# Simple swap logic (using the potentially updated move_item)
	Inventory.move_item(
		data["source_area"],
		data["source_index"],
		inventory_area,
		slot_index
	)
