extends SceneTree
## Render an actual simulation snapshot, without introducing a gameplay shortcut.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var file := FileAccess.open("res://.godot/replay-snapshot.json", FileAccess.READ)
	if file == null:
		push_error("Run replay_weather.gd with --snapshot=res://.godot/replay-snapshot.json first")
		quit(1)
		return
	var state: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	main.sim.humidity = PackedFloat32Array(state.humidity)
	main.sim.cloud = PackedFloat32Array(state.cloud)
	main.sim.rain = PackedFloat32Array(state.rain)
	main.sim.charge = PackedFloat32Array(state.charge)
	main.sim.plot_water = state.plot_water
	main.sim.rain_lost = state.rain_lost
	main.sim.initial_water = state.initial_water
	main.sim.total_rain_rate = state.rain_rate
	main.sim.refresh_display()
	main.sim.update_goal(0.0)
	main.weather_view.elapsed = 10.0
	main.weather_view.update_weather(0.0, false)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.godot/gameplay.png"
	var result := root.get_texture().get_image().save_png(path)
	print("REPLAY CAPTURE: ", path, " result=", result)
	main.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
