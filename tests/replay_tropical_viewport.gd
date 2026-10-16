extends "res://tests/replay_star_viewport.gd"
func tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	button(point,true)
	await create_timer(0.12).timeout
	button(point,false)
	await process_frame

func place_seed_vortex() -> bool:
	await tap(main.hud.vortex_button)
	var center: Vector2 = main.sim.tropical.sea.seed_position
	var camera: Camera3D = main.weather_view.camera
	button(camera.unproject_position(Vector3(center.x,0.3,center.y)),true)
	if not main.wind_input.dragging: return false
	var height: float = main.wind_input.reference_height
	var start := Time.get_ticks_usec()
	while true:
		var fraction := minf(1.0,(Time.get_ticks_usec()-start)/300000.0)
		var p := center+Vector2.RIGHT*2.5*fraction
		var event := InputEventMouseMotion.new()
		event.position = camera.unproject_position(Vector3(p.x,height,p.y))
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event,true)
		events += 1
		if fraction>=1:
			button(event.position,false)
			break
		await process_frame
	await process_frame
	var placed: bool = main.sim.wind_sources.size()==1 and main.sim.wind_sources[0].kind=="vortex"
	await tap(main.hud.brush_button)
	return placed

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.weather_view.hints_enabled = true # This route explicitly validates rain-area hints.
	await RenderingServer.frame_post_draw
	var pure := "--pure" in OS.get_cmdline_user_args()
	var seed_placed := false
	if pure:
		# Same zero-seed development map variant as the existing headless pure route.
		# Reconstruct a normal humidity-only simulation; never inject or clear fields.
		main.custom_map = main.custom_map.duplicate(true)
		main.custom_map.warm_sea.seed_organization = 0
		main.custom_map.warm_sea.initial_cloud_fraction = 0
		main.custom_map_path = ""
		main.switch_mode("free")
		if main.sim.peak_density!=0:
			push_error("Pure route did not start with humidity only")
			quit(1)
			return
		seed_placed = await place_seed_vortex()
	main.guide.cold_hint_seen = true
	var audio_review := preload("res://tests/audio_route_record.gd").new()
	audio_review.start(main)
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
		audio_review.sample()
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
	if "--audio-review" in OS.get_cmdline_user_args():
		await create_timer(0.8).timeout
		report["audio"] = audio_review.finish("res://.godot/audio-tropical-route.wav")
	report["events"] = events
	report["blocked"] = blocked
	report["input_pick_error"] = input_pick_error
	report["evaporated_water"] = main.sim.evaporated_water
	report["overflow_water"] = main.sim.overflow_water
	report["natural_lift"] = main.sim.tropical.total_lift
	report["pure_start"] = pure
	report["seed_vortex_placed_by_mouse"] = seed_placed
	report["max_wind_lines"] = main.weather_view.visible_wind_lines
	report["rain_area_hints_enabled"] = main.weather_view.hints_enabled
	report["rain_area_seen"] = rain_area_seen
	report["peak_rain_cells"] = peak_rain_cells
	report["peak_rain_focus"] = peak_rain_focus
	var name := "tropical-viewport-" + ("farm-first" if sequence[0] == 0 else "pool-first")
	if pure: name += "-pure"
	var file := FileAccess.open("res://.godot/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("TROPICAL VIEWPORT ", JSON.stringify(report))
	quit(0 if main.sim.result_stars == 3 and not main.sim.timed_out and not main.wind_input.enabled and absf(main.sim.water_error()) < 0.02 and input_pick_error < 0.001 and failures == 0 and (seed_placed or not pure) else 1)
