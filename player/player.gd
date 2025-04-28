# player.gd
extends CharacterBody2D

const DebugItemResource = preload("res://items/consumable_potion_health.tres")

# Signals for HUD
signal health_changed(current_health: float, max_health: float)
signal dash_charges_changed(current_charges: int, max_charges: int)

enum State { IDLE_RUN, DASH, ATTACK }

# Stats
@export var max_health: float = 100.0
var current_health: float :
	set(value):
		var previous_health = current_health
		current_health = clampf(value, 0, max_health)
		if current_health != previous_health:
			emit_signal("health_changed", current_health, max_health)

@export var max_dashes: int = 3
@export var dash_recharge_time: float = 2.0 # Time in seconds to recharge ONE dash
# Removed dash_action_cooldown export
var _current_dashes: int

var current_dashes: int :
	get: return _current_dashes
	set(value):
		var previous_dashes = _current_dashes
		_current_dashes = clampi(value, 0, max_dashes)
		if _current_dashes != previous_dashes:
			emit_signal("dash_charges_changed", _current_dashes, max_dashes)

# Movement Variables
@export var speed: float = 100.0
@export var dash_speed: float = 350.0

# State Variables
var current_state: State = State.IDLE_RUN
var last_direction: Vector2 = Vector2.DOWN
var equipped_item_data: ItemData = null

# Node References
@onready var animated_sprite = $AnimatedSprite2D
@onready var dash_timer = $DashTimer # Dash duration
@onready var dash_recharge_timer = $DashRechargeTimer # Charge regeneration
@onready var equipped_item_sprite = $Hand/EquippedItemSprite
@onready var hud = get_tree().get_first_node_in_group("HUD")

func _ready():
	self.current_health = max_health
	self._current_dashes = max_dashes
	emit_signal("dash_charges_changed", _current_dashes, max_dashes)

	dash_recharge_timer.wait_time = dash_recharge_time
	# Removed setting wait_time for dash_action_cooldown_timer

	# Connect signals
	dash_timer.timeout.connect(_on_dash_timer_timeout)
	dash_recharge_timer.timeout.connect(_on_dash_recharge_timer_timeout)
	# Removed connection for dash_action_cooldown_timer.timeout
	animated_sprite.animation_finished.connect(_on_animation_finished)
	Inventory.selected_slot_changed.connect(_on_selected_slot_changed)

	_equip_item(Inventory.get_selected_item())

# --- Main Loop ---
func _physics_process(delta: float):
	# Check if inventory is open (needs access to HUD state or a global flag)
	var hud = get_node("/root/Main/HUD") # Example path, use a better method like groups or signals
	var is_inventory_open = false
	if hud and hud.has_method("is_inventory_open"): # Add is_inventory_open() to HUD.gd
		is_inventory_open = hud.is_inventory_open()

	# --- Handle Inventory Selection Input (Always Available) ---
	handle_inventory_input()

	# --- Handle Use Item Input (Only if inventory closed?) ---
	if not is_inventory_open and Input.is_action_just_pressed("use_item"):
		try_use_selected_item() # Call new function

	if not is_inventory_open:
		match current_state:
			State.IDLE_RUN:
				process_idle_run_state(delta)
				# Debug Inputs (Keep if needed)
				if Input.is_action_just_pressed("debug_damage"): take_damage(10)
				if Input.is_action_just_pressed("debug_heal"): heal(10)
				if Input.is_action_just_pressed("debug_add_item"):
					if DebugItemResource:
						# Important: DUPLICATE the resource so each add gets a unique instance
						# Otherwise changing quantity of one stack changes all!
						var new_item_instance = DebugItemResource.duplicate()
						# Set initial quantity if needed (or handle in add_item)
						new_item_instance.quantity = 1
						var success = Inventory.add_item(new_item_instance)
						if not success: print("Could not add debug item (inventory full?)")
					else:
						printerr("Debug item resource not loaded!")
			State.DASH:
				process_dash_state(delta)
			State.ATTACK:
				process_attack_state(delta)
		move_and_slide()
	else:
		# Optional: Decelerate player if inventory is open?
		velocity = velocity.move_toward(Vector2.ZERO, speed)
		move_and_slide() # Apply deceleration

