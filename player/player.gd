# player.gd
class_name Player

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

@export var temp_inventory_items: Array = []

# State Variables
var peer_id: int = 0
var current_state: State = State.IDLE_RUN
var last_direction: Vector2 = Vector2.DOWN
var equipped_item_data: ItemData = null
var nearby_items: Array[DroppedItem] = []
var _synced_animation_name: String = ""
var _is_currently_processing_world_drop: bool = false
var _currently_prompted_item: DroppedItem = null
var _just_dropped_item_timer: Timer = Timer.new()

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
	peer_id = name.to_int() # This should now work as spawner names it with peer ID
	print("Player [", name, "] _ready. Peer ID:", peer_id, " Is Auth:", is_multiplayer_authority(), " Initial GlobalPos:", global_position.round())

	if not is_multiplayer_authority():
		var camera = find_child("Camera2D", true, false) # Example
		if camera: camera.enabled = false
	else:
		# This IS the locally controlled player
		var camera = find_child("Camera2D", true, false)
		if camera: camera.enabled = true
		# SceneManager.player_node is now set by Main.gd after spawn
		# If player needs its own initial spawn point on first adding to scene:
		# (This is now handled by Main.gd setting local_player_node.global_position)

	self.current_health = max_health
	self._current_dashes = max_dashes
	emit_signal("dash_charges_changed", _current_dashes, max_dashes)

	dash_recharge_timer.wait_time = dash_recharge_time
	_just_dropped_item_timer.one_shot = true
	_just_dropped_item_timer.wait_time = 0.5 # Can't interact with own drop for 0.5s
	add_child(_just_dropped_item_timer)

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
	# If not multiplayer authority for this node, don't process input
	if not is_multiplayer_authority():
		# --- Handle Synced Animation ---
		if is_instance_valid(animation_player):
			var new_anim_name = animation_player.current_animation # This property is synced
			# Check if the synced animation name has changed OR if it's playing but shouldn't be (e.g. state changed)
			if new_anim_name != _synced_animation_name and not new_anim_name.is_empty():
				if animation_player.has_animation(new_anim_name):
					animation_player.play(new_anim_name)
					_synced_animation_name = new_anim_name
					# print_rich("[color=cyan]REMOTE Player [", name, "] Playing synced animation: ", new_anim_name, "[/color]") # DEBUG
				# else: print_rich("[color=red]REMOTE Player [", name, "] Synced anim not found: ", new_anim_name, "[/color]")
			elif new_anim_name.is_empty() and animation_player.is_playing():
				# If synced animation is empty but player is still playing something, stop it or play default
				# animation_player.stop() # Or play default like idle
				# _synced_animation_name = ""
				pass # Decide how to handle this case - usually current_animation won't be empty if set.

		_update_hand_and_weapon_animation()
		return

	if is_multiplayer_authority():
		_update_nearby_item_prompts()

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

var next_drop_is_personal = false # Add this var

func _unhandled_input(event): # Or _input
	if event.is_action_pressed("toggle_personal_drop_debug"): # New debug input action
		next_drop_is_personal = not next_drop_is_personal
		print("Next drop will be personal:", next_drop_is_personal)


@rpc("authority", "call_local", "reliable") # Only the authority (client for its own player) executes this
func set_initial_network_position(pos: Vector2):
	if not is_multiplayer_authority(): # Should only be called on the authority
		printerr("Player [", name, "] received set_initial_network_position but is not authority. Ignored.")
		return
	global_position = pos
	print("Player [", name, "] initial network position SET to:", pos, "by RPC.")


# --- State Processing ---
func process_idle_run_state(_delta: float):
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

func process_dash_state(_delta: float):
	pass # Movement handled by move_and_slide

func process_attack_state(_delta: float):
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
	var current_health_changed = (current_health > previous_health) # Check if health increased
	if health_changed:
		print("Player healed, health:", current_health_changed)
	return current_health_changed # Return whether health actually changed

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


