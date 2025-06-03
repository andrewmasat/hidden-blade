# CraftingMenu.gd
extends Control

const RecipeEntryScene = preload("res://ui/crafting/RecipeEntry.tscn") # Adjust path

@onready var recipe_list_container = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ScrollContainer/RecipeListContainer
@onready var selected_recipe_info_label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/SelectedRecipeInfoLabel
@onready var crafting_progress_bar = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/CraftingProgressBar
@onready var crafting_status_label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/CraftingStatusLabel
@onready var craft_button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/CraftButton
@onready var hud = null

var all_craftable_items: Array[ItemData] = []
var currently_selected_recipe_item: ItemData = null
var recipe_entry_button_group: ButtonGroup = ButtonGroup.new()

var _is_currently_crafting: bool = false
var _crafting_timer: Timer = Timer.new()
var _current_craft_item_id: String = ""
var _current_craft_duration: float = 0.0

func _ready():
	Inventory.inventory_changed.connect(_on_player_inventory_changed)
	Inventory.main_inventory_changed.connect(_on_player_inventory_changed)

	if get_tree() and get_tree().get_first_node_in_group("HUD"):
		hud = get_tree().get_first_node_in_group("HUD")
	else:
		printerr("CraftingMenu: HUD node not found in group 'HUD'. Temporary messages for non-active crafts might not show.")

	craft_button.pressed.connect(_on_craft_button_pressed)
	craft_button.disabled = true
	selected_recipe_info_label.text = "Select a recipe."
	# Hide the menu initially; Player/HUD will show it.
	visible = false 
	crafting_progress_bar.visible = false
	if is_instance_valid(crafting_status_label): crafting_status_label.visible = false

	_crafting_timer.one_shot = true
	_crafting_timer.timeout.connect(_on_local_crafting_timer_timeout) # We'll define this
	add_child(_crafting_timer)

	_populate_recipe_list()

func _process(delta):
	if _is_currently_crafting and is_instance_valid(crafting_progress_bar) and _crafting_timer.time_left > 0:
		crafting_progress_bar.value = (1.0 - (_crafting_timer.time_left / _current_craft_duration)) * 100.0
	elif _is_currently_crafting and crafting_progress_bar.value != 100 and _crafting_timer.time_left == 0: # Ensure it hits 100 if timer just finished
		crafting_progress_bar.value = 100

func open_menu():
	# Potentially refresh list if new recipes could be learned
	# _populate_recipe_list() # For now, populate once on ready
	visible = true
	_refresh_all_recipe_entry_counts()
	# TODO: Handle input focus, maybe select first recipe if list not empty

func close_menu():
	if _is_currently_crafting:
		print("CraftingMenu: Closing menu, cancelling active client-side craft for ", _current_craft_item_id)
		# No need to inform server if we haven't sent the request yet.
		_reset_crafting_state()
	visible = false
	# TODO: Return input focus to game (from HUD's close_crafting_menu)

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


