extends RefCounted
## cloud = total cloud water; rain = activated subset, transported together.
const Settings = preload("res://scripts/weather_settings.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const Terrain = preload("res://scripts/terrain_model.gd")
const WIDTH := 48
const DEPTH := 40
const COUNT := WIDTH * DEPTH
const CELL := 0.5
const ORIGIN := Vector2(-12.0, -10.0)
const CLOUD_HEIGHT := 3.6
const CLOUD_BOTTOM := 2.8
const CLOUD_TOP := 4.4
const PLOT := Vector2(2.8, 1.2)
const SECOND_PLOT := Vector2(3.6, -2.2)
const PLOT_HALF := 1.25
const SAFE_HALF := 2.1
const MOUNTAIN := Vector2(-1.7, -0.6)
const FIXED_STEP := 1.0 / 60.0

var settings: Resource
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
var slopes := PackedVector2Array()
var plot_water := 0.0
var rain_lost := 0.0
var initial_water := 0.0
var safe_time := 0.0
var outcome := "playing"
var max_progress := 0.0
var last_lift := 0.0
var threat := false
var peak_density := 0.0
var total_rain_rate := 0.0
var sandbox := false
var relay_mode := false
var cold_capable := false
var total_mountain_lift := 0.0
var cold := PackedFloat32Array()
var display_cold := PackedFloat32Array()
var cold_flow := PackedVector2Array()
var low_wind := PackedVector2Array()
var cold_lifted := PackedFloat32Array()
var total_cold_lift := 0.0
var cold_used := 0.0
var cold_lift_near_second := 0.0
var plot_centers := PackedVector2Array()
var second_water := 0.0
var plot_threats: Array[bool] = []
var plot_safe_times := PackedFloat32Array()
var smoothing_stencils: Array[PackedInt32Array] = []
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
var rain_targets := PackedInt32Array()
var smooth_row := PackedFloat64Array()
var rain_row := PackedFloat64Array()
var charge_row := PackedFloat64Array()
var cold_row := PackedFloat64Array()
var step_cold_gradients := PackedVector2Array()

func _init(config: Resource = null, relay: bool = false, single_cold: bool = false, fixed_layout: String = "standard") -> void:
	settings = config if config != null else Settings.new()
	relay_mode = relay
	cold_capable = relay or single_cold
	layout = Layouts.get_layout(fixed_layout if relay else "standard")
	layout_id = layout.id
	terrain = Terrain.new(layout)
	if relay_mode:
		plot_centers = layout.plots.duplicate()
	else:
		plot_centers.append(PLOT)
	for i in COUNT:
		positions.append(cell_position(i))
		slopes.append(terrain.slope(positions[i]))
		var rain_target := -1
		for target in plot_centers.size():
			var offset := positions[i] - plot_centers[target]
			if absf(offset.x) <= PLOT_HALF and absf(offset.y) <= PLOT_HALF:
				rain_target = target
				break
		rain_targets.append(rain_target)
		var x := i % WIDTH
		var z := i / WIDTH
		var left := maxi(x - 1, 0)
		var right := mini(x + 1, WIDTH - 1)
		var top := maxi(z - 1, 0) * WIDTH
		var bottom := mini(z + 1, DEPTH - 1) * WIDTH
		smoothing_stencils.append(PackedInt32Array([top + left, top + x, top + right, z * WIDTH + left, i, z * WIDTH + right, bottom + left, bottom + x, bottom + right]))
	reset()

func reset(test_cloud: bool = false) -> void:
	sandbox = test_cloud
	humidity.resize(COUNT)
	cloud.resize(COUNT)
	rain.resize(COUNT)
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
	lifted.fill(0.0)
	initial_water = 0.0
	for i in COUNT:
		var p := positions[i]
		var distance := pow((p.x + 6.2) / 3.0, 2) + pow((p.y - 1.4) / 3.6, 2)
		if layout_id != "standard":
			var west: Vector2 = layout.west_air
			distance = pow((p.x - west.x) / 3.0, 2) + pow((p.y - west.y) / 3.6, 2)
		humidity[i] = settings.initial_humidity * exp(-distance * 1.4)
		if relay_mode:
			var east := pow((p.x - 5.6) / 3.2, 2) + pow((p.y - 1.0) / 3.4, 2)
			if layout_id != "standard":
				var center: Vector2 = layout.east_air
				east = pow((p.x - center.x) / 3.2, 2) + pow((p.y - center.y) / 3.4, 2)
			humidity[i] += settings.initial_humidity * 0.9 * exp(-east * 1.4)
		if test_cloud:
			cloud[i] = 1.25 * exp(-pow((p.x - 0.6) / 2.1, 2) - pow((p.y - 0.3) / 1.0, 2))
			cloud[i] += 0.75 * exp(-pow((p.x + 1.4) / 1.4, 2) - pow((p.y + 0.6) / 1.1, 2))
			cloud[i] += 0.70 * exp(-pow((p.x - 2.6) / 1.5, 2) - pow((p.y - 0.9) / 0.8, 2))
		initial_water += humidity[i] + cloud[i]
	plot_water = 0.0
	second_water = 0.0
	plot_threats.assign([false, false] if relay_mode else [false])
	plot_safe_times.resize(plot_centers.size())
	plot_safe_times.fill(0.0)
	rain_lost = 0.0
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
	return p.x >= ORIGIN.x and p.y >= ORIGIN.y and p.x < 12.0 and p.y < 10.0

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
	return result

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
	var power := lerpf(0.35, 2.5, clampf(speed / 16.0, 0.0, 1.0))
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
					wind[i] = (wind[i] + impulse * weight * 3.0).limit_length(settings.max_wind)
					low_wind[i] = (wind[i] + cold_flow[i]).limit_length(settings.max_wind)

func step(dt: float) -> void:
	if outcome != "playing":
		return
	var remaining := dt
	while remaining > 0.000001:
		var tick := minf(remaining, FIXED_STEP)
		_step_fixed(tick)
		remaining -= tick
		if outcome != "playing":
			break

func _step_fixed(dt: float) -> void:
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
	var water_scale: float = settings.plot_water_scale
	for i in COUNT:
		var x := i % WIDTH
		var z := i / WIDTH
		var average := wind[i]
		var count := 1.0
		if x > 0:
			average += wind[i - 1]
			count += 1.0
		if x < WIDTH - 1:
			average += wind[i + 1]
			count += 1.0
		if z > 0:
			average += wind[i - WIDTH]
			count += 1.0
		if z < DEPTH - 1:
			average += wind[i + WIDTH]
			count += 1.0
		next_wind[i] = wind[i].lerp(average / count, wind_spread) * wind_fade
	var old_wind := wind
	wind = next_wind
	next_wind = old_wind
	_update_cold_flow()
	_transport(dt)
	lifted.fill(0.0)
	cold_lifted.fill(0.0)
	last_lift = 0.0
	for i in COUNT:
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
	display_cloud = _smooth(cloud)
	max_progress = 0.0
	total_rain_rate = 0.0
	for i in COUNT:
		if rain[i] > rain_end:
			rain[i] = cloud[i]
			charge[i] = 0.0
		elif display_cloud[i] >= threshold:
			charge[i] = minf(cloud[i] * hold, charge[i] + cloud[i] * dt)
			if charge[i] >= cloud[i] * (hold - 0.001) and cloud[i] > 0.0:
				rain[i] = cloud[i]
				charge[i] = 0.0
		else:
			charge[i] = maxf(0.0, charge[i] - maxf(cloud[i], 0.1) * dt * retreat)
		charge[i] = minf(charge[i], cloud[i] * hold)
		max_progress = maxf(max_progress, charge[i] / maxf(cloud[i], 0.0001) / hold)
		if rain[i] > 0.0:
			var fallen := minf(rain[i], (rain[i] * rain_rate + 0.008) * dt)
			rain[i] -= fallen
			cloud[i] -= fallen
			total_rain_rate += fallen / dt
			if cold_enabled:
				cold[i] = minf(cold_cap, cold[i] + fallen * cold_source)
			var target := rain_targets[i]
			if target == 0:
				plot_water += fallen * water_scale
			elif target == 1:
				second_water += fallen * water_scale
			else:
				rain_lost += fallen
			if rain[i] < rain_end:
				humidity[i] += rain[i]
				cloud[i] -= rain[i]
				rain[i] = 0.0
	var cold_fade := exp(-settings.cold_decay * dt)
	for i in COUNT:
		cold[i] *= cold_fade
	refresh_display(total_rain_rate == 0.0)
	update_goal(dt)

func _transport(dt: float) -> void:
	var rain_response: float = settings.rain_response
	next_humidity.resize(COUNT)
	next_cloud.resize(COUNT)
	next_rain.resize(COUNT)
	next_charge.resize(COUNT)
	next_cold.resize(COUNT)
	next_humidity.fill(0.0)
	next_cloud.fill(0.0)
	next_rain.fill(0.0)
	next_charge.fill(0.0)
	next_cold.fill(0.0)
	for i in COUNT:
		var x := float(i % WIDTH)
		var z := float(i / WIDTH)
		if humidity[i] > 0.0000001 or cold[i] > 0.0000001:
			_scatter_low(next_humidity, next_cold, i, x, z, low_wind[i] * dt / CELL)
		if cloud[i] <= 0.0:
			continue
		var rain_fraction := rain[i] / maxf(cloud[i], 0.0001)
		var response := clampf(1.0 / (1.0 + display_cloud[i] * 0.22) * lerpf(1.0, 0.42, rain_fraction), rain_response, 1.0)
		var shift := wind[i] * dt * response / CELL
		_scatter_cloud(i, x, z, shift)
	var previous_humidity := humidity
	var previous_cloud := cloud
	var previous_rain := rain
	var previous_charge := charge
	var previous_cold := cold
	humidity = next_humidity
	cloud = next_cloud
	rain = next_rain
	charge = next_charge
	cold = next_cold
	next_humidity = previous_humidity
	next_cloud = previous_cloud
	next_rain = previous_rain
	next_charge = previous_charge
	next_cold = previous_cold

func _scatter_cloud(i: int, x: float, z: float, shift: Vector2) -> void:
	var water := cloud[i]
	var active := rain[i]
	var progress := charge[i]
	if shift == Vector2.ZERO:
		next_cloud[i] += water
		next_rain[i] += active
		next_charge[i] += progress
		return
	var gx := clampf(x + shift.x, 0.0, WIDTH - 1.0)
	var gz := clampf(z + shift.y, 0.0, DEPTH - 1.0)
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
	next_cloud[a] += water * wa
	next_cloud[b] += water * wb
	next_cloud[c] += water * wc
	next_cloud[d] += water * wd
	if active > 0.0:
		next_rain[a] += active * wa
		next_rain[b] += active * wb
		next_rain[c] += active * wc
		next_rain[d] += active * wd
	if progress > 0.0:
		next_charge[a] += progress * wa
		next_charge[b] += progress * wb
		next_charge[c] += progress * wc
		next_charge[d] += progress * wd

func _update_cold_flow() -> void:
	display_cold = _smooth(cold)
	step_cold_gradients.resize(COUNT)
	var cold_enabled: bool = cold_capable and settings.cold_enabled
	var outflow: float = settings.cold_outflow
	var max_cold: float = settings.cold_max_speed
	var max_wind: float = settings.max_wind
	for i in COUNT:
		var velocity := Vector2.ZERO
		if cold_enabled:
			var n := smoothing_stencils[i]
			var gradient := Vector2(display_cold[n[5]] - display_cold[n[3]], display_cold[n[7]] - display_cold[n[1]]) / (2.0 * CELL)
			step_cold_gradients[i] = gradient
			velocity = (-gradient * outflow).limit_length(max_cold)
		cold_flow[i] = velocity
		low_wind[i] = (wind[i] + velocity).limit_length(max_wind)

func cold_gradient(i: int) -> Vector2:
	var n := smoothing_stencils[i]
	return Vector2(display_cold[n[5]] - display_cold[n[3]], display_cold[n[7]] - display_cold[n[1]]) / (2.0 * CELL)

func _lift_at_cold_front(dt: float) -> void:
	var minimum: float = settings.cold_minimum
	var lift_rate: float = settings.cold_lift_rate
	var cost: float = settings.cold_lift_cost
	for i in COUNT:
		if cold[i] < minimum or humidity[i] < 0.001:
			continue
		var gradient := step_cold_gradients[i]
		var gradient_length := gradient.length()
		if gradient_length < 0.035:
			continue
		var outward := -gradient.normalized()
		# Require moisture moving against the outward front. Contact or co-flow is insufficient.
		var incoming := maxf(0.0, -low_wind[i].dot(outward) - 0.08)
		if incoming == 0.0: continue
		var squeeze := incoming * minf(gradient_length * 2.0, 1.0)
		var strength := smoothstep(minimum, 0.8, cold[i])
		var amount := humidity[i] * (1.0 - exp(-squeeze * strength * lift_rate * dt))
		amount = minf(amount, cold[i] / maxf(cost, 0.001))
		humidity[i] -= amount
		cloud[i] += amount
		cold[i] = maxf(0.0, cold[i] - amount * cost)
		lifted[i] += amount
		cold_lifted[i] = amount
		last_lift += amount
		total_cold_lift += amount
		cold_used += amount * cost
		if relay_mode and absf(positions[i].x - plot_centers[1].x) <= SAFE_HALF and absf(positions[i].y - plot_centers[1].y) <= SAFE_HALF:
			cold_lift_near_second += amount

func velocity_at(p: Vector2, low: bool = true) -> Vector2:
	if not contains(p):
		return Vector2.ZERO
	var g := (p - ORIGIN) / CELL - Vector2(0.5, 0.5)
	var x := floori(g.x)
	var z := floori(g.y)
	var field := low_wind if low else wind
	var a := field[clampi(z, 0, DEPTH - 1) * WIDTH + clampi(x, 0, WIDTH - 1)]
	var b := field[clampi(z, 0, DEPTH - 1) * WIDTH + clampi(x + 1, 0, WIDTH - 1)]
	var c := field[clampi(z + 1, 0, DEPTH - 1) * WIDTH + clampi(x, 0, WIDTH - 1)]
	var d := field[clampi(z + 1, 0, DEPTH - 1) * WIDTH + clampi(x + 1, 0, WIDTH - 1)]
	return a.lerp(b, g.x - x).lerp(c.lerp(d, g.x - x), g.y - z)

func water_for(target: int) -> float:
	return plot_water if target == 0 else second_water

func _scatter_low(next_humidity: PackedFloat32Array, next_cold: PackedFloat32Array, i: int, x: float, z: float, shift: Vector2) -> void:
	# The two low-air fields share a displacement, so compute its stencil once.
	var wet := humidity[i] if humidity[i] > 0.0000001 else 0.0
	var cool := cold[i] if cold[i] > 0.0000001 else 0.0
	if shift == Vector2.ZERO:
		next_humidity[i] += wet
		next_cold[i] += cool
		return
	var gx := clampf(x + shift.x, 0.0, WIDTH - 1.0)
	var gz := clampf(z + shift.y, 0.0, DEPTH - 1.0)
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
		next_humidity[a] += wet * wa
		next_humidity[b] += wet * wb
		next_humidity[c] += wet * wc
		next_humidity[d] += wet * wd
	if cool > 0.0:
		next_cold[a] += cool * wa
		next_cold[b] += cool * wb
		next_cold[c] += cool * wc
		next_cold[d] += cool * wd

func _smooth(field: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(COUNT)
	smooth_row.resize(COUNT)
	# The same 3x3 [1,2,1] kernel, with double-precision intermediate rows.
	# Separating the two axes reduces repeated neighbor reads without extra rounding.
	for i in COUNT:
		var n := smoothing_stencils[i]
		smooth_row[i] = field[n[3]] + field[i] * 2.0 + field[n[5]]
	for i in COUNT:
		var n := smoothing_stencils[i]
		result[i] = (smooth_row[n[1]] + smooth_row[i] * 2.0 + smooth_row[n[7]]) / 16.0
	return result

func refresh_display(cloud_current: bool = false) -> void:
	if not cloud_current: display_cloud = _smooth(cloud)
	display_rain.resize(COUNT)
	display_charge.resize(COUNT)
	display_cold.resize(COUNT)
	rain_row.resize(COUNT)
	charge_row.resize(COUNT)
	cold_row.resize(COUNT)
	for i in COUNT:
		var n := smoothing_stencils[i]
		rain_row[i] = rain[n[3]] + rain[i] * 2.0 + rain[n[5]]
		charge_row[i] = charge[n[3]] + charge[i] * 2.0 + charge[n[5]]
		cold_row[i] = cold[n[3]] + cold[i] * 2.0 + cold[n[5]]
	for i in COUNT:
		var n := smoothing_stencils[i]
		display_rain[i] = (rain_row[n[1]] + rain_row[i] * 2.0 + rain_row[n[7]]) / 16.0
		display_charge[i] = (charge_row[n[1]] + charge_row[i] * 2.0 + charge_row[n[7]]) / 16.0
		display_cold[i] = (cold_row[n[1]] + cold_row[i] * 2.0 + cold_row[n[7]]) / 16.0
	peak_density = 0.0
	for q in display_cloud:
		peak_density = maxf(peak_density, q)
	revision += 1

func update_goal(dt: float) -> void:
	threat = false
	var complete := true
	for target in plot_centers.size():
		var danger := false
		var center := plot_centers[target]
		var lo := Vector2i(((center - Vector2.ONE * SAFE_HALF - ORIGIN) / CELL).floor())
		var hi := Vector2i(((center + Vector2.ONE * SAFE_HALF - ORIGIN) / CELL).ceil())
		for z in range(maxi(0, lo.y), mini(DEPTH, hi.y)):
			for x in range(maxi(0, lo.x), mini(WIDTH, hi.x)):
				var i := z * WIDTH + x
				var p := positions[i]
				if absf(p.x - center.x) <= SAFE_HALF and absf(p.y - center.y) <= SAFE_HALF:
					var visible_progress: bool = charge[i] > 0.01 and display_cloud[i] > 0.12
					if rain[i] > 0.0 or display_cloud[i] >= settings.cloud_threshold or visible_progress:
						danger = true
						break
			if danger:
				break
		plot_threats[target] = danger
		threat = threat or danger
		if water_for(target) > settings.flood_water and not sandbox:
			outcome = "flood"
		plot_safe_times[target] = plot_safe_times[target] + dt if water_for(target) >= settings.target_water and not danger else 0.0
		complete = complete and plot_safe_times[target] >= settings.safe_seconds
	safe_time = plot_safe_times[0]
	if complete and outcome != "flood" and not sandbox:
		outcome = "success"

func water_total() -> float:
	var total: float = rain_lost + (plot_water + second_water) / settings.plot_water_scale
	for i in COUNT:
		total += humidity[i] + cloud[i]
	return total
