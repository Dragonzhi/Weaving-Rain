extends RefCounted
## Shared UI glyphs and bounded water display; no weather state or RNG.
const DROP_WATER := 20.0
const MAX_SLOTS := 6
const INK := Color("354e57")
const MUTED := Color("607b80")
const WATER := Color("7aaebc")
const WARNING := Color("ddc775")
const DAMAGE := Color("c76e60")
const GOLD := Color("ad8b43")
var drop := PackedVector2Array()
var bowl := PackedVector2Array()
var drop_cache: Dictionary = {}
var bowl_cache: Dictionary = {}
var cloud := PackedVector2Array()

func _init() -> void:
	var curves := [
		[Vector2(0.5,0), Vector2(0.34,0.25), Vector2(0,0.51), Vector2(0,0.68)],
		[Vector2(0,0.68), Vector2(0,0.88), Vector2(0.2,1), Vector2(0.5,1)],
		[Vector2(0.5,1), Vector2(0.8,1), Vector2(1,0.88), Vector2(1,0.68)],
		[Vector2(1,0.68), Vector2(1,0.51), Vector2(0.66,0.25), Vector2(0.5,0)]]
	for curve in curves:
		for n in 9: drop.append(curve[0].bezier_interpolate(curve[1], curve[2], curve[3], n / 9.0))
	for n in 25:
		var angle := PI * n / 24.0
		bowl.append(Vector2(0.5 + 0.5 * cos(angle), 0.18 + 0.82 * sin(angle)))
	var cloud_curves := [
		[Vector2(0.12,1),Vector2(-0.04,1),Vector2(-0.04,0.45),Vector2(0.15,0.45)],
		[Vector2(0.15,0.45),Vector2(0.16,0.12),Vector2(0.32,0.1),Vector2(0.4,0.28)],
		[Vector2(0.4,0.28),Vector2(0.43,-0.03),Vector2(0.64,-0.03),Vector2(0.68,0.29)],
		[Vector2(0.68,0.29),Vector2(0.78,0.12),Vector2(0.9,0.28),Vector2(0.89,0.49)],
		[Vector2(0.89,0.49),Vector2(1.04,0.48),Vector2(1.04,1),Vector2(0.88,1)]]
	for curve in cloud_curves:
		for n in 8: cloud.append(curve[0].bezier_interpolate(curve[1],curve[2],curve[3],n/8.0))
	cloud.append(Vector2(0.88,1))

func cloud_reserve(canvas: CanvasItem, rect: Rect2, wet: float, stored: float, wet_color: Color, cloud_color: Color) -> void:
	var outline := PackedVector2Array()
	var sideways := PackedVector2Array()
	for p in cloud:
		outline.append(rect.position+p*rect.size)
		sideways.append(Vector2(p.y,-p.x))
	canvas.draw_colored_polygon(outline,Color(0.96,0.98,0.92,0.94))
	for entry in [[wet+stored,cloud_color],[wet,wet_color]]:
		if entry[0] <= 0: continue
		var clipped := _filled(sideways,-clampf(entry[0],0,1))
		var polygon := PackedVector2Array()
		for p in clipped: polygon.append(rect.position+Vector2(-p.y,p.x)*rect.size)
		if polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty(): canvas.draw_colored_polygon(polygon,entry[1])
	outline.append(outline[0])
	canvas.draw_polyline(outline,Color(INK,0.65),1.2,true)

func clear_cache() -> void:
	drop_cache.clear()
	bowl_cache.clear()

static func water_slots(required: float, amount: float) -> Array[Dictionary]:
	# At most six slots, even for very large valid custom requirements.
	var total := ceilf(required / DROP_WATER)
	var slots: Array[Dictionary] = []
	for index in mini(MAX_SLOTS, int(minf(total, MAX_SLOTS))):
		var start := index * DROP_WATER
		var grouped := total > MAX_SLOTS and index == MAX_SLOTS - 1
		var capacity := required - start if grouped else minf(DROP_WATER, required - start)
		slots.append({"capacity": capacity, "units": total - index if grouped else 1.0,
			"fill": clampf((amount - start) / capacity, 0.0, 1.0)})
	return slots

func _outline(rect: Rect2, reservoir: bool) -> PackedVector2Array:
	var cache := bowl_cache if reservoir else drop_cache
	if cache.has(rect): return cache[rect]
	var result := PackedVector2Array()
	for p in (bowl if reservoir else drop): result.append(rect.position + p * rect.size)
	cache[rect] = result
	return result

