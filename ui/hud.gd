# HUD.gd
extends CanvasLayer

const InventorySlotScene = preload("res://ui/inventory/inventory_slot.tscn")

# Node References (Use unique names!)
@onready var health_bar = $UIContainer/MarginContainer/VBoxContainer/HealthBar # % shorthand requires Godot 4 and unique names in the scene tree branch
@onready var hotbar_container = $UIContainer/MarginContainer/VBoxContainer/HotbarContainer
@onready var selection_indicator = $UIContainer/MarginContainer/VBoxContainer/HotbarContainer/SelectionIndicator
@onready var inventory_panel = $InventoryPanel

# Keep track of references to slot elements for easier updates
var slot_buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var hotbar_slot_instances: Array[Control] = []
# var slot_quantities: Array[Label] = [] # Uncomment if using quantity labels
var inventory_open: bool = false
var previous_mouse_mode = Input.get_mouse_mode()

# Store dash icon texture to reuse
@export var dash_icon_texture: Texture2D

func _ready():
	# --- Setup Hotbar ---
	setup_hotbar_slots() # Call new setup function

	if inventory_panel:
		inventory_panel.visible = false
		inventory_panel.close_requested.connect(close_inventory)
	else:
		printerr("HUD Error: InventoryPanel node not found!")
	previous_mouse_mode = Input.get_mouse_mode()

	# --- Connect to Global Inventory signals ---
	Inventory.inventory_changed.connect(_on_hotbar_inventory_changed)
	Inventory.selected_slot_changed.connect(_on_selected_slot_changed)

	# --- Connect to Player signals (Requires Player emitting signals) ---
	# Need a way to find the player. Using groups is common.
	# Wait a frame to ensure player might be ready.
	await get_tree().process_frame # Or use call_deferred
	var player = get_tree().get_first_node_in_group("player") # Assumes Player is in group "player"
	if player:
		# Connect signals (These need to be defined in Player.gd!)
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_player_health_changed)
	else:
		printerr("HUD could not find player node in group 'player'")

	# --- Initialize HUD state ---
	# Update hotbar from inventory
	for i in range(Inventory.HOTBAR_SIZE):
		_on_hotbar_inventory_changed(i, Inventory.get_item_from_hotbar(i))
	# Set initial selection indicator position
	_update_selection_indicator(Inventory.get_selected_slot_index())

func _unhandled_input(event):
	# Handle Toggle Key
	if event.is_action_pressed("toggle_inventory"):
		toggle_inventory_panel()
		get_viewport().set_input_as_handled()
	# Handle Esc Key ONLY if inventory is currently open
	elif inventory_open and event.is_action_pressed("ui_cancel"):
		close_inventory() # Use the centralized close function
		get_viewport().set_input_as_handled()

func setup_hotbar_slots():
	# Assuming hotbar_container already has InventorySlot scene instances named HotbarSlot0, HotbarSlot1 etc.
	# If not, you'd instantiate them here like in InventoryPanel
	for i in range(Inventory.HOTBAR_SIZE):
		var slot_node = hotbar_container.get_node_or_null("HotbarSlot" + str(i)) as Control # Cast to Control or InventorySlot script type
		if slot_node:
			# Set the crucial info for DnD
			if slot_node.has_method("set"): # Check if script variables exist before setting
				slot_node.set("slot_index", i)
				slot_node.set("inventory_area", Inventory.InventoryArea.HOTBAR)
			else:
				printerr("Hotbar slot", i, " instance missing script variables (slot_index/inventory_area)")

			hotbar_slot_instances.append(slot_node)
			# Connect button press signal (still needed for click-selection)
			if slot_node is Button: # Check if it's actually a button
				slot_node.pressed.connect(_on_hotbar_slot_button_pressed.bind(i))
		else:
			printerr("Error finding HotbarSlot node for index", i)

func toggle_inventory_panel():
	if inventory_open:
		close_inventory()
	else:
		open_inventory()

func open_inventory():
	if not inventory_panel: return
	if inventory_open: return # Already open

	inventory_open = true
	inventory_panel.show_panel()
	previous_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Inventory opened.")


func close_inventory():
	if not inventory_panel: return
	if not inventory_open: return # Already closed

	inventory_open = false
	inventory_panel.hide_panel()
	Input.set_mouse_mode(previous_mouse_mode)
	print("Inventory closed.")

func is_inventory_open() -> bool:
	return inventory_open

# --- Signal Callback Functions ---

func _on_hotbar_slot_button_pressed(index: int):
	Inventory.set_selected_slot(index)

func _on_hotbar_inventory_changed(slot_index: int, item_data: ItemData): # Add ItemData type hint
	if slot_index >= 0 and slot_index < hotbar_slot_instances.size():
		var slot_node = hotbar_slot_instances[slot_index]
		if slot_node and slot_node.has_method("display_item"):
			slot_node.display_item(item_data) # Pass ItemData or null

func _on_selected_slot_changed(new_index: int, old_index: int, item_data):
	_update_selection_indicator(new_index)

func _on_player_health_changed(current_health: float, max_health: float):
	health_bar.max_value = max_health
	health_bar.value = current_health
	print("HUD: Health updated to", current_health, "/", max_health)


# --- Helper Functions ---

func _update_selection_indicator(index: int):
	if index >= 0 and index < hotbar_slot_instances.size():
		# Position indicator over the selected slot instance
		selection_indicator.global_position = hotbar_slot_instances[index].global_position
		selection_indicator.visible = true
	else:
		selection_indicator.visible = false
