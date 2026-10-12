extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Loader = preload("res://scripts/config_loader.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	var loaded := Loader.map("res://configs/maps/needs_lab.tres", 1.25)
	check(loaded.errors.is_empty(), "Two-plot needs map validates: " + str(loaded.errors))
	if not loaded.errors.is_empty(): quit(1); return
	var sim := Sim.new(null, true, false, "needs_lab", loaded.resource)
	check(sim.required_water(0) == 100 and sim.flood_limit(1) == 55 and sim.required_water(1) == 40, "Independent configured thresholds")
	check(sim.plot_regions[0].area(1.25) == sim.plot_regions[1].area(1.25), "Sample holds area constant")
	check(sim.peak_density == 0 and Array(sim.rain).max() == 0 and Array(sim.cold).max() == 0, "Sample starts only with wet air")
	sim.plot_waters[0] = 39
	sim.plot_waters[1] = 40
	sim.update_goal(0.5)
	check(sim.plot_status(0) == "dry" and sim.plot_status(1) == "confirming", "Same water can leave ordinary dry and seedling ready")
	check(sim.earned_stars() == 0, "Adequate water still needs safe time")
	var rain_cell := 0
	for i in Sim.COUNT:
		if sim.positions[i].distance_squared_to(sim.plot_centers[1]) < sim.positions[rain_cell].distance_squared_to(sim.plot_centers[1]): rain_cell = i
	sim.cloud[rain_cell] = 3.0
	sim.rain[rain_cell] = 3.0
	sim.refresh_display()
	sim.update_goal(2.1)
	check(sim.plot_status(1) == "danger" and sim.earned_stars() == 0, "Configured adequate seedling still loses safety under real rain")
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.refresh_display()
	sim.update_goal(0.5)
	check(sim.plot_status(1) == "confirming", "Removing threat starts a fresh safety interval")
	sim.update_goal(2.0)
	check(sim.earned_stars() == 1 and sim.three_star_remaining() < 0, "Two-plot sample uses normal safe stars without a perfect countdown until both fields are saved")
	sim.plot_waters[1] = 55
	sim.update_goal(0.1)
	check(not sim.plot_destroyed[1] and sim.plot_warning(1) == 1.0, "At limit stays yellow and alive")
	sim.plot_waters[1] = 55.001
	sim.update_goal(0.1)
	check(sim.plot_destroyed[1] and sim.outcome == "playing", "Above limit permanently damages only that plot")
	sim.plot_waters[1] = 40
	sim.plot_waters[0] = 100
	sim.update_goal(2.1)
	check(sim.plot_destroyed[1] and sim.earned_stars() == 1 and sim.can_finish(), "Loss does not undo; ordinary can still be saved")
	check(is_equal_approx(sim.minimum_water_needed(), INF), "No shortage when all living fields have enough water")
	sim.reset()
	check(not sim.plot_destroyed.any(func(v): return v) and sim.plot_waters[1] == 0, "Retry clears water and damage")
	sim.plot_waters[0] = 90
	sim.plot_waters[1] = 39
	check(is_equal_approx(sim.minimum_water_needed(), 1.0 / sim.plot_water_scales[1]), "Reserve comparison uses individual missing real water")
	sim.plot_waters[0] = 0
	sim.plot_waters[1] = 20
	sim.remaining_humidity = 0
	sim.remaining_cloud = 0
	check(sim.water_insufficient() and sim.can_end_shortage(), "Shortage uses seedling's smaller need")
	var legacy := Sim.new(null, true)
	legacy.settings.target_water = 77
	check(legacy.required_water(0) == 77 and legacy.flood_limit(1) == legacy.settings.flood_water, "Legacy maps preserve weather defaults including developer overrides")
	var shared: WRMapDefinition = loaded.resource.duplicate(true)
	shared.plot_needs[1] = shared.plot_needs[0]
	var independent := Sim.new(null, true, false, "needs_lab", shared)
	independent.plot_waters[0] = 10
	check(independent.plot_waters[1] == 0 and shared.plot_needs[0].target_water == 100, "Shared configuration never shares runtime water")
	shared.plot_needs[0].target_water = 2
	check(independent.required_water(0) == 100, "Current round snapshots requirements")
	var smaller: WRMapDefinition = loaded.resource.duplicate(true)
	var circle := WRPlotRegion.new()
	circle.shape = "circle"
	smaller.plot_regions = [null, circle]
	var area_sim := Sim.new(null, true, false, "needs_lab", smaller)
	area_sim.humidity.fill(0.0)
	for target in 2:
		var cell := 0
		for i in Sim.COUNT:
			if area_sim.positions[i].distance_squared_to(area_sim.plot_centers[target]) < area_sim.positions[cell].distance_squared_to(area_sim.plot_centers[target]): cell = i
		area_sim.cloud[cell] = 1.0
		area_sim.rain[cell] = 1.0
	area_sim.initial_water = area_sim.water_total()
	area_sim.step(0.1)
	check(area_sim.water_for(1) > area_sim.water_for(0) and area_sim.required_water(1) == 40, "Smaller seedling normalizes real rain without rescaling its configured need")
	check(absf(area_sim.water_total() - area_sim.initial_water) < 0.00001, "Different needs and areas preserve actual water accounting")
	area_sim.plot_waters[0] = 90
	area_sim.plot_waters[1] = 39
	check(is_equal_approx(area_sim.minimum_water_needed(), 1.0 / area_sim.plot_water_scales[1]), "Smaller area's remaining need converts back to actual water")
	var invalid := WRPlotNeeds.new()
	invalid.target_water = NAN
	check(not invalid.validation_errors().is_empty(), "Nonfinite requirement rejected")
	invalid.target_water = 100
	invalid.flood_water = 100
	check(not invalid.validation_errors().is_empty(), "No tolerance interval rejected")
	print("PLOT NEEDS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
