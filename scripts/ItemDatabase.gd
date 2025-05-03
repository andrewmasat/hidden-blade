# ItemDatabase.gd - Autoload Singleton
extends Node

# Dictionary to hold base item resources, keyed by item_id
var items: Dictionary = {}

# Path to the folder containing your ItemData .tres files
const ITEM_RESOURCE_FOLDER = "res://items/" # ADJUST PATH

func _ready() -> void:
	print("ItemDatabase: Loading item resources...")
	var dir = DirAccess.open(ITEM_RESOURCE_FOLDER)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var path = ITEM_RESOURCE_FOLDER.path_join(file_name)
				var resource = load(path)
				if resource is ItemData:
					if items.has(resource.item_id):
						printerr("ItemDatabase Warning: Duplicate item_id '", resource.item_id, "' found at path '", path, "'!")
					else:
						items[resource.item_id] = resource
						print("  -> Loaded:", resource.item_id, "from", path)
				else:
					printerr("ItemDatabase Warning: File '", path, "' is not a valid ItemData resource.")
			file_name = dir.get_next()
		dir.list_dir_end()
		print("ItemDatabase: Loading complete. Found", items.size(), "items.")
	else:
		printerr("ItemDatabase Error: Could not open item resource folder at:", ITEM_RESOURCE_FOLDER)

# Function to get the base item resource by its ID
func get_item_base(id: String) -> ItemData:
	return items.get(id, null) # Return null if not found
