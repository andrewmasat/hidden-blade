# player.gd
extends CharacterBody2D

const DebugItemResource = preload("res://items/consumable_potion_health.tres")
const DroppedItemScene = preload("res://world/DroppedItem.tscn")

# Signals for HUD
signal health_changed(current_health: float, max_health: float)
signal dash_charges_changed(current_charges: int, max_charges: int)

enum State { IDLE_RUN, DASH, ATTACK, TRANSITIONING }

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
var nearby_items: Array[DroppedItem] = []

# Node References
@onready var animated_sprite = $AnimatedSprite2D
@onready var hand_node = $Hand
@onready var equipped_item_sprite = $Hand/EquippedItemSprite
@onready var pickup_area = $PickupArea
@onready var dash_timer = $DashTimer
@onready var dash_recharge_timer = $DashRechargeTimer
@onready var animation_player = $AnimationPlayer
@onready var hud = get_tree().get_first_node_in_group("HUD")

func _ready():
	self.current_health = max_health
	self._current_dashes = max_dashes
	emit_signal("dash_charges_changed", _current_dashes, max_dashes)

	dash_recharge_timer.wait_time = dash_recharge_time

	# Connect signals
	dash_timer.timeout.connect(_on_dash_timer_timeout)
	dash_recharge_timer.timeout.connect(_on_dash_recharge_timer_timeout)
	animation_player.animation_finished.connect(_on_animation_finished)
	Inventory.selected_slot_changed.connect(_on_selected_slot_changed)
	if is_instance_valid(pickup_area):
		pickup_area.area_entered.connect(_on_pickup_area_entered)
		pickup_area.area_exited.connect(_on_pickup_area_exited)

	current_state = State.IDLE_RUN

	_equip_item(Inventory.get_selected_item())

# --- Main Loop ---
func _physics_process(delta: float):
	# Check if inventory is open (needs access to HUD state or a global flag)
	var is_inventory_open = false
	if hud and hud.has_method("is_inventory_open"): # Add is_inventory_open() to HUD.gd
		is_inventory_open = hud.is_inventory_open()

	# --- Handle Inventory Selection Input (Always Available) ---
	handle_inventory_input()
	
	if is_inventory_open:
		# Optional: Decelerate player
		velocity = velocity.move_toward(Vector2.ZERO, speed)
		move_and_slide()
		# --- IMPORTANT: Do NOT process gameplay actions ---
		return # Exit physics process early

	# --- Handle Use Item Input (Only if inventory closed?) ---
	if Input.is_action_just_pressed("drop_item"):
		try_drop_selected_item()
	if Input.is_action_just_pressed("pickup_item"):
		try_pickup_nearby_item()
	if Input.is_action_just_pressed("use_item"):
		try_use_selected_item() # Handle use if it's a different button

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
		State.TRANSITIONING:
			velocity = Vector2.ZERO
			pass

	move_and_slide()

	_update_hand_and_weapon_animation()

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

	# --- Handle standard movement input ---
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction != Vector2.ZERO:
		velocity = input_direction.normalized() * speed
		last_direction = input_direction.normalized()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed)

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
	_update_hand_and_weapon_animation()
	dash_timer.start() # Start dash duration

	# Start recharge timer if needed
	if dash_recharge_timer.is_stopped() and current_dashes < max_dashes:
		dash_recharge_timer.start()

func start_attack():
	# Keep existing logic
	var equipped_item: ItemData = Inventory.get_selected_item()

	if current_state == State.IDLE_RUN and equipped_item != null and equipped_item.item_type == ItemData.ItemType.WEAPON:
		current_state = State.ATTACK
		_update_hand_and_weapon_animation()
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

