extends Node3D
const Sim = preload("res://scripts/weather_simulation.gd")
const CLOUD_SHADER = preload("res://shaders/cloud.gdshader")
const CLOUD_BOUNDS_SHADER = preload("res://shaders/cloud_bounds.gdshader")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const OCEAN_SHADER = preload("res://shaders/ocean.gdshader")
const AIR_SHADER = preload("res://shaders/low_air.gdshader")
const RAIN_SHADER = preload("res://shaders/rain.gdshader")
const ARROW_SHADER = preload("res://shaders/weather_arrows.gdshader")
const RainArea = preload("res://scripts/rain_area_view.gd")
const SceneStyle = preload("res://scripts/scene_style.gd")
const CONTACT_SHADER = preload("res://shaders/contact_shadow.gdshader")
const VAPOR_COUNT := 210
const RAIN_COUNT := 750
const LIFT_COUNT := 120

var sim: Sim
var scene_style: SceneStyle
var style_errors := PackedStringArray()
var style_path := "res://configs/scene_style.tres"
var contact_positions: Array[Vector3] = []
var contact_radii: Array[float] = []
var terrain_shadow_texture: ImageTexture
var terrain_shadow_build_ms := 0.0
var farm_top_meshes: Array[MeshInstance3D] = []
var farm_ridge_materials: Array[ShaderMaterial] = []
var farm_side_materials: Array[ShaderMaterial] = []
var camera: Camera3D
var ocean_material := ShaderMaterial.new()
var image: Image
var water_texture: ImageTexture
var cloud_bounds_viewport: SubViewport
var cloud_material: ShaderMaterial
var rainfall: MultiMesh
var ascent: MultiMesh
var vapor_positions := PackedVector2Array()
var lift_positions := PackedVector3Array()
var lift_age := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var plot_material: ShaderMaterial
var plot_materials: Array[ShaderMaterial] = []
var plant_groups: Array[Node3D] = []
var plant_materials: Array[ShaderMaterial] = []
var plant_growth := PackedFloat32Array()
var plant_wilt := PackedFloat32Array()
var plot_wetness := PackedFloat32Array()
var reservoir_surfaces: Array[MeshInstance3D] = []
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
var source_emission: Dictionary = {}
var source_trace_serial := 0
var visible_source_lines := 0
var field_emission := 0.0
var field_line_revision := -1
var field_line_refresh := -1.0
var field_line_candidates := PackedInt32Array()
var field_line_serial := 0
var front_line_cells := PackedInt32Array()
var front_line_revision := -1
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
var ribbon_eye := Vector3.ZERO
var hints_enabled := true
var rain_area: Node3D
var arrow_mesh := ArrayMesh.new()
var arrow_material: ShaderMaterial
var arrow_instances := MultiMesh.new()
var arrow_candidates: Array[Dictionary] = []
var arrow_refresh := -1.0
var interaction_point := Vector2.ZERO
var interaction_until := -1.0
var visible_arrows := 0
const WET_ARROW := Color("ef987f")
const COLD_ARROW := Color("78b8d8")
const CLOUD_ARROW := Color("e6f1ed")
const LIFT_ARROW := Color("e7c77a")

func setup(model: RefCounted) -> void:
	sim = model
	var loaded := preload("res://scripts/config_loader.gd").scene_style(style_path)
	scene_style = loaded.resource
	style_errors = loaded.errors
	if not style_errors.is_empty(): print("SCENE STYLE retained: ", "；".join(style_errors))
	var shadow_start := Time.get_ticks_usec()
	terrain_shadow_texture = ImageTexture.create_from_image(preload("res://scripts/terrain_shadow.gd").build(sim.terrain,scene_style.light_direction))
	terrain_shadow_build_ms = (Time.get_ticks_usec()-shadow_start)/1000.0
	ocean_material.shader = OCEAN_SHADER
	ribbon_points.resize(4)
	rng.seed = 44721
	image = Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	water_texture = ImageTexture.create_from_image(image)
	cloud_bounds_viewport = SubViewport.new()
	cloud_bounds_viewport.size = Vector2i(Sim.WIDTH, Sim.DEPTH)
	cloud_bounds_viewport.disable_3d = true
	cloud_bounds_viewport.use_hdr_2d = true
	add_child(cloud_bounds_viewport)
	var bounds_material := ShaderMaterial.new()
	bounds_material.shader = CLOUD_BOUNDS_SHADER
	bounds_material.set_shader_parameter("water_map", water_texture)
	var bounds_rect := ColorRect.new()
	bounds_rect.size = cloud_bounds_viewport.size
	bounds_rect.material = bounds_material
	cloud_bounds_viewport.add_child(bounds_rect)
	air_image = Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	air_texture = ImageTexture.create_from_image(air_image)
	update_map()
	ocean_material.set_shader_parameter("water_map",water_texture)
	ocean_material.set_shader_parameter("edge_fade",sim.settings.open_boundary)
	scene_style.apply(ocean_material)
	_create_scene()
	_create_weather()
	rain_area = RainArea.new()
	add_child(rain_area)
	rain_area.setup(sim, camera)
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
	material.set_shader_parameter("edge_fade", sim.settings.open_boundary)
	material.set_shader_parameter("terrain_shadow_map",terrain_shadow_texture)
	material.set_shader_parameter("terrain_shadow_enabled",true)
	scene_style.apply(material)
	return material

