extends "res://tests/test_ui_visuals.gd"
## Display-only fixtures. These pictures do not prove normal gameplay completion.

func save_picture(name: String, hover := -1) -> void:
	main.hud.ui_time = 1.0
	main.hud.reset_feedback()
	main.hud.ui_time = 1.0
	main.weather_view.update_weather(0,false)
	await render()
	move(main.hud.plot_label_rects[hover].get_center() if hover>=0 else Vector2(12,190))
	var picture := await render()
	picture.save_png("res://.godot/ui-review/"+name+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/ui-review")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await render()
	main.set_process(false)
	main.hud.set_process(false)
	main.guide.cold_hint_seen = true
	main.guide.cold_hint_left = 0
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size = resolution
		await render()
		main.select_layout("meadow")
		main.sim.humidity.fill(0)
		main.sim.cloud.fill(0)
		main.sim.rain.fill(0)
		main.sim.cold.fill(0)
		main.sim.plot_waters = PackedFloat64Array([50,110,110])
		var cell: int = main.sim.safety_indices[1][0]
		main.sim.cloud[cell] = 0.1
		main.sim.rain[cell] = 0.1
		main.sim.refresh_display()
		main.sim.update_goal(1.0)
		await save_picture("states-"+str(resolution.x),1)
		main.sim.cloud.fill(0)
		main.sim.rain.fill(0)
		main.sim.plot_waters = PackedFloat64Array([110,110,151])
		main.sim.refresh_display()
		main.sim.update_goal(3)
		await save_picture("loss-"+str(resolution.x),2)
		main.sim.finish()
		await render()
		main.hud.ui_time += 1.0
		var picture := await render()
		picture.save_png("res://.godot/ui-review/result-"+str(resolution.x)+".png")
		main.select_layout("reservoir_lab")
		main.sim.plot_waters = PackedFloat64Array([50,250])
		main.sim.update_goal(0)
		await save_picture("reservoir-"+str(resolution.x),1)
	print("UI REVIEW CAPTURE: eight GPU display fixtures; no normal route claim")
	quit()
