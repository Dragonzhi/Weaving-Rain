extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func empty() -> RefCounted:
	var sim := Sim.new()
	sim.humidity.fill(0.0)
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.charge.fill(0.0)
	sim.refresh_display()
	return sim

func index_at(p: Vector2) -> int:
	var g := Vector2i(((p - Sim.ORIGIN) / Sim.CELL).floor())
	return g.y * Sim.WIDTH + g.x

func cloud_patch(sim: RefCounted, center: Vector2, water: float, active: bool = false) -> void:
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		if absf(p.x - center.x) < 1.3 and absf(p.y - center.y) < 1.3:
			sim.cloud[i] = water
			sim.rain[i] = water if active else 0.0
	sim.refresh_display()
	sim.initial_water = sim.water_total()

func total(field: PackedFloat32Array) -> float:
	var result := 0.0
	for value in field:
		result += value
	return result

func run() -> void:
	var started := Time.get_ticks_usec()
	var slow := Sim.new()
	var fast := Sim.new()
	slow.stroke(Vector2(-7, 1), Vector2(-5, 1), 2.0)
	fast.stroke(Vector2(-7, 1), Vector2(-5, 1), 30.0)
	var near := index_at(Vector2(-6, 1))
	check(fast.wind[near].length() > slow.wind[near].length() * 2.0, "Fast strokes are stronger")
	check(fast.wind[index_at(Vector2(6, 6))] == Vector2.ZERO, "Stroke remains local")
	for i in 15:
		fast.stroke(Vector2(-7, 1), Vector2(-5, 1), 200.0)
	var capped := true
	for v in fast.wind:
		capped = capped and v.length() <= fast.settings.max_wind + 0.00001
	check(capped, "Wind strength is capped")
	var before: float = fast.wind[near].length()
	var initial_humidity: PackedFloat32Array = fast.humidity.duplicate()
	fast.step(0.5)
	check(fast.wind[near].length() > 0.01 and fast.wind[near].length() < before, "Wind persists and decays after release")
	check(absf(fast.humidity[near] - initial_humidity[near]) > 0.001, "Moisture continues moving after release")
	var idle := Sim.new()
	idle.step(3.0)
	check(total(idle.cloud) < 0.00001, "No clouds without uphill airflow")
	var flat := empty()
	flat.humidity[index_at(Vector2(-7, 4))] = 10.0
	flat.wind.fill(Vector2(2, 0))
	flat.step(0.15)
	check(total(flat.cloud) < 0.00001, "Flat terrain does not lift moisture")
	var uphill := empty()
	var downhill := empty()
	var slope_cell := index_at(Vector2(-3.7, -0.6))
	uphill.humidity[slope_cell] = 10.0
	downhill.humidity[slope_cell] = 10.0
	uphill.wind.fill(Vector2(2, 0))
	downhill.wind.fill(Vector2(-2, 0))
	uphill.step(0.15)
	downhill.step(0.15)
	check(total(uphill.cloud) > 0.1, "Uphill airflow produces clouds")
	check(total(downhill.cloud) < 0.00001, "Downhill airflow does not produce clouds")
	var coupled := empty()
	cloud_patch(coupled, Vector2.ZERO, 2.0)
	for i in Sim.COUNT:
		coupled.rain[i] = coupled.cloud[i] * 0.6
		coupled.wind[i] = Vector2(3.0, 1.0)
	coupled._transport(Sim.FIXED_STEP)
	var ratio_error := 0.0
	for i in Sim.COUNT:
		ratio_error = maxf(ratio_error, absf(coupled.rain[i] - coupled.cloud[i] * 0.6))
	check(ratio_error < 0.00001, "Cloud and activated rain use identical transport")
	var rain := empty()
	cloud_patch(rain, Sim.PLOT, 2.3)
	rain.step(1.8)
	check(total(rain.rain) == 0.0, "Rain requires a hold period")
	check(rain.max_progress > 0.8, "Hold progress is visible")
	rain.step(0.4)
	check(total(rain.rain) > 1.0, "Maintained thick cloud begins raining")
	var stored := total(rain.rain)
	var plot_before: float = rain.plot_water
	rain.step(0.5)
	check(total(rain.rain) > 0.0 and total(rain.rain) < stored, "Rain releases stored water without supply")
	check(rain.plot_water > plot_before, "Rain over plot increases plot water")
	check(absf(rain.water_total() - rain.initial_water) < 0.01, "Water conserved across lifting, rain and ground credit")
	var missed := empty()
	cloud_patch(missed, Vector2(-7, -5), 2.0, true)
	missed.step(1.0)
	check(missed.plot_water == 0.0 and missed.rain_lost > 0.0, "Rain elsewhere never credits plot")
	var retreat := empty()
	cloud_patch(retreat, Vector2.ZERO, 2.0)
	retreat.step(1.0)
	var progress: float = retreat.max_progress
	for i in Sim.COUNT:
		retreat.cloud[i] *= 0.3
		retreat.charge[i] *= 0.3
	retreat.step(0.3)
	check(retreat.max_progress < progress and retreat.max_progress > 0.0, "Thin cloud loses progress gradually")
	var safety := empty()
	safety.plot_water = 100.0
	cloud_patch(safety, Sim.PLOT, 2.0)
	safety.update_goal(3.0)
	check(safety.outcome == "playing" and safety.threat, "Thick cloud in buffer blocks victory")
	safety.cloud.fill(0.0)
	safety.rain.fill(0.0)
	safety.charge.fill(0.0)
	safety.refresh_display()
	safety.update_goal(1.0)
	check(safety.outcome == "playing", "Safety requires confirmation time")
	safety.update_goal(1.1)
	check(safety.outcome == "success", "Adequate water and clear buffer completes goal")
	var invisible := empty()
	invisible.plot_water = 100.0
	var remnant := index_at(Sim.PLOT)
	invisible.cloud[remnant] = 0.01
	invisible.charge[remnant] = 0.02
	invisible.refresh_display()
	invisible.update_goal(2.1)
	check(invisible.outcome == "success", "Invisible thin progress remnants do not block safety")
	var flood := empty()
	flood.plot_water = 150.01
	flood.update_goal(0.01)
	check(flood.outcome == "flood", "Overwatering requires retry")
	var pick := empty()
	cloud_patch(pick, Sim.PLOT, 2.0)
	var hit: Variant = pick.pick_cloud(Vector3(Sim.PLOT.x, 15, Sim.PLOT.y), Vector3.DOWN)
	check(hit != null and pick.density_at(hit) > 0.0, "Cloud picking hits the rendered density profile")
	check(pick.pick_cloud(Vector3(-10, 15, -8), Vector3.DOWN) == null, "Empty air is not a cloud hit")
	var deform := empty()
	cloud_patch(deform, Vector2.ZERO, 1.0)
	var shape_before: PackedFloat32Array = deform.cloud.duplicate()
	deform.stroke(Vector2(0.6, -1.0), Vector2(2.0, -1.0), 8.0)
	deform.step(0.25)
	var local_change := 0.0
	var distant_change := 0.0
	for i in Sim.COUNT:
		var p: Vector2 = deform.positions[i]
		if p.x > 0.0:
			local_change += absf(deform.cloud[i] - shape_before[i])
		elif p.x < -0.6:
			distant_change += absf(deform.cloud[i] - shape_before[i])
	check(local_change > 0.1 and distant_change < local_change * 0.1, "Cloud edge deforms locally rather than translating the whole cloud")
	var replenished := empty()
	cloud_patch(replenished, Vector2(-3.0, -0.6), 1.0, true)
	var supply_cell := index_at(Vector2(-3.2, -0.6))
	replenished.humidity[supply_cell] = 10.0
	replenished.wind.fill(Vector2(1.0, 0.0))
	var water_before: float = total(replenished.cloud)
	replenished.step(0.1)
	check(total(replenished.cloud) > water_before and replenished.total_rain_rate > 0.0, "Effective uphill supply replenishes established rain")
	var conservation := Sim.new()
	for tick in 300:
		if tick % 30 == 0:
			conservation.stroke(Vector2(-6 + tick * 0.01, 0.5), Vector2(-3 + tick * 0.01, 0.5), 10.0)
		conservation.step(Sim.FIXED_STEP)
	check(absf(conservation.water_total() - conservation.initial_water) < 0.02, "Mixed weather transport conserves water over repeated strokes")
	var valid := true
	for i in Sim.COUNT:
		valid = valid and conservation.cloud[i] >= -0.00001 and conservation.rain[i] >= 0.0 and conservation.rain[i] <= conservation.cloud[i] + 0.00001
	check(valid, "Cloud fields stay nonnegative and activated rain stays a subset")
	conservation.reset()
	check(conservation.plot_water == 0.0 and conservation.outcome == "playing" and total(conservation.cloud) == 0.0, "Retry restores deterministic humidity-only start")
	var impulse := PackedFloat32Array()
	impulse.resize(Sim.COUNT)
	var center := 20 * Sim.WIDTH + 24
	impulse[center] = 1.0
	var spread := conservation._smooth(impulse)
	check(is_equal_approx(total(spread), 1.0) and is_equal_approx(spread[center], 0.25) and is_equal_approx(spread[center - Sim.WIDTH - 1], 0.0625), "Display smoothing preserves the original symmetric impulse footprint and total")
	impulse.fill(2.0)
	spread = conservation._smooth(impulse)
	check(Array(spread).min() == 2.0 and Array(spread).max() == 2.0, "Separable smoothing preserves constant fields at clamped borders")
	print("WEATHER TESTS: ", checks, " checks, ", failures, " failures, ", (Time.get_ticks_usec() - started) / 1000.0, " ms")
	quit(0 if failures == 0 else 1)