func _scene_material(color: Color) -> ShaderMaterial:
	var material := _terrain_material(color)
	material.set_shader_parameter("ground_material",false)
	return material

func _boundary_wall(points: PackedVector2Array, low: float, high: float, inward := false) -> ArrayMesh:
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		var a := points[index]
		var b := points[(index+1)%points.size()]
		var outward := Vector2((b-a).y,-(b-a).x).normalized()
		var normal := Vector3(outward.x,0,outward.y)*(-1.0 if inward else 1.0)
		var vertices := [Vector3(a.x,low,a.y),Vector3(a.x,high,a.y),Vector3(b.x,high,b.y),Vector3(a.x,low,a.y),Vector3(b.x,high,b.y),Vector3(b.x,low,b.y)]
		# Godot front faces use clockwise winding; outward faces need the
		# reverse of the geometric cross-product orientation of this strip.
		if not inward: vertices.reverse()
		for p in vertices: _vertex(wall,p,normal)
	return wall.commit()

func _ring(outer: PackedVector2Array, inner: PackedVector2Array, low: float, high: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outer.size():
		var next := (i+1)%outer.size()
		var a := Vector3(outer[i].x,low,outer[i].y)
		var b := Vector3(outer[next].x,low,outer[next].y)
		var c := Vector3(inner[i].x,high,inner[i].y)
		var d := Vector3(inner[next].x,high,inner[next].y)
		var normal := (c-a).cross(b-a).normalized()
		for p in [a,b,c,b,d,c]: _vertex(surface,p,normal)
	return surface.commit()

func plot_display_height(target: int) -> float:
	return scene_style.reservoir_rim_height if sim.is_reservoir(target) else scene_style.farm_top_height

func display_surface_height(p: Vector2, ground_height: float = NAN) -> float:
	var height: float = sim.terrain.height(p) if is_nan(ground_height) else ground_height
	for target in sim.plot_centers.size():
		if sim.plot_regions[target].contains(p-sim.plot_centers[target],sim.plot_half):
			height = maxf(height,plot_display_height(target))
	return height

func _farm_ridges(region: WRPlotRegion, inset: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes := region.axes(sim.plot_half)*inset
	for row in 3:
		var x := (row-1)*minf(0.75,axes.x*0.5)
		var width := minf(0.11,axes.x*0.1)
		var length := axes.y*0.96
		if region.shape != "rectangle": length *= sqrt(maxf(0,1.0-pow((absf(x)+width)/axes.x,2)))
		for side in [-1.0,1.0]:
			var a := Vector3(x+side*width,0,-length)
			var b := Vector3(x+side*width,0,length)
			var c := Vector3(x,0.03,-length)
			var d := Vector3(x,0.03,length)
			var normal := Vector3(side*0.03,width,0).normalized()
			var vertices := [a,c,b,b,c,d]
			if side > 0: vertices.reverse()
			for p in vertices: _vertex(st,p,normal)
	return st.commit()

func _plant_mesh(seedling: bool) -> ArrayMesh:
	# Stem and both leaves share one surface/material and one instance per plant.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.020 if seedling else 0.025
	stem.bottom_radius = stem.top_radius
	stem.height = 0.15 if seedling else 0.21
	stem.radial_segments = 5
	st.append_from(stem,0,Transform3D(Basis.IDENTITY,Vector3.UP*stem.height*0.5))
	var leaf := SphereMesh.new()
	leaf.radius = 0.09 if seedling else 0.13
	leaf.height = 0.075 if seedling else 0.12
	leaf.radial_segments = 8
	leaf.rings = 3
	for side in [-1.0,1.0]:
		var basis := Basis(Vector3.FORWARD,side*0.4).scaled(Vector3(1,1,0.55))
		st.append_from(leaf,0,Transform3D(basis,Vector3(side*leaf.radius*0.70,stem.height*0.9,0)))
	return st.commit()

func _create_contact_shadows() -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)
	instances.mesh = plane
	instances.instance_count = contact_positions.size()
	for index in contact_positions.size():
		var radius := contact_radii[index]
		var offset := Vector3(-scene_style.light_direction.x,0,-scene_style.light_direction.z).normalized()*radius*0.35
		instances.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3(radius,1,radius*0.65)),contact_positions[index]+offset))
	var node := MultiMeshInstance3D.new()
	node.multimesh = instances
	var material := ShaderMaterial.new()
	material.shader = CONTACT_SHADER
	material.render_priority = -8
	material.set_shader_parameter("contact_shadow_strength",scene_style.contact_shadow_strength)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _plot_contact_shadow(target: int) -> void:
	var region: WRPlotRegion = sim.plot_regions[target]
	var axes := region.axes(sim.plot_half)
	var expanded := WRPlotRegion.new()
	expanded.shape = region.shape
	expanded.half_axes = axes+Vector2.ONE*0.16
	var material := ShaderMaterial.new()
	material.shader = CONTACT_SHADER
	material.render_priority = -8
	material.set_shader_parameter("plot_shadow",true)
	material.set_shader_parameter("ellipse",region.shape != "rectangle")
	# Local geometry includes the expanded outline; its inner falloff follows
	# the unexpanded actual region, independent of the receiver height.
	material.set_shader_parameter("plot_axes",axes)
	material.set_shader_parameter("contact_shadow_strength",scene_style.contact_shadow_strength)
	var center: Vector2 = sim.plot_centers[target]
	var offset := -Vector2(scene_style.light_direction.x,scene_style.light_direction.z).normalized()*0.06
	var node := _mesh_instance(expanded.mesh(sim.plot_half),material,Vector3(center.x+offset.x,0.223,center.y+offset.y))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
	_mesh_instance(top.commit(), _terrain_material(scene_style.land_color))
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
	_mesh_instance(shore.commit(), _terrain_material(scene_style.shore_color, true))
	# Small decorative water band; the simulation coastline/height field stays unchanged.
	var nearshore := SurfaceTool.new()
	nearshore.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 96:
		var a := segment*TAU/96.0
		var b := (segment+1)*TAU/96.0
		var p0 := _island_point(a,1.045)
		var p1 := _island_point(b,1.045)
		var p2 := _island_point(a,1.13)
		var p3 := _island_point(b,1.13)
		for p in [p0,p2,p1,p1,p2,p3]: _vertex(nearshore,Vector3(p.x,-0.076,p.y),Vector3.UP)
	var water_band := _scene_material(Color("72c1c5"))
	water_band.set_shader_parameter("terrain_shadow_enabled",false)
	water_band.set_shader_parameter("water_surface",true)
	_mesh_instance(nearshore.commit(),water_band)
	if sim.layout.get("river_enabled", true): _create_river()
	for target in sim.plot_centers.size():
		_create_plot(target)
	plot_material = plot_materials[0]
	for p in [Vector2(-5.4, -1.6), Vector2(-3.8, 3.2), Vector2(5.7, -1.8), Vector2(1.2, -3.7)]:
		if not sim.terrain.is_land(p): continue
		var near_plot := false
		for plot in sim.plot_centers:
			near_plot = near_plot or p.distance_to(plot) < sim.plot_half * 1.5
		if near_plot: continue
		var rock := SphereMesh.new()
		rock.radius = 0.23
		rock.height = 0.38
		rock.radial_segments = 6
		rock.rings = 3
		_mesh_instance(rock, _terrain_material(Color("6f917c")), Vector3(p.x, sim.terrain.height(p) + 0.09, p.y))
		contact_positions.append(Vector3(p.x,sim.terrain.height(p)+0.003,p.y))
		contact_radii.append(0.28)
	_create_contact_shadows()

