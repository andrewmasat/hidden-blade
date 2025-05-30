# DroppedItem.gd
extends Area2D
class_name DroppedItem

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: TextureRect = $ItemSprite
@onready var quantity_label: Label = $QuantityLabel
@onready var prompt_label: Label = $PromptLabel
@onready var despawn_timer: Timer = $DespawnTimer

@export var default_despawn_duration: float = 60.0

enum DropMode { GLOBAL, PERSONAL }

var _item_identifier_synced: String = ""
var item_identifier_synced: String:
	get: return _item_identifier_synced
	set(new_id_or_path):
		if _item_identifier_synced == new_id_or_path and _item_identifier_synced != "": return # Avoid re-processing if truly same and not initial default
		var old_id = _item_identifier_synced
		_item_identifier_synced = new_id_or_path
		_reconstruct_local_item_data()
		_request_visual_update() # Always request update after potential reconstruction

var _quantity_synced: int = 0 # Default to 0 to ensure sync with 1 triggers setter
var quantity_synced: int:
	get: return _quantity_synced
	set(new_qty):
		if _quantity_synced == new_qty and _quantity_synced != 0 : return # Avoid re-processing if truly same and not initial default
		var old_qty = _quantity_synced
		_quantity_synced = new_qty
		if is_instance_valid(_local_item_data_instance):
			_local_item_data_instance.quantity = _quantity_synced
		else:
			_reconstruct_local_item_data()
		_request_visual_update()

var _drop_mode: DropMode = DropMode.GLOBAL
var drop_mode: DropMode:
	get: return _drop_mode
	set(new_mode):
		if _drop_mode == new_mode: return
		_drop_mode = new_mode
		_request_visual_update()

var _owner_peer_id: int = 0
var owner_peer_id: int:
	get: return _owner_peer_id
	set(new_id):
		if _owner_peer_id == new_id: return
		_owner_peer_id = new_id
		_request_visual_update()

var _item_unique_id: String = ""
var item_unique_id: String:
	get: return _item_unique_id
	set(new_id):
		if _item_unique_id == new_id: return
		_item_unique_id = new_id
		# No visual update needed for ID usually. If you display it, call _request_visual_update()

var _local_item_data_instance: ItemData = null
var _visual_update_requested: bool = false

@export var bounce_height: float = 12.0 # Pixels to bounce up
@export var bounce_duration: float = 0.3 # Seconds for the bounce animation

# --- Setters for Synced Properties ---
func set_item_identifier_synced(new_id_or_path: String):
	if _item_identifier_synced == new_id_or_path and _item_identifier_synced != "": return
	_item_identifier_synced = new_id_or_path
	# Avoid multiplayer check here; this setter is for when data IS synced
	# print("DroppedItem [", name, "] (Peer:", multiplayer.get_unique_id() if is_node_ready() and multiplayer else "PreReady", ") SETTER item_identifier_synced..." )
	_reconstruct_local_item_data()
	_request_visual_update()

func set_quantity_synced(new_qty: int):
	# if _quantity_synced == new_qty and _quantity_synced != 0: return # Keep this to avoid no-op syncs
	# Allow setting to 0 if item is fully depleted (e.g. partial pickup later)
	if _quantity_synced == new_qty: return

	var old_qty = _quantity_synced
	_quantity_synced = new_qty
	print("DroppedItem [", name, "] (Peer:", multiplayer.get_unique_id() if multiplayer else "N/A", ") SETTER quantity_synced. Old:", old_qty, "New:", _quantity_synced)

	# Update the quantity on the local ItemData instance if it exists
	if is_instance_valid(_local_item_data_instance):
		_local_item_data_instance.quantity = _quantity_synced
		print("  -> Updated _local_item_data_instance quantity to:", _local_item_data_instance.quantity)
	else:
		# If no instance, reconstruction will pick up the new quantity when identifier is set/synced
		_reconstruct_local_item_data() # This might be needed if qty changes before ID fully syncs

	_request_visual_update() # Always update visuals after quantity change

