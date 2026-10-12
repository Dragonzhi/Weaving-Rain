extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func empty() -> Sim:
	var sim := Sim.new()
	sim.humidity.fill(0)
	sim.cloud.fill(0)
	sim.cold.fill(0)
	sim.refresh_display()
	return sim

func sum(field: PackedFloat32Array) -> float:
	var total := 0.0
	for value in field: total += value
	return total

func _init() -> void:
	check(Sim.WIDTH == 64 and Sim.DEPTH == 56 and Sim.ORIGIN == Vector2(-16, -14), "Open domain retains 0.5 spacing with four-unit buffers")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var sim := empty()
		var x := 0 if direction.x < 0 else Sim.WIDTH - 1 if direction.x > 0 else Sim.WIDTH / 2
		var z := 0 if direction.y < 0 else Sim.DEPTH - 1 if direction.y > 0 else Sim.DEPTH / 2
		var i := z * Sim.WIDTH + x
		sim.humidity[i] = 2
		sim.cloud[i] = 4
		sim.rain[i] = 2
		sim.charge[i] = 4
		sim.cold[i] = 3
		sim.wind[i] = direction.normalized() * 6
		sim.low_wind[i] = sim.wind[i]
		sim.refresh_display()
		sim.initial_water = sim.water_total()
		sim._transport(0.5)
		check(sum(sim.humidity) + sum(sim.cloud) < 0.00001, "Weather exits without accumulation: " + str(direction))
		check(absf(sim.escaped_water - 6) < 0.00001 and absf(sim.water_total() - sim.initial_water) < 0.00001, "Exiting water is counted once: " + str(direction))
		check(sum(sim.rain) + sum(sim.charge) + sum(sim.cold) < 0.00001, "Rain, progress and cold exit with their parent fields: " + str(direction))
	var partial := empty()
	var edge := 28 * Sim.WIDTH + Sim.WIDTH - 1
	partial.humidity[edge] = 2
	partial.cloud[edge] = 4
	partial.rain[edge] = 2
	partial.charge[edge] = 3
	partial.wind[edge] = Vector2(0.5, 0)
	partial.low_wind[edge] = partial.wind[edge]
	partial.refresh_display()
	partial.initial_water = partial.water_total()
	partial._transport(0.25)
	check(sum(partial.cloud) > 0 and partial.escaped_water > 0, "Fractional boundary weights split retained and exited water")
	check(absf(sum(partial.rain) / sum(partial.cloud) - 0.5) < 0.00001 and absf(sum(partial.charge) / sum(partial.cloud) - 0.75) < 0.00001, "Partial outflow preserves rain and progress fractions")
	partial._dissipate_edges(0.25)
	check(absf(partial.water_total() - partial.initial_water) < 0.00001, "Buffer dissipation is included in the water budget")
	check(absf(sum(partial.rain) / sum(partial.cloud) - 0.5) < 0.00001, "Buffer dissipation does not separate rain from cloud")
	var inside := empty()
	var i := 28 * Sim.WIDTH + 32
	inside.humidity[i] = 3
	inside.cloud[i] = 2
	inside._dissipate_edges(1.0)
	check(inside.humidity[i] == 3 and inside.cloud[i] == 2 and inside.escaped_water == 0, "Interior weather is not consumed by the boundary buffer")
	check(inside.edge_visibility(Vector2(14, 0)) == 1 and inside.edge_visibility(Vector2(15, 0)) == 0.5 and inside.edge_visibility(Vector2(16, 0)) == 0, "Display and cloud picking share a smooth outward fade")
	var closed := empty()
	closed.settings.open_boundary = false
	closed.humidity[edge] = 2
	closed.low_wind[edge] = Vector2(6, 0)
	closed._transport(0.5)
	check(sum(closed.humidity) == 2 and closed.escaped_water == 0, "Closed developer reference keeps its original conservation behavior")
	var steady := empty()
	steady.humidity[edge] = 10
	steady.initial_water = steady.water_total()
	for n in 120:
		steady.wind.fill(Vector2(6, 0))
		steady._update_cold_flow()
		steady._transport(Sim.FIXED_STEP)
		steady._dissipate_edges(Sim.FIXED_STEP)
	check(sum(steady.humidity) < 0.0001 and steady.escaped_water > 9.999, "Sustained outward wind cannot create an air wall")
	check(absf(steady.water_total() - steady.initial_water) < 0.001, "Repeated outflow closes the water budget")
	var still := empty()
	still.cloud[i] = 2.0
	still.rain[i] = 0.5
	still.charge[i] = 0.75
	still.wind.fill(Vector2(1e-20, -1e-20))
	var cloud_bytes: PackedByteArray = still.cloud.to_byte_array()
	var rain_bytes: PackedByteArray = still.rain.to_byte_array()
	var progress_bytes: PackedByteArray = still.charge.to_byte_array()
	still._transport(Sim.FIXED_STEP)
	check(still.cloud.to_byte_array() == cloud_bytes and still.rain.to_byte_array() == rain_bytes and still.charge.to_byte_array() == progress_bytes, "Displacements below grid-coordinate precision preserve the exact cloud, rain and progress fields")
	print("OPEN BOUNDARY: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
