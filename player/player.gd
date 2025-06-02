# Player.gd
class_name Player
extends CharacterBody2D

const DebugItemResource = preload("res://items/tool_pickaxe.tres")
const DroppedItemScene = preload("res://world/DroppedItem.tscn")

# Signals for HUD
signal local_player_is_ready(player_instance)
signal health_changed(current_health: float, max_health: float)
signal dash_charges_changed(current_charges: int, max_charges: int)
signal crafting_attempt_completed(was_successful: bool, crafted_item_id: String, message: String)

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
var player_name: String = "Ninja" : set = set_player_name
var current_state: State = State.IDLE_RUN
var last_direction: Vector2 = Vector2.DOWN
var equipped_item_data: ItemData = null
var nearby_items: Array[DroppedItem] = []
var nearby_resource_nodes: Array[ResourceNode] = []
var _currently_targeted_resource_node: ResourceNode = null
var _synced_animation_name: String = ""
var _is_currently_processing_world_drop: bool = false
var _currently_prompted_item: DroppedItem = null
var _just_dropped_item_timer: Timer = Timer.new()

var _current_equipped_item_data_for_visuals: ItemData = null
var synced_equipped_item_id: String = "" :
	set(value):
		if synced_equipped_item_id == value: return
		synced_equipped_item_id = value
		if not is_multiplayer_authority(): # If this is a remote player instance
			_update_remote_equipped_visuals()

# Node References
@onready var animated_sprite = $AnimatedSprite2D
@onready var hand_node = $Hand
@onready var equipped_item_sprite = $Hand/EquippedItemSprite
@onready var pickup_area = $PickupArea
@onready var dash_timer = $DashTimer
@onready var dash_recharge_timer = $DashRechargeTimer
@onready var animation_player = $AnimationPlayer
@onready var hud = get_tree().get_first_node_in_group("HUD")
@onready var nameplate_positioner: Node2D = $NameplatePositioner
@onready var nameplate_node: Control = $NameplatePositioner/Nameplate

func _ready():
	peer_id = name.to_int() # This should now work as spawner names it with peer ID
	print("Player [", name, "] _ready. Peer ID:", peer_id, " Is Auth:", is_multiplayer_authority(), " Initial GlobalPos:", global_position.round())

	_update_nameplate_if_ready()

	var camera = find_child("Camera2D", true, false)
	if camera:
		camera.enabled = is_multiplayer_authority()

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
	if is_multiplayer_authority():
		emit_signal("local_player_is_ready", self)



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
			elif new_anim_name.is_empty() and animation_player.is_playing():
				# If synced animation is empty but player is still playing something, stop it or play default
				# animation_player.stop() # Or play default like idle
				# _synced_animation_name = ""
				pass # Decide how to handle this case - usually current_animation won't be empty if set.

		_update_hand_and_weapon_animation()
		return

	if is_multiplayer_authority():
		_update_nearby_item_prompts()
		_update_resource_node_target_and_prompt()
		
		if Input.is_action_just_pressed("use_item"):
			if is_instance_valid(_currently_targeted_resource_node) and \
				not _currently_targeted_resource_node.is_depleted:
				# Attempt to gather from the targeted resource node
				_try_gather_from_node(_currently_targeted_resource_node)

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
				if is_multiplayer_authority(): # Only the local player should send this for themselves
					var item_id_to_spawn = DebugItemResource.item_id # Assuming DebugItemResource is your tool's ItemData
					var quantity_to_spawn = 1 
					
					# RPC to Main.gd on server
					var main_node = get_node_or_null("/root/Main")
					if is_instance_valid(main_node):
						print("Player [", name, "]: Requesting server to spawn debug item '", item_id_to_spawn, "'")
						main_node.rpc_id(1, "server_handle_debug_add_item_to_inventory", item_id_to_spawn, quantity_to_spawn)
					else:
						printerr("Player [", name, "]: Could not find Main node for debug item spawn RPC.")
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