func _create_plot(target: int) -> void:
	_plot_contact_shadow(target)
	var center: Vector2 = sim.plot_centers[target]
	var region: WRPlotRegion = sim.plot_regions[target]
	var plot_mesh := region.mesh(sim.plot_half)
	var material := _scene_material(scene_style.soil_color)
	material.set_shader_parameter("plot_center",center)
	plot_materials.append(material)
	var height := 0.255 if sim.is_reservoir(target) else scene_style.farm_top_height
	var top := _mesh_instance(plot_mesh, material, Vector3(center.x,height,center.y))
	farm_top_meshes.append(top)
	farm_ridge_materials.append(null)
	farm_side_materials.append(null)
	var group := Node3D.new()
	group.position = Vector3(center.x,height+0.03,center.y)
	add_child(group)
	plant_groups.append(group)
	var plant_material := _scene_material(Color("578563"))
	plant_materials.append(plant_material)
	plant_growth.append(0.65 if sim.plot_needs[target] != null else 1.0)
	plant_wilt.append(0.0)
	plot_wetness.append(0.0)
	reservoir_surfaces.append(null)
	if sim.is_reservoir(target):
		material.set_shader_parameter("base_color",Color("779997"))
		var outline := region.outline(sim.plot_half)
		var rim := scene_style.reservoir_rim_height
		var bevel := scene_style.bevel_width
		var axes := region.axes(sim.plot_half)
		var pool_inset := minf(0.89,1.0-1.7*bevel/minf(axes.x,axes.y))
		var rim_points := PackedVector2Array()
		var inside := PackedVector2Array()
		for p in outline:
			rim_points.append(p*(Vector2.ONE-Vector2.ONE*bevel/axes))
			inside.append(p*pool_inset)
		var origin := Vector3(center.x,0,center.y)
		var bank_material := _scene_material(scene_style.bank_color)
		_mesh_instance(_ring(outline,rim_points,rim-bevel,rim),bank_material,origin)
		_mesh_instance(_ring(rim_points,inside,rim,rim),bank_material,origin)
		_mesh_instance(_boundary_wall(outline,0.221,rim-bevel),_scene_material(scene_style.bank_color.darkened(0.08)),origin)
		_mesh_instance(_boundary_wall(inside,0.255,rim,true),_scene_material(scene_style.bank_color.darkened(0.17)),origin)
		var water_material := _scene_material(scene_style.water_color)
		water_material.set_shader_parameter("water_surface",true)
		water_material.set_shader_parameter("plot_center",center)
		var surface := _mesh_instance(region.mesh(sim.plot_half), water_material, Vector3(center.x, 0.27, center.y))
		surface.scale = Vector3(pool_inset,1,pool_inset)
		surface.visible = false
		reservoir_surfaces[target] = surface
		return
	var outline := region.outline(sim.plot_half)
	var inset := Vector2.ONE-Vector2.ONE*scene_style.bevel_width/region.axes(sim.plot_half)
	top.scale = Vector3(inset.x,1,inset.y)
	var inner := PackedVector2Array()
	for p in outline: inner.append(p*inset)
	var side_material := _scene_material(scene_style.soil_color.darkened(0.10))
	farm_side_materials[target] = side_material
	var origin := Vector3(center.x,0,center.y)
	_mesh_instance(_boundary_wall(outline,0.221,height-scene_style.bevel_width),side_material,origin)
	_mesh_instance(_ring(outline,inner,height-scene_style.bevel_width,height),material,origin)
	var ridge_material := _scene_material(scene_style.soil_color.lightened(0.04))
	farm_ridge_materials[target] = ridge_material
	_mesh_instance(_farm_ridges(region,inset),ridge_material,Vector3(center.x,height,center.y))
	var seedling: bool = sim.plot_needs[target] != null and sim.plot_needs[target].appearance == "seedling"
	var plant_mesh := _plant_mesh(seedling)
	for row in 3:
		for column in 3:
			if seedling and (row + column) % 2 != 0: continue
			var point := Vector3(center.x - 0.75 + column * 0.75,height+0.03,center.y - 0.75 + row * 0.75)
			if not region.contains(Vector2(point.x, point.z) - center, sim.plot_half): continue
			contact_positions.append(Vector3(point.x,height+0.033,point.z))
			contact_radii.append(0.13 if seedling else 0.18)
			var plant := _mesh_instance(plant_mesh,plant_material,point)
			plant.reparent(group, true)
	group.scale.y = plant_growth[target]

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
	var instance_material := _material(color)
	# Ascent marks are airborne effects; they must not become the opaque depth that
	# the ground rain projection reconstructs behind them.
	instance_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	node.material_override = instance_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-17, -1, -15), Vector3(34, 8, 30))
	add_child(node)
	return multi

