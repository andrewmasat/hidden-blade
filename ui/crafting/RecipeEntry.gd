# RecipeEntry.gd
extends Button

@onready var item_icon_rect = $HBoxContainer/ItemIcon
@onready var item_name_label = $HBoxContainer/ItemNameLabel
@onready var craftable_count_label = $HBoxContainer/CraftableCountLabel

var item_data_represented: ItemData

func get_item_data() -> ItemData:
	return item_data_represented

func set_recipe_data(p_item_data: ItemData, craftable_count: int = 0):
	item_data_represented = p_item_data
	if is_instance_valid(item_data_represented):
		item_icon_rect.texture = item_data_represented.texture
		
		var display_text = item_data_represented.item_id # Fallback
		if item_data_represented.has_method("get_effective_display_name"):
			display_text = item_data_represented.get_effective_display_name()
		elif item_data_represented.has("display_name") and not item_data_represented.display_name.is_empty():
			display_text = item_data_represented.display_name
		item_name_label.text = display_text

		# Display craftable count if greater than 0 (or 1, depending on preference)
		if is_instance_valid(craftable_count_label):
			if craftable_count > 0:
				craftable_count_label.text = " x" + str(craftable_count)
				craftable_count_label.visible = true
			else:
				craftable_count_label.text = ""
				craftable_count_label.visible = false
	else:
		item_icon_rect.texture = null
		item_name_label.text = "Invalid Recipe"
		if is_instance_valid(craftable_count_label):
			craftable_count_label.visible = false
