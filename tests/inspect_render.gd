extends SceneTree
## Development-only visual inspection, using real viewport events and rain-generated cold.
const Sim = preload("res://scripts/weather_simulation.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.cold_lab()
	main.sim.step(5.0)
	var from := Vector2(5.5, 1.2)
	var to := Vector2(3.8, 1.1)
	var camera: Camera3D = main.weather_view.camera
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = camera.unproject_position(Vector3(from.x, Sim.terrain_height(from) + 0.30, from.y))
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = camera.unproject_position(Vector3(to.x, Sim.terrain_height(to) + 0.30, to.y))
	root.push_input(motion)
	var cost := 0.0
	var frame_cost := 0.0
	for frame in 100:
		var start := Time.get_ticks_usec()
		main._process(Sim.FIXED_STEP)
		if frame >= 10:
			cost += (Time.get_ticks_usec() - start) / 1000.0
		await process_frame
		if frame >= 10:
			frame_cost += main.get_process_delta_time() * 1000.0
		if frame == 12:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/cold-wind.png")
	print("RENDER SAMPLE: process_avg_ms=", cost / 90.0, " frame_avg_ms=", frame_cost / 90.0, " cold_lift=", main.sim.total_cold_lift, " traces=", main.weather_view.wind_traces.size())
	main.queue_free()
	await process_frame
	quit()
