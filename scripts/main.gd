extends Node3D
const Simulation = preload("res://scripts/weather_simulation.gd")
const WeatherView = preload("res://scripts/weather_view.gd")
const WindInput = preload("res://scripts/wind_input.gd")
const HUD = preload("res://scripts/game_hud.gd")
@export var weather_settings: Resource = preload("res://scripts/weather_settings.gd").new()
var sim: RefCounted
var weather_view: Node3D
var wind_input: Node
var hud: Control
var paused := false
var accumulator := 0.0

func _ready() -> void:
	var baseline := "--single-plot" in OS.get_cmdline_user_args()
	sim = Simulation.new(weather_settings, not baseline)
	weather_view = WeatherView.new()
	add_child(weather_view)
	weather_view.setup(sim)
	wind_input = WindInput.new()
	add_child(wind_input)
	wind_input.setup(sim, weather_view.camera)
	wind_input.stroke_applied.connect(weather_view.add_wind_stroke)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HUD.new()
	canvas.add_child(hud)
	hud.setup(sim, weather_view, wind_input)
	wind_input.hud = hud
	hud.restart_requested.connect(func(): restart(false))
	hud.sandbox_requested.connect(func(): restart(true))
	hud.cold_lab_requested.connect(cold_lab)
	for arg in OS.get_cmdline_user_args():
		if arg == "--cloud-lab":
			restart(true)
		elif arg == "--cold-lab":
			cold_lab()
		elif arg.begins_with("--capture="):
			_capture(arg.trim_prefix("--capture="))

func restart(test_cloud: bool) -> void:
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	sim.reset(test_cloud)
	weather_view.reset_tracers()

func cold_lab() -> void:
	restart(true)
	for i in Simulation.COUNT:
		var p: Vector2 = sim.positions[i]
		sim.cloud[i] = 2.1 * exp(-p.distance_squared_to(Simulation.PLOT) / 1.7)
		sim.rain[i] = sim.cloud[i]
		sim.humidity[i] += 2.2 * exp(-p.distance_squared_to(Vector2(5.6, 1.8)) / 3.0)
	sim.initial_water = sim.water_total()
	sim.refresh_display()

func _process(delta: float) -> void:
	var moving: bool = not paused and sim.outcome == "playing"
	var start := Time.get_ticks_usec()
	if moving:
		# Limit catch-up after debugger stalls without skipping simulation steps.
		accumulator += minf(delta, 0.1)
		while accumulator >= Simulation.FIXED_STEP:
			sim.step(Simulation.FIXED_STEP)
			accumulator -= Simulation.FIXED_STEP
	hud.simulation_ms = lerpf(hud.simulation_ms, (Time.get_ticks_usec() - start) / 1000.0, 0.05)
	weather_view.update_weather(minf(delta, 0.1), moving)
	wind_input.enabled = moving
	wind_input.update_hover()
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
