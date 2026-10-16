extends Node3D
const Simulation = preload("res://scripts/weather_simulation.gd")
const WeatherView = preload("res://scripts/weather_view.gd")
const WindInput = preload("res://scripts/wind_input.gd")
const HUD = preload("res://scripts/game_hud.gd")
const Onboarding = preload("res://scripts/onboarding.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const ConfigLoader = preload("res://scripts/config_loader.gd")
const LevelProgress = preload("res://scripts/level_progress.gd")
const WeatherAudio = preload("res://scripts/weather_audio.gd")
const FrontMenu = preload("res://scenes/front_menu.tscn")
const WeatherTransition = preload("res://scripts/weather_transition.gd")
var transition: Control
const SIMULATION_BUDGET_US := 8000
@export var show_front_menu := true
var front_menu: Control
var session_started := false
var front_return_to := "game"
var front_was_paused := false
var game_menu_was_paused := false
@export var weather_settings: WRWeatherSettings = WRWeatherSettings.new()
var settings_path := "res://configs/weather.tres"
var custom_map: WRMapDefinition
var custom_map_path := ""
var lesson_map_path := "res://configs/tutorial.tres"
var lesson_map: WRMapDefinition
var campaign_path := "res://configs/campaign.tres"
var campaign: WRCampaign
var campaign_play := true
var has_free_session := false
var selecting_levels := false
var selection_was_paused := false
var pending_settings: WRWeatherSettings
var tuning_message := ""
var tuning_message_until := 0
var development := false
var sim: Simulation
var weather_view: Node3D
var wind_input: Node
var hud: Control
var weather_audio: Node
var frame_audio_ms := 0.0
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
	var bypass_front := not show_front_menu or direct_start(args)
	if persist_progress and not "--fresh-guide" in args: progress.read(progress_path)
	if not progress.migration_message.is_empty(): _tuning_feedback(progress.migration_message)
	if weather_settings == null: weather_settings = WRWeatherSettings.new()
	if not weather_settings.resource_path.is_empty(): settings_path = weather_settings.resource_path
	development = OS.has_feature("editor") or "--dev" in args
	play_mode = initial_mode(args)
	if "--free-play" in args or "--single-plot" in args or not custom_map_path.is_empty(): campaign_play = false
	for arg in args:
		if arg.begins_with("--layout="):
			free_layout = Layouts.get_layout(arg.trim_prefix("--layout=")).id
			play_mode = "free"
			campaign_play = false
		if arg.begins_with("--settings="): settings_path = arg.trim_prefix("--settings=")
		if arg.begins_with("--map="):
			custom_map_path = arg.trim_prefix("--map=")
			play_mode = "free"
			campaign_play = false
	var loaded := ConfigLoader.settings(settings_path)
	if loaded.errors.is_empty(): weather_settings = loaded.resource
	else:
		weather_settings = WRWeatherSettings.new()
		_tuning_feedback("使用默认配置：" + "；".join(loaded.errors))
	reload_campaign()
	if campaign == null and campaign_play: play_mode = "lesson"
	if play_mode == "free" and campaign_play and campaign != null:
		free_layout = campaign.levels[0].id
		custom_map_path = campaign.levels[0].resource_path
	has_free_session = play_mode == "free"
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
	hud.restart_requested.connect(func(): navigate(func(): restart(false),"cloud"))
	hud.sandbox_requested.connect(func(): restart(true))
	hud.cold_lab_requested.connect(cold_lab)
	hud.free_play_requested.connect(func(): navigate(enter_free_play,"cloud"))
	hud.lesson_requested.connect(func(): navigate(_start_lesson,"cloud"))
	hud.layout_requested.connect(select_layout)
	hud.campaign_layout_requested.connect(func(id): navigate(func(): select_campaign_level(id),"cloud"))
	hud.finish_requested.connect(finish_level)
	hud.next_requested.connect(func(): navigate(next_level,"cloud"))
	hud.levels_requested.connect(func(): navigate(open_level_selection,"cloud"))
	hud.selection_closed.connect(close_level_selection)
	hud.development_requested.connect(func(): open_level_selection(true))
	hud.best_stars = progress.best
	_sync_campaign_hud()
	weather_audio = WeatherAudio.new()
	add_child(weather_audio)
	if "--fresh-guide" in args: weather_audio.preferences_path = ""
	weather_audio.load_preferences()
	_bind_audio()
	wind_input.brush_motion.connect(func(gesture, speed): weather_audio.brush_motion(gesture,speed))
	wind_input.source_created.connect(func(): weather_audio.cue("source"))
	hud.sound_requested.connect(func(sound): weather_audio.cue(sound))
	hud.menu_changed.connect(func(open): navigate(func(): _game_menu_changed(open),"light"))
	hud.front_requested.connect(func(page): navigate(func(): open_front_page(page),"cloud" if page == "home" else "light"))
	hud.audio_changed.connect(func(on, volume):
		var was_enabled: bool = weather_audio.enabled
		weather_audio.set_options(on,volume)
		if on and not was_enabled: weather_audio.cue("click"))
	front_menu = FrontMenu.instantiate()
	canvas.add_child(front_menu)
	front_menu.setup(self)
	hud.use_front_menu = true
	front_menu.action_requested.connect(_front_action)
	front_menu.audio_changed.connect(func(on, volume):
		var was_enabled: bool = weather_audio.enabled
		weather_audio.set_options(on,volume)
		hud.set_audio_options(on,volume)
		if on and not was_enabled: weather_audio.cue("click"))
	var transition_layer := CanvasLayer.new()
	transition_layer.layer = 100
	add_child(transition_layer)
	transition = WeatherTransition.new()
	transition_layer.add_child(transition)
	session_started = true
	if not bypass_front:
		session_started = false
		open_front_page("home")
	for arg in args:
		if arg == "--cloud-lab":
			restart(true)
		elif arg == "--cold-lab":
			cold_lab()
		elif arg.begins_with("--capture="):
			_capture(arg.trim_prefix("--capture="))

func direct_start(args: PackedStringArray) -> bool:
	if not custom_map_path.is_empty(): return true
	for arg in args:
		if arg in ["--skip-menu","--free-play","--single-plot","--cloud-lab","--cold-lab"] or arg.begins_with("--map=") or arg.begins_with("--layout="): return true
	return false

func _game_menu_changed(open: bool) -> void:
	if open:
		game_menu_was_paused = paused
		paused = true
		wind_input.cancel()
		wind_input.enabled = false
	else:
		paused = game_menu_was_paused
		wind_input.enabled = not paused and sim.outcome == "playing" and not front_active()
	hud.paused = paused

func front_active() -> bool:
	return front_menu != null and front_menu.visible

func open_front_page(page: String, from_home := false) -> void:
	var opening_from_game := not front_active()
	if opening_from_game:
		front_was_paused = game_menu_was_paused if hud.menu_open else paused
		front_return_to = "game"
	elif page != "home" and from_home:
		front_return_to = "home"
	if page == "home": front_return_to = "home"
	paused = true
	wind_input.cancel()
	wind_input.enabled = false
	hud.menu_open = false
	hud.front_active = true
	hud.hide()
	weather_view.hide()
	selecting_levels = page == "levels"
	if page == "levels":
		reload_campaign()
		_sync_campaign_hud()
		if opening_from_game: front_menu.selected_id = sim.layout_id
		hud.selection_ids.assign(campaign.ids() if campaign != null else [])
	front_menu.show_page(page)
	if page == "levels" and not tuning_message.is_empty() and Time.get_ticks_msec() < tuning_message_until:
		front_menu.set_error(tuning_message)
	weather_audio.set_paused(true)

func close_front_page() -> void:
	if not front_active(): return
	front_menu.close()
	hud.front_active = false
	hud.show()
	weather_view.show()
	selecting_levels = false
	paused = front_was_paused
	hud.paused = paused
	wind_input.cancel()
	wind_input.enabled = not paused and sim.outcome == "playing"
	weather_audio.set_paused(paused)

func transition_active() -> bool:
	return transition != null and transition.active

func navigate(change: Callable, style := "light") -> void:
	if transition_active(): return
	wind_input.cancel()
	wind_input.enabled = false
	hud.paused = true
	hud.transitioning = true
	weather_audio.set_paused(true)
	await transition.play(style,func():
		change.call()
		transition.fade_target = front_menu.content if front_active() else hud
		wind_input.cancel()
		wind_input.enabled = false
		hud.paused = true
		hud.transitioning = true
		weather_audio.set_paused(true))
	wind_input.cancel()
	wind_input.enabled = not paused and not front_active() and sim.outcome == "playing"
	hud.paused = paused
	hud.transitioning = false
	weather_audio.set_paused(paused)

func _front_action(action: String, id: String) -> void:
	if transition_active(): return
	weather_audio.cue("click")
	if action == "click": return
	if action == "quit":
		get_tree().quit()
		return
	var style := "light"
	if action in ["start","selected","tutorial"]: style = "cloud"
	elif (action == "levels" and front_menu.page == "home") or (action == "back" and front_menu.page == "levels" and front_return_to == "home"): style = "wind"
	elif action == "back" and front_menu.page == "levels": style = "cloud"
	navigate(func(): _apply_front_action(action,id),style)

func _apply_front_action(action: String, _id: String) -> void:
	match action:
		"start":
			if session_started and sim.outcome == "playing":
				front_was_paused = false
				close_front_page()
			elif not session_started:
				if play_mode == "free" and campaign != null: select_campaign_level(campaign.levels[0].id)
				else: _start_lesson()
			elif campaign != null:
				select_campaign_level(campaign.levels[0].id)
			else: _start_lesson()
		"levels", "help", "settings": open_front_page(action,front_menu.page == "home")
		"selected": select_campaign_level(front_menu.selected_id)
		"tutorial": _start_lesson()
		"reload": open_front_page("levels",front_return_to == "home")
		"back":
			if front_return_to == "home": open_front_page("home")
			else: close_front_page()
		"quit": get_tree().quit()

func _start_lesson() -> void:
	var loaded := ConfigLoader.map(lesson_map_path,weather_settings.plot_half)
	if not loaded.errors.is_empty():
		_tuning_feedback("教学未切换："+"；".join(loaded.errors))
		return
	switch_mode("lesson")

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
		var map_path := lesson_map_path if play_mode == "lesson" else (custom_map_path if not custom_map_path.is_empty() else "res://configs/maps/" + (free_layout if play_mode == "free" else "standard") + ".tres")
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
	weather_audio.bind(sim,weather_view.camera)

func _new_simulation() -> RefCounted:
	if play_mode == "lesson":
		var loaded := ConfigLoader.map(lesson_map_path, weather_settings.plot_half)
		if loaded.errors.is_empty():
			lesson_map = loaded.resource
			# Teaching never records a rating or uses a map timer, even if accidentally checked.
			lesson_map.star_level = false
		else: _tuning_feedback("教学地图未应用：" + "；".join(loaded.errors))
		if lesson_map != null:
			return Simulation.new(weather_settings, true, false, lesson_map.id, lesson_map)
	return Simulation.new(weather_settings, play_mode == "free", play_mode == "lesson", free_layout, custom_map)

func select_layout(id: String) -> void:
	if custom_map != null and custom_map.id == id and not id in Layouts.get_ids():
		campaign_play = false
		switch_mode("free")
		return
	var definition := Layouts.get_definition(id)
	var loaded := ConfigLoader.map(definition.resource_path, weather_settings.plot_half)
	if not loaded.errors.is_empty():
		_tuning_feedback("地图未切换：" + "；".join(loaded.errors))
		return
	custom_map = loaded.resource
	campaign_play = false
	custom_map_path = definition.resource_path if not id in Layouts.IDS else ""
	free_layout = definition.id
	switch_mode("free")

func switch_mode(mode: String) -> void:
	if front_active(): close_front_page()
	session_started = true
	selecting_levels = false
	hud.selection_panel.hide()
	hud.menu_open = false
	_apply_pending_restart()
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	play_mode = mode
	if mode == "free": has_free_session = true
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
	_sync_campaign_hud()
	hud.queue_redraw()
	_bind_audio()

func _bind_audio() -> void:
	if weather_audio == null: return
	weather_audio.bind(sim,weather_view.camera)
	hud.set_audio_options(weather_audio.enabled,weather_audio.master_volume)
	if not weather_audio.errors.is_empty(): _tuning_feedback("音效配置保留："+"；".join(weather_audio.errors))

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
	var next := campaign.next_id(sim.layout_id) if campaign_play and campaign != null else ""
	if not next.is_empty(): select_campaign_level(next)
	else: open_level_selection()

func reload_campaign() -> bool:
	var loaded := ConfigLoader.campaign(campaign_path, weather_settings.plot_half)
	if not loaded.errors.is_empty():
		_tuning_feedback(("关卡编排不可用：" if campaign == null else "关卡编排未应用，保留上次有效列表：") + "；".join(loaded.errors))
		return false
	campaign = loaded.resource
	lesson_map_path = campaign.tutorial.resource_path
	return true

func _sync_campaign_hud() -> void:
	hud.campaign = campaign
	hud.campaign_play = campaign_play
	hud.development = development or not persist_progress
	hud.return_to_game = has_free_session
	hud.refresh_layouts()

func select_campaign_level(id: String) -> void:
	var definition := campaign.find_map(id) if campaign != null else null
	if definition == null:
		_tuning_feedback("地图未切换：正式关序中没有 " + id)
		return
	var loaded := ConfigLoader.map(definition.resource_path, weather_settings.plot_half)
	var errors: PackedStringArray = loaded.errors
	if errors.is_empty():
		if loaded.resource.id != id: errors.append("地图id已变化，请修正地图或重新编排：" + definition.resource_path)
		if not loaded.resource.star_level: errors.append("star_level：正式地图须启用风纹评价：" + definition.resource_path)
	if not errors.is_empty():
		_tuning_feedback("地图未切换：" + "；".join(errors))
		return
	custom_map = loaded.resource
	custom_map_path = definition.resource_path
	free_layout = id
	campaign_play = true
	switch_mode("free")
	_remember_entry()

func open_level_selection(developer_maps := false) -> void:
	if not developer_maps and front_menu != null:
		open_front_page("levels", front_active() and front_menu.page == "home")
		return
	if developer_maps and not (development or not persist_progress): return
	if not developer_maps: reload_campaign()
	_sync_campaign_hud()
	if not selecting_levels: selection_was_paused = game_menu_was_paused if hud.menu_open else paused
	selecting_levels = true
	paused = true
	wind_input.cancel()
	wind_input.enabled = false
	hud.show_level_selection(developer_maps)

func close_level_selection() -> void:
	if front_active():
		_front_action("back", "")
		return
	if not selecting_levels: return
	selecting_levels = false
	paused = selection_was_paused
	hud.selection_panel.hide()
	wind_input.enabled = not paused and sim.outcome == "playing"

func enter_free_play() -> void:
	if has_free_session: switch_mode("free")
	elif campaign != null: select_campaign_level(campaign.levels[0].id)
	else:
		open_level_selection()
		return
	_remember_entry()

func _remember_entry() -> void:
	# Tests and explicit development starts do not modify the player's preference.
	var args := OS.get_cmdline_user_args()
	if not persist_progress or "--fresh-guide" in args or "--single-plot" in args or "--free-play" in args or Array(args).any(func(arg): return arg.begins_with("--layout=") or arg.begins_with("--map=")):
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
	weather_audio.set_paused(paused or transition_active())
	var moving: bool = not paused and not transition_active() and not front_active() and sim.outcome == "playing"
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
			weather_audio.observe_states()
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
	if not front_active(): weather_view.update_weather(minf(delta, 0.1), moving, wind_input)
	frame_view_ms = (Time.get_ticks_usec() - start) / 1000.0
	wind_input.enabled = moving
	start = Time.get_ticks_usec()
	if not front_active(): wind_input.update_hover()
	frame_pick_ms = (Time.get_ticks_usec() - start) / 1000.0
	hud.paused = paused or transition_active()
	hud.transitioning = transition_active()
	hud.tuning_message = tuning_message if Time.get_ticks_msec() < tuning_message_until else ""
	hud.frame_ms = lerpf(hud.frame_ms, delta * 1000.0, 0.05)
	start = Time.get_ticks_usec()
	weather_audio.update_audio(minf(delta,0.1),paused or transition_active())
	frame_audio_ms = (Time.get_ticks_usec()-start)/1000.0
	hud.queue_redraw()

func _input(event: InputEvent) -> void:
	if transition_active():
		get_viewport().set_input_as_handled()
		return
	# Space remains the gameplay pause shortcut, never an accidental menu accept.
	if event is InputEventKey and event.keycode == KEY_SPACE and (front_active() or hud.menu_open):
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if transition_active(): return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if front_active():
		if event.keycode == KEY_ESCAPE and front_menu.page != "home": _front_action("back", "")
		return
	if selecting_levels:
		if event.keycode == KEY_ESCAPE: close_level_selection()
		return
	if event.keycode == KEY_ESCAPE:
		hud.menu_open = not hud.menu_open
		navigate(func(): _game_menu_changed(hud.menu_open),"light")
		hud.queue_redraw()
		return
	if hud.menu_open and event.keycode == KEY_SPACE: return
	match event.keycode:
		KEY_R:
			navigate(func(): restart(false),"cloud")
		KEY_F2:
			restart(true)
		KEY_F3:
			hud.debug_visible = not hud.debug_visible
		KEY_F4:
			cold_lab()
		KEY_F6:
			if development: reload_tuning()
		KEY_SPACE:
			navigate(_toggle_pause,"light")

func _toggle_pause() -> void:
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
	if front_active(): front_menu.set_error(message)

func reload_tuning() -> bool:
	var loaded := ConfigLoader.settings(settings_path)
	if not loaded.errors.is_empty():
		_tuning_feedback("配置未应用：" + "；".join(loaded.errors))
		return false
	var candidate: WRWeatherSettings = loaded.resource
	var definition := custom_map if custom_map != null else Layouts.get_definition(free_layout if play_mode == "free" else "standard")
	if play_mode == "lesson" and lesson_map != null: definition = lesson_map
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