@rpc("any_peer", "call_local", "reliable") # Any peer can call, server executes it locallyerver
func server_handle_item_drop_request(item_identifier: String, item_quantity_to_drop: int, drop_mode_int: int, intended_owner_peer_id: int):
	if not multiplayer.is_server(): return

	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1: requesting_peer_id = 1
	print("Player (Server Peer ID:", multiplayer.get_unique_id(), "): Received drop request for item '", item_identifier, "' qty:", item_quantity_to_drop, "from sender:", requesting_peer_id)

	var item_base_res: ItemData = null
	if item_identifier.begins_with("res://"): # It's likely a resource path
		item_base_res = load(item_identifier)
	else: # Assume it's an item_id, use ItemDatabase
		if ItemDatabase: # Check if ItemDatabase Autoload exists
			item_base_res = ItemDatabase.get_item_base(item_identifier)
		else:
			printerr("  -> Server Error: ItemDatabase not found, cannot lookup item by ID:", item_identifier)
			return

	if not item_base_res is ItemData:
		printerr("  -> Server Error: Could not load/find ItemData for identifier '", item_identifier, "'")
		return

	# --- Determine Drop Position (relative to THIS player instance on server) ---
	var drop_offset = last_direction.normalized() * 25.0
	if drop_offset == Vector2.ZERO: drop_offset = Vector2(25, 0)
	var target_drop_position = global_position + drop_offset # Initial target position

	# --- ATTEMPT TO MERGE WITH EXISTING DROPPED STACK ---
	var check_merge_radius: float = 16.0 # How close to check for merging
	var existing_item_to_merge_with: DroppedItem = find_nearby_stackable_dropped_item(
		item_base_res.item_id,
		target_drop_position,
		check_merge_radius
	)

	if is_instance_valid(existing_item_to_merge_with) and \
	   is_instance_valid(existing_item_to_merge_with.get_item_data()) and \
	   not existing_item_to_merge_with.get_item_data().is_stack_full():
		
		var existing_item_data = existing_item_to_merge_with.get_item_data()
		var can_add_to_existing = existing_item_data.max_stack_size - existing_item_data.quantity
		var amount_to_transfer = min(item_quantity_to_drop, can_add_to_existing)

		if amount_to_transfer > 0:
			print("  -> Server: Merging ", amount_to_transfer, " of '", item_base_res.item_id, "' onto existing dropped stack ID '", existing_item_to_merge_with.item_unique_id, "'")
			# Directly update the quantity on the server's instance.
			# The setter for quantity_synced on DroppedItem will trigger sync.
			existing_item_to_merge_with.quantity_synced += amount_to_transfer
			item_quantity_to_drop -= amount_to_transfer # Decrease remaining to drop
			# No need to call _reconstruct_item_data if only quantity changes on existing _local_item_data_instance
			# The setter for quantity_synced should handle updating the _local_item_data_instance.quantity
			# and then call _request_visual_update.

		if item_quantity_to_drop <= 0: # All items merged
			print("  -> Server: All items merged. No new item spawned.")
			return # Successfully merged, no need to spawn new
	# --- END MERGE ATTEMPT ---

	# If item_quantity_to_drop > 0, spawn a new item (or the remainder)
	if item_quantity_to_drop > 0:
		print("  -> Server: Spawning new DroppedItem (or remainder) for '", item_identifier, "' qty:", item_quantity_to_drop)
		# Get DroppedItemSpawner, Main node for ID generation etc.
		var main_node_ref = SceneManager.main_scene_root
		if not is_instance_valid(main_node_ref):
			printerr("  -> Server Error: main_node_ref not found as child of Main node!")
			return
		var dropped_item_spawner = main_node_ref.find_child("DroppedItemSpawner", true, false)
		if not is_instance_valid(dropped_item_spawner):
			printerr("  -> Server Error: DroppedItemSpawner not found as child of Main node!")
			return
		var new_item_id_str = main_node_ref.generate_unique_dropped_item_id()

		# Adjust drop position if initial target was occupied (for visual piling)
		target_drop_position = find_non_overlapping_drop_position(target_drop_position)

		var spawn_custom_data = {
			"item_identifier": item_identifier,
			"item_quantity": item_quantity_to_drop, # Use remaining quantity
			"drop_mode_int": drop_mode_int,
			"owner_peer_id": intended_owner_peer_id,
			"item_unique_id": new_item_id_str,
			"position_x": target_drop_position.x,
			"position_y": target_drop_position.y
		}
		dropped_item_spawner.spawn(spawn_custom_data)
		print("  -> Server requested DroppedItemSpawner to spawn item with gameplay ID:", new_item_id_str)


