extends Node3D
const Simulation = preload("res://scripts/weather_simulation.gd")
const WeatherView = preload("res://scripts/weather_view.gd")
const WindInput = preload("res://scripts/wind_input.gd")
const HUD = preload("res://scripts/game_hud.gd")
const Onboarding = preload("res://scripts/onboarding.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const SIMULATION_BUDGET_US := 8000
@export var weather_settings: Resource = preload("res://scripts/weather_settings.gd").new()
var sim: Simulation
var weather_view: Node3D
var wind_input: Node
var hud: Control
var paused := false
var accumulator := 0.0
var guide := Onboarding.new()
var play_mode := "lesson"
var preferences_path := "user://onboarding.cfg"
var free_layout := "standard"
var frame_simulation_ms := 0.0
var frame_view_ms := 0.0
var frame_pick_ms := 0.0
var frame_steps := 0
var frame_input_ms := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	play_mode = initial_mode(args)
	for arg in args:
		if arg.begins_with("--layout="):
			free_layout = Layouts.get_layout(arg.trim_prefix("--layout=")).id
			play_mode = "free"
	sim = _new_simulation()
	guide.reset(play_mode == "lesson")
	weather_view = WeatherView.new()
	add_child(weather_view)
	weather_view.setup(sim)
	wind_input = WindInput.new()
	add_child(wind_input)
	wind_input.setup(sim, weather_view.camera)
	wind_input.stroke_applied.connect(func(a, b, height): weather_view.add_wind_stroke(a, b, height))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HUD.new()
	canvas.add_child(hud)
	hud.setup(sim, weather_view, wind_input)
	hud.guide = guide
	hud.play_mode = play_mode
	wind_input.hud = hud
	hud.restart_requested.connect(func(): restart(false))
	hud.sandbox_requested.connect(func(): restart(true))
	hud.cold_lab_requested.connect(cold_lab)
	hud.free_play_requested.connect(enter_free_play)
	hud.lesson_requested.connect(func(): switch_mode("lesson"))
	hud.layout_requested.connect(select_layout)
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
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	sim.reset(test_cloud)
	guide.reset(play_mode == "lesson")
	weather_view.reset_tracers()

func _new_simulation() -> RefCounted:
	return Simulation.new(weather_settings, play_mode == "free", play_mode == "lesson", free_layout)

func select_layout(id: String) -> void:
	free_layout = Layouts.get_layout(id).id
	switch_mode("free")

func switch_mode(mode: String) -> void:
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	play_mode = mode
	sim = _new_simulation()
	guide.reset(mode == "lesson")
	remove_child(weather_view)
	weather_view.queue_free()
	weather_view = WeatherView.new()
	add_child(weather_view)
	weather_view.setup(sim)
	wind_input.setup(sim, weather_view.camera)
	# Resolve the current view at emission time, including after mode changes.
	hud.sim = sim
	hud.view = weather_view
	hud.play_mode = mode
	hud.queue_redraw()

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
	var moving: bool = not paused and sim.outcome == "playing"
	var start := Time.get_ticks_usec()
	if moving: wind_input.flush()
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
			guide.update(sim, Simulation.FIXED_STEP)
			last_step_us = Time.get_ticks_usec() - step_start
			accumulator -= Simulation.FIXED_STEP
			frame_steps += 1
	frame_simulation_ms = (Time.get_ticks_usec() - start) / 1000.0
	hud.simulation_ms = lerpf(hud.simulation_ms, frame_simulation_ms, 0.05)
	start = Time.get_ticks_usec()
	weather_view.update_weather(minf(delta, 0.1), moving)
	frame_view_ms = (Time.get_ticks_usec() - start) / 1000.0
	wind_input.enabled = moving
	start = Time.get_ticks_usec()
	wind_input.update_hover()
	frame_pick_ms = (Time.get_ticks_usec() - start) / 1000.0
	hud.paused = paused
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
		KEY_SPACE:
			paused = not paused
			wind_input.cancel()

func _capture(path: String) -> void:
	# Development-only render capture; never changes the normal starting state.
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " result=", result, " simulation_ms=", hud.simulation_ms, " frame_ms=", hud.frame_ms)
	get_tree().quit(0 if result == OK else 1)
