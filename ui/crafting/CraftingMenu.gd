# CraftingMenu.gd
extends Control

const RecipeEntryScene = preload("res://ui/crafting/RecipeEntry.tscn") # Adjust path

@onready var recipe_list_container = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ScrollContainer/RecipeListContainer
@onready var selected_recipe_info_label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/SelectedRecipeInfoLabel
@onready var craft_button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/CraftButton

var all_craftable_items: Array[ItemData] = []
var currently_selected_recipe_item: ItemData = null
var recipe_entry_button_group: ButtonGroup = ButtonGroup.new()

func _ready():
	Inventory.inventory_changed.connect(_on_player_inventory_changed)
	Inventory.main_inventory_changed.connect(_on_player_inventory_changed)

	craft_button.pressed.connect(_on_craft_button_pressed)
	craft_button.disabled = true
	selected_recipe_info_label.text = "Select a recipe."
	# Hide the menu initially; Player/HUD will show it.
	visible = false 
	_populate_recipe_list()

func open_menu():
	# Potentially refresh list if new recipes could be learned
	# _populate_recipe_list() # For now, populate once on ready
	visible = true
	_refresh_all_recipe_entry_counts()
	# TODO: Handle input focus, maybe select first recipe if list not empty

func close_menu():
	visible = false
	# TODO: Return input focus to game

func _populate_recipe_list():
	# Clear existing entries
	for child in recipe_list_container.get_children():
		child.queue_free()
	
	all_craftable_items.clear()

	# Iterate through all items in ItemDatabase
	# For now, we assume ItemDatabase.items is a Dictionary of ItemData
	if ItemDatabase and ItemDatabase.items: # Check ItemDatabase and its items dictionary
		for item_id in ItemDatabase.items:
			var item: ItemData = ItemDatabase.items[item_id]
			if is_instance_valid(item) and item.crafting_ingredients.size() > 0:
				all_craftable_items.append(item)
	else:
		printerr("CraftingMenu: ItemDatabase or ItemDatabase.items not found/empty.")
		return # Can't populate if no items

	# Sort craftable items (e.g., alphabetically by item_id or a display name if you add one)
	all_craftable_items.sort_custom(func(a, b): return a.item_id < b.item_id)

	for item_data in all_craftable_items:
		var recipe_entry = RecipeEntryScene.instantiate() as Button
		recipe_list_container.add_child(recipe_entry)

		var craftable_count = _calculate_max_craftable_count(item_data)
		print("DEBUG: Populating entry for '", item_data.item_id, "' with craftable_count: ", craftable_count) # Add this
		if recipe_entry.has_method("set_recipe_data"):
			recipe_entry.set_recipe_data(item_data, craftable_count)
		else: # Manual setup if no script on RecipeEntry yet
			var icon_rect = recipe_entry.find_child("ItemIcon", true, false) as TextureRect
			var name_label = recipe_entry.find_child("ItemNameLabel", true, false) as Label
			if icon_rect: icon_rect.texture = item_data.texture
			if name_label: name_label.text = item_data.item_id # Or a display_name property

		recipe_entry.button_group = recipe_entry_button_group
		recipe_entry.pressed.connect(_on_recipe_entry_selected.bind(item_data))


func _on_recipe_entry_selected(selected_item_data: ItemData):
	currently_selected_recipe_item = selected_item_data
	
	# Get effective display name for the selected item
	var selected_item_display_name = selected_item_data.item_id # Fallback
	if selected_item_data.has_method("get_effective_display_name"):
		selected_item_display_name = selected_item_data.get_effective_display_name()
	elif selected_item_data.has("display_name") and not selected_item_data.display_name.is_empty():
		selected_item_display_name = selected_item_data.display_name

	var info_text = "Craft: " + selected_item_display_name + "\nIngredients:\n" # Used display name here
	
	for ingredient_dict in selected_item_data.crafting_ingredients:
		var req_item_id = ingredient_dict.get("item_id", "Unknown")
		var req_qty = ingredient_dict.get("quantity", 0)
		
		# Get effective display name for the ingredient
		var ingredient_display_name = req_item_id # Fallback
		var ingredient_item_data = ItemDatabase.get_item_base(req_item_id)
		if is_instance_valid(ingredient_item_data):
			if ingredient_item_data.has_method("get_effective_display_name"):
				ingredient_display_name = ingredient_item_data.get_effective_display_name()
			elif ingredient_item_data.has("display_name") and not ingredient_item_data.display_name.is_empty():
				ingredient_display_name = ingredient_item_data.display_name
		
		var player_has_qty = Inventory.get_item_quantity_by_id(req_item_id)
		
		info_text += "- %s x%d (Have: %d)\n" % [ingredient_display_name, req_qty, player_has_qty] # Used display name here
	
	selected_recipe_info_label.text = info_text
	_update_craft_button_state()


func _on_player_inventory_changed(_slot_index: int, _item_data: ItemData):
	# When inventory changes, re-calculate counts for all visible recipe entries
	# This is a bit broad; could be optimized to only update relevant recipes if performance is an issue.
	if visible: # Only update if the crafting menu is actually open
		_refresh_all_recipe_entry_counts()