@rpc("any_peer", "call_local", "reliable")
func server_request_pickup_item_by_id(item_unique_id_to_pickup: String):
	if not multiplayer.is_server(): return

	var requesting_peer_id = multiplayer.get_remote_sender_id()
	if requesting_peer_id == 0 and multiplayer.get_unique_id() == 1: requesting_peer_id = 1

	print("Server: Received pickup request for item_unique_id '", item_unique_id_to_pickup, "' from peer [", requesting_peer_id, "]")

	var item_node_to_pickup: DroppedItem = null
	# Get the parent node where dropped items are spawned (e.g., WorldYSort under Main)
	# This path needs to be robust. Assume Main node has DroppedItemSpawner, get its spawn_path.
	var main_node = SceneManager.main_scene_root # Get main node reference
	if not is_instance_valid(main_node): printerr("ServerPickup: Main node reference is invalid!"); return
	var player_spawner_node = main_node.find_child("PlayerSpawner", true, false)
	if not is_instance_valid(player_spawner_node): printerr("ServerPickup: PlayerSpawner not found!"); return
	var player_spawn_parent = player_spawner_node.get_node(player_spawner_node.spawn_path) if not player_spawner_node.spawn_path.is_empty() else player_spawner_node
	if not is_instance_valid(player_spawn_parent): printerr("ServerPickup: Player spawn parent invalid!"); return
	var target_player_node_on_server = player_spawn_parent.get_node_or_null(str(requesting_peer_id)) as Player

	if not is_instance_valid(target_player_node_on_server):
		printerr("ServerPickup: Could not find player node '", str(requesting_peer_id), "' on server.")
		return

	var dropped_item_spawner = main_node.find_child("DroppedItemSpawner", true, false)
	if not is_instance_valid(dropped_item_spawner): printerr("ServerPickup: DroppedItemSpawner not found!"); return

	var actual_spawn_parent: Node = null
	if dropped_item_spawner.spawn_path.is_empty() or dropped_item_spawner.spawn_path == NodePath("."):
		actual_spawn_parent = dropped_item_spawner
	else:
		actual_spawn_parent = dropped_item_spawner.get_node_or_null(dropped_item_spawner.spawn_path)

	if not is_instance_valid(actual_spawn_parent):
		printerr("ServerPickup: Actual spawn parent for dropped items is invalid!")
		return

	for child in actual_spawn_parent.get_children():
		if child is DroppedItem and child.item_unique_id == item_unique_id_to_pickup:
			item_node_to_pickup = child
			break

	if not is_instance_valid(item_node_to_pickup):
		printerr("ServerPickup: Item with unique_id '", item_unique_id_to_pickup, "' not found.")
		return

	var actual_item_data_instance = item_node_to_pickup.get_item_data() # Calls getter for _local_item_data_instance
	if not is_instance_valid(actual_item_data_instance):
		printerr("ServerPickup: Item node '", item_unique_id_to_pickup, "' has NO VALID _local_item_data_instance! (Value from get_item_data():", actual_item_data_instance, ")")
		# This means _reconstruct_local_item_data failed or wasn't called yet on server for this item.
		return

	# --- Check ownership for personal items ---
	if item_node_to_pickup.drop_mode == DroppedItem.DropMode.PERSONAL and \
	   item_node_to_pickup.owner_peer_id != 0 and \
	   item_node_to_pickup.owner_peer_id != requesting_peer_id:
		print("ServerPickup: Player [", requesting_peer_id, "] tried to pick up personal item of player [", item_node_to_pickup.owner_peer_id, "]")
		# Optionally, send an RPC back to the client: "pickup_denied_not_owner"
		return # Deny pickup
	# -----------------------------------------

	var data_to_add_to_inventory = item_node_to_pickup.get_item_data()

	# --- Server-Side "Add to Inventory" (Placeholder Logic) ---
	# This part needs to represent the server updating its authoritative state.
	# For now, we assume success and then tell the client.
	var server_add_successful = true # Assume server can always add it for now

	if server_add_successful:
		# (Example using temp_inventory_items on the server's Player node for player 'requesting_peer_id')
		# target_player_node_on_server.temp_inventory_items.append({"item_id": data_to_add_to_inventory.item_id, "quantity": data_to_add_to_inventory.quantity})
		# target_player_node_on_server.notify_property_list_changed()
		print("  -> Server: Item added to peer [", requesting_peer_id, "]'s authoritative data.")

		var item_identifier_for_client = data_to_add_to_inventory.resource_path
		if item_identifier_for_client.is_empty():
			item_identifier_for_client = data_to_add_to_inventory.item_id
		var quantity_for_client = data_to_add_to_inventory.quantity

		# --- DIFFERENTIATE SERVER/HOST ACTION ---
		if requesting_peer_id == multiplayer.get_unique_id(): # Server (host) is picking up for itself
			print("  -> Server (Host) picking up for self. Calling client_add_item_to_inventory directly.")
			# Call the method directly on its own instance.
			# 'self' here refers to the Player node instance that received the original RPC
			# (server_request_pickup_item_by_id). If the host itself sent that RPC,
			# then 'self' IS the host's player.
			# However, this function is an RPC handler. The 'self' here isn't necessarily
			# target_player_node_on_server if a client called this server_request... RPC.
			#
			# The 'target_player_node_on_server' IS the correct instance (node "1" for host).
			if target_player_node_on_server.is_multiplayer_authority(): # Should be true for host's own node
				target_player_node_on_server.client_add_item_to_inventory(item_identifier_for_client, quantity_for_client)
			else:
				# This case is strange, means host doesn't have authority over its own player node "1"
				printerr("  -> Server (Host) picking up, but target_player_node_on_server (node '1') reports no authority!")
		else: # Server processing pickup for a REMOTE client
			print("  -> Server: Sending RPC client_add_item_to_inventory to remote PlayerNode '", target_player_node_on_server.name, "'")
			target_player_node_on_server.rpc("client_add_item_to_inventory", item_identifier_for_client, quantity_for_client)
		# -----------------------------------------

		item_node_to_pickup.queue_free()
	else:
		print("ServerPickup: Server-side inventory full for player [", requesting_peer_id, "].")
		# TODO: Send RPC back to client: "pickup_failed_inventory_full"


