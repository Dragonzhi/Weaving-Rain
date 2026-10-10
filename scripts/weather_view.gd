extends Node3D
const Sim = preload("res://scripts/weather_simulation.gd")
const CLOUD_SHADER = preload("res://shaders/cloud.gdshader")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const OCEAN_SHADER = preload("res://shaders/ocean.gdshader")
const AIR_SHADER = preload("res://shaders/low_air.gdshader")
const RAIN_SHADER = preload("res://shaders/rain.gdshader")
const VAPOR_COUNT := 210
const RAIN_COUNT := 750
const LIFT_COUNT := 120

var sim: Sim
var camera: Camera3D
var image: Image
var water_texture: ImageTexture
var cloud_material: ShaderMaterial
var rainfall: MultiMesh
var ascent: MultiMesh
var vapor_positions := PackedVector2Array()
var lift_positions := PackedVector3Array()
var lift_age := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var plot_material: StandardMaterial3D
var plot_materials: Array[StandardMaterial3D] = []
var air_image: Image
var air_texture: ImageTexture
var lines := ArrayMesh.new()
var line_vertices := PackedVector3Array()
var line_colors := PackedColorArray()
var line_node: MeshInstance3D
var line_material: StandardMaterial3D
var wind_traces: Array[Dictionary] = []
var visible_wind_lines := 0
var wind_spawn_distance := 0.0
var rain_material: ShaderMaterial
var rain_indices := PackedInt32Array()
var rain_drop_counts := PackedInt32Array()
var rain_anchors := PackedVector3Array()
var rain_phases := PackedFloat32Array()
var rain_uploads := 0
var air_material: ShaderMaterial
var map_data := PackedFloat32Array()
var air_data := PackedFloat32Array()
var map_revision := -1
var rain_revision := -1
var line_revision := -1
var line_dirty := true
var ribbon_vertices := PackedVector3Array()
var ribbon_colors := PackedColorArray()
var line_cursor := 0
var ribbon_points := PackedVector3Array()

func setup(model: RefCounted) -> void:
	sim = model
	ribbon_points.resize(4)
	rng.seed = 44721
	image = Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	water_texture = ImageTexture.create_from_image(image)
	air_image = Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	air_texture = ImageTexture.create_from_image(air_image)
	update_map()
	_create_scene()
	_create_weather()
	rain_drop_counts.resize(Sim.COUNT)
	for i in Sim.COUNT:
		for j in 9:
			var p: Vector2 = sim.positions[i]
			var x := p.x + sin(i * 37.1 + j * 17.7) * 0.20
			var z := p.y + sin(i * 13.7 + j * 28.9) * 0.20
			rain_anchors.append(Vector3(x, sim.terrain.height(Vector2(x, z)) + 0.15, z))
			rain_phases.append(fposmod(i * 0.19 + j * 0.37, 1.0))
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
	var slope: Vector2 = sim.terrain.slope(p)
	_vertex(st, Vector3(p.x, height, p.y), Vector3(-slope.x, 1.0, -slope.y).normalized())

func _island_point(angle: float, radius: float) -> Vector2:
	return sim.terrain.island_point(angle, radius)

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
				_top_vertex(top, p, maxf(0.22, sim.terrain.height(p)))
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
	for target in sim.plot_centers:
		_create_plot(target)
	plot_material = plot_materials[0]
	for p in [Vector2(-5.4, -1.6), Vector2(-3.8, 3.2), Vector2(5.7, -1.8), Vector2(1.2, -3.7)]:
		if not sim.terrain.is_land(p): continue
		var near_plot := false
		for plot in sim.plot_centers:
			near_plot = near_plot or p.distance_to(plot) < Sim.PLOT_HALF * 1.5
		if near_plot: continue
		var rock := SphereMesh.new()
		rock.radius = 0.23
		rock.height = 0.38
		rock.radial_segments = 6
		rock.rings = 3
		_mesh_instance(rock, _terrain_material(Color("6f917c")), Vector3(p.x, sim.terrain.height(p) + 0.09, p.y))

func _create_plot(center: Vector2) -> void:
	var plot_mesh := BoxMesh.new()
	plot_mesh.size = Vector3(Sim.PLOT_HALF * 2.0, 0.035, Sim.PLOT_HALF * 2.0)
	var material := _material(Color("bf936b"))
	plot_materials.append(material)
	_mesh_instance(plot_mesh, material, Vector3(center.x, 0.255, center.y))
	for row in 3:
		for column in 3:
			var point := Vector3(center.x - 0.75 + column * 0.75, 0.29, center.y - 0.75 + row * 0.75)
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