func set_drop_mode(new_mode: DropMode):
	if _drop_mode == new_mode: return
	_drop_mode = new_mode
	if is_node_ready(): _request_visual_update()

func set_owner_peer_id(new_id: int):
	if _owner_peer_id == new_id: return
	_owner_peer_id = new_id
	if is_node_ready(): _request_visual_update()

func set_item_unique_id(new_id: String):
	if _item_unique_id == new_id: return
	_item_unique_id = new_id
	# No visual update needed for gameplay ID itself


# --- Local ItemData Reconstruction ---
func _reconstruct_local_item_data() -> void:
	# print("DroppedItem [", name, "] _reconstruct_local_item_data. ID:", _item_identifier_synced, "Qty:", _quantity_synced) # Debug
	if _item_identifier_synced.is_empty():
		_local_item_data_instance = null
		return

	var base_res: ItemData = null
	if _item_identifier_synced.begins_with("res://"):
		base_res = load(_item_identifier_synced)
	elif ItemDatabase:
		base_res = ItemDatabase.get_item_base(_item_identifier_synced)

	if base_res is ItemData:
		# If instance exists and is same base type, just update qty. Else, new duplicate.
		if _local_item_data_instance != null and _local_item_data_instance.item_id == base_res.item_id:
			_local_item_data_instance.quantity = _quantity_synced
		else:
			_local_item_data_instance = base_res.duplicate()
			_local_item_data_instance.quantity = _quantity_synced
		# print("  -> Reconstructed/Updated _local_item_data_instance:", _local_item_data_instance.item_id, "Qty:", _local_item_data_instance.quantity)
	else:
		_local_item_data_instance = null
		printerr("DroppedItem [", name, "] Reconstruct: Failed to get base for:", _item_identifier_synced)

func _request_visual_update():
	if is_node_ready() and not _visual_update_requested:
		_visual_update_requested = true
		call_deferred("_deferred_update_visuals_and_interaction")

func _deferred_update_visuals_and_interaction():
	_visual_update_requested = false # Reset flag
	if not is_instance_valid(self): return # Node might have been freed
	_update_visuals_and_interaction()


func initialize_server_data(p_item_data_ref: ItemData, p_drop_mode: DropMode, p_owner_peer_id: int, p_unique_id: String, start_position: Vector2):
	# Server sets the properties that will trigger setters (and thus sync and reconstruction)
	_item_identifier_synced = p_item_data_ref.resource_path if not p_item_data_ref.resource_path.is_empty() else p_item_data_ref.item_id
	_quantity_synced = p_item_data_ref.quantity
	_drop_mode = p_drop_mode
	_owner_peer_id = p_owner_peer_id
	_item_unique_id = p_unique_id
	global_position = start_position

	_reconstruct_local_item_data()


func _ready():
	var peer_id_str = str(multiplayer.get_unique_id()) if multiplayer else "N/A"
	print("DroppedItem [", name, "] _ready. Peer:", peer_id_str, \
		  " Initial _item_identifier_synced:", _item_identifier_synced, \
		  " Initial _quantity_synced:", _quantity_synced)
	# Initial visual update based on properties set by initialize_server_data (on server)
	# or by MultiplayerSynchronizer via setters (on clients).
	_request_visual_update()
	play_bounce_animation() # Play bounce animation for all peers

	# Connect DespawnTimer timeout signal (only server needs to act on it)
	if multiplayer.is_server() and is_instance_valid(despawn_timer):
		# Start Despawn Timer (MOVED HERE - Server Only, after node is ready)
		var actual_despawn_duration = default_despawn_duration
		# ... (Optional: Get item-specific despawn time from _local_item_data_instance) ...
		if is_instance_valid(_local_item_data_instance) and _local_item_data_instance.has_method("get"):
			var item_specific_duration = _local_item_data_instance.get("world_despawn_duration")
			if item_specific_duration is float and item_specific_duration > 0.0: # Check type also
				actual_despawn_duration = item_specific_duration
		
		if actual_despawn_duration > 0.0:
			despawn_timer.wait_time = actual_despawn_duration
			despawn_timer.start()
			print("DroppedItem [", _item_unique_id, "] Despawn timer started by SERVER for", actual_despawn_duration, "s.")
		# else: print("DroppedItem [", _item_unique_id, "] No despawn needed or invalid duration.")

		# Connect signal
		if not despawn_timer.is_connected("timeout", Callable(self, "_on_DespawnTimer_timeout")):
			var err = despawn_timer.connect("timeout", _on_DespawnTimer_timeout) # Callable not needed for same script
			if err != OK: printerr("DroppedItem: Failed to connect despawn timer timeout. Error:", err)


