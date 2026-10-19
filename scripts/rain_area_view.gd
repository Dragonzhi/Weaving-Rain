extends Node3D
## Two lightweight depth-projected passes. No gameplay state or random-number consumption.
const Sim = preload("res://scripts/weather_simulation.gd")
const SHADER = preload("res://shaders/rain_area.gdshader")
var sim: Sim
var texture: ImageTexture
var image: Image
var pixels := PackedFloat32Array()
var coverage := PackedByteArray()
var groups := PackedInt32Array()
var flood_queue := PackedInt32Array()
var wet_cells := PackedInt32Array()
var focus := PackedFloat32Array()
var passes: Array[MeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var revision := -1
var uploaded_revision := -1
var group_builds := 0
var selected_group := -1
var visible_area := false
var published_time := 0.0
var peak_focus := 0.0
var sampled_time := -INF
var focus_time := -INF

func setup(model: Sim, camera: Camera3D) -> void:
	sim = model
	pixels.resize(Sim.COUNT * 4)
	coverage.resize(Sim.COUNT)
	groups.resize(Sim.COUNT)
	groups.fill(-1)
	flood_queue.resize(Sim.COUNT)
	focus.resize(Sim.COUNT)
	image = Image.create(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF)
	texture = ImageTexture.create_from_image(image)
	for outline in [false, true]:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.render_priority = 20 if outline else -20
		material.set_shader_parameter("outline_pass", outline)
		material.set_shader_parameter("rain_map", texture)
		var pass_node := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		pass_node.mesh = quad
		pass_node.material_override = material
		pass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pass_node.extra_cull_margin = 16384
		pass_node.visible = false
		camera.add_child(pass_node)
		passes.append(pass_node)
		materials.append(material)

func _read_field() -> void:
	var next_coverage := PackedByteArray()
	next_coverage.resize(Sim.COUNT)
	wet_cells.resize(0)
	var rain := sim.ground_rain
	var buffer := pixels
	var cells := wet_cells
	var focus_values := focus
	for i in Sim.COUNT:
		var amount := rain[i]
		var wet := amount > 0.0
		next_coverage[i] = 1 if wet else 0
		buffer[i * 4] = amount
		buffer[i * 4 + 1] = 1.0 if wet else 0.0
		if wet: cells.append(i)
		else: focus_values[i] = 0.0
	if next_coverage != coverage:
		coverage = next_coverage
		_build_groups()
	revision = sim.revision

func _build_groups() -> void:
	group_builds += 1
	var assigned := groups
	var covered := coverage
	var queue := flood_queue
	var left := sim.neighbor_left
	var right := sim.neighbor_right
	var top := sim.neighbor_top
	var bottom := sim.neighbor_bottom
	assigned.fill(-1)
	var group := 0
	for start in wet_cells:
		if assigned[start] >= 0: continue
		var head := 0
		var tail := 1
		queue[0] = start
		assigned[start] = group
		while head < tail:
			var i := queue[head]
			head += 1
			var neighbor := left[i]
			if covered[neighbor] != 0 and assigned[neighbor] < 0:
				assigned[neighbor] = group
				queue[tail] = neighbor
				tail += 1
			neighbor = right[i]
			if covered[neighbor] != 0 and assigned[neighbor] < 0:
				assigned[neighbor] = group
				queue[tail] = neighbor
				tail += 1
			neighbor = top[i]
			if covered[neighbor] != 0 and assigned[neighbor] < 0:
				assigned[neighbor] = group
				queue[tail] = neighbor
				tail += 1
			neighbor = bottom[i]
			if covered[neighbor] != 0 and assigned[neighbor] < 0:
				assigned[neighbor] = group
				queue[tail] = neighbor
				tail += 1
		group += 1

func _selection(pointer: Node) -> int:
	if pointer == null or not pointer.enabled or not pointer.hover_valid or not pointer.hover_cloud or pointer.tool != "brush": return -1
	var p := Vector2(pointer.brush_point.x, pointer.brush_point.z)
	var radius: float = sim.settings.brush_radius
	var closest := radius * radius
	var selected := -1
	for i in wet_cells:
		var distance := p.distance_squared_to(sim.positions[i])
		if distance <= closest:
			closest = distance
			selected = groups[i]
	return selected

func update(dt: float, moving: bool, clock: float, enabled: bool, pointer: Node = null) -> void:
	if not enabled or sim.outcome != "playing":
		visible_area = false
		for pass_node in passes: pass_node.visible = false
		sampled_time = -INF
		focus_time = -INF
		return
	# The simulation publishes at 60 Hz; 15 Hz is ample for a visual footprint and
	# avoids rebuilding texture data and connected regions on every fixed step.
	if revision != sim.revision and (revision < 0 or clock - sampled_time >= 1.0 / 15.0):
		_read_field()
		sampled_time = clock
	var dirty := uploaded_revision != revision
	visible_area = not wet_cells.is_empty()
	for pass_node in passes: pass_node.visible = visible_area
	if not visible_area: return
	if moving and (focus_time < 0.0 or clock - focus_time >= 1.0 / 15.0):
		var focus_dt := 1.0 / 15.0 if focus_time < 0.0 else minf(clock - focus_time, 0.1)
		focus_time = clock
		selected_group = _selection(pointer)
		peak_focus = 0.0
		for i in wet_cells:
			var target := 1.0 if selected_group >= 0 and groups[i] == selected_group else 0.0
			var next := move_toward(focus[i], target, focus_dt / 0.3)
			dirty = dirty or next != focus[i]
			focus[i] = next
			peak_focus = maxf(peak_focus, next)
	if dirty:
		for i in Sim.COUNT: pixels[i * 4 + 2] = focus[i] * coverage[i]
		image.set_data(Sim.WIDTH, Sim.DEPTH, false, Image.FORMAT_RGBAF, pixels.to_byte_array())
		texture.update(image)
		uploaded_revision = revision
	published_time = clock
	for material in materials: material.set_shader_parameter("visual_time", clock)
