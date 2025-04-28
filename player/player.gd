extends CharacterBody2D

# Signals for HUD
signal health_changed(current_health: float, max_health: float)
signal dash_charge_used(charge_index: int, recharge_duration: float)
signal dash_count_changed(ready_count: int)

# States Enum
enum State { IDLE_RUN, DASH, ATTACK }
enum DashSlotState { READY, RECHARGING }

# Stats
@export var max_health: float = 100.0
var current_health: float :
	set(value):
		var previous_health = current_health
		current_health = clampf(value, 0, max_health)
		if current_health != previous_health: # Only emit if changed
			emit_signal("health_changed", current_health, max_health)

@export var max_dashes: int = 3
@export var dash_recharge_time: float = 3.0
var current_dashes: int
var dash_slot_states: Array[DashSlotState] = []

# Movement Variables
@export var speed: float = 100.0
@export var dash_speed: float = 200.0

# State Variables
var current_state: State = State.IDLE_RUN
var last_direction: Vector2 = Vector2.DOWN

# Node References
@onready var animated_sprite = $AnimatedSprite2D
@onready var dash_timer = $DashTimer

func _ready():
	self.current_health = max_health
	self.current_dashes = max_dashes # Start with full dashes

	# Initialize dash slot tracking (optional)
	dash_slot_states.resize(max_dashes)
	dash_slot_states.fill(DashSlotState.READY)

	dash_timer.timeout.connect(_on_dash_timer_timeout)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	Inventory.selected_slot_changed.connect(_on_selected_slot_changed)
	_equip_item(Inventory.get_selected_item())
	emit_signal("dash_count_changed", current_dashes)

func _physics_process(delta: float):
	match current_state:
		State.IDLE_RUN:
			process_idle_run_state(delta)
			# Check for DEBUG input
			if Input.is_action_just_pressed("debug_damage"): # Add "debug_damage" to Input Map (e.g., key '1')
				take_damage(10)
			if Input.is_action_just_pressed("debug_heal"): # Add "debug_heal" to Input Map (e.g., key '2')
				heal(10)
			if Input.is_action_just_pressed("debug_add_item"): # Add "debug_add_item" to Input Map (e.g., key '3')
				# Replace with actual item resource/path later
				var success = Inventory.add_item("res://icon.svg") # Add default Godot icon for testing
				if not success: print("Could not add item (inventory full?)")

		State.DASH:
			process_dash_state(delta)
		State.ATTACK:
			process_attack_state(delta)

	move_and_slide()

func get_max_dashes() -> int:
	return max_dashes

func get_current_dash_charges() -> int:
	return current_dashes

func get_current_health() -> float:
	return current_health

func get_max_health() -> float:
	return max_health

# --- State Processing Functions ---

func process_idle_run_state(_delta: float):
	if Input.is_action_just_pressed("attack"):
		start_attack()
		return

	if Input.is_action_just_pressed("dash"):
		if current_dashes > 0:
			start_dash() # Will handle charge consumption and signal emit
			return
		else:
			print("Out of dashes!")

	# Movement Input (keep existing logic)
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction != Vector2.ZERO:
		velocity = input_direction.normalized() * speed
		last_direction = input_direction.normalized()
		update_animation("run", last_direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed)
		update_animation("idle", last_direction)

func process_dash_state(_delta: float):
	# During dash, movement is fixed based on dash_speed and the direction when started
	# Velocity is set in start_dash() and maintained until timer ends
	# No input checking needed here, waiting for timer timeout
	pass # move_and_slide() will handle the movement

func process_attack_state(_delta: float):
	# Typically stop movement during attack
	velocity = Vector2.ZERO
	# No input checking needed here, waiting for animation_finished signal
	pass # move_and_slide() will apply zero velocity

# --- Action Start Functions ---

