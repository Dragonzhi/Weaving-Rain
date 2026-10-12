extends RefCounted
## Only completed, normal star levels contribute. Retrying never reduces a personal best.
var best: Dictionary = {}

func read(path: String) -> void:
	best.clear()
	var file := ConfigFile.new()
	if file.load(path) != OK: return
	for id in file.get_section_keys("stars") if file.has_section("stars") else PackedStringArray():
		var value = file.get_value("stars", id)
		if typeof(value) == TYPE_INT and value >= 0 and value <= 3: best[id] = value

func record(id: String, stars: int, path: String, persist: bool) -> Error:
	best[id] = maxi(int(best.get(id, 0)), clampi(stars, 0, 3))
	if not persist: return OK
	var file := ConfigFile.new()
	for key in best: file.set_value("stars", key, best[key])
	return file.save(path)