func set_player_name(new_name: String):
	if player_name == new_name: return
	player_name = new_name
	print("Player [", name, "] (Peer:", multiplayer.get_unique_id() if multiplayer else "N/A", ") name set/synced to:", player_name)

	# Update nameplate if node is ready
	if is_node_ready(): # Check if the Player node itself is ready
		_update_nameplate_if_ready()


@rpc("authority", "call_local", "reliable") # Only the authority (client for its own player) executes this
func set_initial_network_position(pos: Vector2):
	if not is_multiplayer_authority(): # Should only be called on the authority
		printerr("Player [", name, "] received set_initial_network_position but is not authority. Ignored.")
		return
	global_position = pos
	print("Player [", name, "] initial network position SET to:", pos, "by RPC.")

func _update_nameplate_if_ready():
	if is_instance_valid(nameplate_node) and nameplate_node.has_method("update_name"):
		nameplate_node.update_name(player_name)
		if is_multiplayer_authority(): # If this is the local player
			nameplate_node.visible = false
		else: # For remote players
			nameplate_node.visible = true

func initialize_networked_data(p_name: String, initial_pos: Vector2):
	self.player_name = p_name
	self.global_position = initial_pos

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
		var dropped_item_spawner = main_node_ref.dropped_item_spawner
		if not is_instance_valid(dropped_item_spawner):
			printerr("  -> Server Error: DroppedItemSpawner not found as child of Main node!")
			return
		var new_item_id_str = main_node_ref.generate_unique_dropped_item_id()

		var final_drop_position = find_non_overlapping_drop_position(
			target_drop_position,
			item_base_res.item_id
		)

		var spawn_custom_data = {
			"item_identifier": item_identifier,
			"item_quantity": item_quantity_to_drop, # Use remaining quantity
			"drop_mode_int": drop_mode_int,
			"owner_peer_id": intended_owner_peer_id,
			"item_unique_id": new_item_id_str,
			"position_x": final_drop_position.x,
			"position_y": final_drop_position.y
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
	var player_spawner_node = main_node.player_spawner
	if not is_instance_valid(player_spawner_node): printerr("ServerPickup: PlayerSpawner not found!"); return
	var player_spawn_parent = player_spawner_node.get_node(player_spawner_node.spawn_path) if not player_spawner_node.spawn_path.is_empty() else player_spawner_node
	if not is_instance_valid(player_spawn_parent): printerr("ServerPickup: Player spawn parent invalid!"); return
	var target_player_node_on_server = player_spawn_parent.get_node_or_null(str(requesting_peer_id)) as Player

	if not is_instance_valid(target_player_node_on_server):
		printerr("ServerPickup: Could not find player node '", str(requesting_peer_id), "' on server.")
		return

	var dropped_item_spawner = main_node.dropped_item_spawner
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
		printerr("ServerPickup: Item with unique_id '", item_unique_id_to_pickup, "' not found for peer ", requesting_peer_id)
		# TODO: RPC failure to client
		return
	
	var item_data_to_give_player = item_node_to_pickup.get_item_data() # This is ItemData
	if not is_instance_valid(item_data_to_give_player):
		printerr("ServerPickup: Item node '", item_unique_id_to_pickup, "' has invalid ItemData for peer ", requesting_peer_id)
		# TODO: RPC failure to client
		return

	# --- SERVER-SIDE AUTHORITATIVE "Add to Inventory" ---
	# Create a fresh instance for the server's inventory
	var item_instance_for_server_inv = item_data_to_give_player.duplicate()
	# Quantity is already set correctly from the dropped item's data

	if ServerInventoryManager.add_item_to_player_inventory(requesting_peer_id, item_instance_for_server_inv):
		print("  -> Server: Item '", item_data_to_give_player.item_id, "' added to ServerInventoryManager for peer [", requesting_peer_id, "]")
		# ServerInventoryManager.add_item_to_player_inventory now handles calling _notify_client_of_slot_update,
		# which sends the client_receive_slot_update RPC to the client's Inventory.gd.
		# This makes the client's inventory UI update authoritatively.
		
		item_node_to_pickup.queue_free() # Remove item from world
	else:
		print("  -> ServerPickup: ServerInventoryManager reported inventory full for player [", requesting_peer_id, "]. Item '", item_data_to_give_player.item_id, "' not picked up.")
		# TODO: Send RPC back to client: "pickup_failed_inventory_full"
		# For now, item remains on ground if server inventory is full.


@rpc("call_remote", "authority", "reliable")
func client_receive_gathered_items(item_id_yielded: String, quantity_yielded: int) -> void:
	if not is_multiplayer_authority():
		print("Player NODE [", name, "] on PEER [", multiplayer.get_unique_id(), "] received client_receive_gathered_items BUT IS NOT AUTHORITY. Ignoring.")
		return

	var item_base_res = ItemDatabase.get_item_base(item_id_yielded)
	if item_base_res is ItemData:
		var item_instance_to_add = item_base_res.duplicate()
		item_instance_to_add.quantity = quantity_yielded
	else:
		printerr("  -> Could not find item base for '", item_id_yielded, "' in ItemDatabase. (Client ", name, ")")


@rpc("call_local", "authority", "reliable")
func client_crafting_result(was_successful: bool, crafted_item_id: String, message: String):
	print("Player [", name, "] (Client Authority) Crafting Result: ", was_successful, " Item: ", crafted_item_id, " Msg: ", message)
	print("  -> Emitting 'crafting_attempt_completed' signal...")
	emit_signal("crafting_attempt_completed", was_successful, crafted_item_id, message)

	if was_successful:
		print("  -> Client: Crafting was successful on server. UI should update based on Inventory signals.")
		# If CraftingMenu is open, it listens to Inventory signals and should refresh its displays.
		if is_instance_valid(hud) and hud.is_crafting_menu_open():
			if is_instance_valid(hud.crafting_menu_instance) and hud.crafting_menu_instance.has_method("_refresh_all_recipe_entry_counts"):
				hud.crafting_menu_instance._refresh_all_recipe_entry_counts()
			if is_instance_valid(hud.crafting_menu_instance) and hud.crafting_menu_instance.has_method("_on_recipe_entry_selected"):
				if is_instance_valid(hud.crafting_menu_instance.currently_selected_recipe_item):
					hud.crafting_menu_instance._on_recipe_entry_selected(hud.crafting_menu_instance.currently_selected_recipe_item)
		# TODO: Play crafting success sound
	else:
		print("  -> Client: Crafting failed on server. Reason: ", message)
		# TODO: Show error message to player on UI (e.g., "Missing Ingredients", "Inventory Full")

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
										item_id_being_dropped: String, # New argument
										max_attempts: int = 5,
										# Define different parameters
										check_radius_same_item: float = 5.0,
										spread_distance_same_item: float = 6.0,
										check_radius_diff_item: float = 10.0, # Larger radius for different items
										spread_distance_diff_item: float = 12.0 # Spread further for different items
										) -> Vector2:
	if not get_world_2d(): return target_pos

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var check_shape = CircleShape2D.new()
	# query.collision_mask = YOUR_DROPPED_ITEM_LAYER_BIT
	query.collide_with_areas = true
	query.collide_with_bodies = false
	# Exclude the player who is dropping if this is called on server
	# query.exclude = [self.get_rid()] # 'self' here is the Player node (server instance)

	var current_pos = target_pos
	for i in range(max_attempts):
		var current_check_radius = check_radius_same_item # Assume checking against same item type initially

		query.transform = Transform2D(0, current_pos)
		# Temporarily set shape radius for this check iteration
		# Note: This isn't ideal as shape is shared. Better to have two query objects or adjust radius per check.
		# For now, let's just use a general radius and adjust spread based on type.
		check_shape.radius = check_radius_diff_item # Use larger radius for general detection
		query.shape = check_shape
		var results = space_state.intersect_shape(query)

		var collision_with_diff_item_found = false
		var collision_with_any_item_found = false

		for result in results:
			if result.collider is DroppedItem:
				collision_with_any_item_found = true
				var existing_item = result.collider as DroppedItem
				var existing_item_data = existing_item.get_item_data()
				if is_instance_valid(existing_item_data) and existing_item_data.item_id != item_id_being_dropped:
					collision_with_diff_item_found = true
					break # Prioritize spreading from different items

		if not collision_with_any_item_found:
			return current_pos # Found a clear spot

		# Determine spread distance
		var current_spread_distance = spread_distance_same_item
		if collision_with_diff_item_found:
			current_spread_distance = spread_distance_diff_item
			print("Drop collision with DIFFERENT item, using larger spread.")
		# else: print("Drop collision with SAME item or general, using smaller spread.")


		# If collision found, try a slightly different position nearby
		var angle_offset = float(i) * (TAU / float(max_attempts)) # Spread in a circle
		var angle = last_direction.angle() + PI + angle_offset # Try to drop behind player, then spread
		# If last_direction is zero, pick a default
		if last_direction == Vector2.ZERO and i == 0 : angle = randf_range(0, TAU)


		var dist_offset = current_spread_distance * (randf() * 0.3 + 0.7) # Slight randomness
		current_pos = target_pos + Vector2(cos(angle), sin(angle)) * dist_offset
		# print("Drop collision, trying new position:", current_pos)

	# print("Max drop attempts reached for overlap, placing at last attempt:", current_pos)
	return current_pos