func _create_weather() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(32, Sim.CLOUD_TOP - Sim.CLOUD_BOTTOM, 28)
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	cloud_material.set_shader_parameter("water_map", water_texture)
	cloud_material.set_shader_parameter("cloud_bounds", cloud_bounds_viewport.get_texture())
	cloud_material.set_shader_parameter("use_cloud_bounds", true)
	cloud_material.set_shader_parameter("edge_fade", sim.settings.open_boundary)
	cloud_material.set_shader_parameter("threshold", sim.settings.cloud_threshold)
	cloud_material.set_shader_parameter("ray_direction", -camera.global_basis.z)
	scene_style.apply(cloud_material)
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
	arrow_material = ShaderMaterial.new()
	arrow_material.shader = ARROW_SHADER
	arrow_material.set_shader_parameter("water_map", water_texture)
	arrow_material.set_shader_parameter("ray_direction", -camera.global_basis.z)
	arrow_material.set_shader_parameter("threshold", sim.settings.cloud_threshold)
	arrow_material.set_shader_parameter("edge_fade", sim.settings.open_boundary)
	var arrow_arrays := []
	arrow_arrays.resize(Mesh.ARRAY_MAX)
	arrow_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,-1,0), Vector3(0,1,0), Vector3(0.68,-1,0), Vector3(0,1,0), Vector3(0.68,1,0), Vector3(0.68,-1,0), Vector3(0.68,-3,0), Vector3(0.68,3,0), Vector3(1,0,0)])
	arrow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrow_arrays)
	arrow_instances.transform_format = MultiMesh.TRANSFORM_3D
	arrow_instances.use_colors = true
	arrow_instances.use_custom_data = true
	arrow_instances.instance_count = 32
	arrow_instances.visible_instance_count = 0
	arrow_instances.mesh = arrow_mesh
	var arrow_node := MultiMeshInstance3D.new()
	arrow_node.multimesh = arrow_instances
	arrow_node.material_override = arrow_material
	arrow_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow_node.custom_aabb = AABB(Vector3(-17, -1, -15), Vector3(34, 8, 30))
	add_child(arrow_node)
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
	rain_material.render_priority = -10
	rain_material.set_shader_parameter("water_map", water_texture)
	rain_material.set_shader_parameter("threshold", sim.settings.cloud_threshold)
	rain_material.set_shader_parameter("ray_direction", -camera.global_basis.z)
	rain_material.set_shader_parameter("edge_fade", sim.settings.open_boundary)
	rain_material.set_shader_parameter("rain_color", Color("a6e3e8"))
	var rain_node := MultiMeshInstance3D.new()
	rain_node.multimesh = rainfall
	rain_node.material_override = rain_material
	rain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_node.custom_aabb = AABB(Vector3(-17, -1, -15), Vector3(34, 8, 30))
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
	source_emission.clear()
	source_trace_serial = 0
	visible_source_lines = 0
	field_emission = 0.0
	field_line_revision = -1
	field_line_refresh = -1.0
	field_line_candidates.clear()
	field_line_serial = 0
	front_line_revision = -1
	lines.clear_surfaces()
	visible_wind_lines = 0
	wind_spawn_distance = 0.0
	arrow_candidates.clear()
	arrow_refresh = -1.0
	interaction_until = -1.0
	arrow_instances.visible_instance_count = 0
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
	air_material.set_shader_parameter("edge_fade", sim.settings.open_boundary)
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
	var vertices := ribbon_vertices
	var colors := ribbon_colors
	var points := ribbon_points
	var eye := ribbon_eye
	var direction := velocity.normalized() if velocity.length() > 0.025 else Vector2.RIGHT
	var p := center
	for k in segments + 1:
		var y := height
		if low:
			var ground: float = sim.terrain.height(p)
			y = maxf(height+ground,display_surface_height(p,ground)+0.08)
		elif height < sim.terrain.maximum_height + 0.10:
			y = maxf(height, sim.terrain.height(p) + 0.10)
		points[k] = Vector3(p.x, y, p.y)
		if k == segments: break
		var v: Vector2 = velocity if k == 0 else sim.velocity_at(p, low)
		if v.length() > 0.025:
			direction = v.normalized()
		p -= direction * length / segments
	for k in segments:
		var tangent := (points[k + 1] - points[k]).normalized()
		var side := tangent.cross(eye).normalized() * width
		var a := color
		var b := color
		a.a *= sin((k + 0.5) / (segments + 1.0) * PI)
		b.a *= sin((k + 1.5) / (segments + 1.0) * PI)
		vertices[line_cursor] = points[k] - side
		vertices[line_cursor + 1] = points[k] + side
		vertices[line_cursor + 2] = points[k + 1] - side
		vertices[line_cursor + 3] = points[k + 1] - side
		vertices[line_cursor + 4] = points[k] + side
		vertices[line_cursor + 5] = points[k + 1] + side
		colors[line_cursor] = a
		colors[line_cursor + 1] = a
		colors[line_cursor + 2] = b
		colors[line_cursor + 3] = b
		colors[line_cursor + 4] = a
		colors[line_cursor + 5] = b
		line_cursor += 6

