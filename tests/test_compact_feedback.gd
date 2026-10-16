extends SceneTree
## Development fixture; injected velocity is only used to isolate display.
var main: Node3D
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func tap(control: Control) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = control.get_global_rect().get_center()
		e.pressed = pressed
		root.push_input(e, true)
	await RenderingServer.frame_post_draw
	while main.transition_active(): await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	main.guide.cold_hint_seen = true
	main.guide.cold_hint_left = 0
	var hud: Control = main.hud
	var view: Node3D = main.weather_view
	check(not hud.menu_open and not hud.retry.visible and not hud.lesson_button.visible, "Menu actions are collapsed by default")
	check(not hud.blocks_wind(Vector2(80, hud.size.y - 65)), "Old large water-card footprint is released")
	check(not hud.blocks_wind(hud.timer_rect.get_center()) and not hud.blocks_wind(hud.reserve_rect.get_center()), "Timer and reserve are pass-through information")
	check(hud.plot_label_rects.size() == 3, "Each plot gets a world-adjacent water bar")
	var labels_clear := true
	for rect in hud.plot_label_rects:
		labels_clear = labels_clear and not hud.blocks_wind(rect.get_center()) and root.get_visible_rect().encloses(rect) and not rect.intersects(hud.wind_toolbar_rect)
	check(labels_clear, "Plot labels fit the viewport, avoid toolbar and allow wind")
	var reclaimed: Vector2 = hud.plot_label_rects[0].get_center()
	var press := InputEventMouseButton.new()
	press.position = reclaimed
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	check(main.wind_input.dragging, "Actual press through plot information starts a weather gesture")
	main.wind_input.cancel()
	await tap(hud.menu_button)
	check(hud.menu_open and hud.retry.visible and hud.blocks_wind(hud.menu_rect.get_center()), "Open menu blocks weather and exposes retry")
	await tap(hud.menu_button)
	check(not hud.menu_open and not hud.blocks_wind(hud.menu_rect.get_center()), "Collapsed menu releases its footprint")
	main.sim.add_wind_source(Vector2(-5, 0), Vector2.RIGHT, 1.0)
	var water: float = main.sim.water_total()
	for i in 30: main.sim.step(1.0 / 60.0)
	view.update_weather(0.4, true)
	check(view.visible_source_lines > 0, "Persistent source alone produces the same white wind ribbons")
	check(absf(main.sim.water_total() - water) < 0.01, "Rendering source ribbons does not create water")
	var buffer: PackedVector3Array = view.line_vertices.duplicate()
	var emission: Dictionary = view.source_emission.duplicate()
	var clock: float = view.elapsed
	view.update_weather(0.8, false)
	check(view.elapsed == clock and view.line_vertices == buffer and view.source_emission == emission, "Pause freezes source emission, positions and ribbon lifetime")
	view.hints_enabled = false
	view.update_weather(0.1, true)
	check(view.visible_arrows == 0 and view.visible_source_lines > 0, "Arrow toggle preserves actual wind ribbons")
	view.hints_enabled = true
	var source_id: int = main.sim.wind_sources[0].id
	main.sim.remove_wind_source(source_id)
	var before: int = view.source_trace_serial
	view.update_weather(0.1, true)
	check(view.source_trace_serial == before and view.wind_traces.size() > 0, "Removal stops emission but retains drifting ribbons")
	view.update_weather(2.5, true)
	check(view.visible_source_lines == 0, "Old ribbons fade after source removal")
	main.sim.add_wind_source(Vector2(-5, 0), Vector2.RIGHT, 1.0)
	view.reset_tracers()
	view.update_weather(0.5, true)
	var full_emission: int = view.source_trace_serial
	view.reset_tracers()
	main.sim.wind_sources[0].remaining = 0.1
	view.update_weather(0.5, true)
	check(view.source_trace_serial < full_emission, "End-of-life source emits fewer ribbons")
	main.sim.wind_sources[0].remaining = 8.0
	for i in 100: view.update_weather(0.1, true)
	check(view.wind_traces.size() <= 48, "All source and mouse wind ribbons share a fixed budget")
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.wind.fill(Vector2(1.0, 0))
	main.sim.low_wind.fill(Vector2(1.0, 0))
	main.sim.refresh_display()
	view.update_weather(0.2, true)
	check(view.visible_arrows > 0 and view.visible_arrows <= 32, "Wet movement arrows remain bounded")
	var horizontal_motion := 0.0
	for index in view.visible_arrows:
		var custom: Color = view.arrow_instances.get_instance_custom_data(index)
		horizontal_motion = maxf(horizontal_motion, Vector2(custom.r, custom.g).length())
	check(horizontal_motion > 0.5, "Horizontal arrows traverse a visible distance instead of a short fixed marker")
	var arrow_buffer: PackedFloat32Array = view.arrow_instances.buffer.duplicate()
	clock = view.elapsed
	view.update_weather(1, false)
	check(view.arrow_instances.buffer == arrow_buffer and view.arrow_material.get_shader_parameter("visual_time") == clock, "Paused moving arrows retain geometry and animation phase")
	view.elapsed = hud.tool_hint_until + 1
	hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(hud.wind_toolbar_rect.size.y <= 69, "Toolbar allocates only controls and existing sources")
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("res://.godot/compact-wind-ui.png")
		DirAccess.make_dir_recursive_absolute("res://.godot/flow-motion")
		for frame in 36:
			view.update_weather(1.0 / 24.0, true)
			hud.queue_redraw()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/flow-motion/%03d.png" % frame)
	main.sim.wind_sources.clear()
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.cold.fill(0)
	main.sim.wind.fill(Vector2.ZERO)
	main.sim.low_wind.fill(Vector2.ZERO)
	main.sim.refresh_display()
	view.reset_tracers()
	view.update_weather(0.5, true)
	check(view.visible_wind_lines == 0, "Still dry air does not invent white wind")
	main.sim.wind.fill(Vector2(0.8, 0))
	main.sim.low_wind.fill(Vector2(0.8, 0))
	main.sim.refresh_display()
	view.update_weather(0.5, true)
	check(view.visible_wind_lines > 0 and view.visible_source_lines == 0, "Dry residual wind gets white lines without mouse or source")
	main.sim.wind.fill(Vector2.ZERO)
	main.sim.low_wind.fill(Vector2(0, 0.8))
	main.sim.refresh_display()
	view.reset_tracers()
	view.update_weather(0.5, true)
	var low_only := true
	for trace in view.wind_traces: low_only = low_only and trace.low
	check(view.visible_wind_lines > 0 and low_only, "Automatic low wind has white lines without inventing upper wind")
	view.hints_enabled = false
	buffer = view.line_vertices.duplicate()
	clock = view.elapsed
	view.update_weather(0.5, false)
	check(view.elapsed == clock and view.line_vertices == buffer, "Field wind lines freeze on pause independently of arrow toggle")
	await tap(hud.menu_button)
	main.restart(false)
	hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(not hud.menu_open and main.weather_view.wind_traces.is_empty(), "Retry closes menu and clears wind display")
	print("COMPACT FEEDBACK: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