func find_nearby_stackable_dropped_item(item_id_to_match: String, at_position: Vector2, radius: float) -> DroppedItem:
	if not multiplayer.is_server(): return null # Server only

	# Get the node where dropped items live
	var main_node_ref = SceneManager.main_scene_root
	if not is_instance_valid(main_node_ref): return null
	var dropped_item_spawner = main_node_ref.dropped_item_spawner
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

func _update_remote_equipped_visuals() -> void:
	if is_multiplayer_authority(): return # Should only run on remote instances

	print("Player [", name, "] (Remote) updating visuals for synced_equipped_item_id: '", synced_equipped_item_id, "'")

	_current_equipped_item_data_for_visuals = null # Reset
	if not synced_equipped_item_id.is_empty():
		_current_equipped_item_data_for_visuals = ItemDatabase.get_item_base(synced_equipped_item_id)

	if is_instance_valid(equipped_item_sprite):
		if is_instance_valid(_current_equipped_item_data_for_visuals) and \
			_current_equipped_item_data_for_visuals.is_equippable() and \
			is_instance_valid(_current_equipped_item_data_for_visuals.equipped_texture):
			equipped_item_sprite.texture = _current_equipped_item_data_for_visuals.equipped_texture
			equipped_item_sprite.visible = true
			print("  -> Remote visual set to: ", _current_equipped_item_data_for_visuals.item_id)
		else:
			equipped_item_sprite.texture = null
			equipped_item_sprite.visible = false
			if synced_equipped_item_id.is_empty():
				print("  -> Remote visual cleared (no item).")
			else:
				print("  -> Remote visual could not be set (item '", synced_equipped_item_id, "' not found, not equippable, or no texture).")

	_update_hand_and_weapon_animation() # Update hand position etc.

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

