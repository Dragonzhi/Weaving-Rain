extends Node3D
const Simulation = preload("res://scripts/weather_simulation.gd")
const WeatherView = preload("res://scripts/weather_view.gd")
const WindInput = preload("res://scripts/wind_input.gd")
const HUD = preload("res://scripts/game_hud.gd")
const Onboarding = preload("res://scripts/onboarding.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const ConfigLoader = preload("res://scripts/config_loader.gd")
const LevelProgress = preload("res://scripts/level_progress.gd")
const SIMULATION_BUDGET_US := 8000
@export var weather_settings: WRWeatherSettings = WRWeatherSettings.new()
var settings_path := "res://configs/weather.tres"
var custom_map: WRMapDefinition
var custom_map_path := ""
var pending_settings: WRWeatherSettings
var tuning_message := ""
var tuning_message_until := 0
var development := false
var sim: Simulation
var weather_view: Node3D
var wind_input: Node
var hud: Control
var paused := false
var accumulator := 0.0
var guide := Onboarding.new()
var play_mode := "lesson"
var preferences_path := "user://onboarding.cfg"
var progress_path := "user://level_stars.cfg"
var persist_progress := true
var progress := LevelProgress.new()
var result_recorded := false
var free_layout := "standard"
var frame_simulation_ms := 0.0
var frame_view_ms := 0.0
var frame_pick_ms := 0.0
var frame_steps := 0
var frame_input_ms := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if persist_progress and not "--fresh-guide" in args: progress.read(progress_path)
	if not progress.migration_message.is_empty(): _tuning_feedback(progress.migration_message)
	if weather_settings == null: weather_settings = WRWeatherSettings.new()
	if not weather_settings.resource_path.is_empty(): settings_path = weather_settings.resource_path
	development = OS.has_feature("editor") or "--dev" in args
	play_mode = initial_mode(args)
	for arg in args:
		if arg.begins_with("--layout="):
			free_layout = Layouts.get_layout(arg.trim_prefix("--layout=")).id
			play_mode = "free"
		if arg.begins_with("--settings="): settings_path = arg.trim_prefix("--settings=")
		if arg.begins_with("--map="):
			custom_map_path = arg.trim_prefix("--map=")
			play_mode = "free"
	var loaded := ConfigLoader.settings(settings_path)
	if loaded.errors.is_empty(): weather_settings = loaded.resource
	else:
		weather_settings = WRWeatherSettings.new()
		_tuning_feedback("使用默认配置：" + "；".join(loaded.errors))
	if not custom_map_path.is_empty():
		var loaded_map := ConfigLoader.map(custom_map_path, weather_settings.plot_half)
		if loaded_map.errors.is_empty(): custom_map = loaded_map.resource
		else: _tuning_feedback("；".join(loaded_map.errors))
	elif play_mode == "free":
		var loaded_map := ConfigLoader.map("res://configs/maps/" + free_layout + ".tres", weather_settings.plot_half)
		if loaded_map.errors.is_empty(): custom_map = loaded_map.resource
		else:
			_tuning_feedback("使用标准布局：" + "；".join(loaded_map.errors))
			free_layout = "standard"
	sim = _new_simulation()
	guide.reset(play_mode == "lesson")
	weather_view = WeatherView.new()
	add_child(weather_view)
	weather_view.setup(sim)
	if not weather_view.style_errors.is_empty(): _tuning_feedback("显示配置保留："+"；".join(weather_view.style_errors))
	wind_input = WindInput.new()
	add_child(wind_input)
	wind_input.setup(sim, weather_view.camera)
	wind_input.stroke_applied.connect(func(a, b, height): weather_view.add_wind_stroke(a, b, height))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HUD.new()
	canvas.add_child(hud)
	hud.setup(sim, weather_view, wind_input)
	hud.reset_feedback()
	hud.guide = guide
	hud.play_mode = play_mode
	wind_input.hud = hud
	hud.restart_requested.connect(func(): restart(false))
	hud.sandbox_requested.connect(func(): restart(true))
	hud.cold_lab_requested.connect(cold_lab)
	hud.free_play_requested.connect(enter_free_play)
	hud.lesson_requested.connect(func(): switch_mode("lesson"))
	hud.layout_requested.connect(select_layout)
	hud.finish_requested.connect(finish_level)
	hud.next_requested.connect(next_level)
	hud.levels_requested.connect(func(): select_layout(Layouts.LEVELS[0]))
	hud.best_stars = progress.best
	hud.refresh_layouts()
	for arg in args:
		if arg == "--cloud-lab":
			restart(true)
		elif arg == "--cold-lab":
			cold_lab()
		elif arg.begins_with("--capture="):
			_capture(arg.trim_prefix("--capture="))

func initial_mode(args: PackedStringArray) -> String:
	var mode := "lesson"
	var preferences := ConfigFile.new()
	if not "--fresh-guide" in args and preferences.load(preferences_path) == OK:
		if preferences.get_value("onboarding", "visited_free_play", false):
			mode = "free"
	if "--free-play" in args:
		mode = "free"
	if "--single-plot" in args:
		mode = "baseline"
	return mode

func restart(test_cloud: bool) -> void:
	var selected_tool: String = wind_input.tool
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	var loaded := ConfigLoader.settings(settings_path)
	if loaded.errors.is_empty():
		var map_path := custom_map_path if not custom_map_path.is_empty() else "res://configs/maps/" + (free_layout if play_mode == "free" else "standard") + ".tres"
		var loaded_map := ConfigLoader.map(map_path, loaded.resource.plot_half)
		if loaded_map.errors.is_empty():
			pending_settings = loaded.resource
			if play_mode == "free": custom_map = loaded_map.resource
		else: _tuning_feedback("重试保留原配置：" + "；".join(loaded_map.errors))
	else: _tuning_feedback("重试保留原配置：" + "；".join(loaded.errors))
	switch_mode(play_mode)
	wind_input.select_tool(selected_tool)
	sim.reset(test_cloud)
	guide.reset(play_mode == "lesson")
	weather_view.reset_tracers()

func _new_simulation() -> RefCounted:
	return Simulation.new(weather_settings, play_mode == "free", play_mode == "lesson", free_layout, custom_map)

func select_layout(id: String) -> void:
	if custom_map != null and custom_map.id == id and not id in Layouts.get_ids():
		switch_mode("free")
		return
	var definition := Layouts.get_definition(id)
	var loaded := ConfigLoader.map(definition.resource_path, weather_settings.plot_half)
	if not loaded.errors.is_empty():
		_tuning_feedback("地图未切换：" + "；".join(loaded.errors))
		return
	custom_map = loaded.resource
	custom_map_path = definition.resource_path if not id in Layouts.IDS else ""
	free_layout = definition.id
	switch_mode("free")

func switch_mode(mode: String) -> void:
	_apply_pending_restart()
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	play_mode = mode
	sim = _new_simulation()
	result_recorded = false
	guide.reset(mode == "lesson")
	var selected_hints: bool = weather_view.hints_enabled
	var selected_style_path: String = weather_view.style_path
	remove_child(weather_view)
	weather_view.queue_free()
	weather_view = WeatherView.new()
	add_child(weather_view)
	weather_view.style_path = selected_style_path
	weather_view.setup(sim)
	if not weather_view.style_errors.is_empty(): _tuning_feedback("显示配置保留："+"；".join(weather_view.style_errors))
	weather_view.hints_enabled = selected_hints
	wind_input.setup(sim, weather_view.camera)
	wind_input.select_tool("brush")
	# Resolve the current view at emission time, including after mode changes.
	wind_input.enabled = true
	hud.sim = sim
	hud.reset_feedback()
	hud.view = weather_view
	hud.play_mode = mode
	hud.refresh_layouts()
	hud.queue_redraw()

func finish_level() -> void:
	wind_input.cancel()
	if sim.finish():
		wind_input.enabled = false
		record_result()

func record_result() -> void:
	if result_recorded or not sim.star_level or sim.sandbox or sim.outcome == "playing": return
	result_recorded = true
	var saved := progress.record(sim.layout_id, sim.result_stars, progress_path, persist_progress and not "--fresh-guide" in OS.get_cmdline_user_args())
	hud.best_stars = progress.best
	hud.refresh_layouts()
	hud.queue_redraw()
	if saved != OK: _tuning_feedback("本局结果有效，保存风纹纪录失败：" + error_string(saved))

func next_level() -> void:
	if not sim.star_level or sim.sandbox or sim.outcome != "success": return
	var index := Layouts.LEVELS.find(sim.layout_id)
	select_layout(Layouts.LEVELS[index + 1] if index >= 0 and index + 1 < Layouts.LEVELS.size() else Layouts.LEVELS[0])

func enter_free_play() -> void:
	switch_mode("free")
	# Tests and explicit development starts do not modify the player's preference.
	var args := OS.get_cmdline_user_args()
	if "--fresh-guide" in args or "--single-plot" in args or "--free-play" in args:
		return
	var preferences := ConfigFile.new()
	preferences.set_value("onboarding", "visited_free_play", true)
	var result := preferences.save(preferences_path)
	if result != OK:
		push_warning("Could not save onboarding preference: " + str(result))

func cold_lab() -> void:
	restart(true)
	for i in Simulation.COUNT:
		var p: Vector2 = sim.positions[i]
		sim.cloud[i] = 2.1 * exp(-p.distance_squared_to(sim.plot_centers[0]) / 1.7)
		sim.rain[i] = sim.cloud[i]
		sim.humidity[i] += 2.2 * exp(-p.distance_squared_to(Vector2(5.6, 1.8)) / 3.0)
	sim.initial_water = sim.water_total()
	sim.refresh_display()

func _process(delta: float) -> void:
	record_result()
	var moving: bool = not paused and sim.outcome == "playing"
	var start := Time.get_ticks_usec()
	if moving:
		wind_input.flush()
		wind_input.update_hover()
		wind_input.update_held()
	frame_input_ms = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	frame_steps = 0
	if moving:
		# Limit catch-up after debugger stalls without skipping simulation steps.
		accumulator += minf(delta, 0.1)
		var last_step_us := 0
		while accumulator >= Simulation.FIXED_STEP:
			# Keep pending fixed steps after a stall, instead of creating another long frame.
			# Always advance at least once; further steps must fit the measured CPU budget.
			if frame_steps > 0 and Time.get_ticks_usec() - start + last_step_us > SIMULATION_BUDGET_US:
				break
			var step_start := Time.get_ticks_usec()
			sim.step(Simulation.FIXED_STEP)
			hud.update_feedback(Simulation.FIXED_STEP)
			guide.update(sim, Simulation.FIXED_STEP)
			last_step_us = Time.get_ticks_usec() - step_start
			accumulator -= Simulation.FIXED_STEP
			frame_steps += 1
			if sim.outcome != "playing": break
	if moving and sim.outcome != "playing":
		moving = false
		wind_input.cancel()
		record_result()
	frame_simulation_ms = (Time.get_ticks_usec() - start) / 1000.0
	hud.simulation_ms = lerpf(hud.simulation_ms, frame_simulation_ms, 0.05)
	start = Time.get_ticks_usec()
	if wind_input.dragging:
		weather_view.note_interaction(Vector2(wind_input.brush_point.x, wind_input.brush_point.z))
	weather_view.update_weather(minf(delta, 0.1), moving, wind_input)
	frame_view_ms = (Time.get_ticks_usec() - start) / 1000.0
	wind_input.enabled = moving
	start = Time.get_ticks_usec()
	wind_input.update_hover()
	frame_pick_ms = (Time.get_ticks_usec() - start) / 1000.0
	hud.paused = paused
	hud.tuning_message = tuning_message if Time.get_ticks_msec() < tuning_message_until else ""
	hud.frame_ms = lerpf(hud.frame_ms, delta * 1000.0, 0.05)
	hud.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
			restart(false)
		KEY_F2:
			restart(true)
		KEY_F3:
			hud.debug_visible = not hud.debug_visible
		KEY_F4:
			cold_lab()
		KEY_F6:
			if development: reload_tuning()
		KEY_SPACE:
			paused = not paused
			wind_input.cancel()
			wind_input.enabled = not paused and sim.outcome == "playing"

func _capture(path: String) -> void:
	# Development-only render capture; never changes the normal starting state.
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " result=", result, " layout=", sim.layout_id, " targets=", sim.plot_centers.size(), " tropical=", sim.tropical != null, " simulation_ms=", hud.simulation_ms, " frame_ms=", hud.frame_ms)
	get_tree().quit(0 if result == OK else 1)

