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
var front_strokes := 0
var first_index := 0
var second_index := 1

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
	var mountain: Vector2 = sim.terrain.mountain
	var best := 0.0
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		if p.distance_to(mountain) > 1.8 and p.distance_to(mountain) < 7.5 and absf(p.y) < 3.5:
			var score: float = sim.humidity[i] / (1.0 + p.distance_to(mountain) * 0.12)
			if score > best:
				best = score
				source = p
	push(sim, source, mountain - source, 2.3)

func feed_front(sim: RefCounted) -> bool:
	var best := 0.0
	var chosen := -1
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		if p.distance_to(sim.plot_centers[second_index]) > 3.5 or sim.cold[i] < 0.12:
			continue
		var gradient: Vector2 = sim.cold_gradient(i)
		var score: float = sim.humidity[i] * minf(sim.cold[i], 1.0) * gradient.length() / (1.0 + p.distance_squared_to(sim.plot_centers[second_index]) * 0.25)
		if score > best:
			best = score
			chosen = i
	if chosen < 0 or best < 0.015:
		return false
	var direction: Vector2 = sim.cold_gradient(chosen).normalized()
	push(sim, sim.positions[chosen] - direction * 0.5, direction, 1.2, 8.0)
	front_strokes += 1
	return true

func snapshot(sim: RefCounted, tick: int) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			var file := FileAccess.open(arg.trim_prefix("--snapshot="), FileAccess.WRITE)
			var velocities: Array = []
			for v in sim.wind:
				velocities.append([v.x, v.y])
			file.store_string(JSON.stringify({"layout": sim.layout_id, "humidity": Array(sim.humidity), "cloud": Array(sim.cloud), "rain": Array(sim.rain), "charge": Array(sim.charge), "cold": Array(sim.cold), "wind": velocities, "plot_water": sim.plot_water, "second_water": sim.second_water, "rain_lost": sim.rain_lost, "initial_water": sim.initial_water, "rain_rate": sim.total_rain_rate, "cold_lift": sim.total_cold_lift, "time": tick / 60.0, "stroke": [[last_from.x, last_from.y], [last_to.x, last_to.y]]}))
			file.close()

func run() -> void:
	if "--mountain" in OS.get_cmdline_user_args() or "--mountain-with-cold" in OS.get_cmdline_user_args():
		mode = "mountain"
	var layout := "standard"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			layout = arg.trim_prefix("--layout=")
	var sim := Sim.new(null, true, false, layout)
	if "--reverse" in OS.get_cmdline_user_args():
		first_index = 1
		second_index = 0
	var a: Vector2 = sim.plot_centers[first_index]
	var b: Vector2 = sim.plot_centers[second_index]
	sim.settings.cold_enabled = mode == "relay" or "--mountain-with-cold" in OS.get_cmdline_user_args()
	var captured := false
	for tick in 12000:
		if tick % 30 == 0:
			# Start relocating before demand is met: stored rain keeps falling during the move.
			var relocate_at := 65.0 if layout == "close" and sim.settings.cold_enabled else 80.0
			if layout == "far": relocate_at = 95.0
			if layout == "close" and first_index == 1: relocate_at = 85.0
			if not reached_first and sim.water_for(first_index) >= relocate_at:
				reached_first = true
				first_cold_lift = sim.total_cold_lift
				first_near_lift = sim.cold_lift_near_second
			var target := b if reached_first else a
			var center := target
			var peak := 0.0
			var mass := 0.0
			for i in Sim.COUNT:
				var p: Vector2 = sim.positions[i]
				if (p.y < 3.0 and p.y > -4.5) or layout != "standard":
					mass += sim.cloud[i]
					if sim.display_cloud[i] > peak:
						peak = sim.display_cloud[i]
						center = p
			var water: float = sim.water_for(second_index) if reached_first else sim.water_for(first_index)
			var clear_at := 100.0 if mode == "relay" else 90.0
			if layout == "close" and mode == "mountain":
				clear_at = 95.0
				if first_index == 1: clear_at = 85.0
			if layout != "standard" and reached_first and water >= clear_at:
				var danger := center
				var strength := 0.0
				var clear_target := 1
				for i in Sim.COUNT:
					var p: Vector2 = sim.positions[i]
					for target_index in 2:
						var plot: Vector2 = sim.plot_centers[target_index]
						if absf(p.x - plot.x) <= Sim.SAFE_HALF and absf(p.y - plot.y) <= Sim.SAFE_HALF:
							var score: float = sim.rain[i] + sim.display_cloud[i] * 0.1
							if score > strength:
								strength = score
								danger = p
								clear_target = target_index
				push(sim, danger, Vector2(0, 1 if clear_target == 0 else -1), 1.7, 14.0)
			elif reached_first and sim.plot_threats[first_index]:
				var danger := a
				var strength := 0.0
				for i in Sim.COUNT:
					var p: Vector2 = sim.positions[i]
					if absf(p.x - a.x) < Sim.SAFE_HALF and absf(p.y - a.y) < Sim.SAFE_HALF and p.distance_to(b) > 1.0:
						if sim.rain[i] > strength:
							strength = sim.rain[i]
							danger = p
				push(sim, danger, b - danger, 1.6, 12.0)
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
	print("DUAL RESULT ", layout, " ", mode, " cold_enabled=", sim.settings.cold_enabled, ": ", sim.outcome, " A=", sim.plot_water, " B=", sim.second_water, " strokes=", strokes, " front_strokes=", front_strokes, " second_lift=", relay_lift, " near_B=", near_lift, " water_error=", sim.water_total() - sim.initial_water)
	quit(0 if sim.outcome == "success" and (mode == "mountain" or (near_lift > 2.0 and front_strokes > 0)) else 1)
