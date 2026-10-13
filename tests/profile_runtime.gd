extends SceneTree
## Real main loop and viewport input. Stress replenishment is development-only.
const Sim = preload("res://scripts/weather_simulation.gd")
var main: Node3D
var previous := Vector2.ZERO
var input_ms := 0.0
var wind_combination := "band"

func _init() -> void:
	call_deferred("run")

func percentile(values: Array[float], fraction: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[mini(ordered.size() - 1, ceili(ordered.size() * fraction) - 1)]

func seed_stress(kind: String) -> void:
	if main.sim.tropical != null:
		# Development pressure only; do not let active weather vanish mid-sample.
		main.sim.tropical.organization = 0.8
		main.sim.tropical.strength = 0.8
		for i in main.sim.tropical.indices:
			main.sim.tropical.heat[i] = main.sim.tropical.sea.initial_energy * main.sim.tropical.sea.weight(main.sim.positions[i])
	for i in Sim.COUNT:
		var p: Vector2 = main.sim.positions[i]
		var q := 2.8 * exp(-p.distance_squared_to(Vector2(-5, 0)) / 35.0)
		q += 3.0 * exp(-p.distance_squared_to(Vector2(3, -2)) / 25.0)
		main.sim.cloud[i] = maxf(main.sim.cloud[i], q)
		if kind != "cloud":
			main.sim.rain[i] = main.sim.cloud[i]
		if kind == "cold":
			main.sim.cold[i] = maxf(main.sim.cold[i], q * 0.7)
	main.sim.sandbox = true
	main.sim.refresh_display()
	main.sim.initial_water = main.sim.water_total() - main.sim.evaporated_water

func pointer(t: float, press: bool = false, release: bool = false) -> void:
	var p := Vector3(sin(t * 1.3) * 4.0, Sim.CLOUD_HEIGHT, cos(t * 0.9) * 1.5)
	var screen: Vector2 = main.weather_view.camera.unproject_position(p)
	if press or release:
		var event := InputEventMouseButton.new()
		event.position = screen
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = press
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = screen
		event.relative = screen - previous
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)
	previous = screen

func stress_sources() -> bool:
	# Development pressure only: keep two simultaneous sources through the sample.
	while main.sim.wind_sources.size() < 2:
		var side := -1.0 if main.sim.wind_sources.is_empty() else 1.0
		var start := Vector2(side * 8, side * 2)
		var end := Vector2(-side * 7, -side * 2)
		var vortex := wind_combination == "vortex" or (wind_combination == "mixed" and side > 0)
		var placed: Dictionary = main.sim.add_vortex(start, 3.0, 1 if side > 0 else -1, 2) if vortex else main.sim.add_wind_source(start, end - start, 1.0, end)
		if not placed.ok:
			push_error("Two-source stress requires source_limit >= 2: " + placed.reason)
			quit(1)
			return false
	for source in main.sim.wind_sources: source.remaining = source.lifetime
	return true

