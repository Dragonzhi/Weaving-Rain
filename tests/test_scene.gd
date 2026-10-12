extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func mouse_motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await RenderingServer.frame_post_draw
	main.set_process(false)
	check(main.play_mode == "lesson" and main.sim.plot_centers.size() == 1 and main.sim.cold_capable, "First entry teaches one target with the same cold weather capability")
	var lesson_initial: float = main.sim.initial_water
	var panel_point: Vector2 = main.hud.guide_rect.position + Vector2(25, 25)
	mouse_button(panel_point, true)
	check(not main.hud.blocks_wind(panel_point), "Lesson text leaves weather gestures available")
	mouse_button(panel_point, false)
	var menu_point: Vector2 = main.hud.menu_button.get_global_rect().get_center()
	mouse_button(menu_point, true)
	mouse_button(menu_point, false)
	await RenderingServer.frame_post_draw
	var skip_point: Vector2 = main.hud.free_button.get_global_rect().get_center()
	mouse_button(skip_point, true)
	mouse_button(skip_point, false)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.play_mode == "free" and main.sim.plot_centers.size() == 2 and main.sim.peak_density == 0.0, "Skip button starts a fresh humidity-only dual-target game")
	check(main.wind_input.sim == main.sim and main.wind_input.camera == main.weather_view.camera, "Mode change reconnects picking to the active weather and camera")
	main.restart(false)
	check(main.play_mode == "free" and main.sim.plot_centers.size() == 2, "Retry keeps the current free-play mode")
	mouse_button(menu_point, true)
	mouse_button(menu_point, false)
	await RenderingServer.frame_post_draw
	var revisit_point: Vector2 = main.hud.lesson_button.get_global_rect().get_center()
	mouse_button(revisit_point, true)
	mouse_button(revisit_point, false)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.play_mode == "lesson" and is_equal_approx(main.sim.initial_water, lesson_initial), "Revisit button restores the same single-target lesson")
	main.guide.phase = 2
	main.restart(false)
	check(main.guide.phase == 0 and main.sim.plot_water == 0.0, "Lesson retry resets its prompts and water together")
	main.sim.outcome = "success"
	main.guide.update(main.sim, 0.0)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.play_mode == "lesson" and main.hud.free_button.visible, "Lesson completion waits for an explicit enter-free-play action")
	var continue_point: Vector2 = main.hud.free_button.get_global_rect().get_center()
	mouse_button(continue_point, true)
	mouse_button(continue_point, false)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.play_mode == "free" and main.guide.phase == 0 and not main.wind_input.dragging, "Completion button enters clean free play without dragging or stale guide steps")
	main.restart(true)
	main.weather_view.update_weather(0.0, false)
	var camera: Camera3D = main.weather_view.camera
	var point := camera.unproject_position(Vector3(1, Sim.CLOUD_HEIGHT, 0.3))
	var wind_input: Node = main.wind_input
	var hit: Vector3 = wind_input.pick(point)
	check(hit.y > 3.0, "Picking starts at visible cloud rather than its ground shadow")
	var outside: Vector3 = wind_input.pick(Vector2(-100000, -100000))
	check(not Sim.contains(Vector2(outside.x, outside.z)), "Off-window rays without plane intersections are safely rejected")
	mouse_button(point, true)
	check(wind_input.dragging, "Viewport mouse press begins a stroke")
	var reference: float = wind_input.reference_height
	mouse_motion(point + Vector2(55, 0))
	wind_input.flush()
	var wind_sum := 0.0
	for wind in main.sim.wind:
		wind_sum += wind.length()
	check(wind_sum > 0.1, "Viewport mouse motion produces local wind")
	main.weather_view.update_weather(0.0, false)
	check(main.weather_view.visible_wind_lines > 0, "Actual viewport stroke creates visible wind ribbons")
	var age: float = main.weather_view.wind_traces[0].age
	main.weather_view.update_weather(0.5, false)
	check(main.weather_view.wind_traces[0].age == age, "Paused rendering freezes wind trace movement and lifetime")
	main.sim.cloud.fill(0.0)
	main.sim.refresh_display()
	mouse_motion(point + Vector2(85, 25))
	check(is_equal_approx(wind_input.brush_point.y, reference), "Stroke reference plane stays fixed after cloud changes")
	wind_input._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not wind_input.dragging, "Losing focus cancels a stroke")
	mouse_button(point, true)
	main.hud.queue_redraw()
	await process_frame
	var button_point: Vector2 = main.hud.menu_button.get_global_rect().get_center()
	mouse_button(button_point, false)
	check(not wind_input.dragging, "Releasing over UI cannot leave a stuck stroke")
	main.restart(true)
	mouse_button(button_point, true)
	check(not wind_input.dragging, "UI buttons do not create wind strokes")
	mouse_button(button_point, false)
	var card_point := Vector2(80, main.hud.size.y - 65)
	mouse_button(card_point, true)
	check(not main.hud.blocks_wind(card_point), "Removed water-card area allows weather input")
	mouse_button(card_point, false)
	main.restart(false)
	for layout_index in [1, 2]:
		main.hud.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var selector_point: Vector2 = main.hud.layout_selector.get_global_rect().get_center()
		mouse_button(selector_point, true)
		mouse_button(selector_point, false)
		var popup: PopupMenu = main.hud.layout_selector.get_popup()
		check(popup.visible and not wind_input.dragging, "Opening layout selector does not stroke the weather")
		popup.index_pressed.emit(layout_index)
		popup.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var id: String = preload("res://scripts/weather_layouts.gd").IDS[layout_index]
		check(main.sim.layout_id == id and main.sim.peak_density == 0.0 and main.wind_input.sim == main.sim, "Selecting layout rebuilds a clean world with connected input")
		var geometry_matches := 0
		for child in main.weather_view.get_children():
			if child is MeshInstance3D:
				for target in 2:
					if child.material_override == main.weather_view.plot_materials[target]:
						var p: Vector2 = main.sim.plot_centers[target]
						if is_equal_approx(child.position.x, p.x) and is_equal_approx(child.position.z, p.y):
							geometry_matches += 1
		check(geometry_matches == 2, "Displayed targets match the selected simulation coverage")
		main.paused = true
		main.wind_input.dragging = true
		main.restart(false)
		check(main.sim.layout_id == id and not main.paused and not wind_input.dragging, "Retry preserves selected layout and clears paused drag state")
	main.switch_mode("lesson")
	check(main.sim.plot_centers.size() == 1 and main.sim.layout_id == "standard", "Revisiting lesson preserves its independent layout")
	main.enter_free_play()
	check(main.sim.layout_id == "close", "Returning from lesson preserves the selected free-play layout")
	main.select_layout("standard")
	check(main.sim.peak_density == 0.0 and not main.sim.sandbox, "Restart returns from lab to humidity-only gameplay")
	check(main.weather_view.plot_materials.size() == 2 and main.sim.second_water == 0.0, "Normal scene has two independent targets")
	main.cold_lab()
	check(main.sim.sandbox and main.sim.total_rain_rate == 0.0, "Cold lab is separate from normal completion")
	main.restart(false)
	var pause_event := InputEventKey.new()
	pause_event.keycode = KEY_SPACE
	pause_event.pressed = true
	root.push_input(pause_event)
	main._process(0.0)
	check(main.paused and not wind_input.enabled, "Pause disables wind input")
	main.restart(false)
	main.sim.cold.fill(0.4)
	main.sim.refresh_display()
	main.guide.update(main.sim, 0.1)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.dismiss_hint.visible, "Actual cold in free play displays its optional hint")
	var dismiss_point: Vector2 = main.hud.dismiss_hint.get_global_rect().get_center()
	mouse_button(dismiss_point, true)
	mouse_button(dismiss_point, false)
	check(main.guide.cold_hint_left == 0.0 and not wind_input.dragging, "Hint can be dismissed without applying wind")
	main.restart(false)
	# A delayed frame must retain its fixed steps across budgeted recovery frames.
	main.sim.sandbox = true
	main.sim.cloud.fill(2.8)
	main.sim.rain.fill(2.8)
	main.sim.cold.fill(1.4)
	main.sim.wind.fill(Vector2(2.0, 0.0))
	main.sim.refresh_display()
	main._process(0.1)
	var recovered_steps: int = main.frame_steps
	for attempt in 12:
		main._process(0.0)
		recovered_steps += main.frame_steps
	check(recovered_steps == 6 and main.accumulator < 0.000001, "Budgeted catch-up retains all six fixed steps without discarding weather time")
	main.restart(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene-capture="):
			main.restart(true)
			main.weather_view.update_weather(0.0, false)
			main.hud.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--scene-capture="))
	print("SCENE TESTS: ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
