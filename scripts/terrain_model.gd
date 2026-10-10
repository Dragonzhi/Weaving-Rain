extends RefCounted
## One source of truth for visible terrain, uphill lifting and pointer/rain heights.
var center := Vector2(-0.6, 0.3)
var axes := Vector2(8.5, 5.5)
var mountain := Vector2(-1.7, -0.6)
var mountain_radius := 3.0
var shape := "standard"

func _init(layout: Dictionary = {}) -> void:
	center = layout.get("island_center", center)
	axes = layout.get("island_axes", axes)
	mountain = layout.get("mountain", mountain)
	mountain_radius = layout.get("mountain_radius", mountain_radius)
	shape = layout.get("shape", shape)

func coast_radius(angle: float) -> float:
	if shape == "long":
		return 1.0 + 0.035 * sin(angle * 3.0) + 0.02 * cos(angle * 5.0)
	if shape == "split":
		return 1.0 + 0.5 * cos(angle * 2.0) + 0.02 * sin(angle * 3.0)
	return 1.0 + 0.12 * sin(angle * 3.0 + 0.3) + 0.075 * cos(angle * 5.0 - 0.7) + 0.025 * sin(angle * 7.0)

func island_point(angle: float, radius: float = 1.0) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * axes * coast_radius(angle) * radius

func is_land(p: Vector2) -> bool:
	var q := (p - center) / axes
	return q.length() <= coast_radius(q.angle())

func height(p: Vector2) -> float:
	if not is_land(p): return -0.08
	var d := p.distance_to(mountain) / mountain_radius
	return 0.22 + 2.5 * pow(maxf(0.0, 1.0 - d * d), 2)

func slope(p: Vector2) -> Vector2:
	if not is_land(p): return Vector2.ZERO
	var offset := p - mountain
	var r2 := mountain_radius * mountain_radius
	var d2 := offset.length_squared() / r2
	return -offset * (10.0 / r2) * (1.0 - d2) if d2 < 1.0 else Vector2.ZERO

func river_point(t: float) -> Vector2:
	if shape == "standard":
		return Vector2(-1.0 + t * 8.0, -1.0 + t * 3.8 + sin(t * 9.0) * 0.45)
	var start := mountain + Vector2(0.4, 0.2)
	var end := Vector2(8.0, 1.8) if shape == "long" else Vector2(7.5, 2.7)
	return start.lerp(end, t) + Vector2(0, sin(t * 9.0) * 0.3)
