extends "res://tests/test_wind_tools_scene.gd"
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	check(main.sim.tropical != null and main.weather_view.reservoir_surfaces[1] != null, "Theme creates runtime weather and native pool geometry")
	check(main.hud.status_text(1).contains("蓄水中"), "Reservoir status has no farm flood warning")
	await held_tap(main.hud.source_button)
	await place(Vector2(8, -3), Vector2(10, -3))
	check(main.sim.wind_sources.size() == 1, "Actual band creation in tropical field")
	await held_tap(main.hud.source_remove[0])
	check(main.sim.wind_sources.is_empty() and main.sim.tropical != null, "Native close removes only artificial source")
	await create_timer(0.5).timeout
	check(main.weather_view.visible_wind_lines > 0 and main.weather_view.visible_wind_lines <= 48, "Natural weather generates shared-budget white lines")
	main.paused = true
	main.wind_input.cancel()
	var heat: PackedFloat32Array = main.sim.tropical.heat.duplicate()
	var center: Vector2 = main.sim.tropical.center
	var clock: float = main.weather_view.elapsed
	await create_timer(0.2).timeout
	check(main.sim.tropical.heat == heat and main.sim.tropical.center == center and main.weather_view.elapsed == clock, "Pause freezes natural heat center and visual time")
	var candidate: WRWeatherSettings = main.sim.settings.duplicate()
	candidate.tropical_radius += 0.2
	candidate.hold_gain += 0.1
	ResourceSaver.save(candidate, "res://.godot/tropical-tuning.tres")
	main.settings_path = "res://.godot/tropical-tuning.tres"
	check(main.reload_tuning() and main.sim.settings.hold_gain == candidate.hold_gain and main.sim.settings.tropical_radius != candidate.tropical_radius and main.sim.tropical.heat == heat, "F6 preserves tropical state and defers its settings")
	main.restart(false)
	await RenderingServer.frame_post_draw
	check(main.sim.settings.tropical_radius == candidate.tropical_radius and main.sim.evaporated_water == 0 and main.sim.overflow_water == 0, "Retry applies tropical settings and resets ledger")
	main.set_process(false)
	main.sim.plot_waters[1] = main.sim.required_water(1)
	main.sim.update_goal(0.1)
	main.hud.update_feedback(0.1)
	main.weather_view.update_weather(0.1, true)
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(main.hud.status_text(1).contains("已蓄满") and main.sim.earned_stars() == 1, "Full pool feedback and real mixed rating")
	check(not main.hud.blocks_wind(main.hud.plot_label_rects[1].get_center()), "Pool information stays input-transparent")
	var surface_height: float = main.weather_view.reservoir_surfaces[1].position.y
	main.weather_view.update_weather(0.2, false)
	check(main.weather_view.reservoir_surfaces[1].position.y == surface_height, "Paused pool visual does not advance")
	var invalid: WRWeatherSettings = candidate.duplicate()
	invalid.tropical_support_rate = 0
	ResourceSaver.save(invalid, "res://.godot/tropical-tuning.tres")
	check(not main.reload_tuning() and main.sim.settings.tropical_support_rate == candidate.tropical_support_rate, "Invalid tropical config preserves active state")
	main.settings_path = "res://configs/weather.tres"
	main.restart(false)
	main.set_process(false)
	for n in 300: main.sim.step(1.0 / 60.0)
	main.weather_view.update_weather(0.1, true)
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/tropical-scene.png")
	check(main.weather_view.ocean_material.get_shader_parameter("warm_enabled") == true and main.sim.tropical.total_lift > 0, "GPU scene uses actual warm field and convection")
	print("TROPICAL SCENE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
