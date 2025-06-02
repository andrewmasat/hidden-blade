extends Node2D
class_name ResourceNode

# --- Configuration ---
@export var yields_item_id: String = "some_material" # To be set in the Inspector for each instance
@export var yields_quantity: int = 1
@export var max_node_health: int = 3 # How many "hits" or interactions to deplete
@export var required_tool_type: ItemData.ItemType = ItemData.ItemType.MISC # Default: any tool or no tool
# Optional: @export var specific_tool_id: String = "" # If a VERY specific tool is needed (e.g., "iron_pickaxe")
@export var respawn_delay_seconds: float = 30.0

# --- State ---
var current_node_health: int:
	set(value):
		if current_node_health == value: return
		current_node_health = value
		# Optional: Update visuals based on health stages on clients if needed
		# _update_health_visuals()

var is_depleted: bool = false:
	set(value):
		if is_depleted == value: return
		is_depleted = value
		_update_visual_state() # This will now react to server-driven changes on clients
		# Server specific logic for starting respawn timer
		if is_multiplayer_authority(): # Check if this instance is server-controlled
			if is_depleted:
				if respawn_delay_seconds > 0:
					respawn_timer.start(respawn_delay_seconds)
			# else: # Just respawned, health set by server
				# current_node_health = max_node_health # Server will set this directly


# --- Node References ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var respawn_timer: Timer = $RespawnTimer
# @onready var animation_player: AnimationPlayer = $AnimationPlayer # If you have animations

func _ready():
	if is_multiplayer_authority(): # Server sets initial state
		current_node_health = max_node_health
		is_depleted = false # Explicitly set to trigger sync if needed
	# else: Clients will receive synced values

	respawn_timer.timeout.connect(_on_RespawnTimer_timeout)

	_update_visual_state() # Initial visual setup based on potentially synced values

# Called by the server (or directly in single player) when a player successfully interacts
func on_gather_interaction() -> Dictionary: # Returns a dictionary with item_id and quantity
	if not is_multiplayer_authority(): # GUARD: Only server can process this
		printerr("ResourceNode: on_gather_interaction called on non-authority instance!")
		return {}

	if is_depleted:
		return {}

	current_node_health -= 1

	if current_node_health <= 0:
		current_node_health = 0
		var items_yielded = {
			"item_id": yields_item_id,
			"quantity": yields_quantity
		}
		_deplete_node() # This will set is_depleted = true, server handles respawn timer
		return items_yielded

	# If syncing current_node_health, the synchronizer will handle sending this change.
	# If not watching properties, you might need to manually notify:
	# if get_multiplayer().is_server() and multiplayer_synchronizer.has_method("notify_property_changed"):
	# multiplayer_synchronizer.notify_property_changed(&"current_node_health")

	return {}


func _deplete_node():
	if not is_multiplayer_authority(): return # Server only
	self.is_depleted = true # Setter on server starts respawn timer & syncs


func _respawn_node():
	if not is_multiplayer_authority(): return # Server only
	self.current_node_health = max_node_health # Server resets health
	self.is_depleted = false # Server sets state, which syncs


func _update_visual_state():
	if is_depleted:
		sprite.modulate = Color(0.5, 0.5, 0.5, 0.5) # Example: Dim and fade if depleted
		interaction_area.monitorable = false # Can't interact if depleted
		interaction_area.monitoring = false
	else:
		sprite.modulate = Color.WHITE
		interaction_area.monitorable = true
		interaction_area.monitoring = true
	# Add more complex visual changes here (e.g., swapping sprite texture)


func _on_RespawnTimer_timeout():
	if is_multiplayer_authority(): # Only server should process respawn logic
		_respawn_node()

# --- Multiplayer Synchronization Placeholder ---
# In a real multiplayer scenario, current_node_health and is_depleted
# would need to be synchronized from the server to clients.
# The server would authoritatively call on_gather_interaction.
# For now, this script will work in a single-player context.
# We will add MultiplayerSynchronizer later.
