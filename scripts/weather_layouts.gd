@tool
extends RefCounted
## The runtime and editor load exactly the same authored resource.
const IDS := ["standard", "far", "close", "ridges"]
const LEVELS := ["meadow", "valleys", "reservoir_lab", "storm_coast"]

static func get_definition(id: String) -> WRMapDefinition:
	var filename := id if id in get_ids() else "standard"
	var path := "res://configs/maps/" + filename + ".tres"
	return load(path) as WRMapDefinition

static func get_layout(id: String) -> Dictionary:
	return get_definition(id).to_layout()

static func get_ids() -> Array:
	var result: Array = IDS.duplicate()
	for file in DirAccess.get_files_at("res://configs/maps"):
		if file.ends_with(".tres") and not file.get_basename() in result:
			var resource = load("res://configs/maps/" + file)
			if resource is WRMapDefinition and resource.id == file.get_basename(): result.append(resource.id)
	return result