func _update_resource_node_target_and_prompt() -> void:
	if not is_multiplayer_authority(): return # Only local player handles its own UI prompts

	var best_target_node: ResourceNode = null
	var min_dist_sq = INF

	# Clean up invalid or depleted nodes from the list first
	for i in range(nearby_resource_nodes.size() - 1, -1, -1):
		var node = nearby_resource_nodes[i]
		if not is_instance_valid(node) or node.is_depleted:
			# If it was the current target and becomes invalid/depleted, clear the prompt
			if _currently_targeted_resource_node == node:
				if is_instance_valid(hud) and hud.has_method("hide_generic_interaction_prompt"):
					hud.hide_generic_interaction_prompt()
					_currently_targeted_resource_node = null
			nearby_resource_nodes.remove_at(i)
			continue

		# Consider for distance if valid
		var dist_sq = global_position.distance_squared_to(node.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_target_node = node

	# Update prompt based on best_target_node
	if is_instance_valid(best_target_node):
		if _currently_targeted_resource_node != best_target_node: # Target changed or new target found
			_currently_targeted_resource_node = best_target_node
			# Show prompt for the new target
			if is_instance_valid(hud) and hud.has_method("show_generic_interaction_prompt"):
				var prompt_message = "Gather (E)" # Default
				if best_target_node.required_tool_type != ItemData.ItemType.MISC:
					if not is_instance_valid(equipped_item_data) or \
						equipped_item_data.item_type != best_target_node.required_tool_type:
						prompt_message = "Requires " + ItemData.ItemType.keys()[best_target_node.required_tool_type].capitalize()
				hud.show_generic_interaction_prompt(prompt_message)
		# Else: Best target is already prompted, do nothing (or refresh if prompt can change dynamically)

	else: # No best target found (or all nearby are depleted/invalid)
		if is_instance_valid(_currently_targeted_resource_node): # If there *was* a target
			if is_instance_valid(hud) and hud.has_method("hide_generic_interaction_prompt"):
				hud.hide_generic_interaction_prompt()
			_currently_targeted_resource_node = null

# --- Equipping ---
func _equip_item(item_data: ItemData):
	if not is_multiplayer_authority():
		# Remote players should not directly call _equip_item based on their own inventory signals.
		# Their visuals are driven by synced_equipped_item_id.
		# However, if _equip_item IS called on a remote instance for some other reason,
		# ensure it doesn't try to update synced_equipped_item_id.
		# The _update_remote_equipped_visuals handles their sprite.
		if is_instance_valid(equipped_item_sprite):
			# This is a bit redundant if _update_remote_equipped_visuals is robust,
			# but ensures remote instances don't take over their visuals if _equip_item is accidentally called.
			if _current_equipped_item_data_for_visuals and is_instance_valid(_current_equipped_item_data_for_visuals.equipped_texture):
				equipped_item_sprite.texture = _current_equipped_item_data_for_visuals.equipped_texture
				equipped_item_sprite.visible = true
			else:
				equipped_item_sprite.texture = null
				equipped_item_sprite.visible = false
		return

	# Local authority player's logic:
	var previous_equipped_id = ""
	if is_instance_valid(equipped_item_data): # Your existing variable for local logic
		previous_equipped_id = equipped_item_data.item_id

	equipped_item_data = null # Clear previous state for local logic
	if is_instance_valid(equipped_item_sprite): equipped_item_sprite.visible = false

	var new_synced_id = ""
	if item_data != null and item_data is ItemData and item_data.is_equippable():
		equipped_item_data = item_data # For local player's direct logic (e.g., attack checks)
		if is_instance_valid(equipped_item_sprite):
			equipped_item_sprite.texture = item_data.equipped_texture
			equipped_item_sprite.visible = (item_data.equipped_texture != null)
		print("Player [", name, "] (Local Authority) equipped:", equipped_item_data.item_id)
		new_synced_id = equipped_item_data.item_id
	else:
		print("Player [", name, "] (Local Authority) equipped nothing (or item not equippable).")
		new_synced_id = "" # Equipped nothing

	# Update the synced variable if it has changed
	if self.synced_equipped_item_id != new_synced_id:
		self.synced_equipped_item_id = new_synced_id # This will trigger the setter and sync

	_update_hand_and_weapon_animation() # Update hand position etc.

func try_use_selected_item():
	var selected_item: ItemData = Inventory.get_selected_item()

	if selected_item != null and selected_item is ItemData:
		if selected_item.item_type == ItemData.ItemType.WEAPON:
			print("'Use' action pressed, but selected item is a weapon. Attack action handles this.")
			return # Don't consume consumables etc. if weapon selected and LMB pressed

		match selected_item.item_type:
			ItemData.ItemType.CONSUMABLE:
				if _can_use_consumable(selected_item):
					_consume_item(selected_item, Inventory.selected_slot_index)
				else:
					print("Cannot use '", selected_item.item_id, "' right now (e.g., health full).")
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

func process_server_craft_attempt(item_id_to_craft: String):
	if not multiplayer.is_server():
		printerr("CRITICAL: process_server_craft_attempt called on client instance for ", name)
		return

	# 'self.name' should be the string representation of the peer_id for this player instance
	var owner_peer_id = self.name.to_int() # This is the peer_id of the player this server node instance represents

	print("Player ", name, " (Server Instance, Owner Peer: ", owner_peer_id, ") processing server craft attempt for: ", item_id_to_craft)

	var craftable_item_data = ItemDatabase.get_item_base(item_id_to_craft)
	if not is_instance_valid(craftable_item_data) or craftable_item_data.crafting_ingredients.is_empty():
		printerr("  -> Server: Invalid item_id '", item_id_to_craft, "' or item is not craftable.")
		client_crafting_result.rpc(false, item_id_to_craft, "Invalid recipe.") # RPC back to the client who owns this player instance
		return

	# --- TODO: Add Crafting Station Check (e.g., Forge) ---
	# var required_station = craftable_item_data.get("required_station_type", "")
	# if not required_station.is_empty():
	#     if not is_near_crafting_station(required_station, owner_peer_id): # Pass owner_peer_id if needed
	#         print("  -> Server: Player not near required station '", required_station, "' for '", item_id_to_craft, "'")
	#         client_crafting_result.rpc(false, item_id_to_craft, "Required station not nearby.")
	#         return
	# ---------------------------------------------------------

	var has_all_ingredients = true
	var ingredients_to_consume_details: Array[Dictionary] = [] # Store details for actual consumption

	for ingredient_dict in craftable_item_data.crafting_ingredients:
		var req_item_id = ingredient_dict.get("item_id")
		var req_qty = ingredient_dict.get("quantity")
		
		# Use ServerInventoryManager to check this specific player's authoritative inventory
		var player_has_qty = ServerInventoryManager.get_player_item_quantity_by_id(owner_peer_id, req_item_id)
		
		if player_has_qty < req_qty:
			has_all_ingredients = false
			print("  -> Server: Player ", name, " (Peer:", owner_peer_id, ") missing ingredient ", req_item_id, " (Needs:", req_qty, " Has:", player_has_qty, ")")
			break
		ingredients_to_consume_details.append({"item_id": req_item_id, "quantity": req_qty})
		
	if not has_all_ingredients:
		printerr("  -> Server: Crafting failed for ", name, " (Peer:", owner_peer_id, ") - Missing ingredients for '", item_id_to_craft, "'.")
		client_crafting_result.rpc(false, item_id_to_craft, "Missing ingredients.")
		return

	# 2. Server-side: Consume Ingredients using ServerInventoryManager
	print("  -> Server: Consuming ingredients for ", name, " (Peer:", owner_peer_id, ") to craft '", item_id_to_craft, "'")
	for ingredient_to_consume in ingredients_to_consume_details:
		var item_id_con = ingredient_to_consume.get("item_id")
		var qty_con = ingredient_to_consume.get("quantity")
		if not ServerInventoryManager.remove_item_from_player_inventory_by_id_and_quantity(owner_peer_id, item_id_con, qty_con):
			printerr("  -> SERVER CRITICAL ERROR: Failed to consume ", item_id_con, " for player ", name, " (Peer:", owner_peer_id, ") even after check! Inventory desync or SIM logic error.")
			# Attempt to rollback or handle inconsistency. For now, notify client of generic error.
			client_crafting_result.rpc(false, item_id_to_craft, "Internal server error during ingredient consumption.")
			return 

	# 3. Server-side: Add Crafted Item using ServerInventoryManager
	print("  -> Server: Adding crafted item '", item_id_to_craft, "' to player ", name, " (Peer:", owner_peer_id, ")'s inventory.")
	var crafted_item_instance_server = craftable_item_data.duplicate() # Server gets its own fresh instance
	crafted_item_instance_server.quantity = 1 # Assuming recipes produce 1 for now
	
	if not ServerInventoryManager.add_item_to_player_inventory(owner_peer_id, crafted_item_instance_server):
		printerr("  -> SERVER CRITICAL ERROR: Inventory full for player ", name, " (Peer:", owner_peer_id, ") after consuming ingredients for '", item_id_to_craft, "'. Item lost on server!")
		client_crafting_result.rpc(false, item_id_to_craft, "Inventory full on server after crafting.")
		# TODO: Ideally, drop the item on the ground near the player on the server.
		return

	# 4. Notify the original client of success
	print("  -> Server: Crafting successful for player ", name, " (Peer:", owner_peer_id, "). Notifying client.")
	client_crafting_result.rpc(true, item_id_to_craft, "Crafted successfully!") # RPC to the client who owns this player instance

func _try_gather_from_node(node_to_gather_from: ResourceNode) -> void:
	if not is_multiplayer_authority(): return
	if not is_instance_valid(node_to_gather_from): return

	print("Player ", name, " requesting to gather from: ", node_to_gather_from.name)

	# 1. Client-side tool check (still good for immediate feedback)
	var required_tool = node_to_gather_from.required_tool_type
	var has_required_tool = false
	if required_tool == ItemData.ItemType.MISC:
		has_required_tool = true
	elif is_instance_valid(equipped_item_data) and equipped_item_data.item_type == required_tool:
		has_required_tool = true

	if not has_required_tool:
		print("  -> Tool requirement not met. Needs: ", ItemData.ItemType.keys()[required_tool])
		if is_instance_valid(hud) and hud.has_method("show_temporary_message"): # Optional
			hud.show_temporary_message("Requires " + ItemData.ItemType.keys()[required_tool].capitalize(), 1.5)
		return
		
	if not is_instance_valid(SceneManager.current_level_root):
		printerr("Player: Cannot get relative path for ResourceNode, current_level_root is invalid.")
		return

	var node_path_from_level: NodePath = SceneManager.current_level_root.get_path_to(node_to_gather_from)
	if node_path_from_level.is_empty():
		printerr("Player: Could not get path for ResourceNode: ", node_to_gather_from.name)
		return

	print("  -> Sending gather request to server for node path: ", node_path_from_level)

	# RPC to Main.gd on the server (peer_id 1)
	var main_node: Node2D = SceneManager.main_scene_root
	main_node.rpc_id(1, "server_process_gather_request", node_path_from_level)

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

func _on_pickup_area_entered(area: Area2D) -> void:
	if area is DroppedItem:
		var item = area as DroppedItem
		if is_instance_valid(item) and not item in nearby_items:
			nearby_items.append(item)
	elif area.is_in_group("resource_node_interaction_zone"): # Check the group you assigned
		var resource_node = area.get_owner() as ResourceNode # Assuming the Area2D's owner is the ResourceNode
		if is_instance_valid(resource_node) and not resource_node in nearby_resource_nodes:
			if not resource_node.is_depleted: # Only add if not initially depleted
				nearby_resource_nodes.append(resource_node)
	elif area.is_in_group("player_pickup_area"):
		pass
	# ... (rest of your existing logic for other area types) ...
	else:
		print("Player pickup area entered unknown/unhandled area type:", area.name, " (Owner: ", area.get_owner().name if area.get_owner() else "None", ")")

func _on_pickup_area_exited(area):
	if area is DroppedItem:
		var item = area as DroppedItem
		if item in nearby_items:
			nearby_items.erase(item)
			if _currently_prompted_item == item:
				if is_instance_valid(item): item.hide_prompt() # Hide its prompt
				_currently_prompted_item = null
	elif area.is_in_group("resource_node_interaction_zone"): # Check the group
		var resource_node = area.get_owner() as ResourceNode
		if resource_node in nearby_resource_nodes:
			nearby_resource_nodes.erase(resource_node)
			# If this node was the targeted one, clear the target and its HUD prompt
			if _currently_targeted_resource_node == resource_node:
				if is_instance_valid(hud) and hud.has_method("hide_generic_interaction_prompt"):
					hud.hide_generic_interaction_prompt()
				_currently_targeted_resource_node = null

func _on_animation_finished(_anim_name: String):
	# Keep existing attack animation logic
	if current_state == State.ATTACK and animated_sprite.animation.begins_with("attack_"):
		current_state = State.IDLE_RUN
		_update_hand_and_weapon_animation()

func _on_selected_slot_changed(_new_index: int, _old_index: int, item_data: ItemData):
	if is_multiplayer_authority(): # Only the authoritative player processes their own inventory selection
		print("Player [", name, "] detected selected slot change. New Item:", item_data)
		_equip_item(item_data)