func _create_river() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 70:
		var t0 := float(i) / 70.0
		var t1 := float(i + 1) / 70.0
		var p0: Vector2 = sim.terrain.river_point(t0)
		var p1: Vector2 = sim.terrain.river_point(t1)
		var side := Vector2(-(p1 - p0).y, (p1 - p0).x).normalized() * 0.13
		for p in [p0 - side, p1 - side, p0 + side, p1 - side, p1 + side, p0 + side]:
			_vertex(st, Vector3(p.x, sim.terrain.height(p) + 0.022, p.y), Vector3.UP)
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
	var lift_mesh := BoxMesh.new()
	lift_mesh.size = Vector3(0.014, 0.16, 0.014)
	ascent = _multimesh(LIFT_COUNT, lift_mesh, Color("d8f4dd"))
	_create_low_air()
	line_material = _material(Color.WHITE)
	line_material.vertex_color_use_as_albedo = true
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_node = _mesh_instance(lines, line_material)
	line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drop := BoxMesh.new()
	drop.size = Vector3(0.018, 0.22, 0.018)
	rainfall = MultiMesh.new()
	rainfall.transform_format = MultiMesh.TRANSFORM_3D
	rainfall.use_custom_data = true
	rainfall.instance_count = RAIN_COUNT
	rainfall.visible_instance_count = 0
	rainfall.mesh = drop
	rain_material = ShaderMaterial.new()
	rain_material.shader = RAIN_SHADER
	rain_material.set_shader_parameter("rain_color", Color("a6e3e8"))
	var rain_node := MultiMeshInstance3D.new()
	rain_node.multimesh = rainfall
	rain_node.material_override = rain_material
	rain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_node.custom_aabb = AABB(Vector3(-13, -1, -11), Vector3(26, 8, 22))
	add_child(rain_node)
	for i in LIFT_COUNT:
		lift_positions.append(Vector3.ZERO)
		lift_age.append(-1.0)

func reset_tracers() -> void:
	line_dirty = true
	rng.seed = 44721
	vapor_positions.resize(VAPOR_COUNT)
	for i in VAPOR_COUNT:
		vapor_positions[i] = Vector2(rng.randf_range(-10.5, 5.0), rng.randf_range(-6.0, 7.0))
	for i in LIFT_COUNT:
		lift_age[i] = -1.0
	elapsed = 0.0
	wind_traces.clear()
	lines.clear_surfaces()
	visible_wind_lines = 0
	wind_spawn_distance = 0.0
	rain_indices.resize(0)
	rainfall.visible_instance_count = 0

func _create_low_air() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in Sim.DEPTH:
		for x in Sim.WIDTH:
			var p := Sim.ORIGIN + Vector2(x, z) * Sim.CELL
			for offset in [Vector2.ZERO, Vector2(0, Sim.CELL), Vector2(Sim.CELL, 0), Vector2(Sim.CELL, 0), Vector2(0, Sim.CELL), Vector2.ONE * Sim.CELL]:
				var q: Vector2 = p + offset
				_vertex(mesh, Vector3(q.x, sim.terrain.height(q) + 0.20, q.y), Vector3.UP)
	air_material = ShaderMaterial.new()
	air_material.shader = AIR_SHADER
	air_material.set_shader_parameter("air_map", air_texture)
	var air := _mesh_instance(mesh.commit(), air_material)
	air.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func add_wind_stroke(from: Vector2, to: Vector2, height: float) -> void:
	line_dirty = true
	wind_spawn_distance += from.distance_to(to)
	if wind_spawn_distance < 0.20:
		return
	var count := clampi(ceili(wind_spawn_distance / 0.42), 1, 5)
	wind_spawn_distance = 0.0
	for i in count:
		var p := from.lerp(to, (i + 0.5) / count)
		var side := (to - from).orthogonal().normalized()
		p += side * rng.randf_range(-0.75, 0.75)
		wind_traces.append({"p": p, "height": height, "low": height < Sim.CLOUD_BOTTOM, "age": 0.0})
	while wind_traces.size() > 48:
		wind_traces.pop_front()

