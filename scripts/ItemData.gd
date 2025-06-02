# ItemData.gd
extends Resource
class_name ItemData

enum ItemType {
	MISC,
	CONSUMABLE,
	WEAPON,
	TOOL,
	RESOURCE,
	PLACEABLE
}

# --- Existing Properties ---
@export var item_id: String = ""
@export var display_name: String = ""
@export var quantity: int = 1:
	set(value): quantity = max(0, value)
@export var max_stack_size: int = 1
@export var texture: Texture2D

# --- Property ---
@export var item_type : ItemType = ItemType.MISC

# --- Type Specific Properties ---
@export_group("Consumable")
@export var heal_amount: int = 0
@export_group("Weapon")
@export var equipped_texture: Texture2D
@export var damage: float = 0.0
@export_group("Placeable")
@export var placeable_scene: PackedScene
@export_group("Behavior")
@export var world_despawn_duration: float = 60.0
@export_group("Crafting")
## Array of dictionaries, e.g., [{"item_id": "wood_log", "quantity": 3}, {"item_id": "stone_chunk", "quantity": 1}]
## If this array is empty, the item is not craftable via this recipe system.
@export var crafting_ingredients: Array[Dictionary] = []
@export var crafting_time_seconds: float = 1.0

# --- Helper Functions ---
func is_stack_full() -> bool:
	return quantity >= max_stack_size

func can_add_to_stack(amount: int = 1) -> bool:
	return quantity + amount <= max_stack_size

# Helper to check if this item is equippable
func is_equippable() -> bool:
	return item_type == ItemType.WEAPON or item_type == ItemType.TOOL

func get_effective_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return item_id # Fallback to item_id if display_name is empty
