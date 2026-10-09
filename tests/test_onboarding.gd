extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Guide = preload("res://scripts/onboarding.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _init() -> void:
	var sim := Sim.new(null, false, true)
	var guide := Guide.new()
	guide.update(sim, 1.0)
	check(guide.phase == 0 and Array(sim.cloud).max() == 0.0, "Lesson begins with humidity and a useful first instruction")
	var original_water: float = sim.water_total()
	for i in 100:
		sim.stroke(Vector2(-9, 4), Vector2(-8, 4), 9.0)
		sim.step(Sim.FIXED_STEP)
		guide.update(sim, Sim.FIXED_STEP)
	check(guide.phase == 0, "Horizontal flat-ground strokes do not complete mountain instruction")
	for i in 120:
		sim.stroke(Vector2(-4.5, -0.6), Vector2(-2.5, -0.6), 9.0)
		sim.step(Sim.FIXED_STEP)
		guide.update(sim, Sim.FIXED_STEP)
	check(guide.phase >= 1 and sim.total_mountain_lift > 0.0, "Actual uphill wind and visible cloud advance the guide")
	check(absf(sim.water_total() - original_water) < 0.01, "Guidance adds no water to the simulation")
	# Development fixtures isolate rain coverage and safety without UI shortcuts.
	sim.reset()
	guide.reset(true)
	var i := 20 * Sim.WIDTH + 20
	sim.cloud[i] = 2.0
	sim.rain[i] = 2.0
	sim.step(Sim.FIXED_STEP)
	guide.update(sim, Sim.FIXED_STEP)
	check(guide.phase == 2 and sim.plot_water == 0.0, "Actual rain outside the plot skips completed steps but does not claim enough water")
	check(Array(sim.cold).max() > 0.0 and sim.plot_centers.size() == 1, "Single-target lesson naturally generates cold from rain")
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.step(Sim.FIXED_STEP)
	guide.update(sim, 0.0)
	check(guide.phase == 2 and "补给" in guide.instruction(sim), "Lost clouds offer a recovery instruction without resetting achievements")
	sim.plot_water = sim.settings.target_water
	sim.cloud[i] = 2.0
	sim.rain[i] = 2.0
	# Place the threat at the real target rather than the earlier outside location.
	for cell in Sim.COUNT:
		if sim.positions[cell].distance_to(Sim.PLOT) < 0.4:
			sim.cloud[cell] = 2.0
			sim.rain[cell] = 2.0
	sim.refresh_display()
	sim.update_goal(3.0)
	guide.update(sim, 0.0)
	check(guide.phase == 3 and sim.outcome == "playing", "Adequate water with nearby danger enters safety step without completion")
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.refresh_display()
	sim.update_goal(sim.settings.safe_seconds + 0.1)
	guide.update(sim, 0.0)
	check(guide.phase == 4 and sim.outcome == "success", "Actual safety completion finishes the lesson")
	guide.reset(true)
	sim.reset(true)
	guide.update(sim, 0.1)
	check(guide.phase == 0, "Preseeded development clouds never complete guide steps")
	sim.reset()
	sim.plot_water = sim.settings.flood_water + 1.0
	sim.update_goal(0.0)
	guide.update(sim, 0.0)
	check("重试" in guide.instruction(sim) and sim.outcome == "flood", "Flood offers retry rather than a successful transition")
	guide.reset(false)
	sim = Sim.new(null, true)
	guide.update(sim, 1.0)
	check(not guide.cold_hint_seen, "No cold technique is presented before cold exists")
	sim.cold.fill(0.4)
	sim.refresh_display()
	guide.update(sim, 0.1)
	check(guide.cold_hint_left > 0.0, "Visible cold produces one optional hint in free play")
	guide.update(sim, 13.0)
	check(guide.cold_hint_left == 0.0 and guide.cold_hint_seen, "Hint expires and does not reappear on the same cold field")
	check(not Sim.new().cold_capable, "Historical single-target regression stays cold-free")
	var main := preload("res://scripts/main.gd").new()
	main.preferences_path = "res://.godot/onboarding-test.cfg"
	var preferences := ConfigFile.new()
	preferences.set_value("onboarding", "visited_free_play", false)
	preferences.save(main.preferences_path)
	check(main.initial_mode(PackedStringArray()) == "lesson", "Unvisited preference starts with the lesson")
	preferences.set_value("onboarding", "visited_free_play", true)
	preferences.save(main.preferences_path)
	check(main.initial_mode(PackedStringArray()) == "free", "Returning players enter free play after it was visited")
	check(main.initial_mode(PackedStringArray(["--fresh-guide"])) == "lesson", "Fresh-guide development flag ignores saved onboarding status")
	check(main.initial_mode(PackedStringArray(["--single-plot"])) == "baseline", "Baseline flag keeps its original configuration despite saved status")
	main.free()
	print("ONBOARDING TESTS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
