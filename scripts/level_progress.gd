extends RefCounted
## Only completed, normal star levels contribute. Retrying never reduces a personal best.
var best: Dictionary = {}
var legacy: Dictionary = {}
var load_error := OK
var migration_message := ""

func read(path: String) -> void:
	best.clear()
	legacy.clear()
	load_error = OK
	migration_message = ""
	var file := ConfigFile.new()
	var loaded := file.load(path)
	if loaded != OK:
		if loaded != ERR_FILE_NOT_FOUND:
			load_error = loaded
			migration_message = "纪录读取失败，保留原文件：" + error_string(loaded)
		return
	var version = file.get_value("meta", "rating_version", 1)
	if version not in [1, 2]:
		load_error = ERR_FILE_UNRECOGNIZED
		migration_message = "不支持的评价纪录版本，保留原文件"
		return
	var current: bool = version == 2
	if not current:
		var backup := path + ".v1-backup"
		if not FileAccess.file_exists(backup):
			load_error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
		if load_error != OK:
			migration_message = "旧纪录备份失败，保留原文件：" + error_string(load_error)
			return
	for id in file.get_section_keys("legacy_saved_counts") if file.has_section("legacy_saved_counts") else PackedStringArray():
		legacy[id] = file.get_value("legacy_saved_counts", id)
	for id in file.get_section_keys("stars") if file.has_section("stars") else PackedStringArray():
		var value = file.get_value("stars", id)
		if typeof(value) != TYPE_INT or value < 0 or value > 3: continue
		if current: best[id] = value
		else:
			# Historical built-in counts, never the currently edited map's count.
			var counts := {"meadow": 3, "valleys": 3, "needs_lab": 2}
			if counts.has(id) and value <= counts[id]:
				best[id] = preload("res://scripts/level_rating.gd").stars(value, counts[id])
			else: legacy[id] = value
	if not current: migration_message = "旧纪录已备份并更新评价；未知田数的自定义图纪录保留为历史"

func record(id: String, stars: int, path: String, persist: bool) -> Error:
	best[id] = maxi(int(best.get(id, 0)), clampi(stars, 0, 3))
	if not persist: return OK
	if load_error != OK: return load_error
	var file := ConfigFile.new()
	file.set_value("meta", "rating_version", 2)
	for key in best: file.set_value("stars", key, best[key])
	for key in legacy: file.set_value("legacy_saved_counts", key, legacy[key])
	return file.save(path)
