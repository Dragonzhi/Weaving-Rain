extends Node3D
const Sim = preload("res://scripts/weather_simulation.gd")
const CLOUD_SHADER = preload("res://shaders/cloud.gdshader")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const OCEAN_SHADER = preload("res://shaders/ocean.gdshader")
const VAPOR_COUNT := 620
const RAIN_COUNT := 750
const LIFT_COUNT := 120

var sim: RefCounted
var camera: Camera3D
var image: Image
var water_texture: ImageTexture
var cloud_material: ShaderMaterial
var vapor: MultiMesh
var rainfall: MultiMesh
var ascent: MultiMesh
var vapor_positions := PackedVector2Array()
var lift_positions := PackedVector3Array()
var lift_age := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var plot_material: StandardMaterial3D

func setup(model: RefCounted) -> void:
	sim = model
	rng.seed = 44721
	image = Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	water_texture = ImageTexture.create_from_image(image)
	update_map()
	_create_scene()
	_create_weather()
	reset_tracers()

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = color
	return result

func _mesh_instance(mesh: Mesh, material: Material, point := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = point
	add_child(instance)
	return instance

func _terrain_material(color: Color, shore: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("shore", shore)
	material.set_shader_parameter("water_map", water_texture)
	return material

func _vertex(st: SurfaceTool, p: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(p)

func _top_vertex(st: SurfaceTool, p: Vector2, height: float) -> void:
	var slope := Sim.slope(p)
	_vertex(st, Vector3(p.x, height, p.y), Vector3(-slope.x, 1.0, -slope.y).normalized())

func _island_point(angle: float, radius: float) -> Vector2:
	return Vector2(-0.6, 0.3) + Vector2(cos(angle) * 8.5, sin(angle) * 5.5) * Sim.coast_radius(angle) * radius

func _create_scene() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("58aab1")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.2
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(11.0, 15.0, 18.0)
	add_child(camera)
	camera.look_at(Vector3(-0.7, 0.8, 0.0))
	camera.current = true
	var ocean_mesh := PlaneMesh.new()
	ocean_mesh.size = Vector2(120.0, 120.0)
	var ocean_material := ShaderMaterial.new()
	ocean_material.shader = OCEAN_SHADER
	_mesh_instance(ocean_mesh, ocean_material, Vector3(0, -0.08, 0))
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 32:
		for segment in 96:
			var a := float(segment) / 96.0 * TAU
			var b := float(segment + 1) / 96.0 * TAU
			var r0 := float(ring) / 32.0
			var r1 := float(ring + 1) / 32.0
			var p0 := _island_point(a, r0)
			var p1 := _island_point(b, r0)
			var p2 := _island_point(a, r1)
			var p3 := _island_point(b, r1)
			for p in [p0, p2, p1, p1, p2, p3]:
				_top_vertex(top, p, maxf(0.22, Sim.terrain_height(p)))
	top.index()
	_mesh_instance(top.commit(), _terrain_material(Color("9bbb83")))
	var shore := SurfaceTool.new()
	shore.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 96:
		var a := float(segment) / 96.0 * TAU
		var b := float(segment + 1) / 96.0 * TAU
		var p0 := _island_point(a, 1.0)
		var p1 := _island_point(b, 1.0)
		var p2 := _island_point(a, 1.045)
		var p3 := _island_point(b, 1.045)
		var v0 := Vector3(p0.x, 0.22, p0.y)
		var v1 := Vector3(p1.x, 0.22, p1.y)
		var v2 := Vector3(p2.x, 0.0, p2.y)
		var v3 := Vector3(p3.x, 0.0, p3.y)
		for p in [v0, v2, v1, v1, v2, v3]:
			_vertex(shore, p, Vector3.UP)
		var normal := Vector3(cos((a + b) * 0.5), 0, sin((a + b) * 0.5))
		for p in [v2, v2 - Vector3.UP * 0.65, v3, v3, v2 - Vector3.UP * 0.65, v3 - Vector3.UP * 0.65]:
			_vertex(shore, p, normal)
	_mesh_instance(shore.commit(), _terrain_material(Color("e5d6a4"), true))
	_create_river()
	var plot_mesh := BoxMesh.new()
	plot_mesh.size = Vector3(Sim.PLOT_HALF * 2.0, 0.035, Sim.PLOT_HALF * 2.0)
	plot_material = _material(Color("bf936b"))
	_mesh_instance(plot_mesh, plot_material, Vector3(Sim.PLOT.x, 0.255, Sim.PLOT.y))
	for row in 3:
		for column in 3:
			var point := Vector3(Sim.PLOT.x - 0.75 + column * 0.75, 0.29, Sim.PLOT.y - 0.75 + row * 0.75)
			var stem := CylinderMesh.new()
			stem.top_radius = 0.024
			stem.bottom_radius = 0.024
			stem.height = 0.18
			stem.radial_segments = 5
			_mesh_instance(stem, _material(Color("4e8060")), point + Vector3.UP * 0.09)
			var leaf := SphereMesh.new()
			leaf.radius = 0.10
			leaf.height = 0.10
			leaf.radial_segments = 8
			leaf.rings = 3
			var plant := _mesh_instance(leaf, _material(Color("578563")), point + Vector3(0.06, 0.17, 0))
			plant.scale = Vector3(1.0, 1.0, 0.5)
	for p in [Vector2(-5.4, -1.6), Vector2(-3.8, 3.2), Vector2(5.7, -1.8), Vector2(1.2, -3.7)]:
		var rock := SphereMesh.new()
		rock.radius = 0.23
		rock.height = 0.38
		rock.radial_segments = 6
		rock.rings = 3
		_mesh_instance(rock, _terrain_material(Color("6f917c")), Vector3(p.x, Sim.terrain_height(p) + 0.09, p.y))

func _create_river() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 70:
		var t0 := float(i) / 70.0
		var t1 := float(i + 1) / 70.0
		var p0 := Vector2(-1.0 + t0 * 8.0, -1.0 + t0 * 3.8 + sin(t0 * 9.0) * 0.45)
		var p1 := Vector2(-1.0 + t1 * 8.0, -1.0 + t1 * 3.8 + sin(t1 * 9.0) * 0.45)
		var side := Vector2(-(p1 - p0).y, (p1 - p0).x).normalized() * 0.13
		for p in [p0 - side, p1 - side, p0 + side, p1 - side, p1 + side, p0 + side]:
			_vertex(st, Vector3(p.x, Sim.terrain_height(p) + 0.022, p.y), Vector3.UP)
	_mesh_instance(st.commit(), _material(Color("72ccd0")))

func _multimesh(count: int, mesh: Mesh, color: Color) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.instance_count = count
	multi.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-13, -1, -11), Vector3(26, 8, 22))
	add_child(node)
	return multi

func _create_weather() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(24, Sim.CLOUD_TOP - Sim.CLOUD_BOTTOM, 20)
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	cloud_material.set_shader_parameter("water_map", water_texture)
	cloud_material.set_shader_parameter("threshold", sim.settings.cloud_threshold)
	cloud_material.set_shader_parameter("ray_direction", -camera.global_basis.z)
	var clouds := _mesh_instance(box, cloud_material, Vector3(0, (Sim.CLOUD_TOP + Sim.CLOUD_BOTTOM) * 0.5, 0))
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	dot.radial_segments = 6
	dot.rings = 3
	vapor = _multimesh(VAPOR_COUNT, dot, Color("95f2e7"))
	ascent = _multimesh(LIFT_COUNT, dot, Color("bcfff0"))
	var drop := BoxMesh.new()
	drop.size = Vector3(0.018, 0.22, 0.018)
	rainfall = _multimesh(RAIN_COUNT, drop, Color("a6e3e8"))
	for i in LIFT_COUNT:
		lift_positions.append(Vector3.ZERO)
		lift_age.append(-1.0)

func reset_tracers() -> void:
	rng.seed = 44721
	vapor_positions.resize(VAPOR_COUNT)
	for i in VAPOR_COUNT:
		vapor_positions[i] = Vector2(rng.randf_range(-10.5, 5.0), rng.randf_range(-6.0, 7.0))
	for i in LIFT_COUNT:
		lift_age[i] = -1.0
	elapsed = 0.0

func update_map() -> void:
	for i in Sim.COUNT:
		var q: float = sim.display_cloud[i]
		var progress: float = sim.display_charge[i] / maxf(q * sim.settings.hold_seconds, 0.0001)
		image.set_pixel(i % Sim.WIDTH, floori(float(i) / Sim.WIDTH), Color(q, sim.display_rain[i], progress, sim.humidity[i]))
	water_texture.update(image)

func _transform(point: Vector3, scale: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * scale), point)