func run() -> void:
	var duration := 60.0
	var warmup := 5.0
	var label := "after"
	var hints_off := false
	var kinds := ["cloud", "rain", "cold"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): duration = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--warmup="): warmup = float(arg.trim_prefix("--warmup="))
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--kind="): kinds = [arg.trim_prefix("--kind=")]
		if arg.begins_with("--wind-combination="): wind_combination = arg.trim_prefix("--wind-combination=")
		if arg == "--hints-off": hints_off = true
	if wind_combination not in ["band", "vortex", "mixed"]:
		push_error("Unknown wind combination: " + wind_combination)
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("RUNTIME viewport=", root.get_visible_rect().size, " window=", root.size, " rendered_image=", root.get_texture().get_image().get_size(), " layout=", main.sim.layout_id)
	var reports: Array = []
	for kind in kinds:
		for drag in [false, true]:
			main.restart(false)
			# Development-only old rain shader for same-session cost comparison.
			if "--legacy-rain" in OS.get_cmdline_user_args():
				var legacy := Shader.new()
				legacy.code = load("res://tests/test_rain_layers.gd").LEGACY_RAIN
				main.weather_view.rain_material.shader = legacy
			main.weather_view.hints_enabled = not hints_off
			seed_stress(kind)
			main.guide.cold_hint_seen = true
			var start := Time.get_ticks_usec()
			var last_seed := 0.0
			var frames: Array[float] = []
			var sums := Vector4.ZERO
			var input_sum := 0.0
			var steps := 0
			var sample_steps := 0
			var max_backlog_ms := 0.0
			var slow := 0
			var peak_arrows := 0
			var peak_source_lines := 0
			var peak_rain_cells := 0
			var peak_rain_focus := 0.0
			var min_sources := 4
			var previous_draw := Time.get_ticks_usec()
			var trace := PackedStringArray(["frame_ms,steps,simulation_ms,view_ms,pick_ms,input_ms,gpu_ms"])
			if drag:
				if not stress_sources(): return
				pointer(0.0, true)
			while true:
				await process_frame
				var t := (Time.get_ticks_usec() - start) / 1000000.0
				if t >= duration + warmup: break
				# Keep the stress field populated throughout the sample, excluding seed frames.
				var seeded := t - last_seed >= 5.0
				if seeded:
					seed_stress(kind)
					if drag and not stress_sources(): return
					last_seed = t
				var input_start := Time.get_ticks_usec()
				if drag: pointer(t)
				input_ms = (Time.get_ticks_usec() - input_start) / 1000.0
				await RenderingServer.frame_post_draw
				var draw_time := Time.get_ticks_usec()
				var ms := (draw_time - previous_draw) / 1000.0
				previous_draw = draw_time
				if t >= warmup:
					peak_arrows = maxi(peak_arrows, main.weather_view.visible_arrows)
					peak_source_lines = maxi(peak_source_lines, main.weather_view.visible_source_lines)
					peak_rain_cells = maxi(peak_rain_cells, main.weather_view.rain_area.wet_cells.size())
					peak_rain_focus = maxf(peak_rain_focus, main.weather_view.rain_area.peak_focus)
					min_sources = mini(min_sources, main.sim.wind_sources.size())
					sample_steps += main.frame_steps
					max_backlog_ms = maxf(max_backlog_ms, main.accumulator * 1000.0)
				if t < warmup or seeded: continue
				var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
				frames.append(ms)
				sums += Vector4(main.frame_simulation_ms, main.frame_view_ms, main.frame_pick_ms, gpu_ms)
				input_sum += input_ms + main.frame_input_ms
				steps += main.frame_steps
				trace.append("%.4f,%d,%.4f,%.4f,%.4f,%.4f,%.4f" % [ms, main.frame_steps, main.frame_simulation_ms, main.frame_view_ms, main.frame_pick_ms, input_ms + main.frame_input_ms, gpu_ms])
				if ms > 33.0: slow += 1
			pointer(duration + warmup, false, true)
			var count := frames.size()
			var report := {"layout": main.sim.layout_id, "kind": kind, "drag": drag, "frames": count, "p50": percentile(frames, 0.5), "p95": percentile(frames, 0.95), "p99": percentile(frames, 0.99), "slow_33ms": slow, "sim_ms": sums.x / count, "view_ms": sums.y / count, "pick_ms": sums.z / count, "input_ms": input_sum / count, "gpu_ms": sums.w / count, "steps_per_frame": float(steps) / count, "sample_seconds": duration, "simulation_seconds": sample_steps * Sim.FIXED_STEP, "max_backlog_ms": max_backlog_ms, "final_backlog_ms": main.accumulator * 1000.0}
			report["min_sources"] = min_sources
			report["wind_combination"] = wind_combination
			report["source_kinds"] = main.sim.wind_sources.map(func(s): return s.kind) if drag else []
			report["rendered_size"] = Array([root.get_texture().get_image().get_width(), root.get_texture().get_image().get_height()])
			report["peak_arrows"] = peak_arrows
			report["peak_source_lines"] = peak_source_lines
			report["arrows_enabled"] = main.weather_view.hints_enabled
			report["rain_area_visible"] = main.weather_view.rain_area.visible_area
			report["peak_rain_area_cells"] = peak_rain_cells
			report["peak_rain_focus"] = peak_rain_focus
			report["rain_area_group_builds"] = main.weather_view.rain_area.group_builds
			report["natural_weather"] = main.sim.tropical != null
			report["natural_organization"] = main.sim.tropical.organization if main.sim.tropical != null else 0.0
			reports.append(report)
			print("RUNTIME ", JSON.stringify(report))
			var csv := FileAccess.open("res://.godot/runtime-" + label + "-" + main.sim.layout_id + "-" + kind + ("-drag" if drag else "-idle") + ".csv", FileAccess.WRITE)
			csv.store_string("\n".join(trace))
			csv.close()
	var file := FileAccess.open("res://.godot/runtime-" + label + "-" + main.sim.layout_id + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	main.queue_free()
	await process_frame
	quit()