func _ribbon(center: Vector2, velocity: Vector2, height: float, low: bool, color: Color, width: float, length: float, segments: int = 3) -> void:
	var direction := velocity.normalized() if velocity.length() > 0.025 else Vector2.RIGHT
	var p := center
	for k in segments + 1:
		var y: float = sim.terrain.height(p) + height if low else maxf(height, sim.terrain.height(p) + 0.10)
		ribbon_points[k] = Vector3(p.x, y, p.y)
		if k == segments: break
		var v: Vector2 = velocity if k == 0 else sim.velocity_at(p, low)
		if v.length() > 0.025:
			direction = v.normalized()
		p -= direction * length / segments
	for k in segments:
		var tangent := (ribbon_points[k + 1] - ribbon_points[k]).normalized()
		var side := tangent.cross(camera.global_basis.z).normalized() * width
		var a := color
		var b := color
		a.a *= sin((k + 0.5) / (segments + 1.0) * PI)
		b.a *= sin((k + 1.5) / (segments + 1.0) * PI)
		ribbon_vertices[line_cursor] = ribbon_points[k] - side
		ribbon_vertices[line_cursor + 1] = ribbon_points[k] + side
		ribbon_vertices[line_cursor + 2] = ribbon_points[k + 1] - side
		ribbon_vertices[line_cursor + 3] = ribbon_points[k + 1] - side
		ribbon_vertices[line_cursor + 4] = ribbon_points[k] + side
		ribbon_vertices[line_cursor + 5] = ribbon_points[k + 1] + side
		ribbon_colors[line_cursor] = a
		ribbon_colors[line_cursor + 1] = a
		ribbon_colors[line_cursor + 2] = b
		ribbon_colors[line_cursor + 3] = b
		ribbon_colors[line_cursor + 4] = a
		ribbon_colors[line_cursor + 5] = b
		line_cursor += 6

func _update_lines(dt: float, moving: bool) -> void:
	lines.clear_surfaces()
	line_vertices.resize(0)
	line_colors.resize(0)
	ribbon_vertices.resize((VAPOR_COUNT + 96 + 48 * 3) * 6)
	ribbon_colors.resize(ribbon_vertices.size())
	line_cursor = 0
	visible_wind_lines = 0
	for i in VAPOR_COUNT:
		var p := vapor_positions[i]
		var velocity: Vector2 = sim.velocity_at(p)
		if moving:
			p += velocity * dt
			vapor_positions[i] = p
		var q: float = sim.sample(sim.humidity, p)
		if not Sim.contains(p) or q < 0.06:
			if moving:
				vapor_positions[i] = Vector2(rng.randf_range(-10.5, 8.0), rng.randf_range(-6.0, 7.0))
			continue
		var phase := elapsed * 1.1 + i * 1.7
		var opacity := clampf(q * 0.32, 0.0, 0.70) * (0.82 + 0.18 * sin(phase))
		# Local bobbing makes still moisture discoverable without inventing horizontal wind.
		_ribbon(p, velocity, 0.33 + 0.08 * sin(phase), true, Color(0.91, 0.98, 0.85, opacity), 0.011, 0.16 + minf(velocity.length(), 4.0) * 0.13, 1)
	var front_cells := PackedInt32Array()
	for i in range(0, Sim.COUNT, 5):
		if sim.display_cold[i] < 0.12 or sim.cold_gradient(i).length() < 0.04:
			continue
		front_cells.append(i)
	# Cap passive front annotations across the whole field; active strokes stay curved.
	var stride := maxi(1, ceili(front_cells.size() / 96.0))
	for index in range(0, front_cells.size(), stride):
		var i := front_cells[index]
		var p: Vector2 = sim.positions[i]
		var velocity: Vector2 = sim.velocity_at(p)
		if velocity.length() < 0.04:
			continue
		_ribbon(p, velocity, 0.26, true, Color(0.55, 0.80, 0.93, minf(sim.display_cold[i] * 0.40, 0.65)), 0.010, 0.16 + velocity.length() * 0.17, 1)
	for i in range(wind_traces.size() - 1, -1, -1):
		var trace := wind_traces[i]
		var p: Vector2 = trace.p
		var velocity: Vector2 = sim.velocity_at(p, trace.low)
		if moving:
			trace.age += dt
			trace.p = p + velocity * dt
		if trace.age > 2.4 or not Sim.contains(p):
			wind_traces.remove_at(i)
			continue
		var alpha := minf(velocity.length() / 2.0, 0.85) * maxf(0.0, 1.0 - trace.age / 2.4)
		if alpha < 0.015:
			continue
		var height: float = 0.37 if trace.low else trace.height
		_ribbon(p, velocity, height, trace.low, Color(0.98, 0.99, 0.89, alpha), 0.015, 0.16 + minf(velocity.length(), 5.0) * 0.18)
		visible_wind_lines += 1
	line_vertices = ribbon_vertices.slice(0, line_cursor)
	line_colors = ribbon_colors.slice(0, line_cursor)
	if not line_vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = line_vertices
		arrays[Mesh.ARRAY_COLOR] = line_colors
		lines.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func update_map() -> void:
	map_data.resize(Sim.COUNT * 4)
	air_data.resize(Sim.COUNT * 4)
	var cloud: PackedFloat32Array = sim.display_cloud
	var rain: PackedFloat32Array = sim.display_rain
	var charge: PackedFloat32Array = sim.display_charge
	var humidity: PackedFloat32Array = sim.humidity
	var cold: PackedFloat32Array = sim.display_cold
	var hold: float = sim.settings.hold_seconds
	for i in Sim.COUNT:
		var q := cloud[i]
		var progress := charge[i] / maxf(q * hold, 0.0001)
		var offset := i * 4
		map_data[offset] = q
		map_data[offset + 1] = rain[i]
		map_data[offset + 2] = progress
		map_data[offset + 3] = humidity[i]
		air_data[offset] = humidity[i]
		air_data[offset + 1] = cold[i]
		air_data[offset + 3] = 1.0
	image.set_data(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF, map_data.to_byte_array())
	air_image.set_data(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF, air_data.to_byte_array())
	water_texture.update(image)
	air_texture.update(air_image)
	map_revision = sim.revision

