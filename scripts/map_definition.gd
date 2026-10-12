@tool
class_name WRMapDefinition
extends Resource
@export var id := "custom"
@export var title := "新地图"
@export_multiline var hint := "借山坡造云，把雨送到两处土地"
@export_group("岛形")
@export_enum("standard", "long", "split") var shape := "standard"
@export var island_center := Vector2(-0.6, 0.3)
@export var island_axes := Vector2(8.5, 5.5)
@export_range(0.0, 1.5, 0.05) var coast_variation := 1.0
@export var river_enabled := true
@export_group("山、目标与湿空气")
@export var mountains: Array[WRMountain] = []
@export var plots := PackedVector2Array([Vector2(2.8, 1.2), Vector2(3.6, -1.9)])
## 按地块顺序指定形状，未指定的沿用全局尺寸的矩形。
@export var plot_regions: Array[WRPlotRegion] = []
## 星级关卡：一块适量且安全的土地一颗星，至少一星可主动收尾；旧练习局保持全部达标规则。
@export var star_level := false
## 星级关卡的游玩时限，单位为秒。越短越需要提前安排输雨与安全收尾；越长越容易继续争星。
## 到时仅计算已经适量且连续安全的地块。入门、旧练习局和开发小样不计时；修改后重新开局生效。
@export_range(1.0, 3600.0, 1.0) var time_limit_seconds := 180.0
@export var humidity_sources: Array[WRHumiditySource] = []

func to_layout() -> Dictionary:
	var first := mountains[0] if not mountains.is_empty() and mountains[0] != null else WRMountain.new()
	var west := humidity_sources[0].position if not humidity_sources.is_empty() and humidity_sources[0] != null else Vector2.ZERO
	var east := humidity_sources[1].position if humidity_sources.size() > 1 and humidity_sources[1] != null else west
	return {"id": id, "title": title, "hint": hint, "shape": shape, "island_center": island_center,
		"island_axes": island_axes, "coast_variation": coast_variation, "river_enabled": river_enabled,
		"mountain": first.position, "mountain_radius": first.radius, "mountains": mountains,
		"plots": plots, "plot_regions": plot_regions, "star_level": star_level, "time_limit_seconds": time_limit_seconds,
		"west_air": west, "east_air": east, "humidity_sources": humidity_sources}

func region(index: int) -> WRPlotRegion:
	return plot_regions[index] if index < plot_regions.size() and plot_regions[index] != null else WRPlotRegion.new()

func validation_errors(plot_half: float = 1.25) -> PackedStringArray:
	var errors := PackedStringArray()
	if id.strip_edges().is_empty(): errors.append("id：不能为空")
	if title.strip_edges().is_empty(): errors.append("title：不能为空")
	if not is_finite(time_limit_seconds) or time_limit_seconds < 1.0 or time_limit_seconds > 3600.0:
		errors.append("time_limit_seconds：须为 1–3600 秒的有限数值")
	if not island_center.is_finite() or not island_axes.is_finite() or island_axes.x <= 0 or island_axes.y <= 0:
		errors.append("island_axes：岛屿长宽必须是有限正数")
		return errors
	if not is_finite(coast_variation) or coast_variation < 0 or coast_variation > 1.5: errors.append("coast_variation：必须在 0–1.5")
	if not shape in ["standard", "long", "split"]: errors.append("shape：未知岛形")
	if plots.is_empty() or plots.size() > 3: errors.append("plots：首版须有 1–3 处目标")
	if plot_regions.size() > plots.size(): errors.append("plot_regions：形状数量不能多于目标")
	for n in plots.size():
		if not plots[n].is_finite(): errors.append("plots[%d]：位置须为有限坐标" % n)
	for n in plot_regions.size():
		if plot_regions[n] == null: continue
		var error := plot_regions[n].validation_error()
		if not error.is_empty(): errors.append("plot_regions[%d]：%s" % [n, error])
	for n in mountains.size():
		var m := mountains[n]
		if m == null or not m.position.is_finite() or not is_finite(m.radius) or m.radius <= 0 or not is_finite(m.height) or m.height <= 0 or m.height > 2.5:
			errors.append("mountains[%d]：位置、宽度或高度无效；高度须在 0–2.5" % n)
	for n in humidity_sources.size():
		var source := humidity_sources[n]
		if source == null or not source.position.is_finite() or not source.spread.is_finite() or source.spread.x <= 0 or source.spread.y <= 0 or not is_finite(source.concentration) or source.concentration < 0 or not is_finite(source.falloff) or source.falloff <= 0:
			errors.append("humidity_sources[%d]：位置、覆盖或浓度无效" % n)
		elif absf(source.position.x) > 12 or absf(source.position.y) > 10: errors.append("humidity_sources[%d]：中心超出地图编辑范围" % n)
	if not errors.is_empty(): return errors
	var terrain := preload("res://scripts/terrain_model.gd").new(to_layout())
	for n in 192:
		var p: Vector2 = terrain.island_point(n * TAU / 192.0)
		if absf(p.x) > 12.0 or absf(p.y) > 10.0:
			errors.append("岛形：海岸超出 24×20 编辑范围")
			break
	for n in mountains.size():
		var m := mountains[n]
		for k in 64:
			if not terrain.is_land(m.position + Vector2.from_angle(k * TAU / 64.0) * m.radius):
				errors.append("mountains[%d]：山脚须完整位于岛内" % n)
				break
	for n in plots.size():
		var valid := plots[n].is_finite()
		var region_value := region(n)
		var boundary := region_value.outline(plot_half)
		# Check every hill against the actual convex shape, including tiny hills between samples.
		for m in mountains:
			valid = valid and not region_value.contains(m.position - plots[n], plot_half)
			for k in boundary.size():
				var closest := Geometry2D.get_closest_point_to_segment(m.position, plots[n] + boundary[k], plots[n] + boundary[(k + 1) % boundary.size()])
				valid = valid and closest.distance_squared_to(m.position) >= m.radius * m.radius
		for k in boundary.size():
			for step in 9:
				var p := plots[n] + boundary[k].lerp(boundary[(k + 1) % boundary.size()], step / 8.0)
				valid = valid and terrain.is_land(p) and terrain.height(p) <= 0.22001
		if not valid: errors.append("plots[%d]：整个受雨区域须位于平坦陆地" % n)
	for a in plots.size():
		for b in range(a + 1, plots.size()):
			var first := region(a).outline(plot_half)
			var second := region(b).outline(plot_half)
			for k in first.size(): first[k] += plots[a]
			for k in second.size(): second[k] += plots[b]
			if not Geometry2D.intersect_polygons(first, second).is_empty(): errors.append("plots：受雨区域不能重叠")
	return errors