func handle_server_crafting_result(was_successful: bool, p_crafted_item_id: String, message_from_server: String):
	print("CraftingMenu [", name, "] handle_server_crafting_result TRIGGERED. Success: ", was_successful, " Item: ", p_crafted_item_id, " Server Msg: ", message_from_server)

	# Ensure item_base_data is fetched and valid before trying to get its display name
	var item_base_data = ItemDatabase.get_item_base(p_crafted_item_id)
	var item_display_name_str = p_crafted_item_id # Fallback to ID if item_base_data is invalid

	if is_instance_valid(item_base_data):
		item_display_name_str = _get_item_display_name(item_base_data) # This should always return a string
	else:
		print("CraftingMenu: Could not find ItemData for '", p_crafted_item_id, "' to get display name for result message.")

	# Ensure message_from_server is treated as a string for concatenation
	var server_message_str = str(message_from_server) # Explicitly cast, though it should be string

	if _is_currently_crafting and p_crafted_item_id == _current_craft_item_id:
		if was_successful:
			if is_instance_valid(crafting_status_label):
				crafting_status_label.text = "%s crafted!" % [item_display_name_str] # Using string formatting
				crafting_status_label.modulate = Color.GREEN
				crafting_status_label.visible = true
			print("  -> CraftingMenu: Craft successful on server for ", p_crafted_item_id)
		else:
			if is_instance_valid(crafting_status_label):
				crafting_status_label.text = "Failed: %s" % [server_message_str] # Using string formatting
				crafting_status_label.modulate = Color.RED
				crafting_status_label.visible = true
			print("  -> CraftingMenu: Craft FAILED on server for ", p_crafted_item_id, ". Reason: ", server_message_str)
		
		var result_message_timer = get_tree().create_timer(2.0)
		result_message_timer.timeout.connect(func():
			if is_instance_valid(self):
				_reset_crafting_state()
				_refresh_all_recipe_entry_counts()
				_update_craft_button_state()
				if is_instance_valid(currently_selected_recipe_item):
					_on_recipe_entry_selected(currently_selected_recipe_item)
		)

	elif not _is_currently_crafting:
		if was_successful:
			print("  -> CraftingMenu: Received craft success for '", p_crafted_item_id,"' (not actively crafting). Inv should be updated.")
			if is_instance_valid(hud) and hud.has_method("show_temporary_message"):
				hud.show_temporary_message("%s crafted!" % [item_display_name_str], 2.0) # String formatting
		else:
			print("  -> CraftingMenu: Received craft failure for '", p_crafted_item_id,"' (not actively crafting). Reason: ", server_message_str)
			if is_instance_valid(hud) and hud.has_method("show_temporary_message"):
				hud.show_temporary_message("Craft failed: %s" % [server_message_str], 2.5) # String formatting
		
		if visible: # Only refresh if menu is open
			_refresh_all_recipe_entry_counts()
			_update_craft_button_state()


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
	# Check ingredients (existing logic)
	for ingredient_dict in currently_selected_recipe_item.crafting_ingredients:
		var req_item_id = ingredient_dict.get("item_id")
		var req_qty = ingredient_dict.get("quantity")
		if Inventory.get_item_quantity_by_id(req_item_id) < req_qty:
			can_craft = false
			break
	
	if not can_craft: # If already false due to ingredients, no need to check station
		craft_button.disabled = true
		return

	# --- Check for required crafting station (Client-side for UI) ---
	var required_station = currently_selected_recipe_item.get("required_station_type") # Use .get for safety
	if required_station is String and not required_station.is_empty():
		var local_player = SceneManager.player_node # Assuming SceneManager holds local player ref
		if is_instance_valid(local_player) and local_player.has_method("is_near_crafting_station"):
			if not local_player.is_near_crafting_station(required_station):
				can_craft = false
				# Optional: Update selected_recipe_info_label to say "Requires [STATION_TYPE] nearby"
				selected_recipe_info_label.text += "\nRequires " + required_station + " nearby." 
		else:
			# Player node not found or method missing, assume cannot meet station req for safety
			can_craft = false 
			printerr("CraftingMenu: Could not check station proximity (player node or method issue).")

	craft_button.disabled = not can_craft


func _on_local_crafting_timer_timeout():
	if not _is_currently_crafting: return

	print("CraftingMenu: Local crafting timer finished for ", _current_craft_item_id)
	crafting_progress_bar.value = 100
	
	if is_instance_valid(crafting_status_label):
		var item_being_crafted_data = ItemDatabase.get_item_base(_current_craft_item_id)
		var item_name_for_status = _current_craft_item_id # Fallback
		if is_instance_valid(item_being_crafted_data):
			item_name_for_status = _get_item_display_name(item_being_crafted_data)
			
		crafting_status_label.text = "Finishing: " + item_name_for_status # Corrected
		
	_send_craft_request_to_server(_current_craft_item_id)


func _send_craft_request_to_server(item_id_to_craft: String):
	var main_node = get_tree().get_root().get_node_or_null("/root/Main")
	if is_instance_valid(main_node):
		print("  -> CraftingMenu: Sending craft request RPC to Main on server for item: ", item_id_to_craft)
		main_node.rpc_id(1, "server_handle_craft_item_request", item_id_to_craft)
	else:
		printerr("CraftingMenu: Could not find Main node to send craft RPC.")
		_reset_crafting_state() # Reset if we can't even send the request