# --- State Processing ---
func process_idle_run_state(delta: float):
	# Check for state transitions FIRST
	if Input.is_action_just_pressed("attack"):
		start_attack()
		return

	if Input.is_action_just_pressed("dash"):
		# Check only for available charges
		if current_dashes > 0:
			start_dash()
			return
		else:
			print("Out of dashes!") # Feedback

	# Handle standard movement input
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction != Vector2.ZERO:
		velocity = input_direction.normalized() * speed
		last_direction = input_direction.normalized()
		update_animation("run", last_direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed)
		update_animation("idle", last_direction)

func process_dash_state(delta: float):
	pass # Movement handled by move_and_slide

func process_attack_state(delta: float):
	velocity = Vector2.ZERO
	pass # State ends on animation finish

# --- Action Start Functions ---
func start_dash():
	self.current_dashes -= 1

	# Removed starting the action cooldown timer and setting the flag

	current_state = State.DASH
	velocity = last_direction * dash_speed
	update_animation("dash", last_direction)
	dash_timer.start() # Start dash duration

	# Start recharge timer if needed
	if dash_recharge_timer.is_stopped() and current_dashes < max_dashes:
		dash_recharge_timer.start()

func start_attack():
	# Keep existing logic
	var equipped_item = Inventory.get_selected_item()
	if current_state == State.IDLE_RUN and equipped_item != null:
		current_state = State.ATTACK
		update_animation("attack", last_direction)
		velocity = Vector2.ZERO
		print("Player attacks with:", equipped_item)
	elif equipped_item == null:
		print("No item equipped to attack with!")

# --- Stat Management (Keep take_damage, heal, die) ---
func take_damage(amount: float):
	self.current_health -= amount
	print("Player took damage, health:", current_health)
	if current_health <= 0: die()

func heal(amount: float) -> bool:
	var previous_health = current_health
	self.current_health += amount # Use the setter (which handles clamping & signal)
	var health_changed = (current_health > previous_health) # Check if health increased
	if health_changed:
		print("Player healed, health:", current_health)
	return health_changed # Return whether health actually changed

func die():
	print("Player has died!")
	queue_free()

func handle_inventory_input():
	# Cycle selection
	if Input.is_action_just_pressed("inventory_next"):
		Inventory.select_next_slot()
	if Input.is_action_just_pressed("inventory_previous"):
		Inventory.select_previous_slot()

	# Direct slot selection (Quick Select)
	if Input.is_action_just_pressed("inventory_slot_1"):
		Inventory.set_selected_slot(0) # Slot 1 corresponds to index 0
	if Input.is_action_just_pressed("inventory_slot_2"):
		Inventory.set_selected_slot(1)
	if Input.is_action_just_pressed("inventory_slot_3"):
		Inventory.set_selected_slot(2)
	if Input.is_action_just_pressed("inventory_slot_4"):
		Inventory.set_selected_slot(3)
	if Input.is_action_just_pressed("inventory_slot_5"):
		Inventory.set_selected_slot(4)
	if Input.is_action_just_pressed("inventory_slot_6"):
		Inventory.set_selected_slot(5)
	if Input.is_action_just_pressed("inventory_slot_7"):
		Inventory.set_selected_slot(6)
	if Input.is_action_just_pressed("inventory_slot_8"):
		Inventory.set_selected_slot(7)
	if Input.is_action_just_pressed("inventory_slot_9"):
		Inventory.set_selected_slot(8)

# --- Helper Functions (Keep update_animation) ---
func update_animation(action_prefix: String, direction: Vector2):
	var direction_name = ""
	if abs(direction.x) > abs(direction.y):
		direction_name = "right" if direction.x > 0 else "left"
	else:
		direction_name = "down" if direction.y > 0 else "up"
	var new_anim = action_prefix + "_" + direction_name
	if animated_sprite.animation != new_anim:
		animated_sprite.play(new_anim)

