extends "res://tests/replay_star_viewport.gd"
## Isolated input/lifecycle fixtures. Normal-start transport is a separate replay.
var checks := 0
var preview_captured := false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	button(point, true)
	await create_timer(0.12).timeout
	button(point, false)
	await process_frame
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	while main.transition_active(): await process_frame
func photograph(name: String) -> void:
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/vortex-" + name + ".png")
func mouse(point: Vector2, pressed: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = which
	event.pressed = pressed
	root.push_input(event, true)
func wheel(point: Vector2, upward: bool) -> void:
	mouse(point, true, MOUSE_BUTTON_WHEEL_UP if upward else MOUSE_BUTTON_WHEEL_DOWN)
func place(tier: int = 1, which: MouseButton = MOUSE_BUTTON_LEFT, radius: float = 1.5, release: bool = true, duration: float = 0.2) -> void:
	var center := Vector2(5, 2)
	var camera: Camera3D = main.weather_view.camera
	var height: float = main.sim.terrain.height(center) + 0.3
	var at := camera.unproject_position(Vector3(center.x, height, center.y))
	mouse(at, true, which)
	check(main.wind_input.dragging, "Actual button press starts a range preview")
	if not main.wind_input.dragging: return
	height = main.wind_input.reference_height
	if tier != 1: wheel(at, tier > 1)
	var started := Time.get_ticks_usec()
	while true:
		var fraction := minf(1, (Time.get_ticks_usec() - started) / 1000000.0 / duration)
		var p := center + Vector2.RIGHT * radius * fraction
		var motion := InputEventMouseMotion.new()
		motion.position = camera.unproject_position(Vector3(p.x, height, p.y))
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		root.push_input(motion, true)
		main.hud.queue_redraw()
		if fraction >= 1:
			main.wind_input.flush()
			check(main.sim.wind_sources.is_empty() and Array(main.sim.wind).all(func(w): return w == Vector2.ZERO), "Preview does not apply ordinary strokes or source force")
			if tier == 1 and radius == 1.5 and not preview_captured:
				await photograph("preview")
				preview_captured = true
			if release: mouse(motion.position, false, which)
			break
		await process_frame
	await process_frame
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	await tap(main.hud.vortex_button)
	check(main.wind_input.tool == "vortex", "Native tool button selects vortex")
	for tier in [0, 1, 2]:
		main.restart(false)
		await process_frame
		var which: MouseButton = MOUSE_BUTTON_RIGHT if tier == 1 else MOUSE_BUTTON_LEFT
		await place(tier, which, 1.5, true, 0.6 if tier == 0 else 0.15)
		check(main.sim.wind_sources.size() == 1, "Range drag releases exactly one source")
		if main.sim.wind_sources.is_empty(): quit(1); return
		var source: Dictionary = main.sim.wind_sources[0]
		check(source.kind == "vortex" and source.tier == tier, "Wheel selects a fixed tier independent of dragging speed")
		check(source.spin == (1 if which == MOUSE_BUTTON_LEFT else -1), "Left is clockwise and right is counterclockwise")
		check(source.position.distance_to(Vector2(5, 2)) < 0.04 and absf(source.radius - 1.5) < 0.04, "Actual projection keeps world center and radius")
		main.sim.step(0.8)
		main.weather_view.update_weather(0.8, true)
		main.hud.queue_redraw()
		await process_frame
		check(main.weather_view.visible_source_lines > 0 and main.weather_view.visible_wind_lines <= 48, "Vortex emits actual white wind lines within shared budget")
		if tier == 1: await photograph("active")
		wheel(main.weather_view.camera.unproject_position(Vector3(5, 0.3, 2)), false)
		check(source.tier == tier, "Wheel after release does not retune an existing source")
		if tier != 2:
			await tap(main.hud.source_remove[0])
			check(main.sim.wind_sources.is_empty(), "Held native close button removes vortex")
	var source: Dictionary = main.sim.wind_sources[0]
	var life: float = source.remaining
	var before: PackedByteArray = main.sim.humidity.to_byte_array()
	var config: WRWeatherSettings = main.sim.settings.duplicate(true)
	config.vortex_core_fraction = 0.4
	config.vortex_inward_acceleration = Vector3(0.8, 1.6, 3.2)
	ResourceSaver.save(config, "res://.godot/vortex-settings.tres")
	main.settings_path = "res://.godot/vortex-settings.tres"
	check(main.reload_tuning() and source.remaining == life and source.tier == 2 and main.sim.humidity.to_byte_array() == before, "F6 keeps source geometry, tier, time and water")
	main.sim.step(Sim.FIXED_STEP)
	check(source.core_fraction == 0.4, "F6 rebuilds geometry weights on next fixed step")
	var band: Dictionary = main.sim.add_wind_source(Vector2(-6, 1), Vector2.RIGHT, 0.5, Vector2(-3, 1))
	check(band.ok and not main.sim.add_vortex(Vector2(3, 3), 2, 1, 1).ok, "Mixed tools share source cap in actual scene")
	main.hud.queue_redraw()
	await process_frame
	var close_at: Vector2 = main.hud.source_remove[0].get_global_rect().get_center()
	button(close_at, true)
	source.remaining = 0.05
	main.sim.step(0.1)
	main.hud.queue_redraw()
	await create_timer(0.12).timeout
	button(close_at, false)
	await process_frame
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].id == band.id, "Expired held row cannot close the next source")
	main.sim.add_vortex(Vector2(5, 2), 1.5, 1, 1)
	main.set_process(true)
	await key(KEY_SPACE)
	await RenderingServer.frame_post_draw
	var paused_life: float = main.sim.wind_sources[1].remaining
	var clock: float = main.weather_view.elapsed
	await create_timer(0.25).timeout
	check(main.paused and main.sim.wind_sources[1].remaining == paused_life and main.weather_view.elapsed == clock, "Actual pause freezes sources and wind animation")
	await photograph("paused")
	await key(KEY_SPACE)
	await process_frame
	main.restart(false)
	check(main.wind_input.tool == "vortex" and main.sim.wind_sources.is_empty(), "Retry retains tool and clears mixed sources")
	main.set_process(false)
	var camera: Camera3D = main.weather_view.camera
	var at := camera.unproject_position(Vector3(5, 0.3, 2))
	mouse(at, true, MOUSE_BUTTON_RIGHT)
	mouse(at, false, MOUSE_BUTTON_RIGHT)
	check(main.sim.wind_sources.is_empty(), "Right click without dragging creates no wind")
	await place(1, MOUSE_BUTTON_LEFT, 0.5)
	check(main.sim.wind_sources.is_empty(), "Too-small radius is refused without resizing")
	await place(1, MOUSE_BUTTON_RIGHT, 1.5, false)
	var end := camera.unproject_position(Vector3(6.5, main.wind_input.reference_height, 2))
	mouse(end, true, MOUSE_BUTTON_LEFT)
	mouse(end, false, MOUSE_BUTTON_LEFT)
	check(main.wind_input.dragging and main.wind_input.gesture_button == MOUSE_BUTTON_RIGHT and main.wind_input.vortex_spin == -1 and main.sim.wind_sources.is_empty(), "Opposite button cannot change or release the owner gesture")
	wheel(end, true)
	wheel(end, true)
	check(main.wind_input.source_tier == 2, "Preview wheel clamps to strong tier")
	mouse(end, false, MOUSE_BUTTON_RIGHT)
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].spin == -1 and main.sim.wind_sources[0].tier == 2, "Owner release keeps direction and chosen tier")
	main.restart(false)
	await place(1, MOUSE_BUTTON_RIGHT, 1.5, false)
	mouse(main.hud.menu_button.get_global_rect().get_center(), false, MOUSE_BUTTON_RIGHT)
	check(not main.wind_input.dragging and main.sim.wind_sources.is_empty(), "Right release over UI cancels placement")
	await place(1, MOUSE_BUTTON_RIGHT, 1.5, false)
	main.wind_input._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not main.wind_input.dragging and main.sim.wind_sources.is_empty(), "Focus loss cancels a right-button preview")
	await place(1, MOUSE_BUTTON_RIGHT, 1.5, false)
	await key(KEY_SPACE)
	check(main.paused and not main.wind_input.dragging and main.sim.wind_sources.is_empty(), "Pause cancels a right-button preview")
	mouse(at, true, MOUSE_BUTTON_RIGHT)
	check(not main.wind_input.dragging and main.sim.wind_sources.is_empty(), "Pause blocks another press immediately, before the next main frame")
	mouse(at, false, MOUSE_BUTTON_RIGHT)
	await key(KEY_SPACE)
	await place(1, MOUSE_BUTTON_LEFT, 1.5, false)
	var limit_config: WRWeatherSettings = main.sim.settings.duplicate(true)
	limit_config.vortex_radius_limits = Vector2(0.75, 1.0)
	ResourceSaver.save(limit_config, "res://.godot/placement-limits.tres")
	main.settings_path = "res://.godot/placement-limits.tres"
	check(main.reload_tuning() and main.wind_input.vortex_preview().ok, "F6 does not change the active preview radius limits")
	mouse(main.weather_view.camera.unproject_position(Vector3(6.5, main.wind_input.reference_height, 2)), false)
	check(main.sim.wind_sources.size() == 1 and absf(main.sim.wind_sources[0].radius - 1.5) < 0.04, "Active preview releases its original picked range after F6: " + str(main.sim.wind_sources.size()))
	main.restart(false)
	await place(1, MOUSE_BUTTON_LEFT, 1.5)
	check(main.sim.wind_sources.is_empty(), "Next placement uses the newly saved radius limits")
	limit_config.vortex_radius_limits = Vector2(0.75, 5.0)
	ResourceSaver.save(limit_config, "res://.godot/placement-limits.tres")
	main.reload_tuning()
	await place(1, MOUSE_BUTTON_RIGHT, 1.5, false)
	var outside := InputEventMouseMotion.new()
	outside.position = Vector2(-1,20)
	root.push_input(outside,true)
	check(not main.wind_input.dragging and main.sim.wind_sources.is_empty(), "Viewport exit cancels a right-button placement")
	main.wind_input.select_tool("brush")
	mouse(at,true,MOUSE_BUTTON_RIGHT)
	mouse(at,false,MOUSE_BUTTON_RIGHT)
	check(not main.wind_input.dragging and main.sim.wind_sources.is_empty(), "Right button remains inactive in ordinary brush mode")
	main.wind_input.select_tool("vortex")
	main.set_process(true)
	var single: WRMapDefinition = load("res://configs/maps/needs_lab.tres").duplicate(true)
	single.plots.resize(1)
	single.plot_needs.resize(1)
	main.custom_map = single
	main.switch_mode("free")
	main.sim.plot_waters[0] = 100
	main.sim.update_goal(2.1)
	await create_timer(3.7).timeout
	check(main.sim.result_stars == 3 and main.sim.result_saved_count == 1 and main.hud.result_details.size() == 1 and not main.wind_input.enabled, "Actual single-field perfect result displays three stars and one saved field")
	await photograph("rating-one")
	print("VORTEX SCENE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