func _on_DespawnTimer_timeout() -> void:
	if not multiplayer.is_server(): return # Should only execute on server

	print("DroppedItem [", _item_unique_id, "] Despawn timer timed out. Removing item.")
	# Server freeing the node will trigger MultiplayerSpawner to despawn it on clients
	queue_free()

func _update_visuals_and_interaction() -> void:
	if not is_node_ready(): return
	if not is_instance_valid(self): return

	var local_player_id = multiplayer.get_unique_id()
	var should_be_visible_and_interactive = false

	if self.drop_mode == DropMode.GLOBAL:
		should_be_visible_and_interactive = true
	elif self.drop_mode == DropMode.PERSONAL:
		if self.owner_peer_id != 0 and self.owner_peer_id == local_player_id:
			should_be_visible_and_interactive = true

	# We only set it if the calculated state is different.
	if self.visible != should_be_visible_and_interactive:
		self.visible = should_be_visible_and_interactive # This will be synced if 'visible' is in ReplicationConfig

	# 'monitoring' and 'collision_shape.disabled' should be PURELY local based on should_be_visible_and_interactive
	if self.monitoring != should_be_visible_and_interactive:
		self.monitoring = should_be_visible_and_interactive

	if is_instance_valid(collision_shape):
		var target_shape_disabled_state = not should_be_visible_and_interactive
		if collision_shape.disabled != target_shape_disabled_state:
			# This should be fine with set_deferred
			collision_shape.set_deferred("disabled", target_shape_disabled_state)

	# Update visual components only if this instance thinks it should be visible
	if self.visible:
		if is_instance_valid(_local_item_data_instance) and is_instance_valid(_local_item_data_instance.texture):
			if is_instance_valid(sprite):
				sprite.texture = _local_item_data_instance.texture
				sprite.visible = true
			update_quantity_label()
		else:
			if is_instance_valid(sprite):
				sprite.texture = null
				sprite.visible = false # Hide sprite
			if is_instance_valid(quantity_label):
				quantity_label.visible = false
	else: # Not visible to this client
		if is_instance_valid(sprite): sprite.visible = false
		if is_instance_valid(quantity_label): quantity_label.visible = false
		if is_instance_valid(prompt_label): prompt_label.visible = false


func update_quantity_label() -> void:
	if not is_instance_valid(quantity_label): return

	if is_instance_valid(_local_item_data_instance) and _local_item_data_instance.max_stack_size > 1 and _local_item_data_instance.quantity > 1:
		quantity_label.text = "x" + str(_local_item_data_instance.quantity)
		quantity_label.visible = true
	else:
		quantity_label.text = ""
		quantity_label.visible = false


func play_bounce_animation() -> void:
	# Create a tween to handle the animation
	var tween = create_tween()
	# Define the target position (upwards bounce)
	var bounce_target_pos = global_position - Vector2(0, bounce_height)
	# Define the final landing position (the initial position)
	var final_pos = global_position

	# Sequence: Bounce up quickly, then fall back down slightly slower
	tween.set_ease(Tween.EASE_OUT) # Ease out for the upward movement
	tween.set_trans(Tween.TRANS_QUAD) # Quadratic transition feels bouncy
	tween.tween_property(self, "global_position", bounce_target_pos, bounce_duration * 0.4)

	tween.set_ease(Tween.EASE_IN) # Ease in for the downward movement
	tween.set_trans(Tween.TRANS_BOUNCE) # Bounce transition for landing
	tween.tween_property(self, "global_position", final_pos, bounce_duration * 0.6)

	await tween.finished
	enable_interaction()

	# Optional: Could tween scale or rotation slightly too