func _reset_crafting_state():
	_is_currently_crafting = false
	_crafting_timer.stop()
	_current_craft_item_id = ""
	_current_craft_duration = 0.0
	if is_instance_valid(crafting_progress_bar): crafting_progress_bar.visible = false
	if is_instance_valid(crafting_status_label): crafting_status_label.visible = false
	
	# Re-enable recipe selection
	if is_instance_valid(recipe_list_container):
		for child_node in recipe_list_container.get_children():
			if child_node is Button:
				var recipe_button = child_node as Button
				recipe_button.disabled = false

	_update_craft_button_state() # Re-evaluate craft button (might be craftable again or not)
	print("CraftingMenu: Crafting state reset.")

func _on_player_nearby_stations_changed(_stations_array: Array): # We don't strictly need stations_array here
	if visible: # Only update if the crafting menu is open
		print("CraftingMenu: Player's nearby stations changed, updating craft button state.")
		_update_craft_button_state() 
		# Optional: If a recipe is selected, re-trigger its info display to update station message
		if is_instance_valid(currently_selected_recipe_item):
			_on_recipe_entry_selected(currently_selected_recipe_item)

func _on_craft_button_pressed():
	if _is_currently_crafting: # Don't allow starting a new craft if one is in progress
		print("Crafting already in progress for: ", _current_craft_item_id)
		return

	if currently_selected_recipe_item != null:
		# Client-side check for ingredients (still good for immediate feedback)
		var can_craft_locally = true
		for ingredient_dict in currently_selected_recipe_item.crafting_ingredients:
			var req_item_id = ingredient_dict.get("item_id")
			var req_qty = ingredient_dict.get("quantity")
			if Inventory.get_item_quantity_by_id(req_item_id) < req_qty:
				can_craft_locally = false
				break
		
		if not can_craft_locally:
			print("CraftingMenu: Cannot start craft, client-side check indicates missing ingredients for ", currently_selected_recipe_item.item_id)
			# Optionally show a message to the user
			_update_craft_button_state() # Refresh button state just in case
			return

		# --- Start Timed Craft ---
		_current_craft_item_id = currently_selected_recipe_item.item_id
		_current_craft_duration = currently_selected_recipe_item.crafting_time_seconds
		
		print("CraftingMenu: Starting to craft: ", _current_craft_item_id, " (Duration: ", _current_craft_duration, "s)")

		if _current_craft_duration > 0.01: # Only show progress bar for non-instant crafts
			_is_currently_crafting = true
			craft_button.disabled = true # Disable while crafting

			# Disable recipe selection by disabling each recipe entry button
			for child_node in recipe_list_container.get_children():
				if child_node is Button: # Assuming RecipeEntry is a Button or extends Button
					var recipe_button = child_node as Button
					recipe_button.disabled = true

			crafting_progress_bar.value = 0
			crafting_progress_bar.visible = true
			if is_instance_valid(crafting_status_label):
				# Ensure currently_selected_recipe_item is valid before getting its name
				var item_name_for_status = "Item"
				if is_instance_valid(currently_selected_recipe_item):
					item_name_for_status = _get_item_display_name(currently_selected_recipe_item)

				crafting_status_label.text = "Crafting: " + item_name_for_status
				crafting_status_label.visible = true

			_crafting_timer.start(_current_craft_duration)
			# TODO: Play crafting start sound/animation
		else: # Instant craft
			_send_craft_request_to_server(_current_craft_item_id)
			# For instant crafts, the UI might briefly flash or we might rely on server RPC for feedback
			# Resetting immediately might be too fast. Server response will dictate UI update.


func _get_item_display_name(item_data: ItemData) -> String:
	if not is_instance_valid(item_data): return "Unknown Item" # Return a default string
	var display_name = item_data.item_id # Fallback
	if item_data.has_method("get_effective_display_name"):
		display_name = item_data.get_effective_display_name()
	elif item_data.has("display_name") and not item_data.display_name.is_empty():
		display_name = item_data.display_name
	return display_name if not display_name.is_empty() else "Unnamed Item" # Ensure non-empty

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
