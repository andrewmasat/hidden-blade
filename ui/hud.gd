# HUD.gd
extends CanvasLayer

const DashIconScene = preload("res://ui/dash_icon.tscn")

# Node References (Use unique names!)
@onready var health_bar = $UIContainer/MarginContainer/VBoxContainer/HealthBar # % shorthand requires Godot 4 and unique names in the scene tree branch
@onready var dash_charges_container = $UIContainer/MarginContainer/VBoxContainer/DashChargesContainer
@onready var hotbar_container = $UIContainer/MarginContainer/VBoxContainer/HotbarContainer
@onready var selection_indicator = $UIContainer/MarginContainer/VBoxContainer/HotbarContainer/SelectionIndicator

# Keep track of references to slot elements for easier updates
var slot_buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var slot_quantities: Array[Label] = [] # Uncomment if using quantity labels

var dash_icon_instances: Array[Control] = []

var player_node = null

func _ready():
	# --- Get references to hotbar elements ---
	for i in range(Inventory.HOTBAR_SIZE):
		var button = hotbar_container.get_node_or_null("SlotButton" + str(i)) as Button
		if button:
			var icon = button.get_node_or_null("ItemIcon") as TextureRect
			if icon:
				slot_buttons.append(button)
				slot_icons.append(icon)
				button.pressed.connect(_on_slot_button_pressed.bind(i))
			else: printerr("Missing ItemIcon in SlotButton", i)
		else: printerr("Missing SlotButton", i)

	# --- Connect to Player signals (requires Player emitting signals) ---
	await get_tree().process_frame # Wait for player to potentially be ready
	player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		print("HUD found player")
		# Connect standard signals
		if player_node.has_signal("health_changed"):
			player_node.health_changed.connect(_on_player_health_changed)

		# Connect NEW player signals for dash usage and recharge logic
		if player_node.has_signal("dash_charge_used"):
			player_node.dash_charge_used.connect(_on_player_dash_charge_used)
		# Connect the count changed signal
		if player_node.has_signal("dash_count_changed"):
			player_node.dash_count_changed.connect(_on_player_dash_count_changed)
		else:
			printerr("Player node missing 'dash_count_changed' signal!")

		# --- Initialize HUD based on Player's MAX values ---
		if player_node.has_method("get_max_dashes"):
			setup_dash_icons(player_node.get_max_dashes())
		else:
			printerr("Player node missing 'get_max_dashes' method")

		# Get initial state AFTER setting up icons
		if player_node.has_method("get_current_health") and player_node.has_method("get_max_health"):
			_on_player_health_changed(player_node.get_current_health(), player_node.get_max_health())

		# Sync initial dash icons based on current charges (assuming they start full)
		if player_node.has_method("get_current_dash_charges"):
			# Use the new reset function for initialization
			var initial_ready_count = player_node.get_current_dash_charges()
			print("HUD Ready: Initializing visuals for count:", initial_ready_count)
			for i in range(dash_icon_instances.size()):
				var icon = dash_icon_instances[i] as Control
				if i < initial_ready_count:
					if icon.has_method("show_ready_and_reset_timer"):
						icon.show_ready_and_reset_timer() # Use resetter for initial state
				else:
					# Assume initially unused slots are also ready visually but timer stopped
					if icon.has_method("show_ready_and_reset_timer"):
						icon.show_ready_and_reset_timer()

			# Alternatively, call the main update function if it handles this correctly
			# _update_dash_visuals(initial_ready_count)
		else:
			printerr("Player node missing 'get_current_dash_charges' method")

	else:
		printerr("HUD could not find player node in group 'player'")

	# --- Initialize Hotbar ---
	for i in range(Inventory.HOTBAR_SIZE):
		_on_inventory_changed(i, Inventory.get_item(i))
	_update_selection_indicator(Inventory.get_selected_slot_index())

func setup_dash_icons(max_charges: int):
	# Clear any existing icons first (important if max dashes can change)
	for icon in dash_icon_instances:
		icon.queue_free()
	dash_icon_instances.clear()

	# Instantiate and configure new icons
	for i in range(max_charges):
		var new_icon_instance = DashIconScene.instantiate() as Control
		dash_charges_container.add_child(new_icon_instance)
		dash_icon_instances.append(new_icon_instance)
		# Connect the icon's finished signal back to the HUD, passing its index
		new_icon_instance.recharge_finished.connect(_on_dash_icon_recharge_finished.bind(i))

