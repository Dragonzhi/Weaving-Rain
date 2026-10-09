extends SceneTree
## Both routes use normal humidity-only state and at most one local stroke per 0.5 s.
const Sim = preload("res://scripts/weather_simulation.gd")
var strokes := 0
var mode := "relay"
var first_cold_lift := 0.0
var reached_first := false
var last_from := Vector2.ZERO
var last_to := Vector2.ZERO
var first_near_lift := 0.0

func _init() -> void:
	call_deferred("run")

func push(sim: RefCounted, at: Vector2, direction: Vector2, length: float = 2.2, speed: float = 9.0) -> void:
	if direction.length() < 0.001:
		return
	direction = direction.normalized()
	last_from = at - direction * 0.7
	last_to = at + direction * length
	sim.stroke(last_from, last_to, speed)
	strokes += 1

func feed_mountain(sim: RefCounted) -> void:
	var source := Vector2(-6, 1)
	var best := 0.0
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		if p.distance_to(Sim.MOUNTAIN) > 1.8 and p.distance_to(Sim.MOUNTAIN) < 7.5 and absf(p.y) < 3.5:
			var score: float = sim.humidity[i] / (1.0 + p.distance_to(Sim.MOUNTAIN) * 0.12)
			if score > best:
				best = score
				source = p
	push(sim, source, Sim.MOUNTAIN - source, 2.3)

func feed_front(sim: RefCounted) -> bool:
	var best := 0.0
	var chosen := -1
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		if p.distance_to(Sim.SECOND_PLOT) > 3.5 or sim.cold[i] < 0.12:
			continue
		var gradient: Vector2 = sim.cold_gradient(i)
		var score: float = sim.humidity[i] * minf(sim.cold[i], 1.0) * gradient.length() / (1.0 + p.distance_squared_to(Sim.SECOND_PLOT) * 0.25)
		if score > best:
			best = score
			chosen = i
	if chosen < 0 or best < 0.015:
		return false
	var direction: Vector2 = sim.cold_gradient(chosen).normalized()
	push(sim, sim.positions[chosen] - direction * 0.5, direction, 1.2, 8.0)
	return true

func snapshot(sim: RefCounted, tick: int) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			var file := FileAccess.open(arg.trim_prefix("--snapshot="), FileAccess.WRITE)
			var velocities: Array = []
			for v in sim.wind:
				velocities.append([v.x, v.y])
			file.store_string(JSON.stringify({"humidity": Array(sim.humidity), "cloud": Array(sim.cloud), "rain": Array(sim.rain), "charge": Array(sim.charge), "cold": Array(sim.cold), "wind": velocities, "plot_water": sim.plot_water, "second_water": sim.second_water, "rain_lost": sim.rain_lost, "initial_water": sim.initial_water, "rain_rate": sim.total_rain_rate, "cold_lift": sim.total_cold_lift, "time": tick / 60.0, "stroke": [[last_from.x, last_from.y], [last_to.x, last_to.y]]}))
			file.close()

func run() -> void:
	if "--mountain" in OS.get_cmdline_user_args():
		mode = "mountain"
	var sim := Sim.new(null, true)
	sim.settings.cold_enabled = mode == "relay"
	var captured := false
	for tick in 12000:
		if tick % 30 == 0:
			# Start relocating before demand is met: stored rain keeps falling during the move.
			if not reached_first and sim.plot_water >= 80.0:
				reached_first = true
				first_cold_lift = sim.total_cold_lift
				first_near_lift = sim.cold_lift_near_second
			var target := Sim.SECOND_PLOT if reached_first else Sim.PLOT
			var center := target
			var peak := 0.0
			var mass := 0.0
			for i in Sim.COUNT:
				var p: Vector2 = sim.positions[i]
				if p.y < 3.0 and p.y > -4.5:
					mass += sim.cloud[i]
					if sim.display_cloud[i] > peak:
						peak = sim.display_cloud[i]
						center = p
			var water: float = sim.second_water if reached_first else sim.plot_water
			if reached_first and sim.plot_threats[0]:
				var danger := Sim.PLOT
				var strength := 0.0
				for i in Sim.COUNT:
					var p: Vector2 = sim.positions[i]
					if absf(p.x - Sim.PLOT.x) < Sim.SAFE_HALF and absf(p.y - Sim.PLOT.y) < Sim.SAFE_HALF and p.distance_to(Sim.SECOND_PLOT) > 1.0:
						if sim.rain[i] > strength:
							strength = sim.rain[i]
							danger = p
				push(sim, danger, Sim.SECOND_PLOT - danger, 1.6, 12.0)
			elif water >= 100.0:
				push(sim, center, Vector2(0, -1), 1.7, 14.0)
			elif reached_first and mode == "relay" and (peak < 1.25 or (tick / 30) % 3 == 0) and feed_front(sim):
				pass
			elif (mass < 25.0 or (peak < 1.1 and sim.total_rain_rate < 0.2 and (tick / 30) % 3 == 0)) and water < 95.0:
				feed_mountain(sim)
			elif center.distance_to(target) > 0.7:
				push(sim, center, target - center, 1.4)
			else:
				var angle := float(tick / 30) * 2.4
				var edge := Vector2(cos(angle), sin(angle))
				push(sim, target + edge * 1.7, -edge, 1.0, 8.0)
		sim.step(Sim.FIXED_STEP)
		if reached_first and sim.second_water >= 30.0 and sim.total_cold_lift - first_cold_lift > 2.0 and not captured:
			snapshot(sim, tick)
			captured = true
		if tick % 1200 == 0:
			print("DUAL ", mode, " t=", tick / 60.0, " A=", sim.plot_water, " B=", sim.second_water, " peak=", sim.peak_density, " cold_lift=", sim.total_cold_lift, " status=", sim.outcome)
		if sim.outcome != "playing":
			break
	var relay_lift: float = sim.total_cold_lift - first_cold_lift
	var near_lift: float = sim.cold_lift_near_second - first_near_lift
	print("DUAL RESULT ", mode, ": ", sim.outcome, " A=", sim.plot_water, " B=", sim.second_water, " strokes=", strokes, " second_lift=", relay_lift, " near_B=", near_lift, " water_error=", sim.water_total() - sim.initial_water)
	quit(0 if sim.outcome == "success" and (mode == "mountain" or near_lift > 2.0) else 1)
