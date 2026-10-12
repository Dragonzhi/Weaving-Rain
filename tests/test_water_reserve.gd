extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _init() -> void:
	var sim := Sim.new(null, true, false, "meadow")
	check(is_equal_approx(sim.weather_reserve(), sim.initial_water) and sim.remaining_cloud == 0.0, "Formal opening reserve is exactly its initial humidity")
	check(not sim.can_end_shortage(), "Normal opening cannot prematurely end with zero stars")
	sim.humidity.fill(0.0)
	sim.cloud.fill(0.0)
	sim.humidity[0] = 1.0
	sim.cloud[0] = 2.0
	sim.rain[0] = 2.0
	sim.cold.fill(100.0)
	sim.escaped_water = 400.0
	sim.rain_lost = 500.0
	sim.plot_waters[0] = 90.0
	sim.refresh_display()
	check(sim.remaining_humidity == 1.0 and sim.remaining_cloud == 2.0 and sim.weather_reserve() == 3.0, "Reserve excludes rain subset, cold, fallen water and escaped water")
	var reserve: float = sim.weather_reserve()
	sim.cloud[0] += sim.humidity[0]
	sim.humidity[0] = 0.0
	sim.refresh_display()
	check(sim.weather_reserve() == reserve and sim.remaining_humidity == 0.0, "Turning humidity into cloud preserves reserve")
	sim.plot_waters.fill(0.0)
	check(is_equal_approx(sim.minimum_water_needed(), sim.settings.target_water * PI / (4.0 * sim.settings.plot_water_scale)), "Circular field is currently the least actual water demand")
	sim.plot_waters[0] = 110.0
	sim.plot_waters[1] = 110.0
	check(is_equal_approx(sim.minimum_water_needed(), sim.settings.target_water / sim.plot_water_scales[2]), "Remaining ellipse uses its actual authored area-adjusted demand")
	sim.plot_waters.fill(0.0)
	sim.plot_waters[0] = 99.0
	var needed: float = sim.minimum_water_needed()
	check(is_equal_approx(needed, 1.0 / sim.plot_water_scales[0]), "Closest-to-adequate rectangle becomes the cheapest field")
	sim.cloud[0] = needed * 1.1
	sim.refresh_display()
	check(not sim.water_insufficient() and not sim.can_end_shortage(), "No low vapor but enough cloud storage does not trigger shortage")
	sim.cloud[0] = needed
	sim.refresh_display()
	check(not sim.water_insufficient(), "Exactly enough total water is not declared impossible")
	sim.cloud[0] = needed * 0.5
	sim.refresh_display()
	sim.update_goal(0.0)
	check(sim.water_insufficient() and sim.can_end_shortage() and sim.outcome == "playing", "Insufficient reserve offers ending but keeps simulation running")
	var elapsed: float = sim.elapsed_seconds
	sim.step(Sim.FIXED_STEP)
	check(sim.outcome == "playing" and sim.elapsed_seconds > elapsed, "Shortage continues normal weather and countdown until player chooses")
	check(sim.finish() and sim.outcome == "shortage" and sim.result_stars == 0 and sim.ended_for_shortage and not sim.timed_out, "Player may explicitly finish shortage with zero stars")
	reserve = sim.weather_reserve()
	sim.step(1.0)
	check(sim.weather_reserve() == reserve, "Shortage result freezes remaining weather")
	sim.reset()
	check(not sim.ended_for_shortage and not sim.can_end_shortage() and is_equal_approx(sim.weather_reserve(), sim.initial_water), "Retry restores reserve and clears shortage ending")
	sim.plot_waters.fill(110.0)
	sim.humidity.fill(0.0)
	sim.refresh_display()
	check(not sim.water_insufficient() and not sim.can_end_shortage(), "All adequate fields need safety, not additional water")
	sim.plot_waters[2] = 99.0
	sim.plot_waters[0] = 151.0
	sim.update_goal(0.0)
	check(sim.plot_destroyed[0] and is_equal_approx(sim.minimum_water_needed(), 1.0 / sim.plot_water_scales[2]), "Destroyed and already adequate fields are excluded from demand")
	sim.update_goal(2.1)
	# A threat over a deficient field cannot erase the safe star on B.
	var target_cell: int = sim.safety_indices[2][0]
	sim.cloud[target_cell] = 0.001
	sim.rain[target_cell] = 0.001
	sim.refresh_display()
	sim.update_goal(0.0)
	check(sim.threat and not sim.can_finish() and sim.can_end_shortage(), "Shortage ending is available despite threats to an unfinished field")
	check(sim.finish() and sim.result_stars == 1 and sim.outcome == "success", "Shortage settlement counts only safe surviving fields")
	sim.reset()
	sim.humidity.fill(0.0)
	sim.plot_waters[0] = 110.0
	sim.refresh_display()
	sim.update_goal(0.5)
	check(sim.can_end_shortage() and sim.earned_stars() == 0, "Adequate field without safety remains playable during shortage")
	sim.update_goal(2.1)
	check(sim.outcome == "playing" and sim.earned_stars() == 1, "Continuing after shortage can still earn a safety star")
	sim.reset(true)
	sim.humidity.fill(0.0)
	sim.cloud.fill(0.0)
	sim.refresh_display()
	check(not sim.can_end_shortage() and not sim.finish(), "Development labs cannot use shortage settlement")
	sim = Sim.new(null, true)
	sim.humidity.fill(0.0)
	sim.refresh_display()
	check(not sim.can_end_shortage() and not sim.finish(), "Practice keeps its original finish rules")
	print("WATER RESERVE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
