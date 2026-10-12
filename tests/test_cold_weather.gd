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

func total(field: PackedFloat32Array) -> float:
	var result := 0.0
	for value in field:
		result += value
	return result

func empty() -> RefCounted:
	var sim := Sim.new(null, true)
	sim.humidity.fill(0.0)
	sim.cloud.fill(0.0)
	sim.rain.fill(0.0)
	sim.refresh_display()
	return sim

func patch(sim: RefCounted, center: Vector2, raining: bool = false) -> void:
	for i in Sim.COUNT:
		if sim.positions[i].distance_to(center) < 0.9:
			sim.cloud[i] = 0.9
			sim.rain[i] = 0.9 if raining else 0.0
	sim.refresh_display()
	sim.initial_water = sim.water_total()

func front() -> RefCounted:
	var sim := empty()
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		sim.cold[i] = 1.7 * exp(-p.distance_squared_to(Vector2(7, 4)) / 1.5)
		sim.humidity[i] = 2.0 if p.distance_to(Vector2(7, 4)) < 2.4 else 0.0
	sim.initial_water = sim.water_total()
	sim._update_cold_flow()
	return sim

func run() -> void:
	var idle := Sim.new(null, true)
	idle.step(3.0)
	check(total(idle.cloud) == 0.0 and total(idle.cold) == 0.0, "Formal start has no cloud or cold air, and idle cannot create them")
	var dry := empty()
	patch(dry, Sim.PLOT)
	dry.step(0.3)
	check(total(dry.cold) == 0.0, "Non-raining cloud does not generate cold air")
	var rain := empty()
	patch(rain, Sim.PLOT, true)
	var water_before := total(rain.cloud)
	rain.step(Sim.FIXED_STEP)
	var released := water_before - total(rain.cloud)
	check(absf(total(rain.cold) - released * rain.settings.cold_from_rain * exp(-rain.settings.cold_decay * Sim.FIXED_STEP)) < 0.0001, "Cold source is actual released rainfall")
	check(absf(rain.water_total() - rain.initial_water) < 0.001, "Cold source never adds or duplicates water")
	var outside := empty()
	patch(outside, Vector2(7, 4), true)
	outside.step(0.2)
	check(total(outside.cold) > 0.0 and outside.plot_water == 0.0 and outside.second_water == 0.0, "Rain outside targets still produces cold without credit")
	var residual := front()
	residual.humidity.fill(0.0)
	var cold_before := total(residual.cold)
	residual.step(1.0)
	check(total(residual.cold) > 0.0 and total(residual.cold) < cold_before, "Stored cold persists and decays after rain stops")
	var cloud_cold := empty()
	var cloud_base := empty()
	patch(cloud_cold, Vector2(7, 4))
	patch(cloud_base, Vector2(7, 4))
	for i in Sim.COUNT:
		cloud_cold.cold[i] = exp(-cloud_cold.positions[i].distance_squared_to(Vector2(7, 4)))
	cloud_cold.step(0.3)
	cloud_base.step(0.3)
	check(total(cloud_cold.cloud) == total(cloud_base.cloud) and cloud_cold.cloud == cloud_base.cloud, "Automatic cold outflow never directly transports high cloud")
	var moving := front()
	moving.humidity.fill(0.0)
	var center_before := Vector2.ZERO
	for i in Sim.COUNT:
		center_before += moving.positions[i] * moving.cold[i] / total(moving.cold)
	moving.stroke(Vector2(6.2, 4), Vector2(8.2, 4), 12.0)
	moving.step(0.35)
	var center_after := Vector2.ZERO
	var cold_sum := total(moving.cold)
	for i in Sim.COUNT:
		center_after += moving.positions[i] * moving.cold[i] / cold_sum
	check(center_after.x > center_before.x + 0.12, "Local strokes can move residual cold and its front")
	var contact := front()
	contact._lift_at_cold_front(0.1)
	check(total(contact.cloud) == 0.0, "Contact alone does not lift moisture")
	var following := front()
	var opposing := front()
	for i in Sim.COUNT:
		var direction: Vector2 = opposing.cold_gradient(i).normalized()
		opposing.wind[i] = direction * 2.0
		following.wind[i] = -direction * 2.0
	following._update_cold_flow()
	opposing._update_cold_flow()
	following._lift_at_cold_front(0.1)
	opposing._lift_at_cold_front(0.1)
	check(total(following.cloud) == 0.0, "Following the cold outflow does not lift moisture")
	check(total(opposing.cloud) > 1.0, "Opposing moisture flow at a cold front creates cloud")
	check(opposing.cold_used > 0.0 and total(opposing.cold) < total(contact.cold), "Effective lift weakens available cold air")
	check(absf(opposing.water_total() - opposing.initial_water) < 0.001, "Front lift transfers moisture without creating water")
	var weak_push := front()
	for i in Sim.COUNT:
		var flow: Vector2 = weak_push.cold_flow[i]
		weak_push.wind[i] = -flow * 0.4
	weak_push._update_cold_flow()
	weak_push._lift_at_cold_front(0.1)
	check(total(weak_push.cloud) == 0.0, "Weak opposition that still leaves net co-flow cannot lift moisture")
	var dual := empty()
	patch(dual, Sim.SECOND_PLOT, true)
	dual.step(0.4)
	check(dual.second_water > 0.0 and dual.plot_water == 0.0, "Second plot uses its own actual rain coverage")
	var goal := empty()
	goal.plot_water = 110.0
	goal.update_goal(3.0)
	check(goal.outcome == "playing", "One adequate safe plot does not end the dual test")
	goal.second_water = 110.0
	patch(goal, Sim.SECOND_PLOT, true)
	goal.update_goal(3.0)
	check(goal.outcome == "playing" and goal.plot_threats[1], "Dangerous rain at second plot blocks joint completion")
	goal.cloud.fill(0.0)
	goal.rain.fill(0.0)
	goal.refresh_display()
	goal.update_goal(2.1)
	check(goal.outcome == "success", "Both adequate plots with safe buffers complete")
	var flood := empty()
	flood.second_water = 150.01
	flood.update_goal(0.01)
	check(flood.outcome == "flood", "Overwatering either plot requires retry")
	opposing.reset()
	check(total(opposing.cold) == 0.0 and opposing.second_water == 0.0 and opposing.total_cold_lift == 0.0, "Retry clears cold, both goals and relay diagnostics")
	var injected := empty()
	injected.cold[20 * Sim.WIDTH + 30] = 2.0
	injected._update_cold_flow()
	var expected: PackedFloat32Array = injected._smooth(injected.cold)
	check(injected.display_cold == expected and injected.cold_flow[20 * Sim.WIDTH + 29].length() > 0.0, "Direct cold injection invalidates the published smoothing cache")
	injected.cold.fill(0.0)
	injected.cold[20 * Sim.WIDTH + 30] = 1e-40
	injected.refresh_display()
	var numeric_safe := true
	for tick in 32:
		injected._update_cold_flow()
		numeric_safe = numeric_safe and is_finite(exp(-0.03))
	check(numeric_safe and injected.display_cold.to_byte_array() == injected._smooth(injected.cold).to_byte_array(), "Subnormal cold remnants safely reuse exact published bytes before subsequent math")
	print("COLD WEATHER TESTS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
