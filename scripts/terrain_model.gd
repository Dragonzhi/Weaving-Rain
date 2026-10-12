@tool
extends RefCounted
## One source of truth for visible terrain, uphill lifting and pointer/rain heights.
var center := Vector2(-0.6, 0.3)
var axes := Vector2(8.5, 5.5)
var mountain := Vector2(-1.7, -0.6)
var mountain_radius := 3.0
var shape := "standard"
var coast_variation := 1.0
var mountains: Array[WRMountain] = []
var hill_data := PackedFloat64Array()
var maximum_height := 0.22
var coast_inner_squared := 0.0
var coast_outer_squared := 1.0

func _init(layout: Dictionary = {}) -> void:
	center = layout.get("island_center", center)
	axes = layout.get("island_axes", axes)
	mountain = layout.get("mountain", mountain)
	mountain_radius = layout.get("mountain_radius", mountain_radius)
	shape = layout.get("shape", shape)
	coast_variation = layout.get("coast_variation", 1.0)
	# Exact conservative bounds: skip coast trigonometry away from the shoreline.
	var amplitude := 0.055 if shape == "long" else 0.52 if shape == "split" else 0.22
	var variation := absf(coast_variation) * amplitude
	coast_inner_squared = pow(maxf(0.0, 1.0 - variation - 0.000001), 2)
	coast_outer_squared = pow(1.0 + variation + 0.000001, 2)
	if layout.has("mountains"):
		mountains.assign(layout.mountains)
	else:
		var m := WRMountain.new()
		m.position = mountain
		m.radius = mountain_radius
		mountains.append(m)
	# Compile immutable map geometry once; a changed map creates a new height field.
	for m in mountains:
		if m == null or not m.position.is_finite() or not is_finite(m.radius) or m.radius <= 0 or not is_finite(m.height): continue
		hill_data.append_array(PackedFloat64Array([m.position.x, m.position.y, m.radius * m.radius, m.height]))
		maximum_height = maxf(maximum_height, 0.22 + m.height)

func coast_radius(angle: float) -> float:
	if shape == "long":
		return 1.0 + coast_variation * (0.035 * sin(angle * 3.0) + 0.02 * cos(angle * 5.0))
	if shape == "split":
		return 1.0 + coast_variation * (0.5 * cos(angle * 2.0) + 0.02 * sin(angle * 3.0))
	return 1.0 + coast_variation * (0.12 * sin(angle * 3.0 + 0.3) + 0.075 * cos(angle * 5.0 - 0.7) + 0.025 * sin(angle * 7.0))

func island_point(angle: float, radius: float = 1.0) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * axes * coast_radius(angle) * radius

func is_land(p: Vector2) -> bool:
	var q := (p - center) / axes
	var distance := q.length_squared()
	if coast_inner_squared > 0.0 and distance < coast_inner_squared: return true
	if distance > coast_outer_squared: return false
	return q.length() <= coast_radius(q.angle())

func height(p: Vector2) -> float:
	if not is_land(p): return -0.08
	var hill := 0.0
	var hills := hill_data
	for n in range(0, hills.size(), 4):
		var d2 := p.distance_squared_to(Vector2(hills[n], hills[n + 1])) / hills[n + 2]
		if d2 < 1.0: hill = maxf(hill, hills[n + 3] * pow(1.0 - d2, 2))
	return 0.22 + hill

func slope(p: Vector2) -> Vector2:
	if not is_land(p): return Vector2.ZERO
	var hill := 0.0
	var gradient := Vector2.ZERO
	var hills := hill_data
	for n in range(0, hills.size(), 4):
		var offset := p - Vector2(hills[n], hills[n + 1])
		var r2 := hills[n + 2]
		var d2 := offset.length_squared() / r2
		if d2 >= 1.0: continue
		var h := hills[n + 3] * pow(1.0 - d2, 2)
		if h > hill:
			hill = h
			gradient = -offset * (4.0 * hills[n + 3] / r2) * (1.0 - d2)
	return gradient

func river_point(t: float) -> Vector2:
	if shape == "standard":
		return Vector2(-1.0 + t * 8.0, -1.0 + t * 3.8 + sin(t * 9.0) * 0.45) + (mountain - Vector2(-1.7, -0.6)) * (1.0 - t)
	var start := mountain + Vector2(0.4, 0.2)
	var end := Vector2(8.0, 1.8) if shape == "long" else Vector2(7.5, 2.7)
	return start.lerp(end, t) + Vector2(0, sin(t * 9.0) * 0.3)
