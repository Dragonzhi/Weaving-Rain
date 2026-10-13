extends "res://tests/test_wind_tools_scene.gd"
const Sim = preload("res://scripts/weather_simulation.gd")
func fixture() -> void:
	main.set_process(false)
	main.sim.sandbox = true
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.charge.fill(0)
	main.sim.wind.fill(Vector2.ZERO)
	main.sim.cold.fill(0)
	for i in Sim.COUNT:
		var p: Vector2 = main.sim.positions[i]
		var distance := minf(p.distance_to(Vector2(0, 0)), p.distance_to(Vector2(6, -1)))
		if distance < 2.1:
			main.sim.cloud[i] = 3.0 * (1.0 - distance * distance / (2.1 * 2.1))
			main.sim.rain[i] = main.sim.cloud[i]
	main.sim.step(Sim.FIXED_STEP)
	main.sim.initial_water = main.sim.water_total()
	main.weather_view.update_weather(0.1, true, main.wind_input)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	check(main.weather_view.hints_enabled and not main.weather_view.rain_area.visible_area, "Default hints are on but dry opening shows no rain area")
	fixture()
	var area: Node3D = main.weather_view.rain_area
	check(area.visible_area and Array(area.groups).max() == 1, "Real fixed-step release creates two separate visible regions")
	check(area.texture.get_image().get_pixel(32, 28).g == 1, "GPU texture publishes actual binary support independent of intensity")
	main.wind_input.enabled = true
	var cloud_screen: Vector2 = main.weather_view.camera.unproject_position(Vector3(0, Sim.CLOUD_HEIGHT, 0))
	main.wind_input.brush_point = main.wind_input.pick(cloud_screen)
	main.wind_input.hover_valid = Sim.contains(Vector2(main.wind_input.brush_point.x, main.wind_input.brush_point.z))
	check(main.wind_input.hover_valid and main.wind_input.hover_cloud, "Real camera ray identifies the visible test cloud")
	for i in 4: main.weather_view.update_weather(0.1, true, main.wind_input)
	var first_group: int = area.selected_group
	check(first_group >= 0 and Array(area.focus).max() == 1.0, "Cloud hover strengthens its actual rain region")
	button(cloud_screen, true)
	check(main.wind_input.dragging and main.wind_input.gesture_cloud, "Real mouse press locks cloud context for the gesture")
	var moved_cloud_point: Vector2 = main.weather_view.camera.unproject_position(Vector3(1.0, Sim.CLOUD_HEIGHT, 0.0))
	move(moved_cloud_point)
	main.wind_input.brush_point = Vector3(1.0, Sim.CLOUD_HEIGHT, 0.0)
	main.wind_input.hover_cloud = main.wind_input.gesture_cloud
	main.weather_view.update_weather(0.1, true, main.wind_input)
	check(main.wind_input.hover_cloud and area.selected_group == first_group, "Dragging keeps the picked cloud reference and rain region")
	button(moved_cloud_point, false)
	main.wind_input.cancel()
	var other_untouched := true
	for i in area.wet_cells:
		if area.groups[i] != first_group: other_untouched = other_untouched and area.focus[i] == 0
	check(other_untouched, "Other disconnected rain is not globally highlighted")
	var builds: int = area.group_builds
	main.sim.refresh_display()
	main.weather_view.update_weather(0.01, true, main.wind_input)
	check(area.group_builds == builds, "Unchanged binary support reuses connected regions")
	var focus: PackedFloat32Array = area.focus.duplicate()
	var clock: float = area.published_time
	main.weather_view.update_weather(1, false, main.wind_input)
	check(area.focus == focus and area.published_time == clock, "Pause freezes ripple time and focus transition")
	await RenderingServer.frame_post_draw
	var active_image := root.get_texture().get_image()
	active_image.save_png("res://.godot/rain-area-active.png")
	await held_tap(main.hud.arrows_button)
	main.weather_view.update_weather(0, false, main.wind_input)
	check(not main.weather_view.hints_enabled and not area.visible_area and main.weather_view.visible_arrows == 0, "Real held button hides rain and arrows together even during pause")
	await RenderingServer.frame_post_draw
	var off_image := root.get_texture().get_image()
	off_image.save_png("res://.godot/rain-area-off.png")
	var ground_screen: Vector2 = main.weather_view.camera.unproject_position(Vector3(0, main.sim.terrain.height(Vector2.ZERO) + 0.05, 0))
	var visual_differences := 0
	for y in range(maxi(0, int(ground_screen.y) - 100), mini(active_image.get_height(), int(ground_screen.y) + 100)):
		for x in range(maxi(0, int(ground_screen.x) - 100), mini(active_image.get_width(), int(ground_screen.x) + 100)):
			if active_image.get_pixel(x, y).get_luminance() - off_image.get_pixel(x, y).get_luminance() > 0.018:
				visual_differences += 1
	check(visual_differences > 20, "Shared toggle visibly changes the ground rain overlay in a fixed scene region")
	await held_tap(main.hud.arrows_button)
	main.weather_view.update_weather(0, false, main.wind_input)
	check(area.visible_area and area.passes[0].visible and area.passes[1].visible, "Re-enable immediately restores both passes")
	main.wind_input.hover_cloud = false
	for i in 4: main.weather_view.update_weather(0.1, true, main.wind_input)
	check(Array(area.focus).max() == 0, "Ground gesture and leaving cloud return to faint normal appearance")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/rain-area-idle.png")
	check(not main.hud.blocks_wind(main.hud.plot_label_rects[0].get_center()), "Area does not add an input-blocking panel")
	main.sim.outcome = "success"
	main.weather_view.update_weather(0, false)
	check(not area.visible_area and main.weather_view.visible_arrows == 0, "Results hide all auxiliary weather hints")
	main.weather_view.hints_enabled = false
	main.restart(false)
	await RenderingServer.frame_post_draw
	check(not main.weather_view.hints_enabled and main.weather_view.rain_area.wet_cells.is_empty(), "Retry preserves toggle and clears prior rain focus")
	main.select_layout("storm_coast")
	await RenderingServer.frame_post_draw
	check(not main.weather_view.hints_enabled, "Map switch preserves session toggle")
	main.switch_mode("lesson")
	await RenderingServer.frame_post_draw
	check(not main.weather_view.hints_enabled, "Mode switch preserves session toggle")
	# Paired ordinary simulations show that visual hints consume no weather state.
	main.restart(false)
	var control := Sim.new(main.sim.settings, main.sim.relay_mode, main.sim.cold_capable, main.free_layout, main.custom_map)
	main.sim.stroke(Vector2(-4.0, 0.0), Vector2(-3.4, 0.2), 2.5)
	control.stroke(Vector2(-4.0, 0.0), Vector2(-3.4, 0.2), 2.5)
	for i in 30:
		main.sim.step(Sim.FIXED_STEP)
		control.step(Sim.FIXED_STEP)
		main.weather_view.hints_enabled = i % 2 == 0
		main.weather_view.update_weather(Sim.FIXED_STEP, false)
	check(main.sim.humidity == control.humidity and main.sim.cloud == control.cloud and main.sim.rain == control.rain, "Hint visibility does not change atmospheric fields")
	check(main.sim.cold == control.cold and main.sim.wind == control.wind and main.sim.plot_waters == control.plot_waters, "Hint visibility does not change wind, cold air, or target water")
	check(is_equal_approx(main.sim.water_error(), control.water_error()), "Hint visibility leaves water accounting identical")
	print("RAIN AREA SCENE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