func _update_craft_button_state():
	if currently_selected_recipe_item == null:
		craft_button.disabled = true
		return

	var can_craft = true
	# Check if player has all ingredients for currently_selected_recipe_item
	for ingredient_dict in currently_selected_recipe_item.crafting_ingredients:
		var req_item_id = ingredient_dict.get("item_id")
		var req_qty = ingredient_dict.get("quantity")
		if Inventory.get_item_quantity_by_id(req_item_id) < req_qty:
			can_craft = false
			break
	
	# TODO: Add check for crafting station proximity if needed (e.g., near a forge)
	# var player = SceneManager.player_node (or however you get player)
	# if currently_selected_recipe_item.requires_station == "FORGE" and not player.is_near_forge():
	#     can_craft = false

	craft_button.disabled = not can_craft


func _on_craft_button_pressed():
	if currently_selected_recipe_item != null:
		print("Attempting to craft: ", currently_selected_recipe_item.item_id)
		# This will be Task 2.3: Implement crafting logic (consume items, give crafted item)
		# For now, just a print. We'll call an Inventory or CraftingManager function here.
		var success = _perform_crafting(currently_selected_recipe_item)
		if success:
			print("Crafted successfully!")
			_on_recipe_entry_selected(currently_selected_recipe_item)
			_refresh_all_recipe_entry_counts()
		else:
			print("Crafting failed (not enough ingredients - should be caught by button state).")


# Placeholder for actual crafting logic (Task 2.3)
func _perform_crafting(item_to_craft: ItemData) -> bool:
	# 1. Re-verify ingredients (server will do this authoritatively)
	var has_all_ingredients = true
	for ingredient_dict in item_to_craft.crafting_ingredients:
		var req_item_id = ingredient_dict.get("item_id")
		var req_qty = ingredient_dict.get("quantity")
		if Inventory.get_item_quantity_by_id(req_item_id) < req_qty:
			has_all_ingredients = false
			break
	
	if not has_all_ingredients:
		printerr("Crafting failed: Missing ingredients (logic error, button should have been disabled).")
		return false

	# 2. Consume Ingredients (Needs a robust function in Inventory.gd)
	for ingredient_dict in item_to_craft.crafting_ingredients:
		var item_id_to_consume = ingredient_dict.get("item_id")
		var qty_to_consume = ingredient_dict.get("quantity")
		if not Inventory.remove_item_by_id_and_quantity(item_id_to_consume, qty_to_consume): # Needs this new function
			printerr("Critical Error: Failed to consume ", item_id_to_consume, " during crafting!")
			# TODO: Potential rollback logic if some items were consumed but not all. Complex.
			return false 

	# 3. Add Crafted Item to Inventory
	var crafted_item_instance = item_to_craft.duplicate() # DUPLICATE the resource
	crafted_item_instance.quantity = 1 # Assuming crafting recipes produce 1 item unless specified otherwise
	
	if not Inventory.add_item(crafted_item_instance):
		printerr("Critical Error: Inventory full after consuming ingredients! Crafted item '", item_to_craft.item_id, "' lost!")
		# TODO: Drop item on ground or more robust handling.
		return false # Or true if ingredients were consumed but item couldn't be added. Depends on desired behavior.

	return true

func _calculate_max_craftable_count(recipe_item_data: ItemData) -> int:
	if not is_instance_valid(recipe_item_data) or recipe_item_data.crafting_ingredients.is_empty():
		return 0
	var max_possible_crafts: int = -1 # Use -1 to indicate "not yet set" or "effectively infinite until first constraint"
	var first_ingredient_processed = false

	for ingredient_dict in recipe_item_data.crafting_ingredients:
		var req_item_id = ingredient_dict.get("item_id")
		var req_qty_per_craft = ingredient_dict.get("quantity")

		if req_item_id == null or req_qty_per_craft <= 0:
			return 0
		var player_has_qty = Inventory.get_item_quantity_by_id(req_item_id)
		var possible_crafts_for_this_ingredient = 0
		if req_qty_per_craft > 0: # Avoid division by zero
			possible_crafts_for_this_ingredient = floori(float(player_has_qty) / req_qty_per_craft)

		if not first_ingredient_processed:
			max_possible_crafts = possible_crafts_for_this_ingredient
			first_ingredient_processed = true
		else:
			max_possible_crafts = mini(max_possible_crafts, possible_crafts_for_this_ingredient)

		if max_possible_crafts == 0:
			break 

	var final_count = max_possible_crafts if max_possible_crafts >= 0 else 0
	return final_count

func _refresh_all_recipe_entry_counts():
	for child_node in recipe_list_container.get_children():
		if child_node is Button and child_node.has_method("set_recipe_data"):
			var recipe_entry_button = child_node as Button 
			# We need to get the ItemData associated with this button.
			# RecipeEntry.gd stores it as item_data_represented.
			# We need a getter or direct access (if safe). Let's add a getter to RecipeEntry.
			if recipe_entry_button.has_method("get_item_data"): # Assume you add this to RecipeEntry.gd
				var entry_item_data = recipe_entry_button.get_item_data()
				if is_instance_valid(entry_item_data):
					var new_craftable_count = _calculate_max_craftable_count(entry_item_data)
					recipe_entry_button.set_recipe_data(entry_item_data, new_craftable_count)
