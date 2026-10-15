extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const Progress = preload("res://scripts/level_progress.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func nearest(sim: RefCounted, point: Vector2) -> int:
	var cell := 0
	for i in Sim.COUNT:
		if sim.positions[i].distance_squared_to(point) < sim.positions[cell].distance_squared_to(point): cell = i
	return cell

func _init() -> void:
	# Historical rule samples, independent of the editable formal campaign.
	for id in ["meadow", "valleys", "reservoir_lab", "storm_coast"]:
		var definition := Layouts.get_definition(id)
		check(definition.validation_errors().is_empty(), "Star map validates: " + id + " " + str(definition.validation_errors()))
		var sim := Sim.new(null, true, false, id)
		check(sim.star_level and sim.plot_centers.size() == definition.plots.size() and sim.earned_stars() == 0, "Authored target count begins incomplete: " + id)
		var initial_clouds: bool = definition.warm_sea != null and definition.warm_sea.initial_cloud_fraction > 0
		check((Array(sim.cloud).max() > 0 if initial_clouds else Array(sim.cloud).max() == 0) and Array(sim.cold).max() == 0 and absf(sim.water_error()) < 0.001, "Only authored theme transfers its opening cloud budget")
		var path: String = "res://.godot/star-map-" + id + ".tres"
		check(ResourceSaver.save(definition, path) == OK, "Shape map saves")
		var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var shapes := true
		for n in definition.plots.size(): shapes = shapes and restored.region(n).shape == definition.region(n).shape and restored.region(n).half_axes == definition.region(n).half_axes
		check(restored.star_level and restored.time_limit_seconds == definition.time_limit_seconds and shapes, "Star flag, deadline and actual authored shapes survive reload")
	var sim := Sim.new(null, true, false, "meadow")
	check(not sim.can_finish() and not sim.finish(), "No stars cannot finish")
	sim.plot_waters[0] = 110.0
	for tick in 119: sim.update_goal(Sim.FIXED_STEP)
	check(not sim.can_finish(), "Real fixed ticks do not settle before the safety interval")
	for tick in 3: sim.update_goal(Sim.FIXED_STEP)
	check(sim.can_finish(), "Global safety runs concurrently without a second safety interval")
	sim.reset()
	sim.plot_waters[0] = 110.0
	sim.update_goal(2.1)
	check(sim.earned_stars() == 1 and sim.can_finish() and sim.outcome == "playing", "One safe star offers finish without ending further play")
	sim.plot_waters[2] = 151.0
	sim.update_goal(0.0)
	check(sim.plot_destroyed[2] and sim.outcome == "playing" and sim.earned_stars() == 1, "One destroyed field leaves weather and other fields playable")
	sim.plot_waters[2] = 0.0
	sim.update_goal(0.0)
	check(sim.plot_destroyed[2], "Destruction is irreversible until retry")
	var cell := nearest(sim, sim.plot_centers[1])
	sim.cloud[cell] = 3.0
	sim.rain[cell] = 3.0
	sim.refresh_display()
	sim.update_goal(2.1)
	check(not sim.can_finish() and not sim.finish(), "Threats to an unfinished surviving field block settlement")
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.refresh_display()
	sim.update_goal(0.5)
	check(not sim.can_finish(), "Global safety requires a fresh continuous interval")
	sim.update_goal(2.1)
	check(sim.can_finish() and sim.finish() and sim.result_stars == 1 and sim.outcome == "success", "Explicit settlement awards exactly the saved fields")
	var before := sim.humidity.duplicate()
	sim.step(1.0)
	check(sim.humidity == before, "Completed result freezes weather")
	sim.reset()
	check(not sim.plot_destroyed.any(func(value): return value) and sim.result_stars == 0 and sim.plot_waters == PackedFloat64Array([0, 0, 0]), "Retry resets all three fields and destruction")
	sim.plot_waters.fill(110.0)
	sim.update_goal(2.1)
	check(sim.earned_stars() == 3 and sim.outcome == "playing" and sim.finish() and sim.result_stars == 3, "Perfect result still waits for player settlement")
	sim.reset()
	sim.plot_waters.fill(151.0)
	sim.update_goal(0.0)
	check(sim.outcome == "flood" and sim.result_stars == 0, "All destroyed fields produce a zero-star retry result")
	sim.reset(true)
	sim.plot_waters.fill(110.0)
	sim.cloud.fill(0.0)
	sim.refresh_display()
	sim.update_goal(3.0)
	check(not sim.can_finish() and not sim.finish() and sim.outcome == "playing", "Development labs cannot finish or award a result")
	var timed_map := Layouts.get_definition("meadow").duplicate(true)
	timed_map.time_limit_seconds = 3.0
	check(ResourceSaver.save(timed_map, "res://.godot/timed-map.tres") == OK, "Custom deadline saves through the map resource")
	var timed_reload = ResourceLoader.load("res://.godot/timed-map.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(timed_reload.time_limit_seconds == 3.0, "Custom deadline survives deep resource reload")
	sim = Sim.new(null, true, false, "meadow", timed_map)
	sim.plot_waters[0] = 110.0
	sim.plot_waters[1] = 110.0
	sim.plot_waters[2] = 151.0
	sim.update_goal(2.1)
	cell = nearest(sim, sim.plot_centers[1])
	sim.cloud[cell] = 3.0
	sim.rain[cell] = 3.0
	sim.refresh_display()
	sim.update_goal(0.0)
	check(not sim.can_finish() and sim.earned_stars() == 1, "Threatened adequate field blocks early finish and loses its own star")
	sim.elapsed_seconds = 3.0 - Sim.FIXED_STEP * 1.5
	sim.step(Sim.FIXED_STEP)
	check(sim.outcome == "playing" and sim.time_remaining() > 0.0, "Deadline does not settle early")
	sim.step(1.0)
	check(sim.timed_out and sim.outcome == "success" and sim.result_stars == 1 and sim.time_remaining() == 0.0, "Deadline counts safe fields despite another threatened field and a destroyed field")
	check(is_equal_approx(sim.elapsed_seconds, 3.0), "A large step stops at the exact map deadline")
	before = sim.cloud.duplicate()
	sim.step(1.0)
	check(sim.cloud == before and sim.elapsed_seconds == 3.0, "Timed result freezes weather and timer")
	sim.reset()
	check(not sim.timed_out and sim.elapsed_seconds == 0.0 and sim.time_remaining() == 3.0, "Retry resets the entire countdown and result reason")
	sim.humidity.fill(0.0)
	sim.elapsed_seconds = 3.0 - Sim.FIXED_STEP
	sim.step(Sim.FIXED_STEP)
	check(sim.outcome == "timeout" and sim.result_stars == 0 and not sim.plot_destroyed.any(func(value): return value), "Exhausted humidity with no stars reaches a zero-star retry result")
	sim.reset()
	sim.plot_waters[0] = 110.0
	sim.update_goal(1.0)
	sim.elapsed_seconds = 3.0 - Sim.FIXED_STEP
	sim.step(Sim.FIXED_STEP)
	check(sim.outcome == "timeout" and sim.result_stars == 0, "Adequate water without the full safety interval earns no deadline star")
	sim.reset(true)
	sim.step(0.1)
	check(sim.elapsed_seconds == 0.0 and not sim.timed_out, "Development cloud lab is untimed")
	sim = Sim.new(null, true)
	sim.step(0.1)
	check(not sim.timer_active() and sim.elapsed_seconds == 0.0, "Legacy practice stays untimed")
	sim = Sim.new()
	sim.step(0.1)
	check(not sim.timer_active() and sim.elapsed_seconds == 0.0, "Single-target baseline stays untimed")
	for invalid in [0.0, -1.0, INF, NAN, 3601.0]:
		timed_map.time_limit_seconds = invalid
		check(timed_map.validation_errors()[0].begins_with("time_limit_seconds"), "Invalid deadline reports its field: " + str(invalid))
	var circle := WRPlotRegion.new()
	circle.shape = "circle"
	check(circle.contains(Vector2(1, 0), 1.25) and not circle.contains(Vector2(1, 1), 1.25), "Circle clips square corners from rain coverage")
	var ellipse := WRPlotRegion.new()
	ellipse.shape = "ellipse"
	ellipse.half_axes = Vector2(1.5, 0.9)
	check(ellipse.contains(Vector2(1.4, 0), 1.25) and not ellipse.contains(Vector2(0, 1), 1.25), "Ellipse uses both axes")
	check(is_equal_approx(circle.area(1.25), PI * 1.25 * 1.25), "Area normalization uses analytic circle area")
	sim = Sim.new(null, true, false, "meadow")
	sim.humidity.fill(0.0)
	for target in 3:
		cell = nearest(sim, sim.plot_centers[target])
		check(sim.rain_targets[cell] == target, "Each shape credits its own actual location")
		sim.cloud[cell] = 1.0
		sim.rain[cell] = 1.0
	sim.initial_water = sim.water_total()
	sim.step(0.1)
	check(absf(sim.water_total() - sim.initial_water) < 0.00001, "Area-normalized field water converts back to actual mass without double counting")
	check(sim.plot_waters[1] > sim.plot_waters[0], "Same fallen mass on a smaller circle yields more normalized coverage")
	var outside := nearest(sim, sim.plot_centers[1] + Vector2(1.1, 1.1))
	check(sim.rain_targets[outside] == -1, "A real grid cell in circle's bounding corner does not credit rain")
	var progress := Progress.new()
	var path := "res://.godot/star-progress-test.cfg"
	check(progress.record("meadow", 3, path, true) == OK and progress.record("meadow", 1, path, true) == OK, "Result persistence succeeds")
	var restored := Progress.new()
	restored.read(path)
	check(restored.best.get("meadow") == 3, "Lower-star retries preserve the personal best")
	progress.record("valleys", 2, path, false)
	restored.read(path)
	check(not restored.best.has("valleys"), "Nonpersistent development runs do not modify saved results")
	print("STAR LEVELS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
