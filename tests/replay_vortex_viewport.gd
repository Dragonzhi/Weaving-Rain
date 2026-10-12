extends "res://tests/replay_plot_needs_viewport.gd"
## Normal-start comparison. Only actual mouse input changes the weather.
func distribution(center: Vector2, core: float) -> Dictionary:
	var mass := 0.0
	var inside := 0.0
	var moment := 0.0
	for i in Sim.COUNT:
		var amount: float = main.sim.humidity[i] + main.sim.cloud[i]
		var distance: float = main.sim.positions[i].distance_to(center)
		mass += amount
		moment += amount * distance * distance
		if distance <= core: inside += amount
	return {"mass": mass, "core_mass": inside, "rms_radius": sqrt(moment / maxf(mass, 0.000001))}

func draw_vortex(center: Vector2, radius: float) -> bool:
	await tap(main.hud.vortex_button)
	var camera: Camera3D = main.weather_view.camera
	var height: float = main.sim.terrain.height(center) + 0.3
	var screen := camera.unproject_position(Vector3(center.x, height, center.y))
	button(screen, true)
	if not main.wind_input.dragging: return false
	height = main.wind_input.reference_height
	var wheel := InputEventMouseButton.new()
	wheel.position = screen
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	var started := Time.get_ticks_usec()
	var duration := 0.3
	while main.sim.outcome == "playing":
		var fraction := minf(1, (Time.get_ticks_usec() - started) / 1000000.0 / duration)
		var point := center + Vector2.RIGHT * radius * fraction
		var event := InputEventMouseMotion.new()
		event.position = camera.unproject_position(Vector3(point.x, height, point.y))
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)
		events += 1
		if fraction >= 1:
			button(event.position, false)
			break
		await process_frame
	await process_frame
	return main.sim.wind_sources.size() == 1

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	var use_vortex := not "--no-vortex" in OS.get_cmdline_user_args()
	var center := Vector2(-6.2, 1.4)
	var radius := 2.2
	var gathering: Dictionary = {}
	var vortex_closed := false
	if use_vortex:
		if not await draw_vortex(center, radius):
			push_error("Normal-start range placement failed")
			quit(1)
			return
		var source: Dictionary = main.sim.wind_sources[0]
		gathering = {"tier": source.tier, "radius": source.radius, "center": [source.position.x, source.position.y], "spin": source.spin, "lifetime": source.lifetime, "before": distribution(center, 0.5)}
		var until: float = main.sim.elapsed_seconds + 2.0
		while main.sim.elapsed_seconds < until: await process_frame
		gathering["after"] = distribution(center, 0.5)
		gathering["active_seconds"] = 2.0
		gathering["hold_seconds"] = 2.0
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/vortex-route-gather.png")
		await tap(main.hud.source_remove[0])
		vortex_closed = main.sim.wind_sources.is_empty()
		gathering["active_seconds"] = source.lifetime - source.remaining
		await tap(main.hud.brush_button)
	var controller := Route.new([0, 1])
	# Gathering concentrates later rainfall: clear the fragile field earlier.
	# Both comparison routes use the same controller; no weather thresholds change.
	controller.narrow_lookahead = 7.0
	var next_at: float = main.sim.elapsed_seconds + 0.5
	var band_at := -1.0
	var placed := false
	var removed := false
	var photographed := false
	while main.sim.outcome == "playing":
		if main.sim.plot_destroyed.any(func(v): return v): break
		if placed and not removed and main.sim.elapsed_seconds - band_at >= 1.5:
			await tap(main.hud.source_remove[0])
			removed = main.sim.wind_sources.is_empty()
		if main.sim.elapsed_seconds >= next_at:
			var command := controller.next_command(main.sim, main.sim.elapsed_seconds)
			next_at += 0.25 if command.get("kind", "") == "clear" and command.get("target", -1) == 1 else 0.5
			if not command.is_empty():
				if not placed and command.kind == "feed":
					await tap(main.hud.source_button)
					await stroke(command)
					placed = not main.sim.wind_sources.is_empty()
					band_at = main.sim.elapsed_seconds
					await tap(main.hud.brush_button)
				else: await stroke(command)
		if not photographed and main.sim.water_for(1) >= 30:
			await RenderingServer.frame_post_draw
			if use_vortex: root.get_texture().get_image().save_png("res://.godot/vortex-route-rain.png")
			photographed = true
		await process_frame
	await RenderingServer.frame_post_draw
	if use_vortex: root.get_texture().get_image().save_png("res://.godot/vortex-route-result.png")
	var report := controller.report(main.sim)
	report["vortex"] = gathering
	report["vortex_closed"] = vortex_closed
	report["gesture_count"] = controller.strokes + (1 if use_vortex else 0)
	report["placement_path_length"] = radius if use_vortex else 0.0
	var path: float = report.placement_path_length
	for command in controller.actions: path += command.from.distance_to(command.to)
	report["total_path_length"] = path
	report["saved_count"] = main.sim.result_saved_count
	report["events"] = events
	report["blocked"] = blocked
	report["input_pick_error"] = input_pick_error
	report["band_placed"] = placed
	report["band_closed"] = removed
	var suffix := ("vortex" if use_vortex else "control") + ("-repeat" if "--repeat" in OS.get_cmdline_user_args() else "")
	var file := FileAccess.open("res://.godot/vortex-route-" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("VORTEX ROUTE ", JSON.stringify(report))
	quit(0 if main.sim.result_stars == 3 and not main.sim.timed_out and placed and removed and (vortex_closed or not use_vortex) and input_pick_error < 0.001 and failures == 0 and not main.wind_input.enabled and absf(report.water_error) < 0.01 else 1)
