extends RefCounted
## A single authored tropical environment. Water remains exclusively in the simulation grids.
var sea: WRWarmSea
var center := Vector2.ZERO
var motion := Vector2.ZERO
var organization := 0.0
var strength := 0.0
var stage := "对流组织中"
var heat := PackedFloat32Array()
var timers := PackedFloat32Array()
var indices := PackedInt32Array()
var low_velocity := PackedVector2Array()
var high_velocity := PackedVector2Array()
var last_lift := 0.0
var total_lift := 0.0
var heat_mean := 0.0
var supply_rate := 0.0
var weakening := false
var stage_id := 0

func _init(definition: WRWarmSea, sim: RefCounted) -> void:
	sea = definition.duplicate(true)
	center = sea.seed_position
	organization = sea.seed_organization
	strength = organization
	heat.resize(sim.COUNT)
	timers.resize(sim.COUNT)
	low_velocity.resize(sim.COUNT)
	high_velocity.resize(sim.COUNT)
	for i in sim.COUNT:
		if sim.terrain.is_land(sim.positions[i]): continue
		var w := sea.weight(sim.positions[i])
		if w <= 0.0: continue
		heat[i] = sea.initial_energy * w
		indices.append(i)
		var converted: float = sim.humidity[i] * sea.initial_cloud_fraction * w
		sim.humidity[i] -= converted
		sim.cloud[i] += converted
	_refresh_stage()

func has_supply(settings: WRWeatherSettings) -> bool:
	if settings.tropical_evaporation == 0.0: return false
	for i in indices:
		if heat[i] > settings.tropical_energy_min: return true
	return false

func prepare(dt: float, sim: RefCounted) -> void:
	var settings: WRWeatherSettings = sim.settings
	var steering := Vector2.ZERO
	for n in 16:
		var offset := Vector2.from_angle(n * TAU / 16.0) * settings.tropical_radius
		steering += sim.ambient_velocity_at(center + offset)
	steering = (steering / 16.0 * settings.tropical_steering_gain).limit_length(settings.tropical_motion_cap)
	motion = motion.lerp(steering, 1.0 - exp(-dt * settings.tropical_steering_response))
	center += motion * dt
	strength = lerpf(strength, organization, 1.0 - exp(-dt * 0.6))
	supply_rate = 0.0
	heat_mean = 0.0
	var supports := 0
	for i in indices:
		var distance: float = sim.positions[i].distance_to(center) / settings.tropical_radius
		var influence := pow(maxf(0.0, 1.0 - distance * distance), 2)
		heat[i] = maxf(0.0, heat[i] - settings.tropical_cooling * strength * strength * influence * dt)
		if heat[i] > settings.tropical_energy_min:
			var added: float = settings.tropical_evaporation * heat[i] * dt
			var before: float = sim.humidity[i]
			sim.humidity[i] += added
			# Account the representable addition to the authoritative float32 field.
			added = sim.humidity[i] - before
			sim.evaporated_water += added
			supply_rate += added / dt
		if influence > 0.1:
			heat_mean += heat[i]
			supports += 1
	if supports > 0: heat_mean /= supports
	low_velocity.fill(Vector2.ZERO)
	high_velocity.fill(Vector2.ZERO)
	if strength <= 0.00001: return
	var radius: float = settings.tropical_radius
	# Only the current influence rectangle needs analytic wind evaluation.
	var start: Vector2i = ((center - Vector2.ONE * radius - sim.ORIGIN) / sim.CELL).floor()
	var finish: Vector2i = ((center + Vector2.ONE * radius - sim.ORIGIN) / sim.CELL).ceil()
	var spin := -1.0 if sea.hemisphere == 0 else 1.0
	for z in range(maxi(0, start.y), mini(sim.DEPTH, finish.y + 1)):
		for x in range(maxi(0, start.x), mini(sim.WIDTH, finish.x + 1)):
			var i: int = z * sim.WIDTH + x
			var offset: Vector2 = sim.positions[i] - center
			var distance := offset.length()
			if distance >= radius or distance < 0.00001: continue
			var radial := offset / distance
			var tangent := Vector2(-radial.y, radial.x) * spin
			var q := distance / radius
			var profile := sin(q * PI) * sin(q * PI)
			low_velocity[i] = (tangent * settings.tropical_rotation - radial * settings.tropical_inflow) * strength * profile
			high_velocity[i] = (tangent * settings.tropical_rotation + radial * settings.tropical_cloud_outflow) * strength * profile

