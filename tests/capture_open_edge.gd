extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.hud.visible = false
	main.sim.sandbox = true
	main.sim.humidity.fill(0)
	for i in Sim.COUNT:
		var p: Vector2 = main.sim.positions[i]
		main.sim.cloud[i] = 3.5 * exp(-pow((p.x - 12.0) / 1.1, 2) - pow(p.y / 1.8, 2))
		main.sim.rain[i] = main.sim.cloud[i] * 0.4
		main.sim.humidity[i] = 2.0 * exp(-pow((p.x - 12.0) / 1.5, 2) - pow(p.y / 1.8, 2))
	main.sim.refresh_display()
	main.sim.initial_water = main.sim.water_total()
	var camera: Camera3D = main.weather_view.camera
	camera.position = Vector3(22, 19, 25)
	camera.look_at(Vector3(10, 1, 0))
	camera.size = 17
	DirAccess.make_dir_recursive_absolute("res://.godot/open-edge-motion")
	for frame in 150:
		main.sim.wind.fill(Vector2(6, 0))
		main.sim.step(1.0 / 30.0)
		main.weather_view.update_weather(1.0 / 30.0, true)
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_png("res://.godot/open-edge-motion/%04d.png" % frame)
		if frame in [0, 74, 149]: picture.save_png("res://.godot/open-edge-%d.png" % frame)
	print("OPEN EDGE CAPTURE frames=150 escaped=", main.sim.escaped_water, " water_error=", main.sim.water_total() - main.sim.initial_water)
	main.queue_free()
	await process_frame
	quit()
