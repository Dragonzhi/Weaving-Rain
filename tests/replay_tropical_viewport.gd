extends "res://tests/replay_star_viewport.gd"
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	var sequence := [0, 1] if "--reverse" in OS.get_cmdline_user_args() else [1, 0]
	var controller := Route.new(sequence, "tropical")
	controller.farm_lookahead = 7.0
	controller.farm_floor_fraction = 0.2
	controller.clear_to_next = false
	var next_at := 0.5
	var captured := false
	var rain_area_seen := false
	var peak_rain_cells := 0
	var peak_rain_focus := 0.0
	while main.sim.outcome == "playing":
		rain_area_seen = rain_area_seen or main.weather_view.rain_area.visible_area
		peak_rain_cells = maxi(peak_rain_cells, main.weather_view.rain_area.wet_cells.size())
		peak_rain_focus = maxf(peak_rain_focus, main.weather_view.rain_area.peak_focus)
		if main.sim.elapsed_seconds >= next_at:
			var command := controller.next_command(main.sim, main.sim.elapsed_seconds)
			next_at += 0.25
			if not command.is_empty(): await stroke(command)
		if not captured and main.sim.elapsed_seconds >= 8.0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/tropical-route-rain.png")
			captured = true
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/tropical-route-result.png")
	var report := controller.report(main.sim)
	report["events"] = events
	report["blocked"] = blocked
	report["input_pick_error"] = input_pick_error
	report["evaporated_water"] = main.sim.evaporated_water
	report["overflow_water"] = main.sim.overflow_water
	report["natural_lift"] = main.sim.tropical.total_lift
	report["max_wind_lines"] = main.weather_view.visible_wind_lines
	report["rain_area_hints_enabled"] = main.weather_view.hints_enabled
	report["rain_area_seen"] = rain_area_seen
	report["peak_rain_cells"] = peak_rain_cells
	report["peak_rain_focus"] = peak_rain_focus
	var name := "tropical-viewport-" + ("farm-first" if sequence[0] == 0 else "pool-first")
	var file := FileAccess.open("res://.godot/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("TROPICAL VIEWPORT ", JSON.stringify(report))
	quit(0 if main.sim.result_stars == 3 and not main.sim.timed_out and not main.wind_input.enabled and absf(main.sim.water_error()) < 0.02 and input_pick_error < 0.001 and failures == 0 else 1)
