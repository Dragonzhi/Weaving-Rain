extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var sim := Sim.new()
	for i in Sim.COUNT:
		var p: Vector2 = sim.positions[i]
		sim.cloud[i] = 3.0 * exp(-p.distance_squared_to(Vector2(0.3, 0.2)) / 4.0)
		sim.cloud[i] += 1.3 * exp(-pow((p.x + 3.0) / 3.0, 2) - pow(p.y / 0.5, 2))
	sim.refresh_display()
	var texture_image := Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	for i in Sim.COUNT:
		texture_image.set_pixel(i % Sim.WIDTH, i / Sim.WIDTH, Color(sim.display_cloud[i], 0, 0, 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 32)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item; uniform sampler2D water_map : filter_linear, repeat_disable;\n#include "res://shaders/cloud_field.gdshaderinc"\nvoid fragment() { vec2 p = UV * vec2(24.0,20.0) - vec2(12.0,10.0); COLOR = vec4(cloud_state(p).r,0.0,0.0,1.0); }'
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("water_map", ImageTexture.create_from_image(texture_image))
	var rect := ColorRect.new()
	rect.size = viewport.size
	rect.material = material
	viewport.add_child(rect)
	await process_frame
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image()
	var error := 0.0
	for z in 32:
		for x in 64:
			var p := Vector2((x + 0.5) / 64.0 * 24 - 12, (z + 0.5) / 32.0 * 20 - 10)
			error = maxf(error, absf(actual.get_pixel(x, z).r - sim.sample_cloud(sim.display_cloud, p)))
	check(error < 0.005, "GPU reconstruction must match the CPU cloud shape; max error=" + str(error))
	var constant := PackedFloat32Array()
	constant.resize(Sim.COUNT)
	constant.fill(2.0)
	check(is_equal_approx(sim.sample_cloud(constant, Vector2(-11.99, 9.99)), 2.0), "Clamped reconstruction preserves constant boundary fields")
	var previous := 0.0
	var largest_change := 0.0
	for n in 400:
		var q := sim.sample_cloud(sim.display_cloud, Vector2(-5 + n * 0.025, 0.15))
		if n > 0: largest_change = maxf(largest_change, absf(q - previous))
		previous = q
	check(largest_change < 0.08, "Thin and thick cloud reconstruction remains continuous across cells")
	check(sim.sample_cloud(sim.display_cloud, Vector2(20, 0)) == 0.0, "Cloud shape remains empty outside the weather domain")
	# A smooth thick cloud must have smooth INTERNAL color contours, not just a smooth rim.
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.hud.visible = false
	for child in main.weather_view.get_children():
		if child is GeometryInstance3D:
			child.visible = child.material_override == main.weather_view.cloud_material
		elif child is WorldEnvironment:
			child.environment.background_color = Color(0.94, 0.96, 0.92)
	for i in Sim.COUNT:
		var p: Vector2 = main.sim.positions[i]
		main.sim.cloud[i] = 4.0 * exp(-pow(p.x / 2.8, 2) - pow(p.y / 1.8, 2))
	main.sim.rain.fill(0.0)
	main.sim.refresh_display()
	main.weather_view.update_weather(0.0, false)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png("res://.godot/cloud-edge-check.png")
	var rows: Array[Vector2i] = []
	for y in picture.get_height():
		for x in picture.get_width():
			var color := picture.get_pixel(x, y)
			if color.r < 0.86 and color.r > 0.68 and color.b > 0.78:
				rows.append(Vector2i(x, y))
				break
	var maximum_bend := 0
	var contiguous := true
	for i in range(int(rows.size() * 0.2) + 1, int(rows.size() * 0.8) - 1):
		contiguous = contiguous and rows[i].y == rows[i - 1].y + 1
		maximum_bend = maxi(maximum_bend, absi(rows[i + 1].x - rows[i].x * 2 + rows[i - 1].x))
	check(rows.size() > 30 and contiguous, "Internal gray-blue band must form a continuous contour")
	check(maximum_bend <= 4, "Internal gray-blue band must not jump between ray layers; max bend=" + str(maximum_bend))
	main.queue_free()
	print("CLOUD SURFACE: ", checks, " checks, ", failures, " failures; GPU error=", error)
	viewport.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
