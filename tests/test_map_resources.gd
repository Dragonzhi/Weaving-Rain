extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const Loader = preload("res://scripts/config_loader.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _init() -> void:
	for id in Layouts.IDS:
		var definition := Layouts.get_definition(id)
		check(definition.validation_errors().is_empty(), "Authored map is valid: " + id)
		var path: String = "res://.godot/map-" + id + "-check.tres"
		var result := ResourceSaver.save(definition.duplicate(true), path)
		var loaded := Loader.map(path, 1.25)
		check(result == OK and loaded.errors.is_empty() and loaded.resource.to_layout().plots == definition.plots, "Map survives save/reload: " + id)
	var standard := Sim.new(null, true)
	var maximum_error := 0.0
	for i in Sim.COUNT:
		maximum_error = maxf(maximum_error, absf(standard.terrain.height(standard.positions[i]) - Sim.terrain_height(standard.positions[i])))
	check(maximum_error < 0.000001, "Resource migration preserves the original terrain height field")
	var ridges := Sim.new(null, true, false, "ridges")
	check(ridges.terrain.mountains.size() == 2 and ridges.peak_density == 0, "Multi-mountain map starts with only humidity")
	var valid_slopes := true
	for m in ridges.terrain.mountains:
		var p := m.position + Vector2(0.7, 0.2)
		var dx := (ridges.terrain.height(p + Vector2(0.001, 0)) - ridges.terrain.height(p - Vector2(0.001, 0))) / 0.002
		var dz := (ridges.terrain.height(p + Vector2(0, 0.001)) - ridges.terrain.height(p - Vector2(0, 0.001))) / 0.002
		valid_slopes = valid_slopes and ridges.terrain.slope(p).distance_to(Vector2(dx, dz)) < 0.001
	check(valid_slopes, "Every mountain's simulation slope matches the rendered height field")
	var overlap: WRMapDefinition = Layouts.get_definition("ridges").duplicate(true)
	overlap.mountains[1].position = overlap.mountains[0].position
	var terrain := preload("res://scripts/terrain_model.gd").new(overlap.to_layout())
	check(is_equal_approx(terrain.height(overlap.mountains[0].position), 0.22 + 2.3), "Overlapping mountains use maximum height without summation")
	var invalid: WRMapDefinition = overlap.duplicate(true)
	invalid.mountains[0].height = 3.0
	check("mountains[0]" in " ".join(invalid.validation_errors()), "Cloud-layer intersections report a specific mountain")
	invalid = overlap.duplicate(true)
	invalid.plots[0] = invalid.mountains[0].position
	check("plots[0]" in " ".join(invalid.validation_errors()), "A target inside a mountain is rejected")
	invalid = overlap.duplicate(true)
	invalid.plots[1] = invalid.plots[0]
	check("不能重叠" in " ".join(invalid.validation_errors()), "Overlapping rain credit regions are rejected")
	invalid = overlap.duplicate(true)
	invalid.island_axes = Vector2(20, 20)
	check("编辑范围" in " ".join(invalid.validation_errors()), "An oversized island is rejected")
	invalid = overlap.duplicate(true)
	invalid.humidity_sources[0].spread = Vector2.ZERO
	check("humidity_sources[0]" in " ".join(invalid.validation_errors()), "Invalid humidity fields are named")
	invalid = overlap.duplicate(true)
	var tiny := WRMountain.new()
	tiny.position = invalid.plots[0] + Vector2(0.31, 0.31)
	tiny.radius = 0.1
	invalid.mountains.append(tiny)
	check("plots[0]" in " ".join(invalid.validation_errors()), "A tiny mountain between terrain samples still invalidates a target")
	print("MAP RESOURCES: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