func handle_world_drop(item_data_dropped: ItemData):
	if item_data_dropped == null or not item_data_dropped is ItemData:
		printerr("Player handle_world_drop: Received invalid item data.")
		return

	print("Player handling world drop for:", item_data_dropped.item_id)

	# Uses the same logic as try_drop_selected_item, but item is already "removed" (was on cursor)
	if DroppedItemScene == null:
		printerr("DroppedItemScene not preloaded! Cannot drop item.")
		# Try putting item back? Might fail if inventory full.
		Inventory.add_item(item_data_dropped)
		return

	var current_level_node = SceneManager.current_level_root
	if not is_instance_valid(current_level_node):
		printerr("handle_world_drop Error: Cannot find current level node via SceneManager!")
		# Try putting item back as fallback
		Inventory.add_item(item_data_dropped)
		return

	var dropped_item_instance = DroppedItemScene.instantiate()

	# Determine drop position (slightly in front of player)
	var drop_offset = last_direction.normalized() * 25.0
	if drop_offset == Vector2.ZERO: drop_offset = Vector2(25, 0)
	var initial_drop_position = global_position + drop_offset
	var final_drop_position = find_non_overlapping_drop_position(initial_drop_position)

	current_level_node.add_child(dropped_item_instance)
	print("  -> Dropped item added as child of:", current_level_node.name) # Debug
	# -----------------------------------------

	# Initialize the dropped item with data AND position
	if dropped_item_instance.has_method("initialize"):
		# Position is set correctly within initialize now
		dropped_item_instance.initialize(item_data_dropped, final_drop_position)
	else:
		printerr("DroppedItem instance missing initialize method!")
		dropped_item_instance.queue_free() # Clean up invalid instance
		Inventory.add_item(item_data_dropped) # Try to put item back

# --- Helper Functions ---
func get_target_animation() -> String:
	var action_prefix = "idle" # Default

	# Determine action based on state and velocity
	match current_state:
		State.IDLE_RUN:
			if velocity.length_squared() > 0.1:
				action_prefix = "run"
			else:
				action_prefix = "idle"
		State.DASH:
			action_prefix = "dash" # Assumes dash animations exist
		State.ATTACK:
			action_prefix = "attack" # Assumes attack animations exist
		State.TRANSITIONING:
			# While transitioning, visually appear idle based on last direction
			action_prefix = "idle"
		_:
			action_prefix = "idle" # Fallback

	# Determine direction suffix based on last_direction
	var direction_suffix = "down"
	# Use a small threshold to prevent direction switching when stopping near zero
	if abs(last_direction.x) > 0.1 or abs(last_direction.y) > 0.1:
		if abs(last_direction.x) > abs(last_direction.y):
			direction_suffix = "right" if last_direction.x > 0 else "left"
		else:
			direction_suffix = "down" if last_direction.y > 0 else "up"

	# Construct the animation name (e.g., "run_right", "idle_up")
	return action_prefix + "_" + direction_suffix

func find_non_overlapping_drop_position(target_pos: Vector2, max_attempts: int = 5, check_radius: float = 8.0, spread_distance: float = 10.0) -> Vector2:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	# Use a small circle shape for checking overlap
	var check_shape = CircleShape2D.new()
	check_shape.radius = check_radius
	query.shape = check_shape
	# Configure collision mask to ONLY check against other DroppedItems (e.g., set their layer/mask)
	#query.collision_mask = "Items"
	query.collide_with_areas = true # Check Area2D
	query.collide_with_bodies = false

	var current_pos = target_pos
	for i in range(max_attempts):
		query.transform = Transform2D(0, current_pos) # Check at current position
		var results = space_state.intersect_shape(query)

		var collision_found = false
		for result in results:
			if result.collider is DroppedItem: # Check if collision is with another dropped item
				collision_found = true
				break

		if not collision_found:
			return current_pos # Found a clear spot

		# If collision found, try a slightly different position nearby
		# Example: spiral outwards or pick random offset
		var angle = randf() * TAU # Random angle
		var dist = spread_distance * (float(i + 1) / max_attempts) # Spread further each attempt
		current_pos = target_pos + Vector2(cos(angle), sin(angle)) * dist
		print("Drop collision detected, trying new position:", current_pos) # Debug

	# If still colliding after max attempts, return the last attempted position
	print("Max drop attempts reached, placing at:", current_pos)
	return current_pos

