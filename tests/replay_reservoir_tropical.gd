extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Route = preload("res://tests/star_route.gd")
func _init() -> void:
	var layout := "storm_coast"
	var order := [1, 0]
	var loss := false
	var pure := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="): layout = arg.trim_prefix("--layout=")
		if arg == "--reverse": order = [0, 1]
		if arg == "--loss":
			loss = true
			order = [0, 1]
		if arg == "--pure": pure = true
	var map: WRMapDefinition = load("res://configs/maps/" + layout + ".tres").duplicate(true)
	if pure:
		map.warm_sea.seed_organization = 0
		map.warm_sea.initial_cloud_fraction = 0
	var sim := Sim.new(load("res://configs/weather.tres"), true, false, layout, map)
	var controller := Route.new(order, "tropical" if sim.tropical != null else "mountain")
	if sim.tropical != null:
		controller.farm_lookahead = 7.0
		controller.farm_floor_fraction = 0.2
		controller.clear_to_next = false
	if loss: controller.late_clear_seconds = 12.0
	if pure: sim.add_vortex(map.warm_sea.seed_position, 2.5, -1, 1)
	var next_at := 0.0
	var trajectory: Array = []
	while sim.outcome == "playing":
		if sim.elapsed_seconds >= next_at:
			trajectory.append([sim.elapsed_seconds, sim.water_for(0), sim.water_for(1), sim.total_rain_rate])
			var command := controller.next_command(sim, sim.elapsed_seconds)
			if not command.is_empty(): sim.stroke(command.from, command.to, command.speed)
			next_at += 0.25
		sim.step(1.0 / 60.0)
		if loss and sim.plot_destroyed[0] and sim.target_complete(1) and sim.can_finish(): sim.finish()
	var report := controller.report(sim)
	report["initial_water"] = sim.initial_water
	report["trajectory"] = trajectory
	report["evaporated_water"] = sim.evaporated_water
	report["overflow_water"] = sim.overflow_water
	report["escaped_water"] = sim.escaped_water
	report["pure_start"] = pure
	report["natural_lift"] = sim.tropical.total_lift if sim.tropical != null else 0.0
	report["ending"] = "loss_finish" if loss else "full_countdown"
	var name := layout + ("-loss" if loss else "-pure" if pure else "-farm-first" if order[0] == 0 else "-pool-first")
	var file := FileAccess.open("res://.godot/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	report.erase("trajectory")
	print("RESERVOIR ROUTE ", JSON.stringify(report))
	var success: bool = sim.result_stars == (1 if loss else 3) and not sim.timed_out and absf(sim.water_error()) < 0.02
	if loss: success = success and sim.plot_destroyed[0] and sim.target_complete(1)
	quit(0 if success else 1)
