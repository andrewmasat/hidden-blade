# DroppedItem.gd
extends Area2D
class_name DroppedItem

@onready var sprite: TextureRect = $ItemSprite
@onready var quantity_label: Label = $QuantityLabel
@onready var prompt_label: Label = $PromptLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

enum DropMode { GLOBAL, PERSONAL }

var _item_identifier_synced: String = ""
var item_identifier_synced: String:
	get: return _item_identifier_synced
	set(new_id_or_path):
		if _item_identifier_synced == new_id_or_path and _item_identifier_synced != "": return # Avoid re-processing if truly same and not initial default
		var old_id = _item_identifier_synced
		_item_identifier_synced = new_id_or_path
		print("DroppedItem [", name, "] (Peer:", multiplayer.get_unique_id() if multiplayer else "N/A", ") SETTER item_identifier_synced. Old:", old_id, "New:", _item_identifier_synced) # DETAILED DEBUG
		_reconstruct_local_item_data()
		_request_visual_update() # Always request update after potential reconstruction

var _quantity_synced: int = 0 # Default to 0 to ensure sync with 1 triggers setter
var quantity_synced: int:
	get: return _quantity_synced
	set(new_qty):
		if _quantity_synced == new_qty and _quantity_synced != 0 : return # Avoid re-processing if truly same and not initial default
		var old_qty = _quantity_synced
		_quantity_synced = new_qty
		print("DroppedItem [", name, "] (Peer:", multiplayer.get_unique_id() if multiplayer else "N/A", ") SETTER quantity_synced. Old:", old_qty, "New:", _quantity_synced) # DETAILED DEBUG
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
	if _item_identifier_synced == new_id_or_path: return
	_item_identifier_synced = new_id_or_path
	print("DroppedItem [", name, "] (Peer:", multiplayer.get_unique_id() if multiplayer else "N/A", ") Synced ID to:", _item_identifier_synced)
	_reconstruct_local_item_data() # This will set _local_item_data_instance
	# After reconstruction, explicitly request a visual update if node is ready.
	# The _request_visual_update will handle deferring if needed.
	if is_node_ready():
		_request_visual_update()

func set_quantity_synced(new_qty: int):
	if _quantity_synced == new_qty: return
	_quantity_synced = new_qty
	print("DroppedItem [", name, "] (Peer:", multiplayer.get_unique_id() if multiplayer else "N/A", ") Synced Qty to:", _quantity_synced)
	# If _local_item_data_instance already exists due to identifier being set first, update its quantity.
	if is_instance_valid(_local_item_data_instance):
		_local_item_data_instance.quantity = _quantity_synced
	else: # Otherwise, full reconstruction is needed (identifier might not have been set yet)
		_reconstruct_local_item_data()
	if is_node_ready():
		_request_visual_update()

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
	self.item_identifier_synced = p_item_data_ref.resource_path if not p_item_data_ref.resource_path.is_empty() else p_item_data_ref.item_id
	self.quantity_synced = p_item_data_ref.quantity
	self.drop_mode = p_drop_mode
	self.owner_peer_id = p_owner_peer_id
	self.item_unique_id = p_unique_id
	self.global_position = start_position

	# Since this is server init, ensure local data is also immediately consistent
	# The setters for item_identifier_synced & quantity_synced will call _reconstruct_local_item_data
	# _update_visuals_and_interaction will be called by _request_visual_update from setters.

	print("DroppedItem [", name, "] SERVER initialized. UniqueID:", self.item_unique_id, "ItemID:", self.item_identifier_synced, "Qty:", self.quantity_synced)
	play_bounce_animation()


func _ready():
	var peer_id_str = str(multiplayer.get_unique_id()) if multiplayer else "N/A"
	print("DroppedItem [", name, "] _ready. Peer:", peer_id_str, \
		  " Initial _item_identifier_synced:", _item_identifier_synced, \
		  " Initial _quantity_synced:", _quantity_synced)
	call_deferred("_request_visual_update")


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
	# Check if node still exists before enabling
	if not is_instance_valid(self): return

	monitoring = true
	# Check if player is ALREADY overlapping when monitoring starts
	check_initial_overlap()