# Plays the animation if it's different from the current one
func play_animation_if_different(anim_name: String):
	# Check if the AnimationPlayer node reference is valid AND not freed
	if is_instance_valid(animation_player):
		# Check if the animation exists before trying to play
		if animation_player.has_animation(anim_name):
			# Play only if the requested animation is not already the current one
			if animation_player.current_animation != anim_name:
				animation_player.play(anim_name)
				# print("Playing animation:", anim_name) # Debug
		else:
			# Animation doesn't exist, play fallback
			printerr("Animation not found:", anim_name, ". Playing idle_down fallback.")
			var fallback_anim = "idle_down" # Define fallback
			if animation_player.has_animation(fallback_anim) and \
			   animation_player.current_animation != fallback_anim:
				animation_player.play(fallback_anim)
	else:
		printerr("AnimationPlayer node is not valid!")


# Called by SceneManager BEFORE starting the fade/load
func start_scene_transition() -> void:
	if current_state == State.TRANSITIONING: return
	print("Player: Entering TRANSITIONING state.")
	current_state = State.TRANSITIONING
	velocity = Vector2.ZERO

# Called by SceneManager AFTER new scene loaded, player positioned, grace period waited.
func end_scene_transition() -> void:
	if not is_instance_valid(self) or current_state != State.TRANSITIONING: return
	print("Player: Exiting TRANSITIONING state.")
	current_state = State.IDLE_RUN
	velocity = Vector2.ZERO

# Simplify this check if flag removed
func is_currently_transitioning() -> bool:
	return current_state == State.TRANSITIONING

# Central function called whenever state or direction might change animation
func _update_hand_and_weapon_animation():
	var target_anim = get_target_animation() # Get animation based on current state/direction
	play_animation_if_different(target_anim)

# --- Equipping ---
func _equip_item(item_data: ItemData):
	# Clear previous equip state
	equipped_item_data = null
	if equipped_item_sprite: equipped_item_sprite.visible = false

	# Check if the new item is valid and equippable
	if item_data != null and item_data is ItemData and item_data.is_equippable():
		equipped_item_data = item_data
		if equipped_item_sprite:
			# Use the EQUIPPED texture now
			equipped_item_sprite.texture = item_data.equipped_texture
			equipped_item_sprite.visible = (item_data.equipped_texture != null) # Only show if texture exists
		print("Player equipped:", equipped_item_data.item_id)
		# Trigger animation update immediately to position hand correctly
		_update_hand_and_weapon_animation()
	else:
		print("Player equipped nothing (or item not equippable).")
		# Ensure hand position/weapon visibility resets if nothing equipped
		_update_hand_and_weapon_animation()

func try_use_selected_item():
	var selected_item: ItemData = Inventory.get_selected_item()

	if selected_item != null and selected_item is ItemData:
		if selected_item.item_type == ItemData.ItemType.WEAPON:
			print("'Use' action pressed, but selected item is a weapon. Attack action handles this.")
			return # Don't consume consumables etc. if weapon selected and LMB pressed

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

func try_drop_selected_item():
	var slot_index = Inventory.get_selected_slot_index()
	var item_to_drop: ItemData = Inventory.get_selected_item() # Uses hotbar

	if item_to_drop != null and item_to_drop is ItemData:
		print("Player attempting to drop via key:", item_to_drop.item_id)
		# Remove from inventory first
		var removed_item_data: ItemData = Inventory.remove_item_from_hotbar(slot_index) # Assumes this gets unique data

		if removed_item_data != null:
			# Call the same world drop logic, passing the removed data
			handle_world_drop(removed_item_data)
		else:
			printerr("Failed to remove item from hotbar to drop via key.")
	else:
		print("No item selected to drop via key.")