func sync_dash_icons_visuals(current_available_charges: int):
	for i in range(dash_icon_instances.size()):
		var icon = dash_icon_instances[i]
		if i < current_available_charges:
			# This assumes icons not recharging are ready.
			# If an icon IS recharging, calling show_ready() here might interrupt it.
			# We need a more robust way if recharge can happen while count changes.
			# For now, let's assume this is called at init or when charges are added instantly.
			if icon.current_state != DashIcon.State.RECHARGING:
				icon.show_ready()
		else:
			# This charge is considered "used" but might be recharging or fully depleted
			# If it's not already recharging, ensure it looks "empty" (which show_ready handles initially)
			# Or potentially have an "empty" state visual distinct from "recharging"
			# For simplicity, let's assume recharge starts immediately on use.
			if icon.current_state == DashIcon.State.READY:
				# This state is awkward. A charge is missing but not recharging yet?
				# Let's assume this function is mostly for init. The use/recharge signals handle transitions.
				pass # Don't force it ready if it shouldn't be

# --- Signal Callback Functions ---

func _on_slot_button_pressed(index: int):
	Inventory.set_selected_slot(index) # Setter handles the signal emitting

func _on_inventory_changed(slot_index: int, item_data):
	if slot_index >= 0 and slot_index < slot_icons.size():
		if item_data:
			var texture = load(item_data) as Texture2D # Assumes string path
			slot_icons[slot_index].texture = texture
		else:
			slot_icons[slot_index].texture = null

func _on_selected_slot_changed(new_index: int, _old_index: int, _item_data):
	_update_selection_indicator(new_index)

func _on_player_health_changed(current_health: float, max_health: float):
	health_bar.max_value = max_health
	health_bar.value = current_health

func _on_player_dash_count_changed(ready_count: int):
	# This signal tells us how the OVERALL display should look
	print("HUD received dash_count_changed. Ready count:", ready_count)
	_update_dash_visuals(ready_count)

func _on_player_dash_charge_used(charge_index: int, recharge_duration: float):
	print("HUD received dash_charge_used for index:", charge_index)
	if charge_index >= 0 and charge_index < dash_icon_instances.size():
		# Tell the SPECIFIC icon instance to start recharging
		dash_icon_instances[charge_index].start_recharge(recharge_duration)
	else:
		printerr("Invalid charge_index received in HUD:", charge_index)

func _on_dash_icon_recharge_finished(charge_index: int):
	print("HUD received recharge_finished for index:", charge_index)
	# Tell the player they gained a charge back
	if player_node and player_node.has_method("gain_dash_charge"):
		player_node.gain_dash_charge(charge_index) # Player handles its internal count
	else:
		printerr("Cannot signal player dash charge gained!")

func _on_player_dash_charge_gained(charge_index: int):
	# Called if player gains a charge instantly (e.g., pickup)
	print("HUD received dash_charge_gained for index:", charge_index)
	if charge_index >= 0 and charge_index < dash_icon_instances.size():
		# Ensure the corresponding icon is shown as ready
		dash_icon_instances[charge_index].show_ready()

# --- Helper Functions ---

func _update_selection_indicator(index: int):
	if index >= 0 and index < slot_buttons.size():
		var target_button = slot_buttons[index]
		# Position indicator over the selected button
		selection_indicator.global_position = target_button.global_position
		selection_indicator.visible = true
	else:
		selection_indicator.visible = false # Hide if index is invalid (shouldn't happen often)

func _update_dash_visuals(ready_count: int):
	print("HUD updating visuals based on ready count:", ready_count)
	for i in range(dash_icon_instances.size()):
		var icon_instance = dash_icon_instances[i] as Control # Cast if needed
		var should_look_ready = (i < ready_count)

		if icon_instance.has_method("set_visual_state"):
			print(should_look_ready)
			icon_instance.set_visual_state(should_look_ready)
		else:
			printerr("DashIcon instance at index", i, " is missing set_visual_state method.")
