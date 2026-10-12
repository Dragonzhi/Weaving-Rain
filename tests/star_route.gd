extends RefCounted
## Development-only controller: reads weather and returns one local mouse stroke.
const Sim = preload("res://scripts/weather_simulation.gd")
var order := [0, 1, 2]
var mode := "mountain"
var strokes := 0
var transport_strokes := 0
var transport_distance := 0.0
var front_strokes := 0
var actions: Array = []
var per_target: Array = []
var late_clear_seconds := 0.0
var late_clear_started := -1.0
var narrow_lookahead := 4.5

func _init(sequence: Array = [0, 1, 2], route: String = "mountain") -> void:
	order = sequence.duplicate()
	mode = route
	for _target in 3: per_target.append({"strokes": 0, "transport": 0, "distance": 0.0, "front": 0})

func push(at: Vector2, direction: Vector2, length: float, speed: float, kind: String, target: int, time: float) -> Dictionary:
	if direction.length() < 0.001: return {}
	direction = direction.normalized()
	var a := at - direction * 0.7
	var b := at + direction * length
	var command := {"from": a, "to": b, "speed": speed, "kind": kind, "target": target, "time": time}
	strokes += 1
	per_target[target].strokes += 1
	if kind in ["transport", "feed", "transfer"]:
		transport_strokes += 1
		transport_distance += a.distance_to(b)
		per_target[target].transport += 1
		per_target[target].distance += a.distance_to(b)
	if kind == "front":
		front_strokes += 1
		per_target[target].front += 1
	actions.append(command)
	return command

func next_command(sim: RefCounted, time: float) -> Dictionary:
	var target := -1
	for n in order:
		if not sim.plot_destroyed[n] and sim.water_for(n) < sim.required_water(n):
			target = n
			break
	# Clear weather after water is adequate, including all three safety regions.
	var danger_target := -1
	var danger := Vector2.ZERO
	var danger_score := 0.0
	var incoming := [0.0, 0.0, 0.0]
	for i in Sim.COUNT:
		var n: int = sim.rain_targets[i]
		if n >= 0 and sim.rain[i] > 0.0:
			incoming[n] += (sim.rain[i] * sim.settings.rain_rate + sim.settings.rain_base_rate) * sim.plot_water_scales[n]
	for n in order:
		if sim.plot_destroyed[n]: continue
		var need: float = sim.required_water(n)
		var early_clear: float = need + (sim.flood_limit(n) - need) * 0.24
		var floor_water := need * 0.65
		var lookahead := 2.8
		if sim.plot_needs[n] != null and sim.flood_limit(n) - need < need * 0.5:
			floor_water = need * 0.2
			lookahead = narrow_lookahead
		if sim.water_for(n) < need and (sim.water_for(n) < floor_water or sim.water_for(n) + incoming[n] * lookahead < early_clear): continue
		if n == order[0] and late_clear_seconds > 0.0:
			if late_clear_started < 0.0: late_clear_started = time
			if time - late_clear_started < late_clear_seconds: continue
		for i in sim.safety_indices[n]:
			var score: float = sim.rain[i] + sim.display_cloud[i] * 0.1
			if sim.plot_needs[n] != null:
				score *= 1.0 + incoming[n] * lookahead / maxf(1.0, sim.flood_limit(n) - sim.water_for(n))
			if score > danger_score:
				danger_score = score
				danger = sim.positions[i]
				danger_target = n
	if danger_target >= 0 and danger_score > 0.002:
		var direction := Vector2(0, -1 if sim.plot_centers[danger_target].y < 0 else 1)
		var kind := "clear"
		for next_target in order:
			# A narrow-tolerance plot needs the rain cleared before turning it
			# back toward another field; a direct reversal can keep rain overhead.
			if sim.plot_needs[danger_target] != null and sim.flood_limit(danger_target) - sim.required_water(danger_target) < sim.required_water(danger_target) * 0.5: break
			if next_target != danger_target and not sim.plot_destroyed[next_target] and sim.water_for(next_target) < sim.required_water(next_target):
				direction = sim.plot_centers[next_target] - danger
				kind = "transfer"
				break
		return push(danger, direction, 1.7, 14.0, kind, target if target >= 0 else danger_target, time)
	if target < 0: return {}
	var goal: Vector2 = sim.plot_centers[target]
	var center := goal
	var peak := 0.0
	var mass := 0.0
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		# Prioritise useful clouds instead of repeatedly retrieving distant remnants.
		var score: float = sim.display_cloud[i] / (1.0 + p.distance_squared_to(goal) * 0.025)
		mass += sim.cloud[i]
		if score > peak:
			peak = score
			center = p
	if mode == "relay" and (peak < 1.25 or int(time * 2) % 3 == 0):
		var best := 0.015
		var chosen := -1
		for i in Sim.COUNT:
			var p: Vector2 = sim.positions[i]
			if p.distance_to(goal) > 3.5 or sim.cold[i] < 0.12: continue
			var gradient: Vector2 = sim.cold_gradient(i)
			var score: float = sim.humidity[i] * minf(sim.cold[i], 1.0) * gradient.length() / (1.0 + p.distance_squared_to(goal) * 0.25)
			if score > best:
				best = score
				chosen = i
		if chosen >= 0:
			var direction: Vector2 = sim.cold_gradient(chosen).normalized()
			return push(sim.positions[chosen] - direction * 0.5, direction, 1.2, 8.0, "front", target, time)
	if mass < 25.0 or (peak < 1.1 and sim.total_rain_rate < 0.2 and int(time * 2) % 3 == 0):
		var mountain: Vector2 = sim.terrain.mountain
		for candidate in sim.terrain.mountains:
			if candidate.position.distance_to(goal) < mountain.distance_to(goal): mountain = candidate.position
		var source := mountain
		var best := 0.0
		for i in Sim.COUNT:
			var p: Vector2 = sim.positions[i]
			if p.distance_to(mountain) > 1.8 and p.distance_to(mountain) < 7.5:
				var score: float = sim.humidity[i] / (1.0 + p.distance_to(mountain) * 0.12)
				if score > best:
					best = score
					source = p
		return push(source, mountain - source, 2.3, 9.0, "feed", target, time)
	if center.distance_to(goal) > 0.7:
		return push(center, goal - center, 1.4, 9.0, "transport", target, time)
	var angle := time * 4.8
	var edge := Vector2(cos(angle), sin(angle))
	return push(goal + edge * 1.7, -edge, 1.0, 8.0, "gather", target, time)

func report(sim: RefCounted) -> Dictionary:
	var encoded: Array = []
	for action in actions:
		var value: Dictionary = action.duplicate()
		value.from = [action.from.x, action.from.y]
		value.to = [action.to.x, action.to.y]
		encoded.append(value)
	return {"layout": sim.layout_id, "route": mode, "order": order, "outcome": sim.outcome,
		"stars": sim.result_stars, "elapsed": sim.elapsed_seconds, "limit": sim.time_limit_seconds,
		"strokes": strokes, "transport_strokes": transport_strokes, "transport_distance": transport_distance,
		"front_strokes": front_strokes, "per_target": per_target, "water": Array(sim.plot_waters),
		"destroyed": sim.plot_destroyed, "water_error": sim.water_total() - sim.initial_water,
		"cold_lift": sim.total_cold_lift, "actions": encoded}