func _update_lines(dt: float, moving: bool) -> void:
	if moving:
		_emit_source_lines(dt)
		_emit_field_lines(dt)
	ribbon_eye = camera.global_basis.z
	lines.clear_surfaces()
	line_vertices.resize(0)
	line_colors.resize(0)
	ribbon_vertices.resize((VAPOR_COUNT + 96 + 48 * 3) * 6)
	ribbon_colors.resize(ribbon_vertices.size())
	line_cursor = 0
	visible_wind_lines = 0
	visible_source_lines = 0
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
		var opacity := clampf(q * 0.32, 0.0, 0.70) * sim.edge_visibility(p) * (0.82 + 0.18 * sin(phase))
		# Local bobbing makes still moisture discoverable without inventing horizontal wind.
		_ribbon(p, velocity, 0.33 + 0.08 * sin(phase), true, Color(0.91, 0.98, 0.85, opacity), 0.011, 0.16 + minf(velocity.length(), 4.0) * 0.13, 1)
	if front_line_revision != sim.revision:
		front_line_cells.clear()
		var cool := sim.display_cold
		var left := sim.neighbor_left
		var right := sim.neighbor_right
		var top := sim.neighbor_top
		var bottom := sim.neighbor_bottom
		for i in range(0, Sim.COUNT, 5):
			if cool[i] < 0.12: continue
			var gradient := Vector2(cool[right[i]] - cool[left[i]], cool[bottom[i]] - cool[top[i]]) / (2.0 * Sim.CELL)
			if gradient.length() >= 0.04: front_line_cells.append(i)
		front_line_revision = sim.revision
	var front_cells := front_line_cells
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
		var alpha := minf(velocity.length() / 2.0, 0.85) * maxf(0.0, 1.0 - trace.age / 2.4) * sim.edge_visibility(p)
		if alpha < 0.015:
			continue
		var height: float = 0.37 if trace.low else trace.height
		_ribbon(p, velocity, height, trace.low, Color(0.98, 0.99, 0.89, alpha), 0.015, 0.16 + minf(velocity.length(), 5.0) * 0.18)
		visible_wind_lines += 1
		if trace.get("source", false): visible_source_lines += 1
	line_vertices = ribbon_vertices.slice(0, line_cursor)
	line_colors = ribbon_colors.slice(0, line_cursor)
	if not line_vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = line_vertices
		arrays[Mesh.ARRAY_COLOR] = line_colors
		lines.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _emit_source_lines(dt: float) -> void:
	# Per-source visual-time accumulators: emission does not depend on mouse
	# event frequency, and pausing neither emits nor ages existing ribbons.
	var active: Array[int] = []
	if sim.outcome != "playing":
		source_emission.clear()
		return
	for source in sim.wind_sources:
		active.append(source.id)
		var fade := minf(1.0, source.remaining / source.fade)
		var accumulated: float = source_emission.get(source.id, 0.0) + dt * (4.0 + source.strength * 8.0) * fade
		var emit := mini(floori(accumulated), 6)
		source_emission[source.id] = accumulated - floorf(accumulated)
		for index in emit:
			# Distributed along the entire band, with soft lateral coverage.
			# Visual seeds do not consume the vapor/stroke random generator.
			source_trace_serial += 1
			var angle := source_trace_serial * 2.39996323
			var radius := sim.settings.brush_radius * fposmod(source_trace_serial * 0.61803399, 1.0) * 0.9
			var along := fposmod(source_trace_serial * 0.754877666, 1.0)
			var p: Vector2 = source.position.lerp(source.end, along) + Vector2(cos(angle), sin(angle)) * radius
			if source.get("kind", "band") == "vortex":
				p = source.position + Vector2(cos(angle), sin(angle)) * source.radius * sqrt(fposmod(source_trace_serial * 0.61803399, 1.0)) * 0.95
			wind_traces.append({"p": p, "height": 0.37, "low": true, "age": 0.0, "source": true})
			if sim.sample_cloud(sim.display_cloud, p) > 0.06:
				wind_traces.append({"p": p, "height": Sim.CLOUD_TOP + 0.05, "low": false, "age": 0.0, "source": true})
	for id in source_emission.keys():
		if not id in active: source_emission.erase(id)
	# Shared ribbon budget for mouse and persistent sources.
	while wind_traces.size() > 48: wind_traces.pop_front()

