extends "res://tests/test_scene_lighting.gd"
## Art review fixtures only. All pictures are actual GPU renders, not normal routes.
func save_view(name: String) -> void:
	main.wind_input.cancel()
	main.wind_input.hover_valid = false
	main.wind_input.hover_cloud = false
	main.wind_input.enabled = false
	main.weather_view.update_weather(0,false)
	main.hud.reset_feedback()
	(await render()).save_png("res://.godot/scene-review/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/scene-review")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await render()
	main.set_process(false)
	main.hud.set_process(false)
	main.guide.cold_hint_seen = true
	main.guide.cold_hint_left = 0
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size = resolution
		main.select_layout("reservoir_lab")
		main.sim.humidity.fill(0)
		main.sim.cloud.fill(0)
		main.sim.rain.fill(0)
		main.sim.cold.fill(0)
		main.sim.plot_waters[0] = 65
		main.sim.plot_waters[1] = main.sim.required_water(1)
		main.sim.update_goal(0)
		main.weather_view.update_weather(1,true)
		await save_view("ground-"+str(resolution.x))
		main.hud.visible = false
		main.weather_view.camera.size = 9.0
		await save_view("details-"+str(resolution.x))
		main.select_layout("meadow")
		main.hud.visible = true
		main.sim.humidity.fill(0.0)
		main.sim.cloud.fill(0.0)
		main.sim.rain.fill(0.0)
		main.sim.cold.fill(0.0)
		for i in Sim.COUNT:
			var p: Vector2 = main.sim.positions[i]
			var q := 2.8*exp(-p.distance_squared_to(Vector2(-1.5,-0.5))/2.8)
			q += 2.0*exp(-p.distance_squared_to(Vector2(0.4,0.2))/2.1)
			q += 0.6*exp(-pow((p.x+4.0)/2.7,2)-pow((p.y+0.5)/0.55,2))
			main.sim.cloud[i] = q
			# Bound this injected review rain patch. Infinite Gaussian tails would
			# honestly mark the whole half-map as raining and obscure the art review.
			if p.x>0 and q>0.12: main.sim.rain[i] = q
		main.sim.initial_water = main.sim.water_total()
		main.sim.step(Sim.FIXED_STEP)
		main.sim.refresh_display()
		main.weather_view.update_weather(0.3,true)
		await save_view("cloud-rain-"+str(resolution.x))
	print("SCENE REVIEW: six GPU display fixtures; not normal gameplay completion evidence")
	quit()
