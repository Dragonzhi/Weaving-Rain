extends SceneTree
const Layouts = preload("res://scripts/weather_layouts.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await RenderingServer.frame_post_draw
	main.set_process(false)
	click(main.hud.menu_button)
	await RenderingServer.frame_post_draw
	check(main.hud.levels_button.visible, "Practice exposes star-level entry")
	click(main.hud.levels_button)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.layout_id == "meadow" and main.sim.star_level and main.sim.plot_centers.size() == 3, "Actual entry button starts a normal three-field level")
	check(not main.hud.finish_button.visible and main.hud.finish_button.disabled, "No stars keeps unusable finish out of the scene")
	check(main.hud.timer_label.visible and main.hud.timer_label.text == "03:00", "Wind-medal entry displays the compact map countdown")
	check(not main.hud.blocks_wind(main.hud.timer_rect.get_center()), "Informational countdown allows wind through")
	main.paused = true
	main._process(0.1)
	check(main.sim.elapsed_seconds == 0.0, "Actual paused main loop freezes countdown")
	main.paused = false
	main._process(1.0 / 60.0)
	check(is_equal_approx(main.sim.elapsed_seconds, 1.0 / 60.0), "Resumed main loop advances weather and countdown together")
	click(main.hud.finish_button)
	check(main.sim.outcome == "playing" and not main.wind_input.dragging, "Disabled finish neither ends the game nor creates wind")
	check(main.hud.reserve_rect.has_area() and not main.hud.blocks_wind(main.hud.reserve_rect.get_center()), "Compact reserve remains visible and allows wind through")
	main.sim.humidity.fill(0)
	for i in main.sim.COUNT:
		main.sim.cloud[i] = 2.0 * exp(-main.sim.positions[i].distance_squared_to(Vector2(-1, 0)) / 5.0)
	main.sim.refresh_display()
	main.weather_view.update_weather(0.0, false)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.reserve_message == "水汽所剩不多，云中仍有储水" and main.hud.finish_button.disabled, "Cloud storage is explained without falsely offering exhausted settlement")
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/water-reserve-cloud.png")
	main.sim.cloud.fill(0)
	main.sim.refresh_display()
	main.sim.update_goal(0.0)
	main.weather_view.update_weather(0.0, false)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.reserve_message == "剩余水分不足以浇够新地块" and not main.hud.finish_button.disabled and main.hud.finish_button.text == "结束 · 当前 0 枚风纹", "Exhausted reserve offers explicit zero-star ending")
	check(main.sim.outcome == "playing" and main.wind_input.enabled, "Shortage notice allows continued interaction")
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/water-shortage.png")
	click(main.hud.finish_button)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.outcome == "shortage" and main.sim.ended_for_shortage and main.hud.result_retry.visible and not main.hud.next_button.visible, "Actual zero-star shortage ending exposes retry without next level")
	check(not main.wind_input.enabled and not main.wind_input.dragging, "Manual shortage ending immediately disables further wind")
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/water-shortage-result.png")
	click(main.hud.result_retry)
	await process_frame
	await RenderingServer.frame_post_draw
	check(not main.sim.ended_for_shortage and not main.sim.can_end_shortage() and main.sim.time_remaining() == 180.0, "Actual retry restores full weather reserve and time")
	check(main.wind_input.enabled, "Retry immediately restores wind interaction")
	main.sim.humidity.fill(0)
	main.sim.plot_waters[0] = 110
	main.sim.refresh_display()
	main.sim.update_goal(0.5)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.finish_button.text == "结束 · 当前 0 枚风纹" and main.sim.outcome == "playing", "Unsafe adequate field can continue rather than being auto-ended")
	main.sim.step(2.1)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.finish_button.text == "结束 · 当前 1 枚风纹", "Continuing shortage updates the offered stars after real safety ticks")
	main.restart(false)
	main.sim.plot_waters[0] = 110
	main.sim.plot_waters[2] = 151
	main.sim.update_goal(3.0)
	main.weather_view.update_weather(0.0, false)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(not main.hud.finish_button.disabled and main.sim.outcome == "playing", "One safe star offers settlement after another field is damaged")
	click(main.hud.finish_button)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.outcome == "success" and main.sim.result_stars == 1, "Viewport settlement button freezes a one-star success")
	check(main.hud.next_button.visible and main.hud.result_retry.visible and main.progress.best.get("meadow") == 1, "Results expose retry and next and record the star")
	check(main.hud.blocks_wind(main.hud.result_rect.get_center()), "Entire result panel blocks wind input")
	check(not main.wind_input.dragging, "Finish cancels pending input")
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("res://.godot/star-result.png")
	click(main.hud.result_retry)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.layout_id == "meadow" and main.sim.earned_stars() == 0 and not main.sim.plot_destroyed.any(func(value): return value), "Actual retry restores current map with clean weather and fields")
	check(main.progress.best.get("meadow") == 1, "Retry retains the best result")
	main.sim.plot_waters.fill(110)
	main.sim.update_goal(3.0)
	main._process(1.0 / 60.0)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.finish_button.text == "满风纹 · 3 秒后自动结算" and not main.hud.finish_button.disabled, "Actual button shows automatic delay and remains clickable")
	main.paused = true
	main._process(0.1)
	check(main.sim.three_star_remaining() == 3.0, "Real pause freezes perfect countdown")
	main.paused = false
	var danger_cell: int = main.sim.safety_indices[1][0]
	main.sim.cloud[danger_cell] = 0.001
	main.sim.rain[danger_cell] = 0.001
	main.sim.refresh_display()
	main.sim.update_goal(0.0)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(not "自动结算" in main.hud.finish_button.text and main.sim.outcome == "playing", "Lost star removes countdown from the real button")
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.refresh_display()
	main.sim.update_goal(2.1)
	main._process(1.0 / 60.0)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.finish_button.text == "满风纹 · 3 秒后自动结算", "Regained stars show a fresh full countdown")
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/three-star-countdown.png")
	click(main.hud.finish_button)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.result_stars == 3 and main.progress.best.get("meadow") == 3, "Improved result updates the best")
	click(main.hud.next_button)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.layout_id == "valleys" and main.sim.plot_waters == PackedFloat64Array([0, 0, 0]), "Next button starts the second level without stale water")
	check(main.wind_input.sim == main.sim and main.wind_input.camera == main.weather_view.camera and not main.wind_input.dragging, "Next level reconnects picking and cancels drag")
	main.restart(false)
	check(main.sim.layout_id == "valleys", "R keeps the new current level")
	if "--capture" in OS.get_cmdline_user_args():
		main.hud.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/star-fields.png")
	main.sim.humidity.fill(0)
	main.sim.elapsed_seconds = main.sim.time_limit_seconds - 1.0 / 60.0
	main._process(1.0 / 60.0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.outcome == "timeout" and main.hud.result_retry.visible and not main.hud.next_button.visible, "Deadline in real main loop shows zero-star retry without next-level access")
	check(not main.wind_input.enabled and not main.wind_input.dragging and main.result_recorded, "Automatic settlement immediately cancels wind and records its result")
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/star-timeout.png")
	click(main.hud.result_retry)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.time_remaining() == 180.0 and not main.sim.timed_out, "Result retry restores full countdown")
	main.sim.plot_waters.fill(110)
	main.sim.update_goal(3.0)
	main.sim.elapsed_seconds = main.sim.time_limit_seconds - 1.0 / 60.0
	main._process(1.0 / 60.0)
	check(main.sim.timed_out and main.sim.result_stars == 3 and main.progress.best.get("valleys") == 3, "Timed success awards and records safe stars through the real main loop")
	main.next_level()
	check(main.sim.layout_id == "reservoir_lab", "Valleys flows into the new reservoir test")
	# The last entry is now a mixed tropical map. Isolate its normal finish rule
	# before checking the wrap, rather than assuming the old two-entry list.
	main.select_layout(Layouts.LEVELS.back())
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.charge.fill(0)
	for target in main.sim.plot_centers.size(): main.sim.plot_waters[target] = main.sim.required_water(target)
	main.sim.refresh_display()
	main.sim.update_goal(3.0)
	main.finish_level()
	check(main.sim.result_stars == 3, "Last mixed level uses each target's completion rule")
	main.next_level()
	check(main.sim.layout_id == "meadow", "Actual last level returns to the first level")
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.plot_waters.fill(110)
	main.sim.refresh_display()
	main.sim.update_goal(2.1)
	main._process(1.0 / 60.0)
	for frame in 180: main._process(1.0 / 60.0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.sim.outcome == "success" and main.sim.result_stars == 3 and main.result_recorded, "Real main loop automatically settles and records three stars")
	check(not main.wind_input.enabled and main.hud.next_button.visible, "Automatic three-star result disables wind and offers next level")
	main.restart(true)
	main.sim.plot_waters.fill(110)
	main.sim.cloud.fill(0)
	main.sim.refresh_display()
	main.sim.update_goal(3)
	main.finish_level()
	check(main.sim.outcome == "playing" and main.progress.best.get("meadow") == 3, "Cloud lab cannot settle or change a record")
	var editor_scene: Node3D = preload("res://scripts/map_playtest.gd").new()
	editor_scene.progress_path = "res://.godot/editor-star-progress.cfg"
	editor_scene.custom_map_path = "res://.godot/editor-star-map.tres"
	var editor_map = preload("res://scripts/weather_layouts.gd").get_definition("meadow").duplicate(true)
	ResourceSaver.save(editor_map, editor_scene.custom_map_path)
	var record := ConfigFile.new()
	record.set_value("stars", "meadow", 1)
	record.save(editor_scene.progress_path)
	root.add_child(editor_scene)
	check(not editor_scene.persist_progress and editor_scene.progress.best.is_empty(), "Editor preview ignores formal star records")
	editor_scene.set_process(false)
	editor_scene.sim.plot_waters.fill(110)
	editor_scene.sim.update_goal(3)
	editor_scene.finish_level()
	record.load(editor_scene.progress_path)
	check(editor_scene.sim.result_stars == 3 and record.get_value("stars", "meadow") == 1, "Temporary editor play settles locally without overwriting formal records")
	editor_scene.queue_free()
	print("STAR SCENE: ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