func _emit_field_lines(dt: float) -> void:
	# White lines describe actual wind, including cold outflow and residual wind
	# in dry air. Sample the published field without depending on interaction.
	if sim.outcome != "playing": return
	if field_line_revision != sim.revision and elapsed >= field_line_refresh:
		field_line_refresh = elapsed + 0.1
		field_line_candidates.clear()
		var low := sim.low_wind
		var high := sim.cloud_wind
		for i in Sim.COUNT:
			if low[i].length_squared() > 0.0036:
				field_line_candidates.append(i * 2)
			if high[i].length_squared() > 0.0036:
				field_line_candidates.append(i * 2 + 1)
		field_line_revision = sim.revision
	if field_line_candidates.is_empty():
		field_emission = 0.0
		return
	field_emission += dt * 12.0
	var emit := mini(floori(field_emission), 6)
	field_emission -= floorf(field_emission)
	for index in emit:
		field_line_serial += 1
		var n := mini(field_line_candidates.size() - 1, floori(fposmod(field_line_serial * 0.61803399, 1.0) * field_line_candidates.size()))
		# Packed cell/layer indices avoid a temporary dictionary per windy cell.
		var candidate: int = field_line_candidates[n]
		var low := candidate % 2 == 0
		wind_traces.append({"p": sim.positions[candidate / 2], "height": 0.37 if low else Sim.CLOUD_TOP + 0.05, "low": low, "age": 0.0, "field": true})
	while wind_traces.size() > 48: wind_traces.pop_front()

func update_map() -> void:
	map_data.resize(Sim.COUNT * 4)
	air_data.resize(Sim.COUNT * 4)
	var cloud: PackedFloat32Array = sim.display_cloud
	var rain: PackedFloat32Array = sim.display_rain
	var charge: PackedFloat32Array = sim.display_charge
	var humidity: PackedFloat32Array = sim.humidity
	var cold: PackedFloat32Array = sim.display_cold
	var hold: float = sim.settings.hold_seconds
	var water_pixels := map_data
	var air_pixels := air_data
	for i in Sim.COUNT:
		var q := cloud[i]
		var progress := charge[i] / maxf(q * hold, 0.0001)
		var offset := i * 4
		water_pixels[offset] = q
		water_pixels[offset + 1] = rain[i]
		water_pixels[offset + 2] = progress
		water_pixels[offset + 3] = humidity[i]
		air_pixels[offset] = humidity[i]
		air_pixels[offset + 1] = cold[i]
		air_pixels[offset + 2] = sim.tropical.heat[i] if sim.tropical != null else 0.0
		air_pixels[offset + 3] = 1.0
	image.set_data(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF, map_data.to_byte_array())
	air_image.set_data(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF, air_data.to_byte_array())
	water_texture.update(image)
	# Godot renders viewport dependencies before materials sampling their textures.
	# Recompute the conservative bound on GPU from the same publication, no readback.
	cloud_bounds_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	air_texture.update(air_image)
	ocean_material.set_shader_parameter("sea_map", air_texture)
	ocean_material.set_shader_parameter("warm_enabled", sim.tropical != null)
	map_revision = sim.revision