@rpc("any_peer", "call_local", "reliable")
func client_add_item_to_inventory(item_identifier: String, quantity: int):
	if not is_multiplayer_authority(): return

	print("Player [", name, "] (Client Only): Received command to add item to local inventory. ID:", item_identifier, "Qty:", quantity)

	var item_base_res: ItemData = null
	if item_identifier.begins_with("res://"):
		item_base_res = load(item_identifier)
	elif ItemDatabase:
		item_base_res = ItemDatabase.get_item_base(item_identifier)

	if item_base_res is ItemData:
		var item_instance_to_add = item_base_res.duplicate()
		item_instance_to_add.quantity = quantity
		
		var success = Inventory.add_item(item_instance_to_add) # Add to local Inventory singleton
		if success:
			print("  -> Item successfully added to local client inventory.")
			# TODO: Play pickup sound/UI feedback
		else:
			print("  -> Failed to add item to local client inventory (Inventory full?). This indicates a desync with server state.")
			# This case is problematic - server thought it could be added.
			# Might need server to handle "inventory full" responses.
	else:
		printerr("Player [", name, "] (Client): Could not reconstruct item from identifier '", item_identifier, "' for local inventory.")


func handle_world_drop(item_data_to_drop: ItemData, p_drop_mode: DroppedItem.DropMode = DroppedItem.DropMode.GLOBAL, p_owner_peer_id: int = 0):
	if not is_multiplayer_authority():
		printerr("Player [", name, "] handle_world_drop called but not authority.")
		return
	if item_data_to_drop == null or not item_data_to_drop is ItemData:
		printerr("Player [", name, "] handle_world_drop: Invalid item data provided.")
		return

	if _is_currently_processing_world_drop:
		print("Player [", name, "] handle_world_drop: Already processing a world drop. Ignoring.") # DEBUG
		return
	_is_currently_processing_world_drop = true

	print("Player (Client) [", name, "]: handle_world_drop initiated. Requesting server to drop item:", item_data_to_drop.item_id, "Qty:", item_data_to_drop.quantity)

	# Determine identifier (path or ID)
	var identifier = item_data_to_drop.resource_path
	if identifier.is_empty(): identifier = item_data_to_drop.item_id
	if identifier.is_empty():
		printerr("Player [", name, "] handle_world_drop: Item has no identifier!")
		_is_currently_processing_world_drop = false # Reset flag
		return

	# Determine owner for personal drops
	var final_owner_id = p_owner_peer_id
	if p_drop_mode == DroppedItem.DropMode.PERSONAL and final_owner_id == 0:
		final_owner_id = multiplayer.get_unique_id()

	rpc_id(1, "server_handle_item_drop_request", identifier, item_data_to_drop.quantity, p_drop_mode, final_owner_id)

	_just_dropped_item_timer.start()
	_is_currently_processing_world_drop = false
	print("Player (Client) [", name, "]: World drop RPC sent, _is_currently_processing_world_drop reset.")


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

