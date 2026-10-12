extends SceneTree
## GPU comparison of concentrated real grid values; no circular mask or weather edits in gameplay.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func radii(image: Image) -> Array[float]:
	var result: Array[float] = []
	var center := Vector2(image.get_size()) * 0.5
	for n in 32:
		var direction := Vector2(cos(n * TAU / 32), sin(n * TAU / 32))
		var distance := 0.0
		for r in 235:
			var p := Vector2i(center + direction * r)
			if image.get_pixelv(p).a >= 0.03: distance = r
		result.append(distance)
	return result
func _init() -> void: call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512,512)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5
	camera.position = Vector3(0,5,0)
	camera.look_at(Vector3.ZERO, Vector3.BACK)
	camera.current = true
	var image := Image.create(64,56,false,Image.FORMAT_RGBAF)
	image.fill(Color(0,0,0,1))
	for z in [27,28]:
		for x in [31,32]: image.set_pixel(x,z,Color(100,0,0,1))
	var original := image.get_data()
	var texture := ImageTexture.create_from_image(image)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/low_air.gdshader")
	material.set_shader_parameter("air_map", texture)
	material.set_shader_parameter("edge_fade", false)
	material.set_shader_parameter("visual_time", (PI * 0.5 - 15) / 1.1)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5,5)
	mesh.mesh = plane
	mesh.material_override = material
	viewport.add_child(mesh)
	await process_frame
	await RenderingServer.frame_post_draw
	var rounded := viewport.get_texture().get_image()
	var modern := radii(rounded)
	check(modern.min() > 0 and modern.max()/modern.min() < 1.10, "Concentrated moisture has a near-circular GPU footprint")
	var legacy := Shader.new()
	legacy.code = material.shader.code.replace("vec2(moisture_at(map_uv), texture(air_map, map_uv).g)", "texture(air_map, map_uv).rg")
	material.shader = legacy
	await process_frame
	await RenderingServer.frame_post_draw
	var square := viewport.get_texture().get_image()
	var old := radii(square)
	check(modern.max()/modern.min() < old.max()/old.min(), "Radial reconstruction reduces the old square-grid outline")
	check(texture.get_image().get_data() == original, "Display reconstruction leaves authoritative wet grid bytes unchanged")
	if "--capture" in OS.get_cmdline_user_args():
		rounded.save_png("res://.godot/moisture-round.png")
		square.save_png("res://.godot/moisture-bilinear.png")
	print("MOISTURE SURFACE: ", checks, " checks, ", failures, " failures; new radius=", modern.min(), "–", modern.max(), "; old=", old.min(), "–", old.max())
	viewport.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
