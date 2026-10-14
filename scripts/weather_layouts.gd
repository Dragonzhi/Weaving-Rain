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
		# Exported resources are listed as .tres.remap; load their original path.
		var filename := file.trim_suffix(".remap")
		if filename.ends_with(".tres") and not filename.get_basename() in result:
			var resource = load("res://configs/maps/" + filename)
			if resource is WRMapDefinition and resource.id == filename.get_basename(): result.append(resource.id)
	return result
