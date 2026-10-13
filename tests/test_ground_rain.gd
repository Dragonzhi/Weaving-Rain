extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _init() -> void:
	var sim := Sim.new()
	check(sim.ground_rain.size() == Sim.COUNT and Array(sim.ground_rain).max() == 0, "Normal opening has no released rain")
	sim.humidity.fill(0)
	sim.cloud.fill(0)
	sim.cloud[sim.rain_targets.find(0)] = 0.5
	sim.refresh_display()
	sim.step(Sim.FIXED_STEP)
	check(Array(sim.ground_rain).max() == 0, "Cloud without active rain has no footprint")
	var i: int = sim.rain_targets.find(0)
	sim.rain[i] = sim.cloud[i]
	var before: float = sim.plot_waters[0]
	sim.step(Sim.FIXED_STEP)
	check(sim.ground_rain[i] > 0, "Active cloud records real release")
	check(absf(sim.plot_waters[0] - before - sim.ground_rain[i] * Sim.FIXED_STEP * sim.plot_water_scales[0]) < 0.00001, "Footprint rate agrees with actual target rain")
	var total := 0.0
	for value in sim.ground_rain: total += value
	check(absf(total - sim.total_rain_rate) < 0.00001, "Published per-cell rates sum to existing release")
	sim.cloud.fill(0)
	sim.rain.fill(0)
	sim.charge.fill(0)
	sim.step(Sim.FIXED_STEP)
	check(Array(sim.ground_rain).max() == 0, "Next dry step clears old footprint")
	sim.cloud[i] = 0.000001
	sim.rain[i] = sim.cloud[i]
	sim.step(Sim.FIXED_STEP)
	check(sim.ground_rain[i] > 0 and sim.rain[i] == 0, "Last tiny real release remains represented despite rain subset ending")
	sim.step(Sim.FIXED_STEP)
	check(sim.ground_rain[i] == 0, "Tiny release does not leave a false rain wall")
	sim.reset()
	check(Array(sim.ground_rain).max() == 0 and sim.total_rain_rate == 0, "Retry clears rates and scalar release")
	var pool := Sim.new(null, true, false, "reservoir_lab")
	i = pool.rain_targets.find(1)
	pool.plot_waters[1] = pool.required_water(1)
	pool.cloud[i] = 1
	pool.rain[i] = 1
	var ledger: float = pool.water_error()
	pool.step(Sim.FIXED_STEP)
	check(pool.ground_rain[i] > 0 and pool.overflow_water > 0 and pool.target_complete(1), "Full pool still has a real rain footprint and overflow")
	check(absf(pool.water_error() - ledger) < 0.0001, "Display rate is excluded from water budget")
	pool.reset()
	pool.humidity.fill(0)
	pool.cloud.fill(0)
	pool.rain.fill(0)
	for edge in [0, Sim.WIDTH - 1, Sim.COUNT - Sim.WIDTH, Sim.COUNT - 1]:
		pool.cloud[edge] = 0.5
		pool.rain[edge] = 0.5
	pool.step(Sim.FIXED_STEP)
	check(pool.ground_rain[0] > 0 and pool.ground_rain[Sim.COUNT - 1] > 0, "Actual surviving corner rain is not double-faded for display")
	print("GROUND RAIN: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
