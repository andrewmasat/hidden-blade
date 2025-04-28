# ItemData.gd
extends Resource
class_name ItemData

# NEW Enum for Item Categories
enum ItemType {
	MISC,         # Default/uncategorized
	CONSUMABLE,
	WEAPON,
	TOOL,
	RESOURCE,
	PLACEABLE
}

# --- Existing Properties ---
@export var item_id: String = ""
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
@export var damage: float = 0.0
@export_group("Placeable")
@export var placeable_scene: PackedScene

# --- Helper Functions ---
func is_stack_full() -> bool:
	return quantity >= max_stack_size

func can_add_to_stack(amount: int = 1) -> bool:
	return quantity + amount <= max_stack_size

# Helper to check if this item is equippable
func is_equippable() -> bool:
	return item_type == ItemType.WEAPON or item_type == ItemType.TOOL
