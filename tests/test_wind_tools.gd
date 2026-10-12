extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Brush = preload("res://scripts/wind_input.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func source_run(group: float) -> RefCounted:
	var sim := Sim.new()
	sim.sandbox = true
	sim.settings.source_lifetime = 8.0
	sim.add_wind_source(Vector2(-5, 0), Vector2.RIGHT, 0.7)
	for tick in roundi(9.0 / group): sim.step(group)
	return sim

func band_run(tier: int, length: float = 8.0) -> RefCounted:
	var sim := Sim.new()
	sim.sandbox = true
	sim.settings.wind_spread = 0.0
	sim.settings.wind_decay = 0.0
	sim.add_wind_source(Vector2(-6, 3.75), Vector2.RIGHT, tier / 2.0, Vector2(-6 + length, 3.75))
	sim.step(0.1)
	return sim

func _init() -> void:
	var band := band_run(1)
	check(band.wind_sources[0].lifetime == 30.0, "Band default lasts thirty simulation seconds")
	check(band.velocity_at(Vector2(-5, 3.75)).x > 0.0 and band.velocity_at(Vector2(1.5, 3.75)).x > 0.0, "Band pushes near start and far endpoint")
	var mid: float = band.velocity_at(Vector2(-2, 3.75)).x
	check(mid > 0.0 and band.velocity_at(Vector2(-2, 4.75)).x < mid and band.velocity_at(Vector2(-2, 5.75)).x == 0.0, "Band shares brush width with soft lateral edges")
	var short_band := band_run(1, 4.0)
	check(is_equal_approx(short_band.velocity_at(Vector2(-4, 3.75)).x, band.velocity_at(Vector2(-4, 3.75)).x), "Longer bands cover more cells without multiplying local force")
	var weak := band_run(0)
	var strong := band_run(2)
	check(weak.velocity_at(Vector2(-2, 3.75)).x < mid and strong.velocity_at(Vector2(-2, 3.75)).x > mid, "Three wheel levels produce distinct actual wind")
	check(absf(band.water_total() - band.initial_water) < 0.01 and band.last_lift == 0.0, "Flat band creates no water or cloud")
	check(not band.add_wind_source(Vector2.ZERO, Vector2.RIGHT, 0.5, Vector2(30, 0)).ok and not band.add_wind_source(Vector2.ZERO, Vector2.RIGHT, 0.5, Vector2(0.1, 0)).ok, "Band endpoint and net length are validated")
	var gains: WRWeatherSettings = band.settings.duplicate(true)
	gains.source_powers = Vector3(0.1, 0.2, 0.3)
	band.settings.apply_live(gains)
	check(band.settings.source_powers == gains.source_powers and band.wind_sources[0].remaining > 29.0, "Band powers reload live without resetting progress")
	gains.source_powers = Vector3(1, 0.5, 2)
	check(not gains.validation_errors().is_empty(), "Descending band powers are rejected")
	var sim := Sim.new()
	var water := sim.water_total()
	check(not sim.add_wind_source(Vector2(30, 0), Vector2.RIGHT, 0.5).ok, "Outside source rejected")
	check(not sim.add_wind_source(Vector2.ZERO, Vector2.ZERO, 0.5).ok, "Zero direction rejected")
	check(not sim.add_wind_source(Vector2.ZERO, Vector2.RIGHT, NAN).ok, "Nonfinite force rejected")
	var first := sim.add_wind_source(Vector2(-5, 0), Vector2.RIGHT, 1.0)
	var second := sim.add_wind_source(Vector2(4, 0), Vector2.UP, 0.1)
	check(first.ok and second.ok and first.id != second.id, "Stable unique source IDs")
	check(not sim.add_wind_source(Vector2.ZERO, Vector2.UP, 0.5).ok and sim.wind_sources[0].id == first.id, "Capacity rejects without replacement")
	check(sim.water_total() == water and sim.wind[0] == Vector2.ZERO, "Placement only schedules force")
	sim.step(Sim.FIXED_STEP)
	check(sim.velocity_at(Vector2(-5, 0)).x > 0.0, "Source actually pushes")
	check(sim.wind_sources[0].remaining < 30.0, "Lifetime follows fixed step")
	var residual := sim.wind.duplicate()
	sim.remove_wind_source(first.id)
	check(sim.wind_sources.size() == 1 and sim.wind == residual, "Removal leaves existing wind")
	sim.reset()
	check(sim.wind_sources.is_empty() and sim.held_wind.is_empty(), "Reset clears wind emitters")
	sim.sandbox = true
	sim.set_held_wind(Vector2(5, 4), Vector2.RIGHT, 0.0)
	sim.step(0.5)
	var gentle := sim.velocity_at(Vector2(5, 4)).x
	sim.reset()
	sim.sandbox = true
	sim.set_held_wind(Vector2(5, 4), Vector2.RIGHT, 1.0)
	sim.step(0.5)
	check(sim.velocity_at(Vector2(5, 4)).x > gentle * 2.0, "Fast gesture produces stronger continued wind")
	sim.clear_held_wind()
	var before := sim.velocity_at(Vector2(5, 4)).x
	sim.step(0.5)
	check(sim.velocity_at(Vector2(5, 4)).x < before, "Released wind naturally decays")
	check(sim.sample_cloud(sim.cloud, Vector2(5, 4)) < 0.000001, "Flat held wind cannot directly make clouds")
	var low := source_run(1.0 / 60.0)
	var grouped := source_run(0.1)
	check(low.wind_sources.is_empty() and grouped.wind_sources.is_empty(), "Expiry works including grouped catch-up")
	var error := 0.0
	for i in Sim.COUNT: error += low.wind[i].distance_to(grouped.wind[i])
	check(error < 0.002, "Frame grouping does not change continuous force: " + str(error))
	check(absf(low.water_total() - low.initial_water) < 0.01, "Water accounted through continuous wind")
	sim.reset()
	sim.settings.wind_decay = 0.0
	sim.settings.wind_spread = 0.0
	sim.add_wind_source(Vector2.ZERO, Vector2.RIGHT, 0.0)
	sim.wind_sources[0].remaining = 0.01
	sim.step(Sim.FIXED_STEP)
	check(sim.wind_sources.is_empty() and sim.velocity_at(Vector2.ZERO).length() < 0.0001, "Final fading partial step integrated without full-strength overshoot")
	sim.set_held_wind(Vector2.ZERO, Vector2.RIGHT, 1.0)
	sim.add_wind_source(Vector2.ZERO, Vector2.RIGHT, 1.0)
	sim.sandbox = true
	sim.step(3.0)
	var capped := true
	for velocity in sim.wind: capped = capped and velocity.length() <= sim.settings.max_wind + 0.00001
	check(capped, "Held and source sum respects cap")
	var brush := Brush.new()
	brush.sim = sim
	brush.dragging = true
	brush.brush_point = Vector3(5, 0.4, 4)
	brush.last_motion_seconds = 1.0
	brush.update_held(2.0)
	check(sim.held_wind.is_empty(), "Click without direction cannot continue blowing")
	brush.gesture_direction = Vector2.LEFT
	brush.gesture_strength = 0.2
	brush.update_held(1.05)
	check(sim.held_wind.is_empty(), "Motion and held force do not overlap")
	brush.update_held(1.2)
	check(not sim.held_wind.is_empty() and sim.held_wind.direction == Vector2.LEFT, "Quiet press resumes remembered direction")
	brush.meaningful_distance = 0.0
	brush.apply_segment(Vector2.ZERO, Vector2(0.125, 0), 1.0, 1.02)
	brush.apply_segment(Vector2(0.125, 0), Vector2(0.125, -0.03), 1.02, 1.03)
	brush.update_held(1.2)
	check(sim.held_wind.direction == Vector2.UP, "Once armed, a short new stroke changes the continued direction")
	brush.select_tool("source")
	check(sim.held_wind.is_empty() and not brush.dragging, "Tool switch cancels held gesture")
	brush.append_point(Vector2.ZERO, 0.0)
	brush.append_point(Vector2.RIGHT, 0.1)
	var old := sim.wind.duplicate()
	brush.flush()
	check(sim.wind == old, "Source preview never adds stroke impulse")
	brush.free()
	var config := Sim.Settings.new()
	config.source_fade_seconds = 31.0
	check(not config.validation_errors().is_empty(), "Invalid fade configuration rejected")
	config = Sim.Settings.new()
	config.hold_gain = 4.0
	config.source_lifetime = 12.0
	sim.settings.apply_live(config)
	check(sim.settings.hold_gain == 4.0 and sim.settings.source_lifetime == 30.0, "Live gain and retry-only lifetime separated")
	sim.reset()
	var index := 28 * Sim.WIDTH + 32
	sim.cloud[index] = 3.0
	sim.rain[index] = 3.0
	sim.refresh_display()
	sim.wind[index] = Vector2.RIGHT * 2.0
	var v := sim.cloud_velocity_at(sim.positions[index])
	check(v.x < 2.0 and is_equal_approx(v.x, 2.0 * sim.cloud_response(index)), "Cloud arrows share the actual heavy rain-cloud response")
	sim.settings.hold_gain = 0.0
	sim.add_wind_source(Vector2(-5, 0), Vector2.RIGHT, 1.0)
	sim.sandbox = true
	sim.step(0.1)
	check(sim.velocity_at(Vector2(-5, 0)) == Vector2.ZERO, "Zero gain does not inject force")
	sim.reset()
	sim.settings.hold_gain = 2.0
	sim.settings.wind_spread = 0.0
	sim.settings.brush_radius = 0.6
	sim.add_wind_source(Vector2.ZERO, Vector2.RIGHT, 1.0)
	sim.step(Sim.FIXED_STEP)
	var wider := sim.settings.duplicate(true)
	wider.brush_radius = 2.0
	sim.settings.apply_live(wider)
	sim.step(Sim.FIXED_STEP)
	check(sim.velocity_at(Vector2(1.25, 0.25)).x > 0.0, "Live brush radius expands an already placed source without resetting its life")
	for id in ["standard", "far", "close", "ridges", "meadow", "valleys"]:
		var terrain := Sim.Terrain.new(Sim.Layouts.get_layout(id))
		var same := true
		for n in 500:
			var angle := n * 0.137
			var p: Vector2 = terrain.center + Vector2(cos(angle), sin(angle)) * terrain.axes * (0.1 + (n % 17) * 0.09)
			var q: Vector2 = (p - terrain.center) / terrain.axes
			same = same and terrain.is_land(p) == (q.length() <= terrain.coast_radius(q.angle()))
		check(same, "Conservative coast bounds preserve exact shape: " + id)
	print("WIND TOOLS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
