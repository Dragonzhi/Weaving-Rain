@tool
class_name WRMapAuthor
extends Node3D
const Terrain = preload("res://scripts/terrain_model.gd")
@export var map_definition: WRMapDefinition = preload("res://configs/maps/standard.tres"):
	set(value):
		map_definition = value
		if is_inside_tree(): rebuild()
var preview: Node3D
var fingerprint := 0
var poll := 0.0
var errors := PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint(): rebuild()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint(): return
	poll += delta
	if poll < 0.2: return
	poll = 0.0
	if signature() != fingerprint: rebuild()

func signature() -> int:
	if map_definition == null: return 0
	var values: Array = [map_definition.id, map_definition.title, map_definition.shape, map_definition.island_center,
		map_definition.island_axes, map_definition.coast_variation, map_definition.plots, map_definition.river_enabled,
		map_definition.star_level, map_definition.time_limit_seconds, FileAccess.get_modified_time("res://configs/weather.tres")]
	for region in map_definition.plot_regions:
		values.append([region.shape, region.half_axes] if region != null else null)
	for m in map_definition.mountains:
		values.append([m.position, m.radius, m.height] if m != null else null)
	for source in map_definition.humidity_sources:
		values.append([source.position, source.spread, source.concentration, source.falloff] if source != null else null)
	return hash(values)

func rebuild() -> void:
	fingerprint = signature()
	if preview != null:
		remove_child(preview)
		preview.queue_free()
	preview = Node3D.new()
	add_child(preview)
	if map_definition == null: return
	var tuning := preload("res://scripts/config_loader.gd").settings("res://configs/weather.tres")
	var plot_half: float = tuning.resource.plot_half if tuning.errors.is_empty() else 1.25
	errors = map_definition.validation_errors(plot_half)
	var terrain := Terrain.new(map_definition.to_layout())
	var ocean := PlaneMesh.new()
	ocean.size = Vector2(40, 36)
	add_mesh(ocean, Color("58aab1"), Vector3(0, -0.08, 0))
	if not map_definition.island_axes.is_finite() or map_definition.island_axes.x <= 0 or map_definition.island_axes.y <= 0 or not is_finite(map_definition.coast_variation):
		update_configuration_warnings()
		return
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 16:
		for segment in 64:
			var a := segment * TAU / 64.0
			var b := (segment + 1) * TAU / 64.0
			var p0: Vector2 = terrain.island_point(a, ring / 16.0)
			var p1: Vector2 = terrain.island_point(b, ring / 16.0)
			var p2: Vector2 = terrain.island_point(a, (ring + 1) / 16.0)
			var p3: Vector2 = terrain.island_point(b, (ring + 1) / 16.0)
			for p in [p0, p2, p1, p1, p2, p3]:
				var slope: Vector2 = terrain.slope(p)
				top.set_normal(Vector3(-slope.x, 1, -slope.y).normalized())
				top.add_vertex(Vector3(p.x, maxf(0.22, terrain.height(p)), p.y))
	top.index()
	var land := add_mesh(top.commit(), Color("9bbb83"))
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/terrain.gdshader")
	material.set_shader_parameter("base_color", Color("9bbb83"))
	var empty := Image.create(1, 1, false, Image.FORMAT_RGBAF)
	empty.fill(Color(0, 0, 0, 0))
	material.set_shader_parameter("water_map", ImageTexture.create_from_image(empty))
	land.material_override = material
	if map_definition.river_enabled:
		var river := SurfaceTool.new()
		river.begin(Mesh.PRIMITIVE_TRIANGLES)
		for n in 70:
			var p0: Vector2 = terrain.river_point(n / 70.0)
			var p1: Vector2 = terrain.river_point((n + 1) / 70.0)
			if not terrain.is_land(p0) or not terrain.is_land(p1): continue
			var side := (p1 - p0).orthogonal().normalized() * 0.13
			for p in [p0 - side, p1 - side, p0 + side, p1 - side, p1 + side, p0 + side]:
				river.set_normal(Vector3.UP)
				river.add_vertex(Vector3(p.x, terrain.height(p) + 0.022, p.y))
		add_mesh(river.commit(), Color("72ccd0"))
	for n in map_definition.plots.size():
		var p := map_definition.plots[n]
		var region := map_definition.region(n)
		if not region.validation_error().is_empty(): continue
		var plot := region.mesh(plot_half)
		var invalid := false
		for error in errors:
			invalid = invalid or error.begins_with("plots[%d]" % n) or error.begins_with("plots：")
		add_mesh(plot, Color("e68172") if invalid else Color("b99470"), Vector3(p.x, terrain.height(p) + 0.045, p.y))
		add_label(String.chr(65 + n), Vector3(p.x, 0.6, p.y))
	for n in map_definition.mountains.size():
		var m := map_definition.mountains[n]
		if m != null:
			var invalid := false
			for error in errors: invalid = invalid or error.begins_with("mountains[%d]" % n)
			add_label("山 %d" % (n + 1), Vector3(m.position.x, 0.5 + m.height, m.position.y), Color("e68172") if invalid else Color.WHITE)
	for n in map_definition.humidity_sources.size():
		var source := map_definition.humidity_sources[n]
		if source == null: continue
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.02
		var node := add_mesh(disc, Color(0.85, 0.96, 0.85, 0.22), Vector3(source.position.x, 0.35, source.position.y))
		node.scale = Vector3(source.spread.x, 1, source.spread.y)
		add_label("湿空气 %d" % (n + 1), Vector3(source.position.x, 0.65, source.position.y))
	update_gizmos()
	update_configuration_warnings()

