extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.switch_mode("free")
	main.settings_path = "res://.godot/tuning-check.tres"
	main.sim.cloud[28 * Sim.WIDTH + 32] = 2.8
	main.sim.rain[28 * Sim.WIDTH + 32] = 1.4
	main.sim.plot_water = 110
	main.sim.wind.fill(Vector2(4, 0))
	main.sim.refresh_display()
	var cloud: PackedFloat32Array = main.sim.cloud.duplicate()
	var humidity: PackedFloat32Array = main.sim.humidity.duplicate()
	var before: float = main.sim.water_total()
	var settings: WRWeatherSettings = load("res://configs/weather.tres").duplicate(true)
	settings.brush_radius = 2
	settings.max_wind = 2
	settings.cloud_drag = 0.5
	settings.hold_seconds = 3.5
	settings.target_water = 105
	settings.three_star_finish_seconds = 1.5
	ResourceSaver.save(settings, main.settings_path)
	check(main.reload_tuning(), "A valid saved configuration is applied")
	check(main.sim.settings.brush_radius == 2 and main.sim.settings.cloud_drag == 0.5, "Live brush and cloud-response fields change immediately")
	check(main.sim.settings.hold_seconds == 2 and main.sim.settings.target_water == 100 and main.sim.settings.three_star_finish_seconds == 3, "Rain, goals and perfect countdown wait for restart")
	check(main.sim.cloud == cloud and main.sim.humidity == humidity and main.sim.plot_water == 110 and is_equal_approx(main.sim.water_total(), before), "Live tuning preserves the exact weather and water state")
	check(main.sim.wind[0].length() <= 2.00001, "Reducing the wind cap immediately respects the new cap")
	settings.max_wind = -1
	ResourceSaver.save(settings, main.settings_path)
	check(not main.reload_tuning() and main.sim.settings.max_wind == 2 and "max_wind" in main.tuning_message, "Invalid fields retain the live configuration and identify the field")
	settings.max_wind = 2
	ResourceSaver.save(settings, main.settings_path)
	main.restart(false)
	check(main.sim.settings.hold_seconds == 3.5 and main.sim.settings.target_water == 105 and main.sim.settings.three_star_finish_seconds == 1.5, "Restart applies deferred values from the file")
	check(main.sim.peak_density == 0 and main.sim.plot_water == 0 and main.sim.escaped_water == 0, "Restart returns to the humidity-only start")
	var original: WRWeatherSettings = load("res://configs/weather.tres")
	check(original.max_wind == 6 and original.hold_seconds == 2, "Tuning never mutates the shared default resource")
	main.custom_map_path = "res://.godot/tuning-map.tres"
	var map: WRMapDefinition = load("res://configs/maps/ridges.tres").duplicate(true)
	ResourceSaver.save(map, main.custom_map_path)
	main.restart(false)
	check(main.sim.layout_id == "ridges" and main.sim.terrain.mountains.size() == 2, "Restart rebuilds both simulation and rendering from the changed map")
	map.plots[0] = map.mountains[0].position
	ResourceSaver.save(map, main.custom_map_path)
	main.restart(false)
	check(main.sim.plot_centers[0] == Vector2(-6, 1.7) and "plots[0]" in main.tuning_message, "An invalid changed map keeps the prior valid map")
	main.queue_free()
	await process_frame
	print("TUNING: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
