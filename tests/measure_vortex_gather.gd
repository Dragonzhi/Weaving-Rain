extends SceneTree
## Controlled flat-field measurements, separate from normal-start playthrough evidence.
const Sim = preload("res://scripts/weather_simulation.gd")
var center := Vector2(5, 3)
func sample(sim: RefCounted, kind: String, time: float) -> Dictionary:
	var field: PackedFloat32Array = sim.humidity if kind == "humidity" else sim.cloud
	var mass := 0.0
	var core := 0.0
	var second := 0.0
	for i in Sim.COUNT:
		var distance: float = sim.positions[i].distance_to(center)
		mass += field[i]
		second += field[i] * distance * distance
		if distance <= 0.5: core += field[i]
	return {"seconds": time, "mass": mass, "core_fraction": core / maxf(mass, 0.000001), "rms_radius": sqrt(second / maxf(mass, 0.000001)), "rain_rate": sim.total_rain_rate, "water_error": sim.water_total() - sim.initial_water}
func _init() -> void:
	var records: Array = []
	var failures := 0
	for kind in ["humidity", "thin", "thick", "rain"]:
		var sim := Sim.new(load("res://configs/weather.tres"))
		sim.sandbox = true
		sim.humidity.fill(0)
		for i in Sim.COUNT:
			var p: Vector2 = sim.positions[i] - center
			var q := exp(-pow((p.length() - 1.4) / 0.4, 2))
			if kind == "humidity": sim.humidity[i] = q
			else: sim.cloud[i] = q * (0.4 if kind == "thin" else 2.0)
			if kind == "rain": sim.rain[i] = sim.cloud[i]
		sim.refresh_display()
		sim.initial_water = sim.water_total()
		sim.add_vortex(center, 2.5, 1, 1)
		var samples: Array = [sample(sim, kind, 0)]
		for tick in 901:
			sim.step(Sim.FIXED_STEP)
			if tick + 1 in [180, 480, 900]: samples.append(sample(sim, kind, (tick + 1) / 60.0))
		if samples[1].rms_radius >= samples[0].rms_radius or absf(sim.water_total() - sim.initial_water) > 0.01: failures += 1
		records.append({"kind": kind, "tier": 1, "radius": 2.5, "samples": samples})
		print("GATHER ", JSON.stringify(records[-1]))
	var file := FileAccess.open("res://.godot/vortex-gather.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("GATHER MEASUREMENTS: 4 fields, ", failures, " failures")
	quit(0 if failures == 0 else 1)
