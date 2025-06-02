# HUD.gd
extends CanvasLayer

const InventorySlotScene = preload("res://ui/inventory/InventorySlot.tscn")

# Node References (Use unique names!)
@onready var health_bar = $UIContainer/MarginContainer/VBoxContainer/HealthBar # % shorthand requires Godot 4 and unique names in the scene tree branch
@onready var hotbar_container = $UIContainer/MarginContainer/VBoxContainer/Hotbar/HotbarContainer
@onready var selection_indicator = $UIContainer/MarginContainer/VBoxContainer/Hotbar/SelectionIndicator
@onready var inventory_panel = $UIContainer/InventoryPanel
@onready var crafting_menu_instance = $UIContainer/CraftingMenuInstance

@onready var interaction_prompt_label = $UIContainer/MarginContainer/VBoxContainer/Hotbar/KeyboardShortcuts/Use


# Keep track of references to slot elements for easier updates
var slot_buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var hotbar_slot_instances: Array[Control] = []
# var slot_quantities: Array[Label] = [] # Uncomment if using quantity labels
var inventory_open: bool = false
var crafting_menu_open: bool = false
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
	if not is_instance_valid(crafting_menu_instance):
		printerr("HUD Error: CraftingMenuInstance node not found!")
	else:
		crafting_menu_instance.visible = false # Ensure hidden
	previous_mouse_mode = Input.get_mouse_mode()

	# --- Connect to Global Inventory signals ---
	Inventory.inventory_changed.connect(_on_hotbar_inventory_changed)
	Inventory.selected_slot_changed.connect(_on_selected_slot_changed)

	# --- Connect to Player signals (Requires Player emitting signals) ---
	await get_tree().process_frame

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

	if event.is_action_pressed("toggle_inventory"):
		if crafting_menu_open: # If crafting is open, inventory key closes it
			close_crafting_menu()
		else:
			toggle_inventory_panel() # Original inventory toggle
		get_viewport().set_input_as_handled()
	
	elif event.is_action_pressed("toggle_crafting_menu"): # New input action
		toggle_crafting_menu()
		get_viewport().set_input_as_handled()

	elif inventory_open and event.is_action_pressed("ui_cancel"): # Esc for inventory
		close_inventory()
		get_viewport().set_input_as_handled()
	
	elif crafting_menu_open and event.is_action_pressed("ui_cancel"): # Esc for crafting
		close_crafting_menu()
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

func toggle_crafting_menu():
	if crafting_menu_open:
		close_crafting_menu()
	else:
		open_crafting_menu()

func open_crafting_menu():
	if not is_instance_valid(crafting_menu_instance): return
	if crafting_menu_open: return

	# Close main inventory if it's open
	if inventory_open:
		close_inventory()

	crafting_menu_open = true
	crafting_menu_instance.open_menu() # Call the menu's own open function
	previous_mouse_mode = Input.get_mouse_mode() # Store current mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("HUD: Crafting menu opened.")

func close_crafting_menu():
	if not is_instance_valid(crafting_menu_instance): return
	if not crafting_menu_open: return

	crafting_menu_open = false
	crafting_menu_instance.close_menu() # Call the menu's own close function
	Input.set_mouse_mode(previous_mouse_mode) # Restore previous mouse mode
	print("HUD: Crafting menu closed.")

func is_crafting_menu_open() -> bool:
	return crafting_menu_open

func show_generic_interaction_prompt(text: String) -> void:
	if is_instance_valid(interaction_prompt_label):
		interaction_prompt_label.text = text
		interaction_prompt_label.visible = true
	else:
		printerr("HUD: InteractionPromptLabel node not found!")

func hide_generic_interaction_prompt() -> void:
	if is_instance_valid(interaction_prompt_label):
		interaction_prompt_label.visible = false
	# else: It's fine if it's not found when trying to hide, might already be null

# --- Signal Callback Functions ---

func _on_hotbar_slot_button_pressed(index: int):
	Inventory.set_selected_slot(index)

func _on_hotbar_inventory_changed(slot_index: int, item_data: ItemData): # Add ItemData type hint
	if slot_index >= 0 and slot_index < hotbar_slot_instances.size():
		var slot_node = hotbar_slot_instances[slot_index]
		if slot_node and slot_node.has_method("display_item"):
			slot_node.display_item(item_data)
			slot_node.queue_redraw() # <--- ADD THIS

func _on_selected_slot_changed(new_index: int, _old_index: int, _item_data):
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

func assign_player_and_connect_signals(p_player_node: Player):
	if not is_instance_valid(p_player_node):
		printerr("HUD: assign_player_and_connect_signals called with invalid player_node.")
		return
	
	print("HUD: assign_player_and_connect_signals CALLED with player: ", p_player_node)

	# Connect signals (These need to be defined in Player.gd!)
	if p_player_node.has_signal("health_changed"):
		p_player_node.health_changed.connect(_on_player_health_changed)
	# else: printerr("HUD: Player missing expected signals.")

	# Update HUD with initial player values (Requires getter methods in Player.gd)
	if p_player_node.has_method("get_current_health") and p_player_node.has_method("get_max_health"):
		_on_player_health_changed(p_player_node.get_current_health(), p_player_node.get_max_health())
	
	# --- Connection for Crafting Result ---
	if is_instance_valid(p_player_node) and is_instance_valid(crafting_menu_instance): # Ensure both nodes exist
		if p_player_node.has_signal("crafting_attempt_completed"):
			if crafting_menu_instance.has_method("handle_server_crafting_result"):
				# Check if already connected to prevent duplicate connections if this func is called multiple times
				if not p_player_node.is_connected("crafting_attempt_completed", Callable(crafting_menu_instance, "handle_server_crafting_result")):
					var err = p_player_node.crafting_attempt_completed.connect(crafting_menu_instance.handle_server_crafting_result)
					if err == OK:
						print("HUD: SUCCESSFULLY Connected Player.crafting_attempt_completed to CraftingMenu.handle_server_crafting_result")
					else:
						printerr("HUD: FAILED to connect Player.crafting_attempt_completed. Error: ", err)
				else:
					print("HUD: Crafting signal already connected.")
			else:
				printerr("HUD Error: CraftingMenuInstance '", crafting_menu_instance.name, "' is missing 'handle_server_crafting_result' method.")
		else:
			printerr("HUD Error: PlayerNode '", p_player_node.name, "' is missing 'crafting_attempt_completed' signal.")
	else:
		if not is_instance_valid(p_player_node): printerr("HUD Error: PlayerNode is invalid for crafting signal connection.")
		if not is_instance_valid(crafting_menu_instance): printerr("HUD Error: CraftingMenuInstance is invalid for crafting signal connection.")
