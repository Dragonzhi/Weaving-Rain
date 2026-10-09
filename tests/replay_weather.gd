extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Onboarding = preload("res://scripts/onboarding.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var lesson := "--lesson" in OS.get_cmdline_user_args()
	var sim := Sim.new(null, false, lesson)
	var guide := Onboarding.new()
	var phases := PackedInt32Array([0])
	var strokes := 0
	for tick in 7200:
		if tick % 30 == 0:
			var mass := 0.0
			var center := Vector2.ZERO
			var peak := 0.0
			for i in Sim.COUNT:
				mass += sim.cloud[i]
				if sim.display_cloud[i] > peak:
					peak = sim.display_cloud[i]
					center = sim.positions[i]
			if (mass < 25.0 or (sim.peak_density < 1.1 and sim.total_rain_rate < 0.2 and (tick / 30) % 3 == 0)) and sim.plot_water < 95.0:
				var source := Vector2(-7, 0.5)
				var wettest := 0.0
				for i in Sim.COUNT:
					var p: Vector2 = sim.positions[i]
					if p.x < -2.8 and p.x > -9.0 and absf(p.y + 0.6) < 3.0 and sim.humidity[i] > wettest:
						wettest = sim.humidity[i]
						source = p
				var direction := (Vector2(-2.5, -0.6) - source).normalized()
				sim.stroke(source - direction * 0.8, source + direction * 2.3, 9.0)
			elif sim.plot_water < 100.0:
				var p := center
				var direction := (Sim.PLOT - p).normalized()
				if p.distance_to(Sim.PLOT) > 0.7:
					sim.stroke(p - direction * 0.8, p + direction * 1.4, 9.0)
				else:
					var angle := float(tick / 30) * 2.4
					var edge := Vector2(cos(angle), sin(angle))
					sim.stroke(Sim.PLOT + edge * 2.0, Sim.PLOT + edge * 0.2, 8.0)
			else:
				sim.stroke(center - Vector2(0, 0.7), center + Vector2(0, 1.5), 14.0)
			strokes += 1
		sim.step(Sim.FIXED_STEP)
		guide.update(sim, Sim.FIXED_STEP)
		if not guide.phase in phases:
			phases.append(guide.phase)
		if tick % 600 == 0:
			print("REPLAY t=", tick / 60.0, " plot=", sim.plot_water, " peak=", sim.peak_density, " rain=", sim.total_rain_rate, " status=", sim.outcome)
		if tick == 600:
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--snapshot="):
					var file := FileAccess.open(arg.trim_prefix("--snapshot="), FileAccess.WRITE)
					file.store_string(JSON.stringify({"humidity": Array(sim.humidity), "cloud": Array(sim.cloud), "rain": Array(sim.rain), "charge": Array(sim.charge), "plot_water": sim.plot_water, "rain_lost": sim.rain_lost, "initial_water": sim.initial_water, "rain_rate": sim.total_rain_rate, "mountain_lift": sim.total_mountain_lift}))
					file.close()
		if sim.outcome != "playing":
			break
	print("REPLAY RESULT: ", sim.outcome, " plot=", sim.plot_water, " strokes=", strokes, " water_error=", sim.water_total() - sim.initial_water)
	if lesson:
		print("LESSON PHASES: ", phases, " cold_peak=", Array(sim.cold).max())
	quit(0 if sim.outcome == "success" and (not lesson or phases.size() == 5) else 1)