func _transform(point: Vector3, scale: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * scale), point)

func note_interaction(point: Vector2) -> void:
	interaction_point = point
	interaction_until = elapsed + 2.0

func _near_interaction(point: Vector2) -> float:
	var fade := 0.0
	if interaction_until > elapsed and point.distance_to(interaction_point) < sim.settings.brush_radius * 2.0:
		fade = minf(1.0, (interaction_until - elapsed) / 2.0)
	for source in sim.wind_sources:
		if source.get("kind", "band") == "vortex":
			if point.distance_to(source.position) < source.radius: fade = maxf(fade, minf(1.0, source.remaining / source.fade))
			continue
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, source.position, source.end)) < sim.settings.brush_radius * 2.0:
			fade = maxf(fade, minf(1.0, source.remaining / source.fade))
	return fade

func _arrow_context_cells() -> PackedInt32Array:
	var centers := PackedVector2Array()
	if interaction_until > elapsed: centers.append(interaction_point)
	for source in sim.wind_sources:
		if source.get("kind", "band") == "vortex":
			centers.append(source.position)
			for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]: centers.append(source.position + direction * source.radius * 0.6)
			continue
		var count := maxi(1, ceili(source.position.distance_to(source.end) / (sim.settings.brush_radius * 2.0)))
		for n in count + 1: centers.append(source.position.lerp(source.end, float(n) / count))
	var cells := PackedInt32Array()
	var groups: Array[PackedInt32Array] = []
	var biggest := 0
	var seen: Dictionary = {}
	var radius: float = sim.settings.brush_radius * 2.0
	for center in centers:
		var group := PackedInt32Array()
		var lo := Vector2i(((center - Vector2.ONE * radius - Sim.ORIGIN) / Sim.CELL).floor())
		var hi := Vector2i(((center + Vector2.ONE * radius - Sim.ORIGIN) / Sim.CELL).ceil())
		for z in range(maxi(0, lo.y), mini(Sim.DEPTH, hi.y), 2):
			for x in range(maxi(0, lo.x), mini(Sim.WIDTH, hi.x), 2):
				var i := z * Sim.WIDTH + x
				if not seen.has(i) and sim.positions[i].distance_to(center) < radius:
					seen[i] = true
					group.append(i)
		groups.append(group)
		biggest = maxi(biggest, group.size())
	# Round-robin the active brush and each source so one cannot consume all arrows.
	for index in biggest:
		for group in groups:
			if index < group.size(): cells.append(group[index])
	return cells

func _arrow_shape(point: Vector3, direction: Vector3, color: Color, length: float, movement: Vector3, phase: float) -> void:
	var side := direction.cross(-camera.global_basis.z).normalized() * 0.022
	var basis := Basis(direction * length, side, direction.cross(side).normalized())
	arrow_instances.set_instance_transform(visible_arrows, Transform3D(basis, point))
	arrow_instances.set_instance_color(visible_arrows, color)
	arrow_instances.set_instance_custom_data(visible_arrows, Color(movement.x, movement.z, phase, movement.y))

