extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Route = preload("res://tests/star_route.gd")
const Loader = preload("res://scripts/config_loader.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var layout := "meadow"
	var mode := "mountain"
	var order := [0, 1, 2]
	var output := "res://.godot/star-route.json"
	var stop_on_loss := "--stop-on-loss" in OS.get_cmdline_user_args()
	var partial := "--partial" in OS.get_cmdline_user_args()
	var late_clear := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="): layout = arg.trim_prefix("--layout=")
		if arg.begins_with("--route="): mode = arg.trim_prefix("--route=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--late-clear="): late_clear = float(arg.trim_prefix("--late-clear="))
		if arg.begins_with("--order="):
			order.clear()
			for label in arg.trim_prefix("--order=").split(","): order.append(int(label))
	if order.size() != 3 or not order.has(0) or not order.has(1) or not order.has(2) or not mode in ["mountain", "relay"]:
		push_error("order must contain 0,1,2 once; route must be mountain or relay")
		quit(1)
		return
	var config := Loader.settings("res://configs/weather.tres")
	if not config.errors.is_empty():
		push_error("Invalid weather configuration: " + "；".join(config.errors))
		quit(1)
		return
	var sim := Sim.new(config.resource, true, false, layout)
	if not sim.star_level or sim.plot_centers.size() != 3 or not is_finite(late_clear) or late_clear < 0.0 or late_clear > 30.0:
		push_error("Replay requires a three-plot star map and a finite late-clear delay in 0–30 seconds")
		quit(1)
		return
	var errors: PackedStringArray = preload("res://scripts/weather_layouts.gd").get_definition(layout).validation_errors()
	if not errors.is_empty():
		push_error("Invalid replay map: " + "；".join(errors))
		quit(1)
		return
	var controller := Route.new(order, mode)
	controller.late_clear_seconds = late_clear
	for tick in ceili(sim.time_limit_seconds * 60.0) + 1:
		if tick % 30 == 0:
			var command := controller.next_command(sim, tick / 60.0)
			if not command.is_empty(): sim.stroke(command.from, command.to, command.speed)
		sim.step(Sim.FIXED_STEP)
		if partial and sim.plot_destroyed.any(func(value): return value) and sim.can_finish(): sim.finish()
		if tick % 1200 == 0: print("STAR t=", tick / 60.0, " water=", sim.plot_waters, " peak=", sim.peak_density)
		if sim.outcome != "playing": break
		if stop_on_loss and sim.plot_destroyed.any(func(value): return value): break
	var report := controller.report(sim)
	report["late_clear_seconds"] = late_clear
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write route report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("STAR ROUTE ", JSON.stringify(report))
	var pass_result: bool = sim.result_stars >= 1 and sim.plot_destroyed.any(func(value): return value) if partial else sim.result_stars == 3
	quit(0 if sim.outcome == "success" and pass_result and not sim.timed_out and absf(report.water_error) < 0.01 else 1)
