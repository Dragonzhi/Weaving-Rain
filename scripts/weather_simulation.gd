extends RefCounted
## cloud = total cloud water; rain = activated subset, transported together.
const Settings = preload("res://scripts/weather_settings.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const Terrain = preload("res://scripts/terrain_model.gd")
const WIDTH := 64
const DEPTH := 56
const COUNT := WIDTH * DEPTH
const CELL := 0.5
const ORIGIN := Vector2(-16.0, -14.0)
const CLOUD_HEIGHT := 3.6
const CLOUD_BOTTOM := 2.8
const CLOUD_TOP := 4.4
const PLOT := Vector2(2.8, 1.2)
const SECOND_PLOT := Vector2(3.6, -1.9)
const PLOT_HALF := 1.25
const SAFE_HALF := 2.1
const MOUNTAIN := Vector2(-1.7, -0.6)
const FIXED_STEP := 1.0 / 60.0

var settings: Settings
var escaped_water := 0.0
var overflow_water := 0.0
var evaporated_water := 0.0
var edge_indices := PackedInt32Array()
var edge_rates := PackedFloat32Array()
var plot_half := 1.25
var safe_half := 2.1
var humidity := PackedFloat32Array()
var cloud := PackedFloat32Array()
var rain := PackedFloat32Array()
var charge := PackedFloat32Array()
var wind := PackedVector2Array()
var lifted := PackedFloat32Array()
var display_cloud := PackedFloat32Array()
var display_rain := PackedFloat32Array()
var display_charge := PackedFloat32Array()
var positions := PackedVector2Array()
var grid_columns := PackedFloat64Array()
var grid_rows := PackedFloat64Array()
var slopes := PackedVector2Array()
var plot_waters := PackedFloat64Array()
# Compatibility names for the original single / dual-target development checks.
var plot_water: float:
	get: return plot_waters[0] if plot_waters.size() > 0 else 0.0
	set(value):
		if plot_waters.is_empty(): plot_waters.resize(1)
		plot_waters[0] = value
var rain_lost := 0.0
var initial_water := 0.0
var safe_time := 0.0
var outcome := "playing"
var max_progress := 0.0
var last_lift := 0.0
var threat := false
var peak_density := 0.0
var peak_position := Vector2.ZERO
var total_rain_rate := 0.0
## Actual rain released by the last fixed step, mass/second; display only, not stored water.
var ground_rain := PackedFloat32Array()
var sandbox := false
var relay_mode := false
var cold_capable := false
var total_mountain_lift := 0.0
var cold := PackedFloat32Array()
var display_cold := PackedFloat32Array()
var cold_flow := PackedVector2Array()
var low_wind := PackedVector2Array()
var cloud_wind := PackedVector2Array()
var tropical: RefCounted
var cold_lifted := PackedFloat32Array()
var total_cold_lift := 0.0
var cold_used := 0.0
var cold_lift_near_second := 0.0
var plot_centers := PackedVector2Array()
var second_water: float:
	get: return plot_waters[1] if plot_waters.size() > 1 else 0.0
	set(value):
		if plot_waters.size() < 2: plot_waters.resize(2)
		plot_waters[1] = value
var plot_regions: Array[WRPlotRegion] = []
var plot_needs: Array[WRPlotNeeds] = []
var plot_water_scales := PackedFloat64Array()
var plot_destroyed: Array[bool] = []
var star_level := false
var finish_safe_time := 0.0
var result_stars := 0
var result_saved_count := 0
var time_limit_seconds := 180.0
var elapsed_seconds := 0.0
var timed_out := false
var ended_for_shortage := false
var three_star_elapsed := -1.0
var remaining_humidity := 0.0
var remaining_cloud := 0.0
var safety_indices: Array[PackedInt32Array] = []
var plot_threats: Array[bool] = []
var plot_safe_times := PackedFloat32Array()
var neighbor_left := PackedInt32Array()
var neighbor_right := PackedInt32Array()
var neighbor_top := PackedInt32Array()
var neighbor_bottom := PackedInt32Array()
var cold_display_source := PackedByteArray()
var slope_indices := PackedInt32Array()
var layout_id := "standard"
var layout: Dictionary
var terrain: Terrain
var revision := 0
var next_humidity := PackedFloat32Array()
var next_cloud := PackedFloat32Array()
var next_rain := PackedFloat32Array()
var next_charge := PackedFloat32Array()
var next_cold := PackedFloat32Array()
var next_wind := PackedVector2Array()
var zero_wind_bytes := PackedByteArray()
var rain_targets := PackedInt32Array()
var smooth_row := PackedFloat64Array()
var rain_row := PackedFloat64Array()
var charge_row := PackedFloat64Array()
var cold_row := PackedFloat64Array()
var step_cold_gradients := PackedVector2Array()
var held_wind: Dictionary = {}
var wind_sources: Array[Dictionary] = []
var next_source_id := 1
var cloud_motion_velocity := PackedVector2Array()
var cloud_motion_revision := -1

func _init(config: Resource = null, relay: bool = false, single_cold: bool = false, fixed_layout: String = "standard", map_definition: WRMapDefinition = null) -> void:
	settings = config.duplicate(true) if config != null else Settings.new()
	plot_half = settings.plot_half
	safe_half = settings.safe_half
	relay_mode = relay
	cold_capable = relay or single_cold
	layout = map_definition.to_layout() if map_definition != null and relay else Layouts.get_layout(fixed_layout if relay else "standard")
	layout_id = layout.id
	terrain = Terrain.new(layout)
	if relay_mode:
		plot_centers = layout.plots.duplicate()
	else:
		plot_centers.append(PLOT)
	star_level = relay_mode and layout.get("star_level", false)
	time_limit_seconds = layout.get("time_limit_seconds", 180.0)
	for target in plot_centers.size():
		var region := WRPlotRegion.new()
		if relay_mode and target < layout.get("plot_regions", []).size() and layout.plot_regions[target] != null:
			region = layout.plot_regions[target].duplicate(true)
		plot_regions.append(region)
		var needs: WRPlotNeeds = null
		if relay_mode and target < layout.get("plot_needs", []).size() and layout.plot_needs[target] != null:
			needs = layout.plot_needs[target].duplicate(true)
		plot_needs.append(needs)
		plot_water_scales.append(settings.plot_water_scale * 4.0 * plot_half * plot_half / region.area(plot_half))
		safety_indices.append(PackedInt32Array())
	for i in COUNT:
		positions.append(cell_position(i))
		grid_columns.append(float(i % WIDTH))
		grid_rows.append(float(i / WIDTH))
		var p := positions[i]
		var edge_distance := minf(16.0 - absf(p.x), 14.0 - absf(p.y))
		if edge_distance < 2.0:
			edge_indices.append(i)
			edge_rates.append(pow(1.0 - edge_distance / 2.0, 2))
		slopes.append(terrain.slope(positions[i]))
		if slopes[i] != Vector2.ZERO: slope_indices.append(i)
		var rain_target := -1
		for target in plot_centers.size():
			var offset := positions[i] - plot_centers[target]
			if plot_regions[target].contains(offset, plot_half, safe_half - plot_half): safety_indices[target].append(i)
			if rain_target == -1 and plot_regions[target].contains(offset, plot_half):
				rain_target = target
		rain_targets.append(rain_target)
		var x := i % WIDTH
		var z := i / WIDTH
		var left := maxi(x - 1, 0)
		var right := mini(x + 1, WIDTH - 1)
		var top := maxi(z - 1, 0) * WIDTH
		var bottom := mini(z + 1, DEPTH - 1) * WIDTH
		neighbor_left.append(z * WIDTH + left)
		neighbor_right.append(z * WIDTH + right)
		neighbor_top.append(top + x)
		neighbor_bottom.append(bottom + x)
	reset()

func reset(test_cloud: bool = false) -> void:
	held_wind.clear()
	tropical = null
	wind_sources.clear()
	next_source_id = 1
	cloud_motion_revision = -1
	sandbox = test_cloud
	humidity.resize(COUNT)
	cloud.resize(COUNT)
	rain.resize(COUNT)
	ground_rain.resize(COUNT)
	ground_rain.fill(0.0)
	total_rain_rate = 0.0
	charge.resize(COUNT)
	lifted.resize(COUNT)
	wind.resize(COUNT)
	cold.resize(COUNT)
	cold_flow.resize(COUNT)
	low_wind.resize(COUNT)
	cold_lifted.resize(COUNT)
	cold.fill(0.0)
	cold_flow.fill(Vector2.ZERO)
	low_wind.fill(Vector2.ZERO)
	cold_lifted.fill(0.0)
	total_cold_lift = 0.0
	total_mountain_lift = 0.0
	cold_used = 0.0
	cold_lift_near_second = 0.0
	cloud.fill(0.0)
	rain.fill(0.0)
	charge.fill(0.0)
	wind.fill(Vector2.ZERO)
	zero_wind_bytes = wind.to_byte_array()
	lifted.fill(0.0)
	initial_water = 0.0
	for i in COUNT:
		var p := positions[i]
		humidity[i] = 0.0
		var sources: Array = layout.humidity_sources
		var count := sources.size() if relay_mode else mini(1, sources.size())
		for n in count:
			var source: WRHumiditySource = sources[n]
			var distance := (p - source.position) / source.spread
			humidity[i] += settings.initial_humidity * source.concentration * exp(-distance.length_squared() * source.falloff)
		if test_cloud:
			cloud[i] = 1.25 * exp(-pow((p.x - 0.6) / 2.1, 2) - pow((p.y - 0.3) / 1.0, 2))
			cloud[i] += 0.75 * exp(-pow((p.x + 1.4) / 1.4, 2) - pow((p.y + 0.6) / 1.1, 2))
			cloud[i] += 0.70 * exp(-pow((p.x - 2.6) / 1.5, 2) - pow((p.y - 0.9) / 0.8, 2))
		initial_water += humidity[i] + cloud[i]
	cloud_wind = wind
	if relay_mode and layout.get("warm_sea") != null and not test_cloud:
		tropical = preload("res://scripts/tropical_weather.gd").new(layout.warm_sea, self)
		cloud_wind = wind.duplicate()
	plot_waters.resize(plot_centers.size())
	plot_waters.fill(0.0)
	plot_threats.resize(plot_centers.size())
	plot_threats.fill(false)
	plot_destroyed.resize(plot_centers.size())
	plot_destroyed.fill(false)
	finish_safe_time = 0.0
	result_stars = 0
	result_saved_count = 0
	elapsed_seconds = 0.0
	timed_out = false
	ended_for_shortage = false
	three_star_elapsed = -1.0
	plot_safe_times.resize(plot_centers.size())
	plot_safe_times.fill(0.0)
	rain_lost = 0.0
	escaped_water = 0.0
	overflow_water = 0.0
	evaporated_water = 0.0
	safe_time = 0.0
	outcome = "playing"
	max_progress = 0.0
	last_lift = 0.0
	threat = false
	refresh_display()

static func cell_position(i: int) -> Vector2:
	return ORIGIN + Vector2(i % WIDTH + 0.5, floori(float(i) / WIDTH) + 0.5) * CELL

static func coast_radius(angle: float) -> float:
	return 1.0 + 0.12 * sin(angle * 3.0 + 0.3) + 0.075 * cos(angle * 5.0 - 0.7) + 0.025 * sin(angle * 7.0)

static func is_land(p: Vector2) -> bool:
	var q := Vector2((p.x + 0.6) / 8.5, (p.y - 0.3) / 5.5)
	return q.length() <= coast_radius(q.angle())

static func terrain_height(p: Vector2) -> float:
	if not is_land(p):
		return -0.08
	var d := p.distance_to(MOUNTAIN) / 3.0
	return 0.22 + 2.5 * pow(maxf(0.0, 1.0 - d * d), 2)

static func slope(p: Vector2) -> Vector2:
	var offset := p - MOUNTAIN
	var d2 := offset.length_squared() / 9.0
	return -offset * (10.0 / 9.0) * (1.0 - d2) if d2 < 1.0 else Vector2.ZERO

static func contains(p: Vector2) -> bool:
	return p.x >= ORIGIN.x and p.y >= ORIGIN.y and p.x < 16.0 and p.y < 14.0

func sample(field: PackedFloat32Array, p: Vector2) -> float:
	if not contains(p):
		return 0.0
	var g := (p - ORIGIN) / CELL - Vector2(0.5, 0.5)
	var x := floori(g.x)
	var z := floori(g.y)
	var fx := g.x - x
	var fz := g.y - z
	var x0 := clampi(x, 0, WIDTH - 1)
	var x1 := clampi(x + 1, 0, WIDTH - 1)
	var z0 := clampi(z, 0, DEPTH - 1) * WIDTH
	var z1 := clampi(z + 1, 0, DEPTH - 1) * WIDTH
	return lerpf(lerpf(field[z0 + x0], field[z0 + x1], fx), lerpf(field[z1 + x0], field[z1 + x1], fx), fz)

func density_at(p: Vector3) -> float:
	var q := sample_cloud(display_cloud, Vector2(p.x, p.z))
	if q < 0.04:
		return 0.0
	# Shared finite vertical profile with cloud.gdshader.
	var half_height := 0.12 + 0.58 * smoothstep(0.04, settings.cloud_threshold * 1.8, q)
	var y := (p.y - CLOUD_HEIGHT) / half_height
	return q * maxf(0.0, 1.0 - y * y)

func sample_cloud(field: PackedFloat32Array, p: Vector2) -> float:
	if not contains(p): return 0.0
	var g := (p - ORIGIN) / CELL - Vector2(0.5, 0.5)
	var base := Vector2i(g.floor())
	var wx := spline_weights(g.x - base.x)
	var wz := spline_weights(g.y - base.y)
	var result := 0.0
	for z in 4:
		var row := clampi(base.y + z - 1, 0, DEPTH - 1) * WIDTH
		for x in 4:
			result += field[row + clampi(base.x + x - 1, 0, WIDTH - 1)] * wx[x] * wz[z]
	return result * edge_visibility(p)

func edge_visibility(p: Vector2) -> float:
	return smoothstep(0.0, 2.0, minf(16.0 - absf(p.x), 14.0 - absf(p.y))) if settings.open_boundary else 1.0

static func spline_weights(f: float) -> Vector4:
	var f2 := f * f
	var f3 := f2 * f
	return Vector4(pow(1.0 - f, 3), 3.0 * f3 - 6.0 * f2 + 4.0, -3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0, f3) / 6.0

func pick_cloud(origin: Vector3, direction: Vector3) -> Variant:
	if direction.y >= -0.0001:
		return null
	var start := maxf(0.0, (CLOUD_TOP - origin.y) / direction.y)
	var end := (CLOUD_BOTTOM - origin.y) / direction.y
	var dt := (end - start) / 32.0
	var opacity := 0.0
	for i in 32:
		var p := origin + direction * (start + (i + 0.5) * dt)
		if p.y <= terrain.height(Vector2(p.x, p.z)):
			return null
		opacity += (1.0 - opacity) * (1.0 - exp(-density_at(p) * dt * 5.0))
		if opacity > 0.10:
			return p
	return null

func stroke(from: Vector2, to: Vector2, speed: float) -> void:
	var movement := to - from
	if movement.length() < 0.0001 or outcome != "playing":
		return
	var power := lerpf(settings.stroke_min_power, settings.stroke_max_power, clampf(speed / settings.stroke_speed_full, 0.0, 1.0))
	var steps := maxi(1, ceili(movement.length() / (CELL * 0.5)))
	var impulse := movement.normalized() * minf(movement.length(), 20.0) * power / steps
	for s in steps:
		var center := from.lerp(to, (s + 0.5) / steps)
		var lo := Vector2i(((center - Vector2.ONE * settings.brush_radius - ORIGIN) / CELL).floor())
		var hi := Vector2i(((center + Vector2.ONE * settings.brush_radius - ORIGIN) / CELL).ceil())
		for z in range(maxi(0, lo.y), mini(DEPTH, hi.y)):
			for x in range(maxi(0, lo.x), mini(WIDTH, hi.x)):
				var i := z * WIDTH + x
				var distance := positions[i].distance_to(center)
				if distance < settings.brush_radius:
					var weight := pow(1.0 - distance / settings.brush_radius, 2)
					wind[i] = (wind[i] + impulse * weight * settings.stroke_gain).limit_length(settings.max_wind)
					low_wind[i] = (wind[i] + cold_flow[i]).limit_length(settings.max_wind)

func set_held_wind(point: Vector2, direction: Vector2, strength: float) -> void:
	if contains(point) and direction.is_finite() and point.is_finite() and direction.length() > 0.0001 and is_finite(strength) and outcome == "playing":
		held_wind = {"position": point, "direction": direction.normalized(), "strength": clampf(strength, 0.0, 1.0)}
	else: clear_held_wind()

func clear_held_wind() -> void:
	held_wind.clear()

func add_wind_source(point: Vector2, direction: Vector2, strength: float, endpoint: Variant = null) -> Dictionary:
	if outcome != "playing" or not point.is_finite() or not contains(point) or not direction.is_finite() or direction.length() < 0.0001 or not is_finite(strength):
		return {"ok": false, "reason": "无效位置或方向"}
	var end: Vector2 = point
	if endpoint != null:
		if not endpoint is Vector2 or not endpoint.is_finite() or not contains(endpoint) or point.distance_to(endpoint) < 0.25:
			return {"ok": false, "reason": "风带终点须在天气区域内，长度至少 0.25"}
		end = endpoint
		direction = end - point
	if wind_sources.size() >= settings.source_limit:
		return {"ok": false, "reason": "先撤掉一个风源"}
	var id := next_source_id
	next_source_id += 1
	wind_sources.append({"id": id, "kind": "band", "position": point, "end": end, "direction": direction.normalized(), "strength": clampf(strength, 0.0, 1.0), "remaining": settings.source_lifetime, "lifetime": settings.source_lifetime, "fade": settings.source_fade_seconds})
	return {"ok": true, "id": id, "reason": ""}

func add_vortex(point: Vector2, radius: float, spin: int, tier: int) -> Dictionary:
	# Gesture limits are snapshotted on press; physical factory bounds stay valid during F6.
	if outcome != "playing" or not point.is_finite() or not contains(point) or not is_finite(radius) or radius < 0.5 or radius > 8.0 or spin not in [-1, 1] or tier < 0 or tier > 2:
		return {"ok": false, "reason": "无效漩涡范围、方向或档位"}
	if wind_sources.size() >= settings.source_limit: return {"ok": false, "reason": "先撤掉一个风源"}
	var id := next_source_id
	next_source_id += 1
	wind_sources.append({"id": id, "kind": "vortex", "position": point, "end": point, "radius": radius, "spin": spin, "tier": tier, "direction": Vector2.ZERO, "strength": tier / 2.0, "remaining": settings.source_lifetime, "lifetime": settings.source_lifetime, "fade": settings.source_fade_seconds})
	return {"ok": true, "id": id, "reason": ""}

func remove_wind_source(id: int) -> void:
	for index in wind_sources.size():
		if wind_sources[index].id == id:
			wind_sources.remove_at(index)
			return

func _accelerate_wind(point: Vector2, impulse: Vector2) -> void:
	var radius: float = settings.brush_radius
	var maximum: float = settings.max_wind
	var values := wind
	var lo := Vector2i(((point - Vector2.ONE * radius - ORIGIN) / CELL).floor())
	var hi := Vector2i(((point + Vector2.ONE * radius - ORIGIN) / CELL).ceil())
	for z in range(maxi(0, lo.y), mini(DEPTH, hi.y)):
		for x in range(maxi(0, lo.x), mini(WIDTH, hi.x)):
			var i := z * WIDTH + x
			var distance := positions[i].distance_to(point)
			if distance < radius:
				values[i] = (values[i] + impulse * pow(1.0 - distance / radius, 2)).limit_length(maximum)

func _accelerate_source(source: Dictionary, impulse: Vector2) -> void:
	# A placed source does not move. Reuse its exact soft weights until F6 changes
	# the radius; use doubles here so caching does not round the force differently.
	var radius: float = settings.brush_radius
	if source.get("brush_radius", -1.0) != radius:
		var cells := PackedInt32Array()
		var weights := PackedFloat64Array()
		var point: Vector2 = source.position
		var end: Vector2 = source.end
		var lo := Vector2i(((point.min(end) - Vector2.ONE * radius - ORIGIN) / CELL).floor())
		var hi := Vector2i(((point.max(end) + Vector2.ONE * radius - ORIGIN) / CELL).ceil())
		for z in range(maxi(0, lo.y), mini(DEPTH, hi.y)):
			for x in range(maxi(0, lo.x), mini(WIDTH, hi.x)):
				var i := z * WIDTH + x
				var distance := positions[i].distance_to(Geometry2D.get_closest_point_to_segment(positions[i], point, end))
				if distance < radius:
					cells.append(i)
					weights.append(pow(1.0 - distance / radius, 2))
		source.brush_radius = radius
		source.cells = cells
		source.weights = weights
	var cells: PackedInt32Array = source.cells
	var weights: PackedFloat64Array = source.weights
	var values := wind
	var maximum: float = settings.max_wind
	for n in cells.size():
		var i := cells[n]
		values[i] = (values[i] + impulse * weights[n]).limit_length(maximum)

func _accelerate_vortex(source: Dictionary, integral: float) -> void:
	if source.get("core_fraction", -1.0) != settings.vortex_core_fraction or source.get("edge_fraction", -1.0) != settings.vortex_edge_fraction:
		var cells := PackedInt32Array()
		var radial := PackedVector2Array()
		var tangent := PackedVector2Array()
		var point: Vector2 = source.position
		var radius: float = source.radius
		var core := maxf(CELL, radius * settings.vortex_core_fraction)
		var lo := Vector2i(((point - Vector2.ONE * radius - ORIGIN) / CELL).floor())
		var hi := Vector2i(((point + Vector2.ONE * radius - ORIGIN) / CELL).ceil())
		for z in range(maxi(0, lo.y), mini(DEPTH, hi.y)):
			for x in range(maxi(0, lo.x), mini(WIDTH, hi.x)):
				var i := z * WIDTH + x
				var q := positions[i] - point
				var distance := q.length()
				if distance >= radius: continue
				var weight := 1.0 - smoothstep(1.0 - settings.vortex_edge_fraction, 1.0, distance / radius)
				var vector := q / maxf(core, distance) * weight
				cells.append(i)
				radial.append(-vector)
				tangent.append(Vector2(-vector.y, vector.x) * source.spin)
		source.cells = cells
		source.radial = radial
		source.tangent = tangent
		source.core_fraction = settings.vortex_core_fraction
		source.edge_fraction = settings.vortex_edge_fraction
	var powers: Vector3 = settings.vortex_inward_acceleration
	var inward: float = powers[source.tier] * integral
	var rotation: float = settings.vortex_rotation_acceleration * integral
	var values := wind
	var cells: PackedInt32Array = source.cells
	var radial: PackedVector2Array = source.radial
	var tangent: PackedVector2Array = source.tangent
	for n in cells.size():
		var i := cells[n]
		values[i] = (values[i] + radial[n] * inward + tangent[n] * rotation).limit_length(settings.max_wind)

func _step_wind_sources(dt: float) -> void:
	if not held_wind.is_empty():
		var power := lerpf(settings.stroke_min_power, settings.stroke_max_power, held_wind.strength)
		_accelerate_wind(held_wind.position, held_wind.direction * settings.hold_gain * power * dt)
	for index in range(wind_sources.size() - 1, -1, -1):
		var source := wind_sources[index]
		var active := minf(dt, source.remaining)
		# Midpoint integration is exact within the linear fade; split at its boundary.
		var full := minf(active, maxf(0.0, source.remaining - source.fade))
		var fading := active - full
		var integral := full + fading * maxf(0.0, (source.remaining - full - fading * 0.5) / source.fade)
		var powers: Vector3 = settings.source_powers
		var power := lerpf(powers.x, powers.y, source.strength * 2.0) if source.strength <= 0.5 else lerpf(powers.y, powers.z, source.strength * 2.0 - 1.0)
		if source.get("kind", "band") == "vortex": _accelerate_vortex(source, integral)
		else: _accelerate_source(source, source.direction * settings.hold_gain * power * integral)
		source.remaining = maxf(0.0, source.remaining - dt)
		if source.remaining <= 0.000001: wind_sources.remove_at(index)

func step(dt: float) -> void:
	if outcome != "playing":
		return
	var remaining := dt
	while remaining > 0.000001:
		var tick := minf(remaining, FIXED_STEP)
		if timer_active(): tick = minf(tick, time_remaining())
		_step_fixed(tick)
		remaining -= tick
		if outcome != "playing":
			break

func _step_fixed(dt: float) -> void:
	_step_wind_sources(dt)
	if next_wind.size() != COUNT: next_wind.resize(COUNT)
	var wind_fade := exp(-settings.wind_decay * dt)
	var wind_spread: float = settings.wind_spread * dt
	var lift_rate: float = settings.lift_rate
	var cold_enabled: bool = cold_capable and settings.cold_enabled
	var rain_end: float = settings.rain_end_density
	var threshold: float = settings.cloud_threshold
	var hold: float = settings.hold_seconds
	var retreat: float = settings.progress_retreat
	var rain_rate: float = settings.rain_rate
	var cold_cap: float = settings.cold_cap
	var cold_source: float = settings.cold_from_rain
	var previous_wind := wind
	var updated_wind := next_wind
	# Exact native byte comparison includes developer-injected wind. Only the
	# all-positive-zero field can skip the identical zero diffusion calculation.
	if previous_wind.to_byte_array() == zero_wind_bytes:
		updated_wind.fill(Vector2.ZERO)
	else:
		for i in COUNT:
			var x := i % WIDTH
			# Interior cells have the same five contributors in the original order.
			# Avoid four boundary branches and incremental counts for those cells.
			if i >= WIDTH and i < COUNT - WIDTH and x > 0 and x < WIDTH - 1:
				var interior := previous_wind[i] + previous_wind[i - 1] + previous_wind[i + 1] + previous_wind[i - WIDTH] + previous_wind[i + WIDTH]
				updated_wind[i] = previous_wind[i].lerp(interior / 5.0, wind_spread) * wind_fade
				continue
			var z := i / WIDTH
			var average := previous_wind[i]
			var count := 1.0
			if x > 0:
				average += previous_wind[i - 1]
				count += 1.0
			if x < WIDTH - 1:
				average += previous_wind[i + 1]
				count += 1.0
			if z > 0:
				average += previous_wind[i - WIDTH]
				count += 1.0
			if z < DEPTH - 1:
				average += previous_wind[i + WIDTH]
				count += 1.0
			updated_wind[i] = previous_wind[i].lerp(average / count, wind_spread) * wind_fade
	var old_wind := wind
	wind = updated_wind
	next_wind = old_wind
	if tropical != null:
		tropical.prepare(dt, self)
		cloud_wind.resize(COUNT)
		for i in COUNT:
			cloud_wind[i] = (wind[i] + tropical.sea.background_wind + tropical.high_velocity[i]).limit_length(settings.max_wind)
	else:
		cloud_wind = wind
	_update_cold_flow()
	_transport(dt)
	if settings.open_boundary: _dissipate_edges(dt)
	lifted.fill(0.0)
	cold_lifted.fill(0.0)
	last_lift = 0.0
	for i in slope_indices:
		var uphill := maxf(0.0, low_wind[i].dot(slopes[i]))
		if uphill == 0.0: continue
		var amount := humidity[i] * (1.0 - exp(-uphill * lift_rate * dt))
		humidity[i] -= amount
		cloud[i] += amount
		lifted[i] = amount
		last_lift += amount
	total_mountain_lift += last_lift
	if cold_enabled:
		_lift_at_cold_front(dt)
	if tropical != null: tropical.lift(dt, self)
	display_cloud = _smooth(cloud)
	max_progress = 0.0
	total_rain_rate = 0.0
	ground_rain.fill(0.0)
	var stored_cloud := cloud
	var stored_rain := rain
	var stored_progress := charge
	var cloud_surface := display_cloud
	var cold_strength := cold
	var targets := rain_targets
	var base_rain: float = settings.rain_base_rate
	var cold_fade := exp(-settings.cold_decay * dt)
	var water := plot_waters
	var water_scales := plot_water_scales
	for i in COUNT:
		# All updates to rain/progress are exactly zero in this state. Preserve
		# cold decay, but avoid divisions and clamping across empty/thin cells.
		if stored_rain[i] == 0.0 and stored_progress[i] == 0.0 and cloud_surface[i] < threshold:
			cold_strength[i] *= cold_fade
			continue
		if stored_rain[i] > rain_end:
			stored_rain[i] = stored_cloud[i]
			stored_progress[i] = 0.0
		elif cloud_surface[i] >= threshold:
			stored_progress[i] = minf(stored_cloud[i] * hold, stored_progress[i] + stored_cloud[i] * dt)
			if stored_progress[i] >= stored_cloud[i] * (hold - 0.001) and stored_cloud[i] > 0.0:
				stored_rain[i] = stored_cloud[i]
				stored_progress[i] = 0.0
		else:
			stored_progress[i] = maxf(0.0, stored_progress[i] - maxf(stored_cloud[i], 0.1) * dt * retreat)
		stored_progress[i] = minf(stored_progress[i], stored_cloud[i] * hold)
		max_progress = maxf(max_progress, stored_progress[i] / maxf(stored_cloud[i], 0.0001) / hold)
		if stored_rain[i] > 0.0:
			var fallen := minf(stored_rain[i], (stored_rain[i] * rain_rate + base_rain) * dt)
			ground_rain[i] = fallen / dt
			stored_rain[i] -= fallen
			stored_cloud[i] -= fallen
			total_rain_rate += fallen / dt
			if cold_enabled:
				cold_strength[i] = minf(cold_cap, cold_strength[i] + fallen * cold_source)
			var target := targets[i]
			if target >= 0:
				if is_reservoir(target):
					var retained := minf(fallen, maxf(0.0, required_water(target) - water[target]) / water_scales[target])
					water[target] = minf(required_water(target), water[target] + retained * water_scales[target])
					overflow_water += fallen - retained
				else:
					water[target] += fallen * water_scales[target]
			else:
				rain_lost += fallen
			if stored_rain[i] < rain_end:
				humidity[i] += stored_rain[i]
				stored_cloud[i] -= stored_rain[i]
				stored_rain[i] = 0.0
		# This field has no cross-cell reads in the rain loop, so decay here is
		# identical to the former separate pass after all rain cells.
		cold_strength[i] *= cold_fade
	plot_waters = water
	refresh_display(total_rain_rate == 0.0)
	update_goal(dt)
	if timer_active():
		# Count weather time, so pause and deferred fixed steps never consume extra seconds.
		elapsed_seconds = minf(time_limit_seconds, elapsed_seconds + dt)
		if outcome == "playing" and time_remaining() <= 0.000000001:
			elapsed_seconds = time_limit_seconds
			timed_out = true
			result_saved_count = saved_plot_count()
			result_stars = earned_stars()
			outcome = "success" if result_stars > 0 else "timeout"
	_update_three_star_finish(dt)

func _transport(dt: float) -> void:
	# Local packed-array references avoid repeated member lookup in the hot scatter loops.
	var wet_in := humidity
	var cold_in := cold
	var cloud_in := cloud
	var rain_in := rain
	var charge_in := charge
	var cloud_display := display_cloud
	cloud_motion_velocity.resize(COUNT)
	var cloud_velocities := cloud_motion_velocity
	cloud_velocities.fill(Vector2.ZERO)
	var mouse_wind := cloud_wind
	var air_wind := low_wind
	var out_wet := next_humidity
	var out_cold := next_cold
	var out_cloud := next_cloud
	var out_rain := next_rain
	var out_charge := next_charge
	out_wet.resize(COUNT)
	out_cold.resize(COUNT)
	out_cloud.resize(COUNT)
	out_rain.resize(COUNT)
	out_charge.resize(COUNT)
	out_wet.fill(0.0)
	out_cold.fill(0.0)
	out_cloud.fill(0.0)
	out_rain.fill(0.0)
	out_charge.fill(0.0)
	var open_edges: bool = settings.open_boundary
	var drag: float = settings.cloud_drag
	var rain_drag: float = settings.rainy_cloud_response
	var rain_response: float = settings.rain_response
	var columns := grid_columns
	var rows := grid_rows
	for i in COUNT:
		if wet_in[i] <= 0.0000001 and cold_in[i] <= 0.0000001: continue
		var x := columns[i]
		var z := rows[i]
		var shift := air_wind[i] * dt / CELL
		var gx := x + shift.x
		var gz := z + shift.y
		# The two low-air fields share a displacement, so compute its stencil once.
		var wet := wet_in[i] if wet_in[i] > 0.0000001 else 0.0
		var cool := cold_in[i] if cold_in[i] > 0.0000001 else 0.0
		if gx == x and gz == z:
			out_wet[i] += wet
			out_cold[i] += cool
			continue
		if open_edges and (gx < 0 or gx > WIDTH - 1 or gz < 0 or gz > DEPTH - 1):
			var left := floori(gx)
			var top := floori(gz)
			var fx := gx - left
			var fz := gz - top
			for dz in 2:
				for dx in 2:
					var weight := (fx if dx == 1 else 1.0 - fx) * (fz if dz == 1 else 1.0 - fz)
					if left + dx < 0 or left + dx >= WIDTH or top + dz < 0 or top + dz >= DEPTH:
						escaped_water += wet * weight
					else:
						var index := (top + dz) * WIDTH + left + dx
						out_wet[index] += wet * weight
						out_cold[index] += cool * weight
			continue
		if not open_edges:
			gx = clampf(gx, 0.0, WIDTH - 1.0)
			gz = clampf(gz, 0.0, DEPTH - 1.0)
		var left := floori(gx)
		var top := floori(gz)
		var fx := gx - left
		var fz := gz - top
		var right := mini(left + 1, WIDTH - 1)
		var bottom := mini(top + 1, DEPTH - 1)
		var a := top * WIDTH + left
		var b := top * WIDTH + right
		var c := bottom * WIDTH + left
		var d := bottom * WIDTH + right
		var wa := (1.0 - fx) * (1.0 - fz)
		var wb := fx * (1.0 - fz)
		var wc := (1.0 - fx) * fz
		var wd := fx * fz
		if wet > 0.0:
			out_wet[a] += wet * wa
			out_wet[b] += wet * wb
			out_wet[c] += wet * wc
			out_wet[d] += wet * wd
		if cool > 0.0:
			out_cold[a] += cool * wa
			out_cold[b] += cool * wb
			out_cold[c] += cool * wc
			out_cold[d] += cool * wd
	for i in COUNT:
		if cloud_in[i] <= 0.0: continue
		# Exact zero wind cannot displace any of the coupled cloud fields.
		# Its cached velocity is already zero; no response calculation is needed.
		if mouse_wind[i] == Vector2.ZERO:
			out_cloud[i] += cloud_in[i]
			out_rain[i] += rain_in[i]
			out_charge[i] += charge_in[i]
			continue
		var x := columns[i]
		var z := rows[i]
		var fraction := rain_in[i] / maxf(cloud_in[i], 0.0001)
		# Cache the exact transport velocity instead of calling a helper per occupied cell.
		var response := clampf(1.0 / (1.0 + cloud_display[i] * drag) * lerpf(1.0, rain_drag, fraction), rain_response, 1.0)
		cloud_velocities[i] = mouse_wind[i] * response
		var shift := mouse_wind[i] * dt * response / CELL
		var gx := x + shift.x
		var gz := z + shift.y
		var water := cloud_in[i]
		var active := rain_in[i]
		var progress := charge_in[i]
		if gx == x and gz == z:
			out_cloud[i] += water
			out_rain[i] += active
			out_charge[i] += progress
			continue
		if open_edges and (gx < 0 or gx > WIDTH - 1 or gz < 0 or gz > DEPTH - 1):
			var left := floori(gx)
			var top := floori(gz)
			var fx := gx - left
			var fz := gz - top
			for dz in 2:
				for dx in 2:
					var weight := (fx if dx == 1 else 1.0 - fx) * (fz if dz == 1 else 1.0 - fz)
					if left + dx < 0 or left + dx >= WIDTH or top + dz < 0 or top + dz >= DEPTH:
						escaped_water += water * weight
					else:
						var index := (top + dz) * WIDTH + left + dx
						out_cloud[index] += water * weight
						out_rain[index] += active * weight
						out_charge[index] += progress * weight
			continue
		if not open_edges:
			gx = clampf(gx, 0.0, WIDTH - 1.0)
			gz = clampf(gz, 0.0, DEPTH - 1.0)
		var left := floori(gx)
		var top := floori(gz)
		var fx := gx - left
		var fz := gz - top
		var right := mini(left + 1, WIDTH - 1)
		var bottom := mini(top + 1, DEPTH - 1)
		var a := top * WIDTH + left
		var b := top * WIDTH + right
		var c := bottom * WIDTH + left
		var d := bottom * WIDTH + right
		var wa := (1.0 - fx) * (1.0 - fz)
		var wb := fx * (1.0 - fz)
		var wc := (1.0 - fx) * fz
		var wd := fx * fz
		out_cloud[a] += water * wa
		out_cloud[b] += water * wb
		out_cloud[c] += water * wc
		out_cloud[d] += water * wd
		if active > 0.0:
			out_rain[a] += active * wa
			out_rain[b] += active * wb
			out_rain[c] += active * wc
			out_rain[d] += active * wd
		if progress > 0.0:
			out_charge[a] += progress * wa
			out_charge[b] += progress * wb
			out_charge[c] += progress * wc
			out_charge[d] += progress * wd
	humidity = out_wet
	cloud_motion_revision = revision + 1
	cold = out_cold
	cloud = out_cloud
	rain = out_rain
	charge = out_charge
	next_humidity = wet_in
	next_cold = cold_in
	next_cloud = cloud_in
	next_rain = rain_in
	next_charge = charge_in

func _update_cold_flow() -> void:
	# The previous publication already smoothed this exact field. Comparing a native
	# byte array also catches direct development injection without floating-point comparisons
	# of subnormal cold remnants or a second GDScript pass.
	if cold.to_byte_array() != cold_display_source:
		display_cold = _smooth(cold)
		cold_display_source = cold.to_byte_array()
	step_cold_gradients.resize(COUNT)
	var cold_enabled: bool = cold_capable and settings.cold_enabled
	var outflow: float = settings.cold_outflow
	var max_cold: float = settings.cold_max_speed
	var max_wind: float = settings.max_wind
	var cold_display := display_cold
	var left_indices := neighbor_left
	var right_indices := neighbor_right
	var top_indices := neighbor_top
	var bottom_indices := neighbor_bottom
	var gradients := step_cold_gradients
	var flows := cold_flow
	var air_wind := low_wind
	var mouse_wind := wind
	for i in COUNT:
		var velocity := Vector2.ZERO
		if cold_enabled:
			var gradient := Vector2(cold_display[right_indices[i]] - cold_display[left_indices[i]], cold_display[bottom_indices[i]] - cold_display[top_indices[i]]) / (2.0 * CELL)
			gradients[i] = gradient
			velocity = (-gradient * outflow).limit_length(max_cold)
		flows[i] = velocity
		var ambient := mouse_wind[i]
		if tropical != null: ambient += tropical.sea.background_wind + tropical.low_velocity[i]
		air_wind[i] = (ambient + velocity).limit_length(max_wind)

func cold_gradient(i: int) -> Vector2:
	return Vector2(display_cold[neighbor_right[i]] - display_cold[neighbor_left[i]], display_cold[neighbor_bottom[i]] - display_cold[neighbor_top[i]]) / (2.0 * CELL)

func _lift_at_cold_front(dt: float) -> void:
	var minimum: float = settings.cold_minimum
	var lift_rate: float = settings.cold_lift_rate
	var cost: float = settings.cold_lift_cost
	var cool := cold
	var wet := humidity
	var clouds := cloud
	var air_velocity := low_wind
	var gradients := step_cold_gradients
	var lifts := lifted
	var front_lifts := cold_lifted
	var points := positions
	var has_second := plot_centers.size() > 1
	var second := plot_centers[1] if has_second else Vector2.ZERO
	for i in COUNT:
		if cool[i] < minimum or wet[i] < 0.001:
			continue
		var gradient := gradients[i]
		var gradient_length := gradient.length()
		if gradient_length < 0.035:
			continue
		var outward := -gradient.normalized()
		# Require moisture moving against the outward front. Contact or co-flow is insufficient.
		var incoming := maxf(0.0, -air_velocity[i].dot(outward) - 0.08)
		if incoming == 0.0: continue
		var squeeze := incoming * minf(gradient_length * 2.0, 1.0)
		var strength := smoothstep(minimum, 0.8, cool[i])
		var amount := wet[i] * (1.0 - exp(-squeeze * strength * lift_rate * dt))
		amount = minf(amount, cool[i] / maxf(cost, 0.001))
		wet[i] -= amount
		clouds[i] += amount
		cool[i] = maxf(0.0, cool[i] - amount * cost)
		lifts[i] += amount
		front_lifts[i] = amount
		last_lift += amount
		total_cold_lift += amount
		cold_used += amount * cost
		if has_second and absf(points[i].x - second.x) <= safe_half and absf(points[i].y - second.y) <= safe_half:
			cold_lift_near_second += amount
	humidity = wet
	cloud = clouds
	cold = cool
	lifted = lifts
	cold_lifted = front_lifts

func cloud_response(i: int) -> float:
	var fraction := rain[i] / maxf(cloud[i], 0.0001)
	return cloud_response_value(display_cloud[i], fraction, settings.cloud_drag, settings.rainy_cloud_response, settings.rain_response)

static func cloud_response_value(density: float, fraction: float, drag: float, rainy_response: float, minimum: float) -> float:
	return clampf(1.0 / (1.0 + density * drag) * lerpf(1.0, rainy_response, fraction), minimum, 1.0)

func cloud_velocity_at(p: Vector2) -> Vector2:
	if not contains(p): return Vector2.ZERO
	var g := (p - ORIGIN) / CELL - Vector2(0.5, 0.5)
	var x := floori(g.x)
	var z := floori(g.y)
	var result := Vector2.ZERO
	for dz in 2:
		for dx in 2:
			var i := clampi(z + dz, 0, DEPTH - 1) * WIDTH + clampi(x + dx, 0, WIDTH - 1)
			var weight := (g.x - x if dx else 1.0 - (g.x - x)) * (g.y - z if dz else 1.0 - (g.y - z))
			var velocity := cloud_motion_velocity[i] if cloud_motion_revision == revision else cloud_wind[i] * cloud_response(i)
			result += velocity * weight
	return result

func velocity_at(p: Vector2, low: bool = true) -> Vector2:
	return _sample_velocity(low_wind if low else cloud_wind, p)

func ambient_velocity_at(p: Vector2) -> Vector2:
	if not contains(p): return Vector2.ZERO
	return _sample_velocity(wind, p) + (tropical.sea.background_wind if tropical != null else Vector2.ZERO)

func _sample_velocity(field: PackedVector2Array, p: Vector2) -> Vector2:
	if not contains(p):
		return Vector2.ZERO
	var g := (p - ORIGIN) / CELL - Vector2(0.5, 0.5)
	var x := floori(g.x)
	var z := floori(g.y)
	var a := field[clampi(z, 0, DEPTH - 1) * WIDTH + clampi(x, 0, WIDTH - 1)]
	var b := field[clampi(z, 0, DEPTH - 1) * WIDTH + clampi(x + 1, 0, WIDTH - 1)]
	var c := field[clampi(z + 1, 0, DEPTH - 1) * WIDTH + clampi(x, 0, WIDTH - 1)]
	var d := field[clampi(z + 1, 0, DEPTH - 1) * WIDTH + clampi(x + 1, 0, WIDTH - 1)]
	return a.lerp(b, g.x - x).lerp(c.lerp(d, g.x - x), g.y - z)

func required_water(target: int) -> float:
	return plot_needs[target].target_water if plot_needs[target] != null else settings.target_water

func is_reservoir(target: int) -> bool:
	return plot_needs[target] != null and plot_needs[target].goal_kind == "reservoir"

func target_complete(target: int) -> bool:
	if is_reservoir(target): return water_for(target) >= required_water(target)
	return not plot_destroyed[target] and plot_safe_times[target] >= settings.safe_seconds

func flood_limit(target: int) -> float:
	return plot_needs[target].flood_water if plot_needs[target] != null else settings.flood_water

func plot_name(target: int) -> String:
	return plot_needs[target].display_name if plot_needs[target] != null else ""

func plot_progress(target: int) -> float:
	return clampf(water_for(target) / required_water(target), 0.0, 1.0)

func plot_warning(target: int) -> float:
	if is_reservoir(target): return 0.0
	return clampf((water_for(target) - required_water(target)) / (flood_limit(target) - required_water(target)), 0.0, 1.0)

func water_for(target: int) -> float:
	return plot_waters[target]

func plot_status(target: int) -> String:
	# One shared interpretation for the field card, transition feedback and final result.
	if is_reservoir(target): return "safe" if target_complete(target) else "dry"
	if plot_destroyed[target]: return "destroyed"
	if water_for(target) < required_water(target): return "dry"
	if plot_threats[target]: return "danger"
	if plot_safe_times[target] < settings.safe_seconds: return "confirming"
	return "safe"

func _smooth(field: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(COUNT)
	smooth_row.resize(COUNT)
	var rows := smooth_row
	var left_indices := neighbor_left
	var right_indices := neighbor_right
	var top_indices := neighbor_top
	var bottom_indices := neighbor_bottom
	# The same 3x3 [1,2,1] kernel, with double-precision intermediate rows.
	# Separating the two axes reduces repeated neighbor reads without extra rounding.
	for i in COUNT:
		rows[i] = field[left_indices[i]] + field[i] * 2.0 + field[right_indices[i]]
	for i in COUNT:
		result[i] = (rows[top_indices[i]] + rows[i] * 2.0 + rows[bottom_indices[i]]) / 16.0
	return result

func refresh_display(cloud_current: bool = false) -> void:
	if not cloud_current: display_cloud = _smooth(cloud)
	display_rain.resize(COUNT)
	display_charge.resize(COUNT)
	display_cold.resize(COUNT)
	rain_row.resize(COUNT)
	charge_row.resize(COUNT)
	cold_row.resize(COUNT)
	var rain_values := rain
	var charge_values := charge
	var cold_values := cold
	var rain_rows := rain_row
	var charge_rows := charge_row
	var cold_rows := cold_row
	var rain_display := display_rain
	var charge_display := display_charge
	var cold_display := display_cold
	var left_indices := neighbor_left
	var right_indices := neighbor_right
	var top_indices := neighbor_top
	var bottom_indices := neighbor_bottom
	var cloud_display := display_cloud
	for i in COUNT:
		rain_rows[i] = rain_values[left_indices[i]] + rain_values[i] * 2.0 + rain_values[right_indices[i]]
		charge_rows[i] = charge_values[left_indices[i]] + charge_values[i] * 2.0 + charge_values[right_indices[i]]
		cold_rows[i] = cold_values[left_indices[i]] + cold_values[i] * 2.0 + cold_values[right_indices[i]]
	for i in COUNT:
		rain_display[i] = (rain_rows[top_indices[i]] + rain_rows[i] * 2.0 + rain_rows[bottom_indices[i]]) / 16.0
		charge_display[i] = (charge_rows[top_indices[i]] + charge_rows[i] * 2.0 + charge_rows[bottom_indices[i]]) / 16.0
		cold_display[i] = (cold_rows[top_indices[i]] + cold_rows[i] * 2.0 + cold_rows[bottom_indices[i]]) / 16.0
	cold_display_source = cold.to_byte_array()
	peak_density = 0.0
	var wet_values := humidity
	var cloud_values := cloud
	var wet_total := 0.0
	var cloud_total := 0.0
	for i in COUNT:
		wet_total += wet_values[i]
		cloud_total += cloud_values[i]
		if cloud_display[i] > peak_density:
			peak_density = cloud_display[i]
			peak_position = positions[i]
	remaining_humidity = wet_total
	remaining_cloud = cloud_total
	revision += 1

func update_goal(dt: float) -> void:
	threat = false
	var complete := true
	for target in plot_centers.size():
		if is_reservoir(target):
			plot_threats[target] = false
			complete = complete and target_complete(target)
			continue
		var danger := false
		for i in safety_indices[target]:
			var visible_progress: bool = charge[i] > 0.01 and display_cloud[i] > 0.12
			if rain[i] > 0.0 or display_cloud[i] >= settings.cloud_threshold or visible_progress:
				danger = true
				break
		plot_threats[target] = danger
		if water_for(target) > flood_limit(target) and not sandbox:
			plot_destroyed[target] = true
			if not star_level: outcome = "flood"
		threat = threat or (danger and not plot_destroyed[target])
		plot_safe_times[target] = plot_safe_times[target] + dt if water_for(target) >= required_water(target) and not danger and not plot_destroyed[target] else 0.0
		complete = complete and plot_safe_times[target] >= settings.safe_seconds
	safe_time = plot_safe_times[0]
	if star_level:
		# Safety runs alongside individual readiness, rather than adding a second wait after the first star.
		finish_safe_time = minf(settings.safe_seconds, finish_safe_time + dt) if not threat else 0.0
		if plot_destroyed.all(func(value): return value) and not sandbox: outcome = "flood"
	elif complete and outcome != "flood" and not sandbox:
		outcome = "success"
	if not _has_three_stars(): three_star_elapsed = -1.0

func saved_plot_count() -> int:
	var count := 0
	for target in plot_centers.size():
		if target_complete(target): count += 1
	return count

func earned_stars() -> int:
	return preload("res://scripts/level_rating.gd").stars(saved_plot_count(), plot_centers.size())

func can_finish() -> bool:
	return star_level and not sandbox and outcome == "playing" and earned_stars() > 0 and not threat and finish_safe_time >= settings.safe_seconds

func _has_three_stars() -> bool:
	return star_level and not sandbox and outcome == "playing" and plot_centers.size() > 0 and saved_plot_count() == plot_centers.size()

func three_star_remaining() -> float:
	if not _has_three_stars() or three_star_elapsed < 0.0: return -1.0
	return maxf(0.0, settings.three_star_finish_seconds - three_star_elapsed)

func _update_three_star_finish(dt: float) -> void:
	if not _has_three_stars():
		three_star_elapsed = -1.0
		return
	if three_star_elapsed < 0.0:
		# Begin only after every field's safety interval has actually completed.
		three_star_elapsed = 0.0
	else:
		three_star_elapsed += dt
		if three_star_elapsed + 0.000000001 >= settings.three_star_finish_seconds: finish()

func timer_active() -> bool:
	return star_level and not sandbox

func time_remaining() -> float:
	return maxf(0.0, time_limit_seconds - elapsed_seconds)

func weather_reserve() -> float:
	# Raw published water, not the smoothed rendering field. Rain is already inside cloud.
	return remaining_humidity + remaining_cloud

func minimum_water_needed() -> float:
	var needed := INF
	for target in plot_centers.size():
		if plot_destroyed[target] or water_for(target) >= required_water(target): continue
		needed = minf(needed, (required_water(target) - water_for(target)) / plot_water_scales[target])
	return needed

func water_insufficient() -> bool:
	if tropical != null and tropical.has_supply(settings): return false
	var needed := minimum_water_needed()
	# Assume every remaining drop can reach the cheapest field: a conservative impossibility test.
	# If all surviving fields already have enough water, only safety remains, not a water shortage.
	return is_finite(needed) and weather_reserve() + maxf(0.000001, initial_water * 0.0000001) < needed

func can_end_shortage() -> bool:
	return star_level and not sandbox and outcome == "playing" and water_insufficient()

func finish() -> bool:
	if not can_finish() and not can_end_shortage(): return false
	ended_for_shortage = can_end_shortage()
	result_saved_count = saved_plot_count()
	result_stars = earned_stars()
	outcome = "success" if result_stars > 0 else "shortage"
	return true

func water_total() -> float:
	var total: float = escaped_water + rain_lost + overflow_water
	for target in plot_centers.size(): total += plot_waters[target] / plot_water_scales[target]
	for i in COUNT:
		total += humidity[i] + cloud[i]
	return total

func water_error() -> float:
	return water_total() - initial_water - evaporated_water

func _dissipate_edges(dt: float) -> void:
	var decay: float = settings.edge_decay * dt
	var wet := humidity
	var stored_cloud := cloud
	var stored_rain := rain
	var stored_progress := charge
	var cold_strength := cold
	for n in edge_indices.size():
		var i := edge_indices[n]
		var remaining := exp(-decay * edge_rates[n])
		escaped_water += (wet[i] + stored_cloud[i]) * (1.0 - remaining)
		wet[i] *= remaining
		stored_cloud[i] *= remaining
		stored_rain[i] *= remaining
		stored_progress[i] *= remaining
		cold_strength[i] *= remaining