func add_mesh(mesh: Mesh, color: Color, position_value := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = material
	node.position = position_value
	preview.add_child(node)
	return node

func add_label(text: String, p: Vector3, color := Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = p
	label.font_size = 40
	label.pixel_size = 0.015
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	preview.add_child(label)

func _get_configuration_warnings() -> PackedStringArray:
	return errors

func handle_data() -> Array[Dictionary]:
	var handles: Array[Dictionary] = []
	if map_definition == null: return handles
	var c := map_definition.island_center
	handles.append({"label": "岛屿中心", "kind": "island_center", "index": 0, "p": Vector3(c.x, 0.3, c.y)})
	handles.append({"label": "岛屿长轴", "kind": "axis_x", "index": 0, "p": Vector3(c.x + map_definition.island_axes.x, 0.3, c.y)})
	handles.append({"label": "岛屿短轴", "kind": "axis_z", "index": 0, "p": Vector3(c.x, 0.3, c.y + map_definition.island_axes.y)})
	for n in map_definition.mountains.size():
		var m := map_definition.mountains[n]
		if m == null: continue
		for kind in ["mountain_position", "mountain_radius", "mountain_height"]:
			var p := Vector3(m.position.x, 0.25, m.position.y)
			if kind == "mountain_radius": p.x += m.radius
			if kind == "mountain_height": p.y += m.height
			handles.append({"label": "山 %d %s" % [n + 1, kind], "kind": kind, "index": n, "p": p})
	for n in map_definition.plots.size():
		var p := map_definition.plots[n]
		handles.append({"label": "目标 " + String.chr(65 + n), "kind": "plot", "index": n, "p": Vector3(p.x, 0.3, p.y)})
	for n in map_definition.humidity_sources.size():
		var source := map_definition.humidity_sources[n]
		if source == null: continue
		handles.append({"label": "湿空气 %d" % (n + 1), "kind": "air", "index": n, "p": Vector3(source.position.x, 0.35, source.position.y)})
	return handles

func handle_value(id: int) -> Variant:
	var data := handle_data()[id]
	match data.kind:
		"island_center": return map_definition.island_center
		"axis_x", "axis_z": return map_definition.island_axes
		"mountain_position": return map_definition.mountains[data.index].position
		"mountain_radius": return map_definition.mountains[data.index].radius
		"mountain_height": return map_definition.mountains[data.index].height
		"plot": return map_definition.plots[data.index]
		"air": return map_definition.humidity_sources[data.index].position
	return null

func apply_handle(id: int, value: Variant) -> void:
	var data := handle_data()[id]
	match data.kind:
		"island_center": map_definition.island_center = value
		"axis_x", "axis_z": map_definition.island_axes = value
		"mountain_position": map_definition.mountains[data.index].position = value
		"mountain_radius": map_definition.mountains[data.index].radius = value
		"mountain_height": map_definition.mountains[data.index].height = value
		"plot": map_definition.plots[data.index] = value
		"air": map_definition.humidity_sources[data.index].position = value
	map_definition.emit_changed()
	rebuild()

func apply_collection(field: String, values: Array) -> void:
	map_definition.set(field, values)
	map_definition.emit_changed()
	rebuild()

func apply_plots(points: PackedVector2Array, regions: Array[WRPlotRegion]) -> void:
	map_definition.plots = points
	map_definition.plot_regions = regions
	map_definition.emit_changed()
	rebuild()