func _transform(point: Vector3, scale: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * scale), point)

func update_weather(dt: float, moving: bool) -> void:
	if moving:
		elapsed += dt
	if map_revision != sim.revision:
		update_map()
	air_material.set_shader_parameter("visual_time", elapsed)
	if moving or line_dirty or line_revision != sim.revision:
		_update_lines(dt, moving)
		line_revision = sim.revision
		line_dirty = false
	if moving and sim.last_lift > 0.001:
		for attempt in 8:
			var index := rng.randi_range(0, Sim.COUNT - 1)
			if sim.lifted[index] > 0.001:
				for i in LIFT_COUNT:
					if lift_age[i] < 0.0:
						var p: Vector2 = sim.positions[index]
						lift_positions[i] = Vector3(p.x, sim.terrain.height(p) + 0.35, p.y)
						lift_age[i] = 0.0
						break
	for i in LIFT_COUNT:
		if lift_age[i] >= 0.0 and moving:
			lift_age[i] += dt
			lift_positions[i].y += dt * 1.8
			if lift_positions[i].y > Sim.CLOUD_HEIGHT:
				lift_age[i] = -1.0
		ascent.set_instance_transform(i, _transform(lift_positions[i], 1.1 if lift_age[i] >= 0.0 else 0.0))
	if rain_revision != sim.revision:
		_update_rain()
		rain_revision = sim.revision
	rain_material.set_shader_parameter("visual_time", elapsed)
	for target in plot_materials.size():
		var water: float = clampf(sim.water_for(target) / sim.settings.target_water, 0.0, 1.0)
		plot_materials[target].albedo_color = Color("bf936e").lerp(Color("8eaa78"), water)
		if sim.water_for(target) > sim.settings.flood_water:
			plot_materials[target].albedo_color = Color("718e95")

func _update_rain() -> void:
	var total := 0
	var rain: PackedFloat32Array = sim.rain
	for i in Sim.COUNT:
		rain_drop_counts[i] = clampi(ceili(rain[i] * 5.0), 1, 9) if rain[i] > 0.0 else 0
		total += rain_drop_counts[i]
	var count := mini(total, RAIN_COUNT)
	var selected := PackedInt32Array()
	selected.resize(count)
	# Spread the capped display budget over the whole actual rainy area.
	var ordinal := 0
	var chosen := 0
	for i in Sim.COUNT:
		while chosen < count:
			var target := floori((chosen + 0.5) * total / count)
			if target >= ordinal + rain_drop_counts[i]:
				break
			selected[chosen] = i * 9 + target - ordinal
			chosen += 1
		ordinal += rain_drop_counts[i]
	if selected != rain_indices:
		rain_indices = selected
		var buffer := PackedFloat32Array()
		buffer.resize(RAIN_COUNT * 16)
		for index in count:
			var drop := selected[index]
			var p := rain_anchors[drop]
			var offset := index * 16
			buffer[offset] = 1.0
			buffer[offset + 3] = p.x
			buffer[offset + 5] = 1.0
			buffer[offset + 7] = p.y
			buffer[offset + 10] = 1.0
			buffer[offset + 11] = p.z
			buffer[offset + 12] = rain_phases[drop]
			buffer[offset + 13] = Sim.CLOUD_HEIGHT - 0.15 - p.y
		rainfall.buffer = buffer
		rain_uploads += 1
	rainfall.visible_instance_count = count
	rain_material.set_shader_parameter("visual_time", elapsed)