func find_non_overlapping_drop_position(target_pos: Vector2, 
										 max_attempts: int = 3,        # Fewer attempts for closer piling
										 check_radius: float = 5.0,    # Smaller check radius
										 spread_distance: float = 6.0  # Smaller spread
										) -> Vector2:
	if not get_world_2d(): # Safety check if called when not in tree
		printerr("Player: find_non_overlapping_drop_position - World2D not available.")
		return target_pos
		
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var check_shape = CircleShape2D.new()
	check_shape.radius = check_radius
	query.shape = check_shape
	# Configure collision mask to ONLY check against other DroppedItems
	# This requires DroppedItem to be on a specific layer, e.g., layer specified by a constant.
	# query.collision_mask = YOUR_DROPPED_ITEM_LAYER_BIT # Example: 1 << (DROPPED_ITEM_PHYSICS_LAYER - 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [self.get_rid()] # Exclude the player itself

	var current_pos = target_pos
	for i in range(max_attempts):
		query.transform = Transform2D(0, current_pos)
		var results = space_state.intersect_shape(query)

		var collision_with_other_item_found = false
		for result in results:
			# Check if the collider is a DroppedItem and NOT the one we might be trying to merge with
			# For simple overlap prevention, just checking 'is DroppedItem' is enough
			if result.collider is DroppedItem:
				collision_with_other_item_found = true
				break
		
		if not collision_with_other_item_found:
			return current_pos # Found a clear enough spot

		# If collision found, try a slightly different position nearby
		var angle = randf_range(-PI / 4.0, PI / 4.0) + (PI if i % 2 == 0 else 0) # Try to spread a bit
		var dist_offset = spread_distance * (randf() * 0.5 + 0.5) # Slightly random distance
		current_pos = target_pos + Vector2(cos(angle), sin(angle)) * dist_offset
		print("Drop collision, trying new position:", current_pos)

	print("Max drop attempts reached for overlap, placing at last attempt:", current_pos)
	return current_pos


