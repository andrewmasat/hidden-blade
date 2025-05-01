# DroppedItem.gd
extends Area2D
class_name DroppedItem

@onready var sprite: TextureRect = $ItemSprite
@onready var quantity_label: Label = $QuantityLabel
@onready var prompt_label: Label = $PromptLabel

var item_data: ItemData = null

# Bounce animation parameters
@export var bounce_height: float = 12.0 # Pixels to bounce up
@export var bounce_duration: float = 0.3 # Seconds for the bounce animation


func initialize(data: ItemData, start_position: Vector2): # Add start_position
	if data == null or not data is ItemData:
		printerr("DroppedItem: Invalid ItemData provided during initialization!")
		queue_free()
		return

	item_data = data
	global_position = start_position # Set initial position passed from player

	# --- Update Visuals ---
	monitoring = false
	if is_instance_valid(prompt_label):
		prompt_label.visible = false
	if is_instance_valid(sprite) and item_data.texture:
		sprite.texture = item_data.texture
	else:
		printerr("DroppedItem: ItemData missing texture or Sprite node invalid!")

	# --- Update Quantity Label ---
	update_quantity_label()

	print("DroppedItem initialized at", global_position, "with:", item_data.item_id, " Qty:", item_data.quantity)

	# --- Start Bounce Animation ---
	play_bounce_animation()


func update_quantity_label() -> void:
	if not is_instance_valid(quantity_label): return # Node doesn't exist

	if item_data and item_data.max_stack_size > 1 and item_data.quantity > 1:
		quantity_label.text = str(item_data.quantity)
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

	print("DroppedItem:", item_data.item_id if item_data else "??", "bounce finished, enabling monitoring.") # Debug
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
			print("DroppedItem:", item_data.item_id if item_data else "??", "already overlapping with player on enable.") # Debug
			show_prompt(area.get_parent() as Node2D)
			break # No need to check further areas


func get_item_data() -> ItemData:
	return item_data


func _on_area_entered(area: Area2D) -> void:
	# This will now only fire AFTER monitoring is enabled
	if area.is_in_group("player_pickup_area"):
		print("DroppedItem:", item_data.item_id if item_data else "??", "detected player pickup area entry.")
		show_prompt(area.get_parent() as Node2D)


func _on_area_exited(area: Area2D) -> void:
	# This will also only fire AFTER monitoring is enabled
	if area.is_in_group("player_pickup_area"):
		print("DroppedItem:", item_data.item_id if item_data else "??", "detected player pickup area exit.")
		hide_prompt()


# Shows and updates the prompt label based on item type.
func show_prompt(player_node: Node2D = null) -> void: # Optional player reference
	if not is_instance_valid(prompt_label): return

	# --- Determine Prompt Text ---
	# Default prompt
	var prompt_text = "Pick Up  [F]" # Assuming 'F' is your interact key

	# Customize based on item type (optional)
	if item_data != null:
		match item_data.item_type:
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
	# if Inventory.can_add_item_check(item_data):
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