func _tuning_feedback(message: String) -> void:
	tuning_message = message
	tuning_message_until = Time.get_ticks_msec() + 10000
	print("TUNING ", message)

func reload_tuning() -> bool:
	var loaded := ConfigLoader.settings(settings_path)
	if not loaded.errors.is_empty():
		_tuning_feedback("配置未应用：" + "；".join(loaded.errors))
		return false
	var candidate: WRWeatherSettings = loaded.resource
	var definition := custom_map if custom_map != null else Layouts.get_definition(free_layout if play_mode == "free" else "standard")
	var map_errors := definition.validation_errors(candidate.plot_half)
	if not map_errors.is_empty():
		_tuning_feedback("配置未应用：" + "；".join(map_errors))
		return false
	# Never mutate the shared on-disk resource or deferred fields of the live simulation.
	sim.settings.apply_live(candidate)
	for i in Simulation.COUNT:
		sim.wind[i] = sim.wind[i].limit_length(candidate.max_wind)
		if sim.tropical != null: sim.cloud_wind[i] = sim.cloud_wind[i].limit_length(candidate.max_wind)
	sim._update_cold_flow()
	sim.refresh_display()
	pending_settings = candidate
	_tuning_feedback("已应用：拨风、风带、漩涡力度与云响应；范围限制下一笔生效，寿命／数量及天气规则重试生效")
	return true

func _apply_pending_restart() -> void:
	if pending_settings != null:
		weather_settings = pending_settings
		pending_settings = null
	if not custom_map_path.is_empty():
		var loaded := ConfigLoader.map(custom_map_path, weather_settings.plot_half)
		if loaded.errors.is_empty(): custom_map = loaded.resource
		else: _tuning_feedback("地图未应用：" + "；".join(loaded.errors))