func _filled(points: PackedVector2Array, waterline: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var previous := points[-1]
	for current in points:
		if (current.y >= waterline) != (previous.y >= waterline):
			var cut := previous.lerp(current, (waterline - previous.y) / (current.y - previous.y))
			if result.is_empty() or result[-1].distance_squared_to(cut)>0.0000000001: result.append(cut)
		if current.y >= waterline and (result.is_empty() or result[-1].distance_squared_to(current)>0.0000000001): result.append(current)
		previous = current
	if result.size()>1 and result[0].distance_squared_to(result[-1])<=0.0000000001: result.remove_at(result.size()-1)
	return result

func water_glyph(canvas: CanvasItem, rect: Rect2, fill: float, color: Color, reservoir := false) -> void:
	var outline := _outline(rect, reservoir)
	canvas.draw_colored_polygon(outline, Color(0.98, 0.99, 0.94, 0.95))
	if fill > 0.0:
		var top := rect.position.y + rect.size.y * (1.0 - fill * (0.82 if reservoir else 1.0))
		var polygon := outline if fill >= 1.0 else _filled(outline, top)
		# Screen-space float precision can collapse a subpixel fill to a line.
		# Skip only non-triangulable display geometry; never round simulated water.
		var drawable := polygon.size() >= 3 and (fill >= 1.0 or not Geometry2D.triangulate_polygon(polygon).is_empty())
		if drawable: canvas.draw_colored_polygon(polygon, color)
		if reservoir and drawable:
			var left := INF
			var right := -INF
			for p in polygon:
				if absf(p.y-top)<0.01:
					left = minf(left,p.x)
					right = maxf(right,p.x)
			if right-left>2: canvas.draw_line(Vector2(left+1,top),Vector2(right-1,top),Color(0.92,1,1,0.7),1.0,true)
	var closed := outline.duplicate()
	closed.append(closed[0])
	canvas.draw_polyline(closed, INK, 1.35, true)

func state_glyph(canvas: CanvasItem, at: Vector2, state: String, progress: float, radius := 8.0) -> void:
	match state:
		"danger":
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-radius), at+Vector2(radius,radius), at+Vector2(-radius,radius)]), WARNING)
			canvas.draw_line(at+Vector2(0,-3), at+Vector2(0,2), INK, 1.6, true)
			canvas.draw_circle(at+Vector2(0,5), 1.0, INK)
		"confirming":
			canvas.draw_arc(at, radius, 0, TAU, 32, Color("cdd8d3"), 2.0, true)
			if progress > 0: canvas.draw_arc(at, radius, -PI/2, -PI/2+TAU*progress, 32, GOLD, 2.0, true)
		"safe":
			canvas.draw_circle(at, radius, GOLD)
			canvas.draw_polyline(PackedVector2Array([at+Vector2(-4,0),at+Vector2(-1,3),at+Vector2(4,-3)]), Color("f7f6e9"), 1.7, true)
		"destroyed":
			canvas.draw_circle(at, radius, DAMAGE, false, 1.7, true)
			canvas.draw_line(at+Vector2(-3,-3),at+Vector2(3,3), DAMAGE, 1.8, true)
			canvas.draw_line(at+Vector2(-3,3),at+Vector2(3,-3), DAMAGE, 1.8, true)

func medal(canvas: CanvasItem, at: Vector2, radius: float, active: bool, emphasis := 1.0) -> void:
	var color := GOLD if active else MUTED
	color.a = (0.6 + 0.4 * emphasis) if active else 0.70
	if active: canvas.draw_circle(at, radius - 2, Color(GOLD, 0.09 + emphasis * 0.08))
	canvas.draw_arc(at, radius, 0, TAU, 48, color, 1.6, true)
	for row in 3:
		var wave := PackedVector2Array()
		for n in 13:
			var x := n / 12.0
			wave.append(at + Vector2((x-0.5)*radius*1.18, (row-1)*radius*0.32 + sin(x*TAU)*radius*0.08))
		canvas.draw_polyline(wave, color, 1.5 if radius < 20 else 2.0, true)

static func tool_icon(kind: String) -> Texture2D:
	var path := "M3 8H16C23 8 23 1 18 2 M3 13H21 M3 18H13C20 18 20 24 15 23"
	if kind == "source": path = "M2 6C8 2 12 10 18 6 M2 12C8 8 12 16 18 12 M2 18C8 14 12 22 18 18 M17 10L22 12L17 14"
	elif kind == "vortex": path = "M22 12A10 10 0 1 1 12 2 M12 6A6 6 0 1 0 18 12 M12 10A2 2 0 1 1 10 12"
	elif kind == "hints": path = "M4 13A5 5 0 0 1 9 8A5 5 0 0 1 19 11A3 3 0 0 1 20 17H5 M7 20V22 M13 20V22 M19 20V22"
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="0 0 24 24"><path d="'+path+'" fill="none" stroke="#354e57" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>')
	return ImageTexture.create_from_image(image)