# Check if player is already inside when monitoring is enabled
func check_initial_overlap() -> void:
	# Get overlapping areas *now* that monitoring is enabled
	var overlapping_areas = get_overlapping_areas()
	for area in overlapping_areas:
		if area.is_in_group("player_pickup_area"):
			# Player was already inside, show prompt immediately
			show_prompt(area.get_parent() as Node2D)
			break # No need to check further areas


func get_item_data() -> ItemData:
	return _local_item_data_instance


func _on_area_entered(area: Area2D) -> void:
	# This check is now redundant IF monitoring is correctly disabled, but good as a safeguard.
	if not self.visible or not self.monitoring: return

	if area.is_in_group("player_pickup_area"):
		var player_node = area.get_parent()
		# Only show prompt if this client's player entered
		if is_instance_valid(player_node) and player_node.is_multiplayer_authority():
			print("DroppedItem [", name, "] showing prompt for local player.")
			show_prompt(player_node)


func _on_area_exited(area: Area2D) -> void:
	# Redundant check, good safeguard.
	if not self.visible or not self.monitoring: return

	if area.is_in_group("player_pickup_area"):
		var player_node = area.get_parent()
		if is_instance_valid(player_node) and player_node.is_multiplayer_authority():
			hide_prompt()


func _on_synced_property_changed(property_name: StringName):
	# When a relevant synced property changes, refresh visuals and interaction state.
	# property_name can be used to be more specific if needed, but for now, just update all.
	if not is_instance_valid(self): return # Node might be freeing during signal callback
	print("DroppedItem [", name, "] synced property changed (or ready). Updating state. Property:", property_name) # Debug
	_update_visuals_and_interaction()

# Shows and updates the prompt label based on item type.
func show_prompt(_player_node: Node2D = null) -> void: # Optional player reference
	if not is_instance_valid(prompt_label): return
	# Final check: only show if still visible and monitoring (interactive for me)
	if not self.visible or not self.monitoring:
		prompt_label.visible = false # Ensure it's hidden
		return

	# --- Determine Prompt Text ---
	# Default prompt
	var prompt_text = "Pick Up  [F]" # Assuming 'F' is your interact key

	# Customize based on item type (optional)
	if _local_item_data_instance != null:
		match _local_item_data_instance.item_type:
			ItemData.ItemType.WEAPON:
				prompt_text = "Equip  [F]" # Example
			ItemData.ItemType.CONSUMABLE:
				prompt_text = "Take  [F]" # Example
			ItemData.ItemType.RESOURCE:
				prompt_text = "Gather  [F]" # Example
			# Add other types if needed
			_: # Default for MISC, TOOL, PLACEABLE etc.
				prompt_text = "Pick Up  [F]"

	# --- Check if Player can Actually Pick Up (Optional but good) ---
	# This prevents showing "Pick Up" if inventory is full.
	# Requires communication back to Inventory singleton.
	var can_pickup = true # Assume yes initially
	# Example check (needs Inventory function):
	# if Inventory.can_add_item_check(_local_item_data_instance):
	#	 can_pickup = true
	# else:
	#	 can_pickup = false
	#	 prompt_text = "[Inventory Full]" # Change text if cannot pick up

	if can_pickup:
		prompt_label.text = prompt_text
		prompt_label.visible = true
	elif prompt_label.modulate != Color.RED: # Only show "Inventory Full" if we can't pick up
		prompt_label.text = "[Inventory Full]"
		prompt_label.modulate = Color.RED # Make it red
		prompt_label.visible = true


# Hides the prompt label.
func hide_prompt() -> void:
	if is_instance_valid(prompt_label):
		prompt_label.visible = false
		prompt_label.modulate = Color.WHITE # Reset color modulation
