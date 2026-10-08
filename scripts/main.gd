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
	sim = Simulation.new(weather_settings)
	weather_view = WeatherView.new()
	add_child(weather_view)
	weather_view.setup(sim)
	wind_input = WindInput.new()
	add_child(wind_input)
	wind_input.setup(sim, weather_view.camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HUD.new()
	canvas.add_child(hud)
	hud.setup(sim, weather_view, wind_input)
	hud.restart_requested.connect(func(): restart(false))
	hud.sandbox_requested.connect(func(): restart(true))
	for arg in OS.get_cmdline_user_args():
		if arg == "--cloud-lab":
			restart(true)
		elif arg.begins_with("--capture="):
			_capture(arg.trim_prefix("--capture="))

func restart(test_cloud: bool) -> void:
	wind_input.cancel()
	paused = false
	accumulator = 0.0
	sim.reset(test_cloud)
	weather_view.reset_tracers()

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
