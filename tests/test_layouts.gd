extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _init() -> void:
	check(Layouts.get_layout("missing").id == "standard", "Unknown layout falls back to the normal baseline")
	for id in Layouts.IDS:
		var sim := Sim.new(null, true, false, id)
		check(sim.layout_id == id and sim.plot_centers.size() == 2, id + " loads the selected dual-target layout")
		check(Array(sim.cloud).max() == 0.0 and Array(sim.rain).max() == 0.0 and Array(sim.cold).max() == 0.0, id + " starts with humidity only")
		var start: PackedFloat32Array = sim.humidity.duplicate()
		sim.stroke(Vector2(-6, 1), Vector2(-3, 0), 10.0)
		sim.step(0.2)
		sim.reset()
		check(sim.humidity == start and sim.plot_water == 0.0 and sim.second_water == 0.0, id + " retry restores its own deterministic start")
		var a: Vector2 = sim.plot_centers[0]
		var b: Vector2 = sim.plot_centers[1]
		check(absf(a.x - b.x) > Sim.PLOT_HALF * 2.0 or absf(a.y - b.y) > Sim.PLOT_HALF * 2.0, id + " plots never overlap credit coverage")
		if id != "standard":
			var grounded := true
			for plot in sim.plot_centers:
				for offset in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
					var p: Vector2 = plot + offset * Sim.PLOT_HALF
					grounded = grounded and sim.terrain.is_land(p) and is_equal_approx(sim.terrain.height(p), 0.22)
			check(grounded, id + " target surfaces stay on flat island terrain")
			var foot_inside := true
			for n in 64:
				var p: Vector2 = sim.terrain.mountain + Vector2.from_angle(n * TAU / 64.0) * sim.terrain.mountain_radius
				foot_inside = foot_inside and sim.terrain.is_land(p)
			check(foot_inside, id + " mountain base remains inside the island")
		var cell := -1
		var nearest := INF
		for i in Sim.COUNT:
			if sim.positions[i].distance_squared_to(b) < nearest:
				nearest = sim.positions[i].distance_squared_to(b)
				cell = i
		sim.cloud[cell] = 2.0
		sim.rain[cell] = 2.0
		sim.step(Sim.FIXED_STEP)
		check(sim.second_water > 0.0 and sim.plot_water == 0.0, id + " rain credits the moved B rather than its historical location")
	var lesson := Sim.new(null, false, true, "far")
	check(lesson.plot_centers[0] == Sim.PLOT and lesson.layout_id == "standard", "Lesson remains independent of the chosen free-play layout")
	var far := Sim.new(null, true, false, "far")
	check(far.plot_centers[1].distance_to(far.terrain.mountain) > 10.0 and far.terrain.mountain.x < -5.0, "Long island places the mountain west and B at a substantial transport distance")
	var close := Sim.new(null, true, false, "close")
	check(close.plot_centers[0].x < -5 and close.plot_centers[1].x > 5 and close.terrain.mountain == Vector2.ZERO, "Split island puts the two targets on opposite sides of its mountain")
	check(close.terrain.coast_radius(0.0) > close.terrain.coast_radius(PI * 0.5) * 2.0, "Split island has a pronounced waist, unlike the baseline silhouette")
	# Shared safety-area rule still applies to the original baseline.
	close = Sim.new(null, true)
	close.humidity.fill(0.0)
	close.cloud.fill(0.0)
	close.plot_water = 110.0
	close.second_water = 110.0
	var midpoint: Vector2 = (close.plot_centers[0] + close.plot_centers[1]) * 0.5
	var index := 0
	for i in Sim.COUNT:
		if close.positions[i].distance_squared_to(midpoint) < close.positions[index].distance_squared_to(midpoint):
			index = i
	close.cloud[index] = 2.0
	close.rain[index] = 2.0
	close.refresh_display()
	close.update_goal(3.0)
	check(close.plot_threats[0] and close.plot_threats[1] and close.outcome == "playing", "Rain in the shared safety area prevents both targets from finishing")
	close.cloud.fill(0.0)
	close.rain.fill(0.0)
	close.refresh_display()
	close.update_goal(2.1)
	check(close.outcome == "success", "Removing shared dangerous weather permits normal completion")
	print("LAYOUT TESTS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