func update_weather(dt: float, moving: bool) -> void:
	if moving:
		elapsed += dt
	update_map()
	for i in VAPOR_COUNT:
		var p := vapor_positions[i]
		var cell := Vector2i(((p - Sim.ORIGIN) / Sim.CELL).floor())
		var index := clampi(cell.y, 0, Sim.DEPTH - 1) * Sim.WIDTH + clampi(cell.x, 0, Sim.WIDTH - 1)
		if moving:
			p += sim.wind[index] * dt
			vapor_positions[i] = p
		var moisture: float = sim.sample(sim.humidity, p)
		var visible_scale := clampf(moisture * 0.8, 0.0, 1.25)
		if not Sim.contains(p) or moisture < 0.035:
			visible_scale = 0.0
			if moving:
				vapor_positions[i] = Vector2(rng.randf_range(-10.5, 5.0), rng.randf_range(-6.0, 7.0))
		var y := Sim.terrain_height(p) + 0.30 + 0.06 * sin(elapsed * 1.1 + i * 1.7)
		vapor.set_instance_transform(i, _transform(Vector3(p.x, y, p.y), visible_scale))
	if moving and sim.last_lift > 0.001:
		for attempt in 8:
			var index := rng.randi_range(0, Sim.COUNT - 1)
			if sim.lifted[index] > 0.001:
				for i in LIFT_COUNT:
					if lift_age[i] < 0.0:
						var p: Vector2 = sim.positions[index]
						lift_positions[i] = Vector3(p.x, Sim.terrain_height(p) + 0.35, p.y)
						lift_age[i] = 0.0
						break
	for i in LIFT_COUNT:
		if lift_age[i] >= 0.0 and moving:
			lift_age[i] += dt
			lift_positions[i].y += dt * 1.8
			if lift_positions[i].y > Sim.CLOUD_HEIGHT:
				lift_age[i] = -1.0
		ascent.set_instance_transform(i, _transform(lift_positions[i], 1.1 if lift_age[i] >= 0.0 else 0.0))
	# Draw rain inside its simulated cell, so strokes and credited ground area agree.
	var count := 0
	for i in Sim.COUNT:
		if sim.rain[i] <= 0.0:
			continue
		var p: Vector2 = sim.positions[i]
		var drops := clampi(ceili(sim.rain[i] * 5.0), 1, 9)
		for j in drops:
			if count >= RAIN_COUNT:
				break
			var x := p.x + sin(i * 37.1 + j * 17.7) * 0.20
			var z := p.y + sin(i * 13.7 + j * 28.9) * 0.20
			var floor_y := Sim.terrain_height(Vector2(x, z)) + 0.15
			var phase := fposmod(i * 0.19 + j * 0.37 - elapsed * 1.8, 1.0)
			var y := lerpf(floor_y, Sim.CLOUD_HEIGHT - 0.15, phase)
			rainfall.set_instance_transform(count, _transform(Vector3(x, y, z), 1.0))
			count += 1
	rainfall.visible_instance_count = count
	var water: float = clampf(sim.plot_water / sim.settings.target_water, 0.0, 1.0)
	plot_material.albedo_color = Color("bf936e").lerp(Color("8eaa78"), water)
	if sim.outcome == "flood":
		plot_material.albedo_color = Color("718e95")
