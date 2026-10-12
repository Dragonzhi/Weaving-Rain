extends "res://tests/replay_star_viewport.gd"
## Normal wet-air start. Every placement/removal/stroke uses real viewport events.
func tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	button(point, true)
	await create_timer(0.12).timeout
	button(point, false)
	await process_frame

func run() -> void:
	var use_source := not "--no-source" in OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	var controller := Route.new([0, 1, 2], "mountain")
	var next_at := 0.5
	var source_started := -1.0
	var created := false
	var removed := false
	var captured := false
	var active_lift := 0.0
	var source_lift_start := 0.0
	var source_active_seconds := 0.0
	var placed_band: Dictionary = {}
	var captured_front := false
	var strokes := 0
	while main.sim.outcome == "playing":
		if created and not removed and main.sim.elapsed_seconds - source_started >= 3.0:
			active_lift = main.sim.total_mountain_lift - source_lift_start
			source_active_seconds = main.sim.elapsed_seconds - source_started
			if not main.sim.wind_sources.is_empty(): await tap(main.hud.source_remove[0])
			removed = main.sim.wind_sources.is_empty()
		if main.sim.elapsed_seconds >= next_at:
			var command := controller.next_command(main.sim, main.sim.elapsed_seconds)
			next_at += 0.5
			if not command.is_empty():
				if use_source and not created and command.kind == "feed":
					await tap(main.hud.source_button)
					await stroke(command)
					created = not main.sim.wind_sources.is_empty()
					if created:
						var band: Dictionary = main.sim.wind_sources[0]
						placed_band = {"start": [band.position.x, band.position.y], "end": [band.end.x, band.end.y], "strength": band.strength, "lifetime": band.lifetime, "radius": main.sim.settings.brush_radius}
					source_started = main.sim.elapsed_seconds
					source_lift_start = main.sim.total_mountain_lift
					await tap(main.hud.brush_button)
				else:
					await stroke(command)
				strokes += 1
		if created and not captured and main.sim.wind_sources.size() > 0 and main.sim.elapsed_seconds - source_started > 0.7:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/wind-source-play.png")
			captured = true
		if use_source and main.sim.total_rain_rate > 0.01 and main.sim.total_cold_lift > 0.0 and not captured_front:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/wind-flow-rain.png")
			captured_front = true
		await process_frame
	await RenderingServer.frame_post_draw
	if use_source: root.get_texture().get_image().save_png("res://.godot/wind-tools-result.png")
	var report := controller.report(main.sim)
	report["events"] = events
	report["created"] = created
	report["removed"] = removed
	report["source_seconds"] = source_active_seconds
	report["source_active_mountain_lift"] = active_lift
	report["blocked"] = blocked
	report["input_pick_error"] = input_pick_error
	report["cloud_presses"] = cloud_presses
	report["input_disabled"] = not main.wind_input.enabled
	report["commands"] = strokes
	report["use_source"] = use_source
	report["placed_band"] = placed_band
	var file := FileAccess.open("res://.godot/wind-tools-viewport.json" if use_source else "res://.godot/wind-tools-baseline.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("WIND TOOLS VIEWPORT ", JSON.stringify(report))
	if main.sim.result_stars != 3 or main.sim.timed_out or main.sim.sandbox or (use_source and (not created or not removed)) or input_pick_error > 0.001 or failures > 0 or main.wind_input.enabled: failures += 1
	quit(0 if failures == 0 else 1)