func _update_arrows() -> void:
	arrow_material.set_shader_parameter("visual_time", elapsed)
	if not hints_enabled or sim.outcome != "playing":
		arrow_instances.visible_instance_count = 0
		visible_arrows = 0
		return
	if elapsed < arrow_refresh: return
	if elapsed >= arrow_refresh:
		arrow_refresh = elapsed + 0.1
		arrow_candidates.clear()
		# Read the newest actual transfers, not hypothetical directions or old gradients.
		if sim.last_lift > 0.001:
			for i in Sim.COUNT:
				if sim.lifted[i] > 0.0002:
					arrow_candidates.append({"i": i, "kind": "lift"})
					if arrow_candidates.size() >= 8: break
		var context_cells := _arrow_context_cells()
		var moving_count := 0
		for i in context_cells:
			var p: Vector2 = sim.positions[i]
			if _near_interaction(p) <= 0.0: continue
			if sim.low_wind[i].length() >= 0.08:
				if sim.humidity[i] >= 0.06 and moving_count < 16:
					arrow_candidates.append({"i": i, "kind": "wet"})
					moving_count += 1
				if sim.display_cold[i] >= 0.12 and moving_count < 16:
					arrow_candidates.append({"i": i, "kind": "cold"})
					moving_count += 1
			if moving_count >= 16: break
		var clouds := 0
		for i in context_cells:
			if _near_interaction(sim.positions[i]) > 0.0 and sim.display_cloud[i] >= 0.06 and sim.cloud_velocity_at(sim.positions[i]).length() >= 0.08 and clouds < 8:
				arrow_candidates.append({"i": i, "kind": "cloud"})
				clouds += 1
				if clouds >= 8: break
	if arrow_candidates.is_empty():
		arrow_instances.visible_instance_count = 0
		visible_arrows = 0
		return
	visible_arrows = 0
	for candidate in arrow_candidates:
		var i: int = candidate.i
		var p: Vector2 = sim.positions[i]
		var phase := fposmod(i * 0.37, 1.0)
		var color := WET_ARROW
		var alpha := _near_interaction(p)
		var velocity: Vector2 = sim.velocity_at(p)
		var height: float = sim.terrain.height(p) + 0.42
		var point := Vector3(p.x, height, p.y)
		var direction := Vector3(velocity.x, 0, velocity.y).normalized()
		var movement := Vector3(velocity.x, 0, velocity.y) / 0.65
		if candidate.kind == "lift":
			if sim.lifted[i] <= 0.0002: continue
			color = LIFT_ARROW
			alpha = 0.8
			movement = Vector3(0, maxf(0.0, Sim.CLOUD_HEIGHT - height), 0)
			direction = Vector3.UP
		elif candidate.kind == "cloud":
			if sim.display_cloud[i] < 0.06: continue
			color = CLOUD_ARROW
			velocity = sim.cloud_velocity_at(p)
			direction = Vector3(velocity.x, 0, velocity.y).normalized()
			point.y = Sim.CLOUD_TOP + 0.03
			movement = Vector3(velocity.x, 0, velocity.y) / 0.65
		elif candidate.kind == "cold":
			if sim.display_cold[i] < 0.12: continue
			color = COLD_ARROW
			point.y += 0.10
		elif sim.humidity[i] < 0.06: continue
		if candidate.kind != "lift":
			if velocity.length() < 0.08 or alpha <= 0.0: continue
		color.a = alpha * sim.edge_visibility(p)
		_arrow_shape(point, direction, color, 0.35 + minf(velocity.length(), 4.0) * 0.08, movement, phase)
		visible_arrows += 1
	arrow_instances.visible_instance_count = visible_arrows

func update_weather(dt: float, moving: bool, pointer: Node = null) -> void:
	if moving:
		elapsed += dt
	if map_revision != sim.revision:
		update_map()
	air_material.set_shader_parameter("visual_time", elapsed)
	ocean_material.set_shader_parameter("visual_time", elapsed)
	_update_arrows()
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
	rain_area.update(dt, moving, elapsed, hints_enabled, pointer)
	for target in plot_materials.size():
		var water: float = sim.plot_progress(target)
		if sim.is_reservoir(target):
			var surface := reservoir_surfaces[target]
			if moving: surface.material_override.set_shader_parameter("visual_time",elapsed)
			surface.visible = water > 0.0
			if moving: surface.position.y = lerpf(surface.position.y, 0.27 + water * 0.12, 1.0 - exp(-dt * 6.0))
			continue
		if moving: plot_wetness[target] = lerpf(plot_wetness[target],water,1.0-exp(-dt*6.0))
		var soil := scene_style.soil_color.lerp(scene_style.soil_wet_color,plot_wetness[target])
		if plot_materials[target].get_shader_parameter("base_color") != soil: plot_materials[target].set_shader_parameter("base_color",soil)
		if farm_side_materials[target].get_shader_parameter("base_color") != soil.darkened(0.10): farm_side_materials[target].set_shader_parameter("base_color",soil.darkened(0.10))
		if farm_ridge_materials[target].get_shader_parameter("base_color") != soil.lightened(0.04): farm_ridge_materials[target].set_shader_parameter("base_color",soil.lightened(0.04))
		if moving:
			var growth := 0.65 + 0.35 * water if sim.plot_needs[target] != null else 1.0
			if sim.plot_destroyed[target]: growth = 0.55
			var blend := 1.0 - exp(-dt * 6.0)
			plant_growth[target] = lerpf(plant_growth[target], growth, blend)
			plant_wilt[target] = lerpf(plant_wilt[target], 1.0 if sim.plot_destroyed[target] else 0.0, blend)
		plant_groups[target].scale.y = plant_growth[target]
		var leaves := Color("578563").lerp(Color("946856"),plant_wilt[target])
		if plant_materials[target].get_shader_parameter("base_color") != leaves: plant_materials[target].set_shader_parameter("base_color",leaves)

func _update_rain() -> void:
	var total := 0
	var rain: PackedFloat32Array = sim.rain
	var counts := rain_drop_counts
	for i in Sim.COUNT:
		counts[i] = clampi(ceili(rain[i] * 5.0), 1, 9) if rain[i] > 0.0 else 0
		total += counts[i]
	var count := mini(total, RAIN_COUNT)
	var selected := PackedInt32Array()
	selected.resize(count)
	# Spread the capped display budget over the whole actual rainy area.
	var ordinal := 0
	var chosen := 0
	var next_target := floori(0.5 * total / count) if count > 0 else 0
	for i in Sim.COUNT:
		while chosen < count:
			if next_target >= ordinal + counts[i]:
				break
			selected[chosen] = i * 9 + next_target - ordinal
			chosen += 1
			if chosen < count: next_target = floori((chosen + 0.5) * total / count)
		ordinal += counts[i]
		if chosen == count: break
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