func find_nearby_stackable_dropped_item(item_id_to_match: String, at_position: Vector2, radius: float) -> DroppedItem:
	if not multiplayer.is_server(): return null # Server only

	# Get the node where dropped items live
	var main_node_ref = SceneManager.main_scene_root
	if not is_instance_valid(main_node_ref): return null
	var dropped_item_spawner = main_node_ref.find_child("DroppedItemSpawner", true, false)
	if not is_instance_valid(dropped_item_spawner): return null
	var items_parent_node = dropped_item_spawner.get_node_or_null(dropped_item_spawner.spawn_path) if not dropped_item_spawner.spawn_path.is_empty() else dropped_item_spawner
	if not is_instance_valid(items_parent_node): return null

	var closest_stackable_item: DroppedItem = null
	var min_dist_sq = radius * radius # Check within this squared radius

	for child in items_parent_node.get_children():
		if child is DroppedItem:
			var dropped_item = child as DroppedItem
			var item_data = dropped_item.get_item_data() # Accesses _local_item_data_instance

			# Check if same item type, global (or same owner for personal), and not full
			if is_instance_valid(item_data) and \
			   item_data.item_id == item_id_to_match and \
			   not item_data.is_stack_full() and \
			   dropped_item.drop_mode == DroppedItem.DropMode.GLOBAL: # Simplification: only merge global items for now
				
				var dist_sq = dropped_item.global_position.distance_squared_to(at_position)
				if dist_sq < min_dist_sq:
					# Found a potential candidate, is it closer?
					# No need to find the *absolute* closest, just the first suitable one is often fine.
					closest_stackable_item = dropped_item
					min_dist_sq = dist_sq # Update to find even closer ones if any
					# For immediate merging with first found:
					# return dropped_item

	return closest_stackable_item # Returns closest or null


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
	if not is_instance_valid(animation_player): return

	var target_anim_name = get_target_animation() # Based on current_state, last_direction (which are synced)

	if is_multiplayer_authority():
		# Local player: determine and play the animation
		if animation_player.current_animation != target_anim_name or not animation_player.is_playing():
			if animation_player.has_animation(target_anim_name):
				animation_player.play(target_anim_name)
				# No need to set _synced_animation_name for local player,
				# as its current_animation property will be synced out.
			else:
				# Play fallback for local player if target_anim_name is invalid
				var fallback = "idle_down" # Or your default
				if animation_player.has_animation(fallback) and animation_player.current_animation != fallback:
					animation_player.play(fallback)
	else:
		# Remote player: Animation should already be playing due to the check in _physics_process
		# This function might still be useful for other visual updates based on synced state,
		# e.g., if weapon sprite visibility depends on current_state or animation name.
		pass

