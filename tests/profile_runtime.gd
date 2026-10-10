extends SceneTree
## Real main loop and viewport input. Stress replenishment is development-only.
const Sim = preload("res://scripts/weather_simulation.gd")
var main: Node3D
var previous := Vector2.ZERO
var input_ms := 0.0

func _init() -> void:
	call_deferred("run")

func percentile(values: Array[float], fraction: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[mini(ordered.size() - 1, ceili(ordered.size() * fraction) - 1)]

func seed_stress(kind: String) -> void:
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
	main.sim.initial_water = main.sim.water_total()

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

func run() -> void:
	var duration := 60.0
	var warmup := 5.0
	var label := "after"
	var kinds := ["cloud", "rain", "cold"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): duration = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--warmup="): warmup = float(arg.trim_prefix("--warmup="))
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--kind="): kinds = [arg.trim_prefix("--kind=")]
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
			var previous_draw := Time.get_ticks_usec()
			var trace := PackedStringArray(["frame_ms,steps,simulation_ms,view_ms,pick_ms,input_ms,gpu_ms"])
			if drag: pointer(0.0, true)
			while true:
				await process_frame
				var t := (Time.get_ticks_usec() - start) / 1000000.0
				if t >= duration + warmup: break
				# Keep the stress field populated throughout the sample, excluding seed frames.
				var seeded := t - last_seed >= 5.0
				if seeded:
					seed_stress(kind)
					last_seed = t
				var input_start := Time.get_ticks_usec()
				if drag: pointer(t)
				input_ms = (Time.get_ticks_usec() - input_start) / 1000.0
				await RenderingServer.frame_post_draw
				var draw_time := Time.get_ticks_usec()
				var ms := (draw_time - previous_draw) / 1000.0
				previous_draw = draw_time
				if t >= warmup:
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