func lift(dt: float, sim: RefCounted) -> void:
	var settings: WRWeatherSettings = sim.settings
	last_lift = 0.0
	for i in indices:
		var ready: bool = heat[i] > settings.tropical_energy_min and sim.humidity[i] >= settings.tropical_humidity_min
		var convergence: float = -((sim.low_wind[sim.neighbor_right[i]].x - sim.low_wind[sim.neighbor_left[i]].x) + (sim.low_wind[sim.neighbor_bottom[i]].y - sim.low_wind[sim.neighbor_top[i]].y)) / (2.0 * sim.CELL)
		ready = ready and convergence >= settings.tropical_convergence_min
		timers[i] = minf(settings.tropical_convection_seconds, timers[i] + dt) if ready else maxf(0.0, timers[i] - dt * 2.0)
		if not ready or timers[i] + 0.000001 < settings.tropical_convection_seconds: continue
		var offset: Vector2 = sim.positions[i] - center
		var q := offset.length() / settings.tropical_radius
		var band := exp(-pow((q - 0.5) / 0.28, 2)) if organization > 0.05 else 1.0
		# Uneven actual convection, not a visual mask, organizes two broad cloud arms.
		band *= 0.75 + 0.25 * sin(offset.angle() * 2.0 + q * 7.0)
		var amount: float = sim.humidity[i] * (1.0 - exp(-settings.tropical_lift_rate * convergence * heat[i] * band * dt))
		sim.humidity[i] -= amount
		sim.cloud[i] += amount
		sim.lifted[i] += amount
		sim.last_lift += amount
		last_lift += amount
	total_lift += last_lift
	var rotation := 0.0
	var spin := -1.0 if sea.hemisphere == 0 else 1.0
	for n in 16:
		var radial := Vector2.from_angle(n * TAU / 16.0)
		var point := center + radial * settings.tropical_radius * 0.5
		var velocity: Vector2 = sim.ambient_velocity_at(point)
		var cell: Vector2i = ((point - sim.ORIGIN) / sim.CELL).floor()
		if cell.x >= 0 and cell.x < sim.WIDTH and cell.y >= 0 and cell.y < sim.DEPTH:
			velocity += low_velocity[cell.y * sim.WIDTH + cell.x]
		rotation += velocity.dot(Vector2(-radial.y, radial.x) * spin)
	rotation = maxf(0.0, rotation / 16.0)
	var activity := minf(1.0, last_lift / dt / settings.tropical_support_rate)
	var support := activity * minf(1.0, rotation / settings.tropical_rotation_min) * clampf(heat_mean / 0.3, 0.0, 1.0)
	weakening = support < organization - 0.05
	var response: float = settings.tropical_growth if support > organization else settings.tropical_decay
	organization = lerpf(organization, support, 1.0 - exp(-dt * response))
	_refresh_stage()

func _refresh_stage() -> void:
	if stage_id == 0 and organization >= 0.2: stage_id = 1
	if stage_id == 1 and organization >= 0.72: stage_id = 2
	if stage_id == 2 and organization < 0.62: stage_id = 1
	if stage_id == 1 and organization < 0.12: stage_id = 0
	if weakening and organization > 0.12: stage = "衰弱中"
	elif stage_id == 2: stage = "热带风暴"
	elif stage_id == 1: stage = "热带低压"
	else: stage = "对流组织中"
