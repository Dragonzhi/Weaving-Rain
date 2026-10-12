extends SceneTree
var main: Node3D
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _init() -> void: call_deferred("run")
func button(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.pressed = pressed
	e.button_index = MOUSE_BUTTON_LEFT
	root.push_input(e, true)
func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
func wheel(p: Vector2, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.pressed = true
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	root.push_input(e, true)
func screen(p: Vector2) -> Vector2:
	return main.weather_view.camera.unproject_position(Vector3(p.x, main.sim.terrain.height(p) + 0.3, p.y))
func tap(control: Control) -> void:
	var p := control.get_global_rect().get_center()
	button(p, true)
	button(p, false)
	await process_frame
func held_tap(control: Control) -> void:
	var p := control.get_global_rect().get_center()
	button(p, true)
	await create_timer(0.12).timeout
	button(p, false)
	await process_frame
	await RenderingServer.frame_post_draw
func place(a: Vector2, b: Vector2) -> void:
	button(screen(a), true)
	await create_timer(0.06).timeout
	var h: float = main.wind_input.reference_height
	var end: Vector2 = main.weather_view.camera.unproject_position(Vector3(b.x, h, b.y))
	move(end)
	await process_frame
	button(end, false)
	await process_frame
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	check(main.wind_input.tool == "brush", "Default is brush")
	var original_outline: PackedVector2Array = main.hud._ground_region(0)
	var original_zoom: float = main.weather_view.camera.size
	main.weather_view.camera.size = original_zoom * 0.8
	var zoomed_outline: PackedVector2Array = main.hud._ground_region(0)
	var corner: Vector2 = main.sim.plot_centers[0] + main.sim.plot_regions[0].outline(main.sim.plot_half)[0]
	var projected: Vector2 = main.weather_view.camera.unproject_position(Vector3(corner.x, main.sim.terrain.height(corner) + 0.06, corner.y))
	check(zoomed_outline != original_outline and zoomed_outline[0].distance_to(projected) < 0.001, "Ground feedback contours follow changed camera projection")
	main.weather_view.camera.size = original_zoom
	check(main.hud.blocks_wind(main.hud.wind_toolbar_rect.get_center()), "Whole toolbar blocks wind")
	var start := screen(Vector2(-5, 0))
	button(start, true)
	await create_timer(0.2).timeout
	check(main.sim.held_wind.is_empty(), "Holding click without drag adds no force")
	button(start, false)
	button(start, true)
	move(screen(Vector2(-4.5, 0)))
	await create_timer(0.2).timeout
	check(not main.sim.held_wind.is_empty(), "Actual drag then hold continues blowing")
	move(screen(Vector2(-4, 0)))
	check(main.sim.held_wind.is_empty(), "New mouse motion immediately stops held force")
	button(screen(Vector2(-4, 0)), false)
	check(main.sim.held_wind.is_empty(), "Release cancels held force")
	await tap(main.hud.source_button)
	check(main.wind_input.tool == "source", "Actual toolbar selects persistent tool")
	var before: PackedVector2Array = main.sim.wind.duplicate()
	button(screen(Vector2(-5, 0)), true)
	move(screen(Vector2(3, -1)))
	main.wind_input.flush()
	check(main.sim.wind == before, "Preview does not directly push weather")
	check(main.wind_input.source_tier == 1, "Every new band starts at medium power")
	var tip: Vector2 = main.weather_view.camera.unproject_position(main.wind_input.brush_point)
	wheel(tip, true)
	wheel(tip, true)
	check(main.wind_input.source_tier == 2, "Scroll up selects strong and clamps without wrapping")
	await RenderingServer.frame_post_draw
	check(main.hud.strength_meter_rect.has_area() and root.get_visible_rect().encloses(main.hud.strength_meter_rect) and not main.hud.blocks_wind(main.hud.strength_meter_rect.get_center()), "Endpoint meter fits and does not block wind")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/wind-band-preview.png")
	wheel(tip, false)
	wheel(tip, false)
	wheel(tip, false)
	check(main.wind_input.source_tier == 0, "Scroll down selects weak and clamps without wrapping")
	button(tip, false)
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].strength == 0.0 and main.sim.wind_sources[0].position.distance_to(main.sim.wind_sources[0].end) > 0.8, "Release stores endpoints and wheel power")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/wind-band-active.png")
	main.sim.remove_wind_source(main.sim.wind_sources[0].id)
	main.wind_input.cancel()
	button(screen(Vector2(-5, 0)), true)
	move(screen(Vector2(-2, 0)))
	move(screen(Vector2(-5, 0)))
	button(screen(Vector2(-5, 0)), false)
	check(main.sim.wind_sources.is_empty(), "Returning to the origin rejects a zero-length band despite traveled path")
	await place(Vector2(-5, 0), Vector2(-4, 0))
	await place(Vector2(4, -1), Vector2(3, -1))
	check(main.sim.wind_sources.size() == 2, "Actual releases create two sources")
	check(main.sim.wind_sources[0].strength == 0.5 and main.sim.wind_sources[1].strength == 0.5, "New placements reset to medium independent of earlier wheel selection and drag timing")
	await place(Vector2(-4, 2), Vector2(-3, 2))
	check(main.sim.wind_sources.size() == 2 and main.wind_input.message == "先撤掉一个风源", "Third source refused with feedback")
	var source_id: int = main.sim.wind_sources[0].id
	await held_tap(main.hud.source_remove[0])
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].id != source_id, "Actual remove button uses stable source ID")
	await place(Vector2(-5, 0), Vector2(-4, 0))
	var expired_id: int = main.sim.wind_sources[0].id
	var surviving_id: int = main.sim.wind_sources[1].id
	main.sim.remove_wind_source(expired_id)
	await tap(main.hud.source_remove[0])
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].id == surviving_id, "Stale removal card cannot remove another source after expiry")
	await place(Vector2(-5, 0), Vector2(-4, 0))
	var clicked_id: int = main.sim.wind_sources[0].id
	var keep_id: int = main.sim.wind_sources[1].id
	var close_point: Vector2 = main.hud.source_remove[0].get_global_rect().get_center()
	button(close_point, true)
	main.sim.wind_sources[0].remaining = 0.01
	await create_timer(0.12).timeout
	button(close_point, false)
	await RenderingServer.frame_post_draw
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].id == keep_id and main.sim.wind_sources[0].id != clicked_id, "Expiry during a held close click does not remove the replacement row")
	await held_tap(main.hud.source_remove[0])
	check(main.sim.wind_sources.is_empty() and not main.hud.source_remove[0].visible, "Held click removes the last band and hides its row")
	main.guide.cold_hint_left = 12.0
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	await held_tap(main.hud.dismiss_hint)
	check(main.guide.cold_hint_left == 0.0 and not main.hud.dismiss_hint.visible, "Cold hint dismiss also survives redraws during a normal click")
	await place(Vector2(-5, 0), Vector2(-4, 0))
	main.paused = true
	main.wind_input.cancel()
	var remaining: float = main.sim.wind_sources[0].remaining
	var time: float = main.weather_view.elapsed
	await create_timer(0.15).timeout
	check(main.sim.wind_sources[0].remaining == remaining and main.weather_view.elapsed == time, "Pause freezes life and animation")
	if "--capture" in OS.get_cmdline_user_args():
		main.wind_input.message_until = 0
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/wind-tools-paused.png")
	main.paused = false
	await process_frame
	main.restart(false)
	check(main.wind_input.tool == "source" and main.sim.wind_sources.is_empty(), "Retry preserves tool and clears sources")
	await RenderingServer.frame_post_draw
	check(not main.hud.strength_meter_rect.has_area(), "Canceled or released gestures hide the power meter")
	await place(Vector2(-5, 0), Vector2(-4, 0))
	await create_timer(0.3).timeout
	check(main.weather_view.visible_arrows > 0 and main.weather_view.visible_arrows <= 32, "Real source movement gets bounded arrows")
	await tap(main.hud.arrows_button)
	await RenderingServer.frame_post_draw
	check(not main.weather_view.arrows_enabled and main.weather_view.visible_arrows == 0 and main.sim.wind_sources.size() == 1, "Arrow toggle only changes display")
	await tap(main.hud.arrows_button)
	button(screen(Vector2(4, 0)), true)
	move(main.hud.wind_toolbar_rect.get_center())
	button(main.hud.wind_toolbar_rect.get_center(), false)
	check(main.sim.wind_sources.size() == 1 and not main.wind_input.dragging, "Entering UI cancels pending source")
	button(screen(Vector2(4, 0)), true)
	move(Vector2(-20, 30))
	button(Vector2(-20, 30), false)
	check(main.sim.wind_sources.size() == 1 and not main.wind_input.dragging, "Leaving the viewport cancels placement without creating a source")
	button(screen(Vector2(4, 0)), true)
	main.wind_input._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not main.wind_input.dragging and main.sim.wind_sources.size() == 1, "Focus loss cancels gesture, not existing sources")
	var saved_path: String = main.settings_path
	var config: WRWeatherSettings = main.sim.settings.duplicate(true)
	config.hold_gain = 3.0
	config.source_lifetime = 12.0
	ResourceSaver.save(config, "res://.godot/wind-live-test.tres")
	main.settings_path = "res://.godot/wind-live-test.tres"
	var water_before: PackedFloat32Array = main.sim.cloud.duplicate()
	var life_before: float = main.sim.wind_sources[0].remaining
	check(main.reload_tuning(), "Saved wind configuration reloads")
	check(main.sim.settings.hold_gain == 3.0 and main.sim.cloud == water_before and main.sim.wind_sources[0].remaining == life_before and main.sim.settings.source_lifetime == 30.0, "F6 preserves weather and current lifetime while applying gain")
	config.source_fade_seconds = 20.0
	ResourceSaver.save(config, "res://.godot/wind-live-test.tres")
	check(not main.reload_tuning() and main.sim.settings.hold_gain == 3.0, "Bad source field retains valid configuration")
	config.source_fade_seconds = 2.0
	ResourceSaver.save(config, "res://.godot/wind-live-test.tres")
	main.restart(false)
	check(main.sim.settings.source_lifetime == 12.0 and main.sim.wind_sources.is_empty(), "Retry applies saved lifetime and clears emitters")
	main.settings_path = saved_path
	main.switch_mode("lesson")
	check(main.wind_input.tool == "brush" and main.sim.wind_sources.is_empty(), "Mode switch restores brush")
	await RenderingServer.frame_post_draw
	print("WIND TOOLS SCENE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