func enable_interaction() -> void:
	if not is_instance_valid(self): return
	monitoring = true


func get_item_data() -> ItemData:
	return _local_item_data_instance


func _on_area_entered(area: Area2D) -> void:
	if not self.visible or not self.monitoring: return # Still good to have this guard
	if area.is_in_group("player_pickup_area"):
		# print("DroppedItem [", item_unique_id, "] detected player pickup area entry. Player will handle prompt.") # Debug
		pass # Player's _on_pickup_area_entered in Player.gd will add this to its nearby_items list.


func _on_area_exited(area: Area2D) -> void:
	if not self.visible or not self.monitoring: return
	if area.is_in_group("player_pickup_area"):
		# print("DroppedItem [", item_unique_id, "] detected player pickup area exit. Player will handle prompt.") # Debug
		# If this item was being prompted by the Player, the Player script will hide it.
		pass


func _on_synced_property_changed(property_name: StringName):
	# When a relevant synced property changes, refresh visuals and interaction state.
	# property_name can be used to be more specific if needed, but for now, just update all.
	if not is_instance_valid(self): return # Node might be freeing during signal callback
	print("DroppedItem [", name, "] synced property changed (or ready). Updating state. Property:", property_name) # Debug
	_update_visuals_and_interaction()


func show_prompt(player_node: Player = null) -> void:
	if not is_instance_valid(prompt_label): return
	if not self.visible or not self.monitoring:
		if is_instance_valid(prompt_label): prompt_label.visible = false
		return
	if is_instance_valid(player_node) and player_node.has_method("can_interact_with_prompts") and \
	   not player_node.can_interact_with_prompts():
		if is_instance_valid(prompt_label): prompt_label.visible = false
		return

	var current_item_data = get_item_data() # Uses the getter for _local_item_data_instance
	if not is_instance_valid(current_item_data):
		# No item data, maybe hide prompt or show generic error?
		prompt_label.text = "[Error: No Item Data]"
		prompt_label.modulate = Color.RED
		prompt_label.visible = true
		return

	# --- Check if player's local inventory can accept this item ---
	var can_pickup_inventory_wise = true
	if Inventory and Inventory.has_method("can_player_add_item_check"):
		# Pass a COPY of the item data, or at least its current quantity,
		# because can_player_add_item_check might simulate with it.
		# For this check, only the item_id, quantity, and max_stack_size are relevant from current_item_data
		can_pickup_inventory_wise = Inventory.can_player_add_item_check(current_item_data)
	# else: Inventory singleton not found or method missing, assume can pickup.

	var prompt_text = ""
	if not can_pickup_inventory_wise:
		prompt_text = "[Inventory Full]"
		prompt_label.modulate = Color.ORANGE_RED # Or some other warning color
	else:
		# Determine prompt text based on item type (if inventory not full)
		prompt_label.modulate = Color.WHITE # Reset color
		match current_item_data.item_type:
			ItemData.ItemType.WEAPON: prompt_text = "Equip (F)"
			ItemData.ItemType.CONSUMABLE: prompt_text = "Take (F)"
			ItemData.ItemType.RESOURCE: prompt_text = "Gather (F)"
			_: prompt_text = "Pick Up (F)" # Default

	prompt_label.text = prompt_text
	prompt_label.visible = true


# Hides the prompt label.
func hide_prompt() -> void:
	if is_instance_valid(prompt_label):
		prompt_label.visible = false
		prompt_label.modulate = Color.WHITE
