extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func prepare(sim: RefCounted) -> void:
	sim.humidity.fill(0.0)
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.plot_waters.fill(110.0)
	sim.refresh_display()
	sim.update_goal(2.1)

func _init() -> void:
	var sim := Sim.new(null, true, false, "meadow")
	check(sim.three_star_remaining() < 0.0, "Opening never starts a perfect countdown")
	prepare(sim)
	sim.step(Sim.FIXED_STEP)
	check(sim.three_star_remaining() == 3.0 and sim.outcome == "playing", "Three actually safe stars start a fresh three-second countdown")
	sim.step(1.0)
	check(is_equal_approx(sim.three_star_remaining(), 2.0) and sim.outcome == "playing", "Countdown advances only alongside actual weather steps")
	sim.stroke(Vector2(0, 5), Vector2(0.5, 5), 5.0)
	check(Array(sim.wind).any(func(value): return value.length() > 0.0), "Wind remains usable during countdown")
	var cell: int = sim.safety_indices[1][0]
	sim.cloud[cell] = 1.0
	sim.rain[cell] = 1.0
	sim.refresh_display()
	sim.update_goal(0.0)
	check(sim.earned_stars() == 2 and sim.three_star_remaining() < 0.0 and sim.three_star_elapsed < 0.0, "Renewed danger cancels countdown immediately")
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.refresh_display()
	sim.update_goal(0.0)
	check(sim.three_star_remaining() < 0.0, "Clearing danger does not skip the new safety interval")
	sim.step(1.9)
	check(sim.three_star_remaining() < 0.0, "A partly restored safety interval does not restart countdown")
	sim.step(0.2)
	check(sim.three_star_remaining() > 2.8 and sim.outcome == "playing", "Regained three stars restart the full countdown rather than resume old progress")
	sim.step(3.0)
	check(sim.outcome == "success" and sim.result_stars == 3 and not sim.timed_out, "Stable three stars automatically settle a perfect result")
	var elapsed: float = sim.elapsed_seconds
	sim.step(1.0)
	check(sim.elapsed_seconds == elapsed, "Automatic perfect result freezes the simulation")
	sim.reset()
	prepare(sim)
	sim.step(Sim.FIXED_STEP)
	check(sim.finish() and sim.result_stars == 3, "Player can click to finish immediately during countdown")
	sim.reset()
	prepare(sim)
	sim.step(Sim.FIXED_STEP)
	sim.plot_waters[0] = 151.0
	sim.update_goal(0.0)
	check(sim.plot_destroyed[0] and sim.three_star_remaining() < 0.0 and sim.outcome == "playing", "Flooding also cancels perfect countdown without ending remaining play")
	sim.reset()
	check(sim.three_star_elapsed < 0.0 and sim.three_star_remaining() < 0.0, "Retry clears old automatic countdown")
	sim.reset(true)
	prepare(sim)
	sim.step(4.0)
	check(sim.three_star_remaining() < 0.0 and sim.outcome == "playing", "Development lab cannot auto-settle injected stars")
	var definition := preload("res://scripts/weather_layouts.gd").get_definition("meadow").duplicate(true)
	definition.plots.resize(2)
	definition.plot_regions.resize(2)
	sim = Sim.new(null, true, false, "meadow", definition)
	prepare(sim)
	sim.step(4.0)
	check(sim.earned_stars() == 3 and sim.outcome == "success" and sim.result_saved_count == 2, "Two-field custom level automatically finishes all saved fields")
	var config := preload("res://scripts/weather_settings.gd").new()
	config.three_star_finish_seconds = 0.5
	sim = Sim.new(config, true, false, "meadow")
	prepare(sim)
	sim.step(Sim.FIXED_STEP)
	sim.step(0.49)
	check(sim.outcome == "playing", "Configured delay does not settle early")
	sim.step(0.02)
	check(sim.outcome == "success" and sim.result_stars == 3, "Configured delay governs automatic finish")
	for invalid in [0.0, 0.05, -1.0, INF, 31.0]:
		config.three_star_finish_seconds = invalid
		check("three_star_finish_seconds" in " ".join(config.validation_errors()), "Invalid automatic delay reports its field")
	print("THREE STAR FINISH: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
