extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Settings = preload("res://scripts/weather_settings.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func make(id: String = "storm_coast") -> RefCounted:
	return Sim.new(Settings.new(), true, false, id)
func _init() -> void:
	for id in ["reservoir_lab", "storm_coast"]:
		check(load("res://configs/maps/" + id + ".tres").validation_errors().is_empty(), id + " resource validation")
	var sim := make("reservoir_lab")
	check(not sim.is_reservoir(0) and sim.is_reservoir(1), "Target kind preserves old farm default")
	sim.plot_waters[1] = sim.required_water(1)
	var i: int = Array(sim.rain_targets).find(1)
	sim.cloud[i] = 8
	sim.rain[i] = 8
	sim.refresh_display()
	var budget: float = sim.water_total()
	sim.step(0.1)
	check(sim.target_complete(1) and sim.earned_stars() == 1 and not sim.plot_destroyed[1] and not sim.plot_threats[1], "Full pool completes immediately during rain")
	check(sim.overflow_water > 0 and sim.water_for(1) == sim.required_water(1), "Storage capped and actual excess accounted")
	check(absf(sim.water_total() - budget) < 0.001, "Overflow conserves actual rain")
	sim.plot_waters[0] = sim.required_water(0)
	sim.cloud.fill(0)
	sim.rain.fill(0)
	sim.charge.fill(0)
	sim.refresh_display()
	sim.step(sim.settings.safe_seconds + 0.1)
	check(sim.earned_stars() == 3 and sim.three_star_remaining() >= 0, "Mixed targets full completion starts real countdown")
	sim.rain[Array(sim.rain_targets).find(0)] = 1
	sim.cloud[Array(sim.rain_targets).find(0)] = 1
	sim.refresh_display()
	sim.step(0.05)
	check(sim.three_star_remaining() < 0 and sim.target_complete(1), "Farm threat cancels countdown without un-filling pool")
	sim.plot_destroyed[0] = true
	sim.update_goal(0.1)
	check(sim.earned_stars() == 1 and sim.outcome == "playing", "Farm loss still allows reservoir result")
	sim = make()
	check(sim.tropical != null and Array(sim.cloud).max() > 0 and absf(sim.water_error()) < 0.001, "Authored initial clouds transfer existing moisture budget")
	var original_heat: PackedFloat32Array = sim.tropical.heat.duplicate()
	var origin: Vector2 = sim.tropical.center
	sim.step(1.0)
	check(sim.evaporated_water > 0 and absf(sim.water_error()) < 0.003, "Evaporation and cloud rain share explicit budget")
	check(sim.tropical.heat != original_heat and sim.tropical.total_lift > 0, "Storm causes local cooling and real sea convection")
	check(sim.tropical.center != origin and sim.wind.to_byte_array() == sim.zero_wind_bytes, "Environment moves center with no player wind")
	check(sim.cloud_wind != sim.wind and sim.low_wind != sim.cloud_wind, "Natural two-layer winds do not overwrite player wind")
	check(Array(sim.cloud_wind).all(func(w): return w.length() <= sim.settings.max_wind + 0.00001), "Combined cloud wind capped")
	sim.humidity.fill(0)
	sim.cloud.fill(0)
	sim.rain.fill(0)
	sim.refresh_display()
	check(not sim.water_insufficient(), "Future sea supply prevents false shortage")
	sim.tropical.heat.fill(0)
	check(sim.water_insufficient(), "No sea supply restores shortage test")
	var center: Vector2 = sim.tropical.center
	sim.reset()
	check(sim.evaporated_water == 0 and sim.overflow_water == 0 and sim.tropical.center != center, "Retry resets natural state and water ledger")
	var id: int = sim.add_vortex(Vector2(9, 0), 2, -1, 1).id
	sim.remove_wind_source(id)
	sim.step(0.1)
	check(sim.wind_sources.is_empty() and sim.cloud_wind != sim.wind and sim.tropical != null, "Closing player source cannot delete natural weather")
	var map: WRMapDefinition = load("res://configs/maps/storm_coast.tres").duplicate(true)
	map.warm_sea.background_wind = Vector2.ZERO
	sim = Sim.new(Settings.new(), true, false, "storm_coast", map)
	origin = sim.tropical.center
	sim.step(1.0)
	check(sim.tropical.center == origin, "Own rotation cannot self-steer")
	sim.stroke(Vector2(9, -4), Vector2(11, -4), 12)
	sim.step(1.0)
	check(sim.tropical.center.x > origin.x and sim.tropical.motion.length() <= sim.settings.tropical_motion_cap, "Peripheral player wind gradually steers within cap")
	map.warm_sea.seed_organization = 0
	map.warm_sea.initial_cloud_fraction = 0
	map.warm_sea.background_wind = Vector2.ZERO
	sim = Sim.new(Settings.new(), true, false, "storm_coast", map)
	sim.step(1.0)
	check(Array(sim.cloud).max() == 0, "Warm moist sea without convergence does not directly create clouds")
	sim.add_vortex(Vector2(9, 0), 2.5, -1, 1)
	sim.step(4.0)
	check(sim.tropical.total_lift > 0 and Array(sim.cloud).max() > 0, "Actual convergence initiates convection from pure moisture")
	check(absf(sim.water_error()) < 0.005, "Normal moisture germination conserves supplied water")
	var before: float = sim.tropical.organization
	sim.tropical.heat.fill(0)
	sim.step(2.0)
	check(sim.tropical.organization < before and Array(sim.cloud).max() > 0, "No heat weakens organization without clearing cloud")
	sim.tropical.center = Vector2(16.2, 0)
	sim.tropical.motion = Vector2.RIGHT * 0.2
	sim.step(0.5)
	check(sim.tropical.center.x > 16.2 and absf(sim.water_error()) < 0.01, "Center can leave domain without clamp or water deletion")
	sim = Sim.new()
	check(sim.tropical == null and Array(sim.cloud).max() == 0 and sim.cloud_wind == sim.wind, "Old opening and wind fields unchanged")
	var settings := Settings.new()
	settings.tropical_support_rate = 0
	check(not settings.validation_errors().is_empty(), "Invalid tropical divisor rejected")
	var region: WRPlotNeeds = load("res://configs/plots/reservoir.tres").duplicate()
	region.target_water = NAN
	check(not region.validation_errors().is_empty(), "Invalid capacity rejected")
	print("RESERVOIR TROPICAL: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