# --- Equipping (Keep _equip_item) ---
func _equip_item(item_data: ItemData):
	# Clear previous equip state first
	equipped_item_data = null
	if equipped_item_sprite: equipped_item_sprite.visible = false

	# Check if the new item is valid and equippable
	if item_data != null and item_data is ItemData and item_data.is_equippable():
		equipped_item_data = item_data
		if equipped_item_sprite:
			equipped_item_sprite.texture = item_data.texture
			equipped_item_sprite.visible = true
		print("Player equipped:", equipped_item_data.item_id)
	else:
		print("Player equipped nothing (or item not equippable).")

func try_use_selected_item():
	var selected_item: ItemData = Inventory.get_selected_item()

	if selected_item != null and selected_item is ItemData:
		match selected_item.item_type:
			ItemData.ItemType.CONSUMABLE:
				# Check if the specific consumable CAN be used *before* consuming
				if _can_use_consumable(selected_item):
					_consume_item(selected_item, Inventory.selected_slot_index)
				else:
					print("Cannot use '", selected_item.item_id, "' right now (e.g., health full).")
			# ... (other item types remain the same) ...
			ItemData.ItemType.WEAPON:
				print("Selected item is a weapon. Attack action is separate.")
			ItemData.ItemType.TOOL:
				print("Selected item is a tool. Use via interaction.")
			ItemData.ItemType.PLACEABLE:
				print("Selected item is placeable. Placement logic needed.")
			_:
				print("Selected item type cannot be 'used' directly:", ItemData.ItemType.keys()[selected_item.item_type])
	else:
		print("No item selected to use.")

func _can_use_consumable(item_data: ItemData) -> bool:
	if item_data == null or not item_data is ItemData: return false

	match item_data.item_id: # Check based on item ID
		"consumable_potion_health":
			# Can use health potion only if health is not full
			return current_health < max_health
		"potion_mana": # Example for another type
			# Assuming you have current_mana and max_mana variables
			# return current_mana < max_mana
			return true # Placeholder - always usable for now
		"scroll_speed": # Example buff
			# Check if speed buff is already active?
			# return not is_speed_buff_active
			return true # Placeholder - always usable for now
		_:
			# Default: Allow unknown consumables? Or deny? Let's allow for now.
			print("Consumable check: Unknown item_id '", item_data.item_id, "', assuming usable.")
			return true

func _consume_item(item_data: ItemData, hotbar_slot_index: int):
	print("Consuming:", item_data.item_id)

	# --- Apply Effect ---
	var effect_applied = false # Flag to track if any effect actually happened
	match item_data.item_id:
		"consumable_potion_health":
			var heal_value = item_data.get("heal_amount")
			if heal(heal_value): # Use the heal function which returns true if health actually changed
				effect_applied = true
		"potion_mana":
			# apply_mana_effect()
			effect_applied = true # Assume effect applies
		"scroll_speed":
			# apply_speed_buff()
			effect_applied = true # Assume effect applies
		_:
			print("No defined effect for consuming:", item_data.item_id)
			# Decide if unknown consumables should still be used up
			effect_applied = true # Let's assume yes for now

	# --- Decrease Quantity in Inventory ---
	var success = Inventory.decrease_item_quantity(Inventory.InventoryArea.HOTBAR, hotbar_slot_index, 1)
	if not success:
		printerr("Failed to decrease quantity after consuming item!")

# --- Signal Callbacks ---

func _on_dash_timer_timeout():
	# Dash duration finished
	velocity = Vector2.ZERO
	if current_state == State.DASH:
		current_state = State.IDLE_RUN
		update_animation("idle", last_direction)

func _on_dash_recharge_timer_timeout():
	# One charge regenerated
	print("Dash charge regenerated")
	self.current_dashes += 1
	if current_dashes < max_dashes:
		dash_recharge_timer.start()
	else:
		print("Dash charges full.")

# Removed _on_dash_action_cooldown_timer_timeout() function

func _on_animation_finished():
	# Keep existing attack animation logic
	if current_state == State.ATTACK and animated_sprite.animation.begins_with("attack_"):
		current_state = State.IDLE_RUN
		update_animation("idle", last_direction)

func _on_selected_slot_changed(new_index: int, old_index: int, item_data: ItemData):
	print("Player detected selected slot change. New Item:", item_data)
	_equip_item(item_data)