func start_dash():
	var charge_index_to_use = -1
	for i in range(max_dashes - 1, -1, -1): # Loop from end towards beginning
		if dash_slot_states[i] == DashSlotState.READY:
			charge_index_to_use = i
			break # Found the first ready slot from the right

	if charge_index_to_use == -1:
		printerr("StartDash called but no READY slot found (should be caught by current_dashes > 0)")
		return # Should not happen if current_dashes > 0 check works

	# Mark the specific slot as recharging internally
	dash_slot_states[charge_index_to_use] = DashSlotState.RECHARGING
	# Decrement the count of ready dashes
	current_dashes -= 1

	# Signal which specific slot was used (for HUD to start its timer)
	emit_signal("dash_charge_used", charge_index_to_use, dash_recharge_time)
	# Signal the NEW total count of ready dashes (for HUD to update visuals)
	emit_signal("dash_count_changed", current_dashes) # Emit AFTER count is updatede)

	# Start the dash action state
	current_state = State.DASH
	velocity = last_direction * dash_speed
	update_animation("dash", last_direction)
	dash_timer.start() # Start the timer for the dash *movement*

func start_attack():
	var equipped_item = Inventory.get_selected_item()
	if current_state == State.IDLE_RUN and equipped_item != null: # Only attack if idle/run AND item equipped
		current_state = State.ATTACK
		update_animation("attack", last_direction)
		velocity = Vector2.ZERO
		print("Player attacks with:", equipped_item) # Replace with actual attack logic later
	elif equipped_item == null:
		print("No item equipped to attack with!")

# --- Stat Management ---
func take_damage(amount: float):
	self.current_health -= amount
	print("Player took damage, health:", current_health)
	if current_health <= 0:
		die()

func heal(amount: float):
	self.current_health += amount
	print("Player healed, health:", current_health)

func gain_dash_charge(charge_index: int):
	# Validate the index and ensure the slot was actually recharging
	if charge_index >= 0 and charge_index < dash_slot_states.size():
		if dash_slot_states[charge_index] == DashSlotState.RECHARGING:
			dash_slot_states[charge_index] = DashSlotState.READY
			current_dashes += 1 # Increment the ready count

			# Signal the NEW total count of ready dashes
			emit_signal("dash_count_changed", current_dashes) # Emit AFTER count is updated
		else:
			printerr("Tried to gain dash charge for index", charge_index, " but it wasn't recharging!")
	else:
		printerr("Tried to gain dash charge for invalid index:", charge_index)

func die():
	print("Player has died!")
	# Add death animation, game over screen, etc.
	queue_free() # Example: remove player node

# --- Helper Functions ---

func update_animation(action_prefix: String, direction: Vector2):
	# Determine direction string ("up", "down", "left", "right")
	var direction_name = ""
	if abs(direction.x) > abs(direction.y):
		direction_name = "right" if direction.x > 0 else "left"
	else: # Prioritize vertical or if equal
		direction_name = "down" if direction.y > 0 else "up"

	# Construct animation name (e.g., "run_right", "attack_up")
	var new_anim = action_prefix + "_" + direction_name

	# Only play if the animation is different
	if animated_sprite.animation != new_anim:
		animated_sprite.play(new_anim)

func _equip_item(item_data):
	# This is where you'd change the player's visuals or stats based on the item
	if item_data:
		print("Player equips:", item_data)
		# Example: Change a weapon sprite texture
		# if hand_sprite: hand_sprite.texture = load(item_data) # Assuming item_data is path
	else:
		print("Player unequips item (empty slot selected)")
		# Example: Hide weapon sprite
		# if hand_sprite: hand_sprite.texture = null

# --- Signal Callbacks ---

func _on_dash_timer_timeout():
	# Dash finished, return to idle/run state
	velocity = Vector2.ZERO # Stop the dash velocity
	current_state = State.IDLE_RUN
	# Immediately update animation to idle in case no movement keys are held
	update_animation("idle", last_direction)

func _on_animation_finished():
	# Check if the finished animation was an attack animation
	# Godot 4: animation property holds the name of the *current* animation being played
	if current_state == State.ATTACK and animated_sprite.animation.begins_with("attack_"):
		current_state = State.IDLE_RUN
		# Update animation immediately after attack finishes
		update_animation("idle", last_direction)

func _on_selected_slot_changed(_new_index: int, _old_index: int, item_data):
	# Called when the *inventory* signals a selection change
	_equip_item(item_data)
