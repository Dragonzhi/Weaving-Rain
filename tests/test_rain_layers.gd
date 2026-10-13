extends SceneTree
## GPU regression: compare exactly the same frozen cloud with rain visible/hidden.
const Sim = preload("res://scripts/weather_simulation.gd")
const LEGACY_RAIN := "shader_type spatial; render_mode unshaded, fog_disabled, depth_draw_never; uniform float visual_time = 0.0; uniform vec4 rain_color : source_color = vec4(0.65,0.89,0.91,1.0); void vertex() { VERTEX.y += fract(INSTANCE_CUSTOM.x - visual_time * 1.8) * INSTANCE_CUSTOM.y; } void fragment() { ALBEDO = rain_color.rgb; }"
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.hud.visible = false
	var view: Node3D = main.weather_view
	view.hints_enabled = false
	main.sim.humidity.fill(0.0)
	main.sim.cloud.fill(0.0)
	main.sim.rain.fill(0.0)
	main.sim.cold.fill(0.0)
	for i in Sim.COUNT:
		var p: Vector2 = main.sim.positions[i]
		if p.length() < 4.0:
			main.sim.cloud[i] = 4.0
			main.sim.rain[i] = 4.0
	main.sim.refresh_display()
	view.update_weather(0.0, false)
	view.line_node.visible = false
	view.ascent.visible_instance_count = 0
	var count: int = view.rainfall.visible_instance_count
	var capture_suffix := "-legacy" if "--legacy-rain" in OS.get_cmdline_user_args() else ""
	# Optional development reproducer for the shader that caused this report.
	if "--legacy-rain" in OS.get_cmdline_user_args():
		var legacy := Shader.new()
		legacy.code = LEGACY_RAIN
		view.rain_material.shader = legacy
	var peak_cloud_change := 0.0
	var exposed_pixels := 0
	var initial := await capture()
	var image_size := Vector2(initial.get_size())
	var cloud_point: Vector2 = view.camera.unproject_position(Vector3(0, Sim.CLOUD_HEIGHT + 0.5, 0)) * image_size / root.get_visible_rect().size
	var pixel_scale := image_size.y / 1080.0
	for time in [0.0, 0.21, 0.47]:
		view.elapsed = time
		view.update_weather(0.0, false)
		view.rainfall.visible_instance_count = 0
		var dry := await capture()
		view.rainfall.visible_instance_count = count
		var rainy := await capture()
		for y in range(int(cloud_point.y - 50 * pixel_scale), int(cloud_point.y + 50 * pixel_scale)):
			for x in range(int(cloud_point.x - 65 * pixel_scale), int(cloud_point.x + 65 * pixel_scale)):
				var a := rainy.get_pixel(x, y)
				var b := dry.get_pixel(x, y)
				peak_cloud_change = maxf(peak_cloud_change, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
		for y in range(int(cloud_point.y + 150 * pixel_scale), mini(rainy.get_height(), int(cloud_point.y + 340 * pixel_scale))):
			for x in range(int(cloud_point.x - 150 * pixel_scale), int(cloud_point.x + 150 * pixel_scale)):
				if rainy.get_pixel(x, y).g - dry.get_pixel(x, y).g > 0.05:
					exposed_pixels += 1
		if time == 0.21:
			rainy.save_png("res://.godot/rain-layers-review" + capture_suffix + ".png")
	check(peak_cloud_change < 0.004, "Thick cloud occludes rain at all animation phases; max color difference=" + str(peak_cloud_change))
	check(exposed_pixels > 50, "Rain remains visible below/in front of the cloud; pixels=" + str(exposed_pixels))
	# A sparse white cloud is where rain formerly cut holes in cloud integration.
	main.sim.cloud.fill(0.0)
	main.sim.rain.fill(0.0)
	for i in Sim.COUNT:
		if main.sim.positions[i].length() < 4.0:
			main.sim.cloud[i] = 0.22
			main.sim.rain[i] = 0.22
	main.sim.refresh_display()
	view.update_weather(0.0, false)
	count = view.rainfall.visible_instance_count
	view.rainfall.visible_instance_count = 0
	var pale_dry := await capture()
	view.rainfall.visible_instance_count = count
	var pale_rain := await capture()
	var pale_peak := 0.0
	for y in range(int(cloud_point.y - 100 * pixel_scale), int(cloud_point.y + 100 * pixel_scale)):
		for x in range(int(cloud_point.x - 150 * pixel_scale), int(cloud_point.x + 150 * pixel_scale)):
			var a := pale_rain.get_pixel(x, y)
			var b := pale_dry.get_pixel(x, y)
			if b.r > 0.85 and b.g > 0.85 and b.b > 0.80:
				pale_peak = maxf(pale_peak, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	check(pale_peak < 0.004, "Pale cloud also occludes rain without depth holes; peak=" + str(pale_peak))
	pale_rain.save_png("res://.godot/rain-layers-pale" + capture_suffix + ".png")
	var water: float = main.sim.water_total()
	var frozen := await capture()
	view.update_weather(1.0, false)
	var paused := await capture()
	check(frozen.get_data() == paused.get_data(), "Pause freezes rain and cloud compositing")
	check(main.sim.water_total() == water, "Layering changes do not modify simulated water")
	print("RAIN LAYERS: ", checks, " checks, ", failures, " failures; hidden_peak=", peak_cloud_change, " visible_pixels=", exposed_pixels)
	quit(0 if failures == 0 else 1)
