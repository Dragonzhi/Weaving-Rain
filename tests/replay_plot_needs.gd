extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Route = preload("res://tests/star_route.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var order := [0, 1]
	var late := 0.0
	var trace := "--trace" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg == "--reverse": order = [1, 0]
		if arg.begins_with("--late="): late = float(arg.trim_prefix("--late="))
	var config := preload("res://scripts/config_loader.gd").settings("res://configs/weather.tres")
	var map := preload("res://scripts/config_loader.gd").map("res://configs/maps/needs_lab.tres", 1.25)
	if not config.errors.is_empty() or not map.errors.is_empty(): push_error("Invalid needs replay inputs"); quit(1); return
	var sim := Sim.new(config.resource, true, false, "needs_lab", map.resource)
	var controller := Route.new(order)
	controller.late_clear_seconds = late
	for tick in 10801:
		if tick % 30 == 0:
			var command := controller.next_command(sim, tick / 60.0)
			if trace: print("TRACE ", tick / 60.0, " ", sim.plot_waters, " ", command.get("kind", ""), " ", command.get("target", -1))
			if not command.is_empty(): sim.stroke(command.from, command.to, command.speed)
		sim.step(Sim.FIXED_STEP)
		if sim.can_finish() and (sim.earned_stars() == 2 or (late > 0 and sim.plot_destroyed.any(func(v): return v))): sim.finish()
		if tick % 1200 == 0: print("NEEDS t=", tick / 60.0, " water=", sim.plot_waters, " destroyed=", sim.plot_destroyed)
		if sim.outcome != "playing": break
	var report := controller.report(sim)
	report["late"] = late
	var suffix := "late" if late > 0 else ("reverse" if order[0] == 1 else "ordinary")
	var file := FileAccess.open("res://.godot/needs-route-" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("NEEDS ROUTE ", JSON.stringify(report))
	var pass_result: bool = sim.result_stars == 1 and sim.plot_destroyed.any(func(v): return v) if late > 0 else sim.result_stars == 2
	quit(0 if pass_result and sim.outcome == "success" and not sim.timed_out and absf(report.water_error) < 0.01 else 1)
