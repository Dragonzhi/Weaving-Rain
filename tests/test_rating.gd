extends SceneTree
const Rating = preload("res://scripts/level_rating.gd")
const Sim = preload("res://scripts/weather_simulation.gd")
const Progress = preload("res://scripts/level_progress.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	var expected := [[0, 3], [0, 1, 3], [0, 1, 2, 3], [0, 1, 2, 2, 3], [0, 1, 2, 2, 2, 3], [0, 1, 2, 2, 2, 2, 3]]
	for n in 6:
		for saved in n + 2:
			check(Rating.stars(saved, n + 1) == expected[n][saved], "Fixed evaluation %d/%d" % [saved, n + 1])
	for total in range(1, 4):
		var map: WRMapDefinition = load("res://configs/maps/meadow.tres").duplicate(true)
		map.plots.resize(total)
		map.plot_regions.resize(total)
		var sim := Sim.new(null, true, false, "meadow", map)
		sim.humidity.fill(0)
		sim.plot_waters.fill(110)
		sim.refresh_display()
		sim.update_goal(2.1)
		check(sim.saved_plot_count() == total and sim.earned_stars() == 3, "All fields are three stars even with one/two fields")
		sim.step(3.1)
		check(sim.outcome == "success" and sim.result_stars == 3 and sim.result_saved_count == total, "Every field count auto-settles and preserves actual count")
	var map: WRMapDefinition = load("res://configs/maps/needs_lab.tres").duplicate(true)
	var sim := Sim.new(null, true, false, "needs_lab", map)
	sim.plot_waters = PackedFloat64Array([100, 40])
	sim.update_goal(2.1)
	sim.step(Sim.FIXED_STEP)
	sim.plot_waters[1] = 56
	sim.update_goal(0)
	check(sim.earned_stars() == 1 and sim.three_star_remaining() < 0 and sim.plot_centers.size() == 2, "Destroyed field remains in total and cancels perfect rating")
	var legacy := ConfigFile.new()
	legacy.set_value("stars", "meadow", 2)
	legacy.set_value("stars", "needs_lab", 2)
	legacy.set_value("stars", "custom", 1)
	legacy.save("res://.godot/rating-legacy.cfg")
	var progress := Progress.new()
	progress.read("res://.godot/rating-legacy.cfg")
	check(progress.best.get("meadow") == 2 and progress.best.get("needs_lab") == 3 and progress.legacy.get("custom") == 1, "Known historical counts migrate; custom count is not guessed")
	check(FileAccess.file_exists("res://.godot/rating-legacy.cfg.v1-backup"), "Migration backs up original before writing")
	check(progress.record("needs_lab", 1, "res://.godot/rating-legacy.cfg", true) == OK, "Versioned result saves")
	var restored := Progress.new()
	restored.read("res://.godot/rating-legacy.cfg")
	check(restored.best.get("needs_lab") == 3 and restored.legacy.get("custom") == 1, "Reopening preserves highest new score and old custom record")
	legacy.set_value("meta", "rating_version", 99)
	legacy.save("res://.godot/rating-future.cfg")
	progress.read("res://.godot/rating-future.cfg")
	check(progress.record("meadow", 3, "res://.godot/rating-future.cfg", true) != OK, "Unknown version cannot be overwritten")
	print("RATING: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
