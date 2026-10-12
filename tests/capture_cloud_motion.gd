extends SceneTree
## Development review sequence: no fixed clouds or automatic strokes enter gameplay.
const Sim = preload("res://scripts/weather_simulation.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.restart(true)
	var directory := "res://.godot/cloud-motion"
	DirAccess.make_dir_recursive_absolute(directory)
	for phase in 3:
		main.restart(true)
		if phase == 1:
			for i in Sim.COUNT: main.sim.cloud[i] *= 2.0
		elif phase == 2:
			for i in Sim.COUNT:
				main.sim.cloud[i] *= 2.0
				main.sim.rain[i] = main.sim.cloud[i]
		main.sim.refresh_display()
		main.sim.initial_water = main.sim.water_total()
		for frame in 90:
			if frame % 15 == 0:
				var p := Vector2(-1.5 + frame / 90.0 * 4.0, 0.0)
				var to := p + Vector2(0.7, sin(frame * 0.07) * 0.6)
				main.sim.stroke(p, to, 4.0)
				main.weather_view.add_wind_stroke(p, to, Sim.CLOUD_HEIGHT)
			main.sim.step(1.0 / 30.0)
			main.weather_view.update_weather(1.0 / 30.0, true)
			main.hud.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png(directory + "/%04d.png" % (phase * 90 + frame))
			if frame == 30:
				image.save_png("res://.godot/cloud-revision-%d.png" % phase)
	print("CLOUD MOTION: 270 frames at 30 Hz in ", directory)
	main.queue_free()
	await process_frame
	quit()
