extends "res://tests/replay_star_viewport.gd"
## Normal wet-air start with actual picking, wheel, release and held UI clicks.
func button(point: Vector2, pressed: bool) -> void:
	super.button(point, pressed)
	if pressed and main.wind_input.tool == "source" and main.wind_input.dragging:
		var wheel := InputEventMouseButton.new()
		wheel.position = point
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		root.push_input(wheel, true)
		events += 1
func tap(control: Control) -> void:
	var p := control.get_global_rect().get_center()
	button(p, true)
	await create_timer(0.12).timeout
	button(p, false)
	await process_frame
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	var controller := Route.new([0, 1])
	var next_at := 0.5
	var source_at := -1.0
	var placed := false
	var removed := false
	var source: Dictionary = {}
	var photographed := false
	while main.sim.outcome == "playing":
		if placed and not removed and main.sim.elapsed_seconds - source_at >= 1.5:
			await tap(main.hud.source_remove[0])
			removed = main.sim.wind_sources.is_empty()
		if main.sim.earned_stars() == 2 and main.sim.can_finish():
			await tap(main.hud.finish_button)
			continue
		if main.sim.elapsed_seconds >= next_at:
			var command := controller.next_command(main.sim, main.sim.elapsed_seconds)
			next_at += 0.5
			if not command.is_empty():
				if not placed and command.kind == "feed":
					await tap(main.hud.source_button)
					await stroke(command)
					placed = not main.sim.wind_sources.is_empty()
					if placed:
						var band: Dictionary = main.sim.wind_sources[0]
						source = {"strength": band.strength, "lifetime": band.lifetime, "start": [band.position.x, band.position.y], "end": [band.end.x, band.end.y]}
					source_at = main.sim.elapsed_seconds
					await tap(main.hud.brush_button)
				else: await stroke(command)
		if not photographed and main.sim.water_for(1) >= 30:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/needs-route-rain.png")
			photographed = true
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/needs-route-result.png")
	var report := controller.report(main.sim)
	report["events"] = events
	report["blocked"] = blocked
	report["input_pick_error"] = input_pick_error
	report["placed"] = placed
	report["removed"] = removed
	report["band"] = source
	var file := FileAccess.open("res://.godot/needs-viewport-route.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("NEEDS VIEWPORT ", JSON.stringify(report))
	quit(0 if main.sim.result_stars == 2 and not main.sim.timed_out and placed and removed and source.get("strength", -1) == 0.0 and input_pick_error < 0.001 and failures == 0 and not main.wind_input.enabled else 1)
