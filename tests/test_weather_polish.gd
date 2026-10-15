extends "res://tests/replay_star_viewport.gd"
## Display/input fixtures, not normal-play route evidence.
var checks := 0
var directory := "res://.godot/level-review/"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func render() -> Image:
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func preview(radius: float) -> Image:
	var input: Node = main.wind_input
	var camera: Camera3D = main.weather_view.camera
	input.cancel()
	var start := camera.unproject_position(Vector3(0,0.3,2))
	button(start,true)
	var event := InputEventMouseMotion.new()
	event.position = camera.unproject_position(Vector3(radius,input.reference_height,2))
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
	return await render()
func red_on_ring(image: Image) -> int:
	var gesture: Dictionary = main.wind_input.vortex_preview()
	var count := 0
	var scale := Vector2(image.get_size())/root.get_visible_rect().size
	for n in 64:
		var p: Vector2 = gesture.center+Vector2.from_angle(n*TAU/64.0)*gesture.radius
		var screen: Vector2 = main.weather_view.camera.unproject_position(Vector3(p.x,main.wind_input.reference_height,p.y))*scale
		for y in range(-2,3):
			for x in range(-2,3):
				var pixel := Vector2i(screen)+Vector2i(x,y)
				if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height(): continue
				var c := image.get_pixelv(pixel)
				if c.r > 0.45 and c.r > c.g*1.35 and c.r > c.b*1.35: count += 1
	return count
func patch(image: Image, world: Vector3) -> float:
	var p: Vector2 = main.weather_view.camera.unproject_position(world)*Vector2(image.get_size())/root.get_visible_rect().size
	var total := 0.0
	for y in range(-2,3):
		for x in range(-2,3): total += image.get_pixel(int(p.x)+x,int(p.y)+y).get_luminance()
	return total/25.0
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.select_layout("needs_lab")
	main.wind_input.select_tool("vortex")
	var good := await preview(2)
	var good_red := red_on_ring(good)
	check(main.wind_input.vortex_preview().ok,"In-range preview remains valid")
	main.wind_input.cancel()
	var bad := await preview(6)
	var bad_red := red_on_ring(bad)
	check(not main.wind_input.vortex_preview().ok and "范围过大" in main.wind_input.vortex_preview().reason,"Over-limit preview identifies the maximum instead of hiding the reason")
	check(bad_red > good_red+40,"Actual GPU range outline turns visibly red when too large")
	bad.save_png(directory+"vortex-over-"+str(root.size.x)+".png")
	button(main.weather_view.camera.unproject_position(main.wind_input.brush_point),false)
	check(main.sim.wind_sources.is_empty(),"Red invalid preview never creates a vortex")
	await preview(0.5)
	check(not main.wind_input.vortex_preview().ok and "范围过小" in main.wind_input.vortex_preview().reason,"Too-small placement gives its own minimum hint")
	main.wind_input.cancel()
	good = await preview(2)
	check(main.wind_input.vortex_preview().ok and red_on_ring(good) < bad_red,"Dragging back into range recovers the normal preview")
	button(main.weather_view.camera.unproject_position(main.wind_input.brush_point),false)
	check(main.sim.wind_sources.size() == 1,"Valid release still creates exactly one source")
	main.restart(false)
	main.hud.hide()
	main.sim.humidity.fill(0)
	main.sim.refresh_display()
	main.weather_view.update_weather(0,false)
	var dry := await render()
	var view: Node3D = main.weather_view
	var initial_color: Color = view.plot_materials[0].get_shader_parameter("base_color")
	main.sim.plot_waters[0] = main.sim.required_water(0)*0.5
	var before_water: PackedFloat64Array = main.sim.plot_waters.duplicate()
	var before_humidity: PackedByteArray = main.sim.humidity.to_byte_array()
	view.update_weather(1.0/60.0,true)
	var partial: Color = view.plot_materials[0].get_shader_parameter("base_color")
	check(view.plot_wetness[0] > 0 and view.plot_wetness[0] < 0.5,"Soil starts gradually rather than jumping to the new water level")
	check(partial.r < initial_color.r and partial.g < initial_color.g and partial.b < initial_color.b,"Early watering makes warm soil darker")
	for frame in 30: view.update_weather(1.0/60.0,true)
	var halfway: Color = view.plot_materials[0].get_shader_parameter("base_color")
	check(halfway.r < partial.r,"Continued display interpolation gradually deepens wet color")
	var wetness: float = view.plot_wetness[0]
	view.update_weather(1.0,false)
	check(view.plot_wetness[0] == wetness and view.plot_materials[0].get_shader_parameter("base_color") == halfway,"Pause freezes soil color interpolation")
	check(main.sim.plot_waters == before_water and main.sim.humidity.to_byte_array() == before_humidity,"Visual wetness does not consume or add water")
	main.sim.plot_waters[0] = main.sim.required_water(0)
	for frame in 120: view.update_weather(1.0/60.0,true)
	var wet := await render()
	var center: Vector2 = main.sim.plot_centers[0]
	var sample := Vector3(center.x+0.34,view.scene_style.farm_top_height+0.002,center.y+0.32)
	var dry_light := patch(dry,sample)
	var wet_light := patch(wet,sample)
	check(wet_light < dry_light-0.025,"Rendered farm top visibly darkens after watering")
	check(view.farm_side_materials[0].get_shader_parameter("base_color").r < initial_color.r,"Soil sides share wet color with the top")
	dry.save_png(directory+"farm-dry-"+str(root.size.x)+".png")
	wet.save_png(directory+"farm-wet-"+str(root.size.x)+".png")
	var origin: Vector3 = view.plant_groups[1].position
	main.sim.plot_waters[1] = main.sim.flood_limit(1)+0.1
	main.sim.update_goal(0)
	for frame in 60: view.update_weather(1.0/60.0,true)
	check(main.sim.plot_destroyed[1] and view.plant_wilt[1] > 0.99,"Real damage still drives gradual wilt coloring")
	check(view.plant_groups[1].rotation.is_zero_approx() and view.plant_groups[1].position == origin,"Wilt never rotates or moves the plant group")
	check(view.plant_groups[1].scale.y < 0.6,"Wilt shortens plants instead of tipping the entire field")
	var pose: Transform3D = view.plant_groups[1].transform
	view.update_weather(1,false)
	check(view.plant_groups[1].transform == pose,"Pause freezes the new wilt pose")
	(await render()).save_png(directory+"farm-wilt-"+str(root.size.x)+".png")
	main.select_layout("level03")
	var pool_color: Color = main.weather_view.plot_materials[1].get_shader_parameter("base_color")
	main.sim.plot_waters[1] = main.sim.required_water(1)*0.5
	main.weather_view.update_weather(1,true)
	check(main.weather_view.plot_materials[1].get_shader_parameter("base_color") == pool_color and main.weather_view.plot_wetness[1] == 0,"Reservoir keeps its own water appearance instead of becoming wet farmland")
	var report := {"checks":checks,"failures":failures,"size":str(root.size),"ring_red_valid":good_red,"ring_red_invalid":bad_red,"dry_luminance":dry_light,"wet_luminance":wet_light}
	FileAccess.open(directory+"polish-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WEATHER POLISH ",JSON.stringify(report))
	quit(0 if failures == 0 else 1)
