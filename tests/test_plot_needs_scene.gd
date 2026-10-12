extends SceneTree
var main: Node3D
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func paint(a: float, b: float, label: String) -> void:
	main.sim.plot_waters[0] = a
	main.sim.plot_waters[1] = b
	main.sim.update_goal(0.0)
	main.weather_view.update_weather(0.5, true)
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/needs-water-" + label + ".png")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	check(main.sim.plot_name(1) == "幼苗" and main.sim.required_water(1) == 40, "Actual startup loads configured needs")
	check(main.weather_view.plant_groups[1].get_child_count() < main.weather_view.plant_groups[0].get_child_count(), "Seedling appearance is sparser independently of area")
	await paint(30, 10, "blue")
	check(main.hud.water_color(1) == Color("7aaebc") and main.sim.plot_progress(1) == 0.25, "Blue fill uses own required water")
	await paint(100, 40, "adequate")
	check(main.hud.water_color(1) == Color("7aaebc") and main.sim.plot_progress(1) == 1.0 and main.sim.earned_stars() == 0, "Full blue is adequate, not yet a safe star")
	var growth: float = main.weather_view.plant_groups[1].scale.y
	await paint(125, 47.5, "yellow")
	check(main.hud.water_color(1) == Color("7aaebc").lerp(Color("ddc775"), 0.5), "Blue/yellow blend follows own tolerance")
	check(main.weather_view.plant_groups[1].scale.y >= growth, "Plant growth reads own progress")
	await paint(125, 55, "limit")
	check(main.hud.water_color(1) == Color("ddc775") and not main.sim.plot_destroyed[1], "Exact upper limit is yellow, still alive")
	await paint(110, 55.1, "red")
	check(main.hud.water_color(1) == Color("c76e60") and main.sim.plot_destroyed[1], "Damage turns red immediately")
	var pose: Transform3D = main.weather_view.plant_groups[1].transform
	main.weather_view.update_weather(1.0, false)
	check(main.weather_view.plant_groups[1].transform == pose, "Pause freezes growth and wilt interpolation")
	check(not main.hud.blocks_wind(main.hud.plot_label_rects[1].get_center()), "Typed plot information remains pass-through")
	main.sim.plot_waters[0] = 40
	main.sim.update_goal(0.0)
	check("60.0" in main.hud.status_text(0, true) and main.hud.status_text(1, true).contains("过量"), "Result reasons read own needs and permanent damage")
	var needs := WRPlotNeeds.new()
	needs.id = "test_seedling"
	needs.display_name = "测试苗"
	needs.target_water = 60
	needs.flood_water = 80
	needs.appearance = "seedling"
	ResourceSaver.save(needs, "res://.godot/needs-test-preset.tres")
	var definition: WRMapDefinition = load("res://configs/maps/needs_lab.tres").duplicate(true)
	definition.plot_needs[1] = ResourceLoader.load("res://.godot/needs-test-preset.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	ResourceSaver.save(definition, "res://.godot/needs-test-map.tres")
	main.custom_map_path = "res://.godot/needs-test-map.tres"
	var water: PackedFloat64Array = main.sim.plot_waters.duplicate()
	check(main.reload_tuning() and main.sim.required_water(1) == 40 and main.sim.plot_waters == water, "F6 does not reload goals or reset the weather")
	main.restart(false)
	check(main.sim.required_water(1) == 60 and main.sim.flood_limit(1) == 80 and main.sim.plot_waters[1] == 0, "R deeply reloads saved external needs")
	needs.target_water = 90
	ResourceSaver.save(needs, "res://.godot/needs-test-preset.tres")
	main.restart(false)
	check(main.sim.required_water(1) == 60 and "plot_needs[1]" in main.tuning_message and "flood_water" in main.tuning_message, "Invalid saved needs keep previous valid map and identify field")
	main.custom_map_path = ""
	main.select_layout("needs_lab")
	check(main.sim.required_water(1) == 40 and main.sim.peak_density == 0, "Switching reloads normal map without changing source preset")
	main.sim.plot_waters[0] = 100
	main.sim.plot_waters[1] = 40
	main.sim.update_goal(2.1)
	main.finish_level()
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.result_details[0].contains("普通田") and main.hud.result_details[1].contains("幼苗") and main.hud.result_details[1].contains("40.0/40"), "Actual result lists type and its own requirement")
	print("PLOT NEEDS SCENE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