# --- NEW: Pickup Item Logic ---
func try_pickup_nearby_item():
	if nearby_items.is_empty():
		# print("No items nearby to pick up.") # Optional debug
		return

	# Try picking up the first item in the list (could implement closest logic later)
	# Important: Iterate carefully if removing while looping. Let's take the first.
	var item_node_to_pickup: DroppedItem = nearby_items[0]

	# Ensure the node hasn't been freed already by another process
	if not is_instance_valid(item_node_to_pickup):
		printerr("Nearby item instance is invalid!")
		nearby_items.pop_front() # Remove invalid entry
		return # Try again next frame if needed

	var data_to_add: ItemData = item_node_to_pickup.get_item_data()

	if data_to_add != null and data_to_add is ItemData:
		print("Player attempting to pick up:", data_to_add.item_id, "Qty:", data_to_add.quantity)

		# Important: Duplicate the data if add_item doesn't handle it,
		# because we will free the original node holding the data.
		# Let's assume Inventory.add_item makes its own copy if needed.
		var success = Inventory.add_item(data_to_add)

		if success:
			print("  -> Pickup successful!")
			# Remove from nearby list BEFORE freeing the node
			nearby_items.erase(item_node_to_pickup)
			# Remove the item from the game world
			item_node_to_pickup.queue_free()
			# TODO: Play pickup sound/effect
		else:
			print("  -> Inventory full, cannot pick up.")
			# TODO: Display "Inventory Full" message to player
	else:
		printerr("Could not get valid ItemData from nearby item node!")
		# Remove potentially corrupted item from list and maybe world?
		nearby_items.erase(item_node_to_pickup)
		item_node_to_pickup.queue_free()

# --- Signal Callbacks ---
func _on_dash_timer_timeout():
	# Dash duration finished
	velocity = Vector2.ZERO
	if current_state == State.DASH:
		current_state = State.IDLE_RUN
		_update_hand_and_weapon_animation()

func _on_dash_recharge_timer_timeout():
	# One charge regenerated
	print("Dash charge regenerated")
	self.current_dashes += 1
	if current_dashes < max_dashes:
		dash_recharge_timer.start()
	else:
		print("Dash charges full.")

func _on_pickup_area_entered(area):
	# Check if the overlapping area is a DroppedItem
	if area is DroppedItem:
		# --- Item Handles Its Own Prompt ---
		# Add to nearby list for pickup logic, but DON'T show a player-level prompt.
		if not area in nearby_items:
			print("Player detected nearby DroppedItem:", area.get_item_data().item_id) # Debug
			nearby_items.append(area)
		# --- DO NOT display a generic player prompt here ---
		# print("Player showing generic pickup prompt") # REMOVED
		# hud.show_interaction_prompt("Pick Up (F)") # REMOVED (or similar logic)

	# --- Handle other types of interactable areas if needed ---
	# elif area.is_in_group("NPC"):
	#     hud.show_interaction_prompt("Talk (F)")
	# elif area.is_in_group("Chest"):
	#     hud.show_interaction_prompt("Open (F)")
	else:
		print("Player pickup area entered unknown area type:", area.name) # Debug

func _on_pickup_area_exited(area):
	if area is DroppedItem:
		if area in nearby_items:
			print("Player no longer near DroppedItem:", area.get_item_data().item_id) # Debug
			nearby_items.erase(area) # Remove by value
		# --- DO NOT hide a generic player prompt here for items ---
		# hud.hide_interaction_prompt() # REMOVED (or similar logic)

	# --- Handle other types ---
	# elif area.is_in_group("NPC") or area.is_in_group("Chest"):
	#     hud.hide_interaction_prompt()

func _on_animation_finished(anim_name: String):
	# Keep existing attack animation logic
	if current_state == State.ATTACK and animated_sprite.animation.begins_with("attack_"):
		current_state = State.IDLE_RUN
		_update_hand_and_weapon_animation()

func _on_selected_slot_changed(new_index: int, old_index: int, item_data: ItemData):
	print("Player detected selected slot change. New Item:", item_data)
	# --- KEEP CHECK FOR DRAG FLAG ---
	if Inventory.is_dragging_selected_slot and item_data == null:
		print("  -> Player: Ignoring equip(null) because selected slot is being dragged.")
		return
	# -----------------------------
	_equip_item(item_data)
