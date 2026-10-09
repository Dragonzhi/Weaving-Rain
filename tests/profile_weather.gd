extends SceneTree
## Development fixtures reproduce a large cloudy/rainy view; never used in gameplay.
const Sim = preload("res://scripts/weather_simulation.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await RenderingServer.frame_post_draw
	main.set_process(false)
	main.hud.debug_visible = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("PROFILE viewport=", root.get_visible_rect().size, " window=", root.size)
	for scenario in ["clear", "cloud", "rain"]:
		main.restart(false)
		if scenario != "clear":
			for i in Sim.COUNT:
				var p: Vector2 = main.sim.positions[i]
				var q := 2.8 * exp(-p.distance_squared_to(Vector2(-5, 0)) / 35.0)
				q += 3.0 * exp(-p.distance_squared_to(Vector2(3, -2)) / 25.0)
				main.sim.cloud[i] = q
				if scenario == "rain":
					main.sim.rain[i] = q
					main.sim.cold[i] = q * 0.7
		main.sim.sandbox = true
		main.sim.initial_water = main.sim.water_total()
		main.sim.refresh_display()
		var simulation := 0.0
		var rendering := 0.0
		var gpu := 0.0
		var frame_ms := 0.0
		var steps := 0
		for frame in 140:
			var start := Time.get_ticks_usec()
			main.sim.step(Sim.FIXED_STEP)
			var sim_ms := (Time.get_ticks_usec() - start) / 1000.0
			start = Time.get_ticks_usec()
			main.weather_view.update_weather(Sim.FIXED_STEP, true)
			var view_ms := (Time.get_ticks_usec() - start) / 1000.0
			main.hud.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			if frame >= 20:
				simulation += sim_ms
				rendering += view_ms
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
				frame_ms += main.get_process_delta_time() * 1000.0
				steps += 1
			if frame == 25:
				root.get_texture().get_image().save_png("res://.godot/profile-" + scenario + ".png")
		print("PROFILE ", scenario, " sim_ms=", simulation / steps, " view_ms=", rendering / steps, " gpu_ms=", gpu / steps, " frame_ms=", frame_ms / steps)
		var map_time := 0.0
		var line_time := 0.0
		var rain_time := 0.0
		for sample in 20:
			var start := Time.get_ticks_usec()
			main.weather_view.update_map()
			map_time += (Time.get_ticks_usec() - start) / 1000.0
			start = Time.get_ticks_usec()
			main.weather_view._update_lines(0.0, false)
			line_time += (Time.get_ticks_usec() - start) / 1000.0
			start = Time.get_ticks_usec()
			main.weather_view._update_rain()
			rain_time += (Time.get_ticks_usec() - start) / 1000.0
		print("SECTIONS ", scenario, " map=", map_time / 20, " lines=", line_time / 20, " rain=", rain_time / 20, " rain_uploads=", main.weather_view.rain_uploads)
	main.queue_free()
	await process_frame
	quit()