func _update_nearby_item_prompts() -> void:
	if not is_multiplayer_authority(): return

	var best_target: DroppedItem = null
	var min_dist_sq = INF

	# Clean up invalid items from the list first & filter non-interactable
	for i in range(nearby_items.size() - 1, -1, -1):
		var item_node = nearby_items[i] as DroppedItem # Assume items in list are DroppedItem
		if not is_instance_valid(item_node):
			nearby_items.remove_at(i)
			continue

		# General visibility/interactivity check (based on item's own synced state)
		if not item_node.visible or not item_node.monitoring:
			if _currently_prompted_item == item_node: # If it was prompted, hide it
				item_node.hide_prompt()
				_currently_prompted_item = null
			continue # Skip non-interactive items for prompt selection

		# Player state check: Can THIS player interact with prompts right now?
		if not can_interact_with_prompts():
			# If player is busy, ensure no prompts are shown from any item
			if is_instance_valid(_currently_prompted_item):
				_currently_prompted_item.hide_prompt()
			_currently_prompted_item = null
			best_target = null # Explicitly no target if player can't interact
			break # Stop further processing if player can't interact at all

		# Ownership check (is it global or mine?)
		var can_pickup_ownership_wise = false
		if item_node.drop_mode == DroppedItem.DropMode.GLOBAL:
			can_pickup_ownership_wise = true
		elif item_node.drop_mode == DroppedItem.DropMode.PERSONAL and item_node.owner_peer_id == multiplayer.get_unique_id():
			can_pickup_ownership_wise = true

		if not can_pickup_ownership_wise:
			if _currently_prompted_item == item_node: # If it was prompted, hide it
				item_node.hide_prompt()
				_currently_prompted_item = null
			continue # Skip items player doesn't own (if personal)

		# If all checks pass, consider for distance
		var dist_sq = global_position.distance_squared_to(item_node.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_target = item_node

	# Update prompts based on best_target
	if is_instance_valid(best_target):
		if _currently_prompted_item != best_target:
			if is_instance_valid(_currently_prompted_item):
				_currently_prompted_item.hide_prompt()
			best_target.show_prompt(self) # Pass player reference
			_currently_prompted_item = best_target
		# else: Best target is already prompted, do nothing
	else: # No best target found (or player can't interact)
		if is_instance_valid(_currently_prompted_item):
			_currently_prompted_item.hide_prompt()
			_currently_prompted_item = null

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

func can_interact_with_prompts() -> bool:
	# Cannot interact if just dropped an item (timer running)
	# OR if in a scene transition.
	var just_dropped = not _just_dropped_item_timer.is_stopped()
	var currently_transitioning = is_currently_transitioning() # Uses current_state == State.TRANSITIONING

	# if just_dropped: print("Player cannot interact: just dropped.") # Debug
	# if currently_transitioning: print("Player cannot interact: transitioning.") # Debug

	return not just_dropped and not currently_transitioning

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


func try_pickup_nearby_item() -> void:
	if not is_multiplayer_authority(): return # Only local player can initiate pickup
	
	# Use the _currently_prompted_item as the target.
	# _update_nearby_item_prompts should have already selected the best one.
	if is_instance_valid(_currently_prompted_item):
		var item_to_pickup = _currently_prompted_item
		var item_data_of_target = item_to_pickup.get_item_data() # Get its ItemData

		if not is_instance_valid(item_data_of_target):
			printerr("Player [", name, "]: Prompted item '", item_to_pickup.item_unique_id, "' has no valid ItemData.")
			return

		# --- NEW CHECK: Can the player's LOCAL inventory accept this item? ---
		var can_add_locally = true # Assume yes by default
		if Inventory and Inventory.has_method("can_player_add_item_check"):
			can_add_locally = Inventory.can_player_add_item_check(item_data_of_target)
		else:
			printerr("Player [", name, "]: Inventory or can_player_add_item_check method not found for pre-pickup check.")

		if not can_add_locally:
			print("Player [", name, "]: Cannot pick up '", item_data_of_target.item_id, "'. Local inventory check says full.")
			# TODO: Play "inventory full" sound or show a brief UI message here
			return # Do not send RPC if local check fails
		# -------------------------------------------------------------------

		print("Player [", name, "] trying to pick up prompted item ID:", item_to_pickup.item_unique_id, " (Name:", item_to_pickup.name, ")")
		if item_to_pickup.item_unique_id.is_empty():
			printerr("Player [", name, "]: Prompted item has no unique ID set!")
			return

		# Send RPC to server if local check passed
		rpc_id(1, "server_request_pickup_item_by_id", item_to_pickup.item_unique_id)
		
		# Optimistically hide prompt and remove from nearby list.
		# Server will be the source of truth if item is actually removed from world.
		item_to_pickup.hide_prompt()
		if item_to_pickup in nearby_items:
			nearby_items.erase(item_to_pickup)
		_currently_prompted_item = null
		# Force re-evaluation of prompts next frame
		_update_nearby_item_prompts() # This will find a new target or show no prompts
	else:
		print("Player [", name, "]: No item currently prompted for pickup.")


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
	if area is DroppedItem:
		var item = area as DroppedItem
		if is_instance_valid(item) and not item in nearby_items:
			nearby_items.append(item)
	elif area.is_in_group("player_pickup_area"):
		pass

	# --- Handle other types of interactable areas if needed ---
	# elif area.is_in_group("NPC"):
	#     hud.show_interaction_prompt("Talk (F)")
	# elif area.is_in_group("Chest"):
	#     hud.show_interaction_prompt("Open (F)")
	else:
		print("Player pickup area entered unknown/unhandled area type:", area.name, " (Owner: ", area.get_owner().name if area.get_owner() else "None", ")")

func _on_pickup_area_exited(area):
	if area is DroppedItem:
		var item = area as DroppedItem
		if item in nearby_items:
			nearby_items.erase(item)
			# If this item was the one being prompted, player logic will hide it
			if _currently_prompted_item == item:
				if is_instance_valid(item): item.hide_prompt() # Hide its prompt
				_currently_prompted_item = null
			# _update_nearby_item_prompts will re-evaluate next frame

	# --- Handle other types ---
	# elif area.is_in_group("NPC") or area.is_in_group("Chest"):
	#     hud.hide_interaction_prompt()

func _on_animation_finished(_anim_name: String):
	# Keep existing attack animation logic
	if current_state == State.ATTACK and animated_sprite.animation.begins_with("attack_"):
		current_state = State.IDLE_RUN
		_update_hand_and_weapon_animation()

func _on_selected_slot_changed(_new_index: int, _old_index: int, item_data: ItemData):
	print("Player detected selected slot change. New Item:", item_data)
	# --- KEEP CHECK FOR DRAG FLAG ---
	if Inventory.is_dragging_selected_slot and item_data == null:
		print("  -> Player: Ignoring equip(null) because selected slot is being dragged.")
		return
	# -----------------------------
	_equip_item(item_data)
