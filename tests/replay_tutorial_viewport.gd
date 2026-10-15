extends "res://tests/replay_star_viewport.gd"
## Normal authored map start, real picking/strokes; no weather injection or goal edits.
var route_time := 0.0
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/tutorial-review")
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	var tutorial: bool = main.play_mode=="lesson"
	var map: WRMapDefinition = main.lesson_map if tutorial else main.custom_map
	var errors := map.validation_errors(main.sim.plot_half)
	if not errors.is_empty():
		push_error("Map validation: "+"; ".join(errors))
		quit(1)
		return
	var controller := Route.new([0],"mountain")
	var next_at := .5
	# Count every frame, including the frames awaited inside a mouse stroke.
	process_frame.connect(func(): route_time += main.frame_steps*Sim.FIXED_STEP)
	var captured := false
	var phases: Array[int]=[0]
	var report_name: String = "tutorial" if tutorial else main.sim.layout_id
	root.get_texture().get_image().save_png("res://.godot/tutorial-review/"+report_name+"-start.png")
	while main.sim.outcome=="playing" and route_time<180:
		# Tutorial intentionally has no gameplay timer; use the test's fixed-step clock.
		if route_time>=next_at:
			var command := controller.next_command(main.sim,route_time)
			next_at+=.5
			if not command.is_empty(): await stroke(command)
		if tutorial and not main.guide.phase in phases: phases.append(main.guide.phase)
		if not captured and main.sim.plot_water>main.sim.required_water(0)*.5:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/tutorial-review/"+report_name+"-rain.png")
			captured=true
		await process_frame
	await RenderingServer.frame_post_draw
	if tutorial and not main.guide.phase in phases: phases.append(main.guide.phase)
	root.get_texture().get_image().save_png("res://.godot/tutorial-review/"+report_name+"-result.png")
	var report := controller.report(main.sim)
	report["route_seconds"]=route_time
	report["phases"]=phases
	report["map_errors"]=errors
	report["input_pick_error"]=input_pick_error
	report["blocked"]=blocked
	report["events"]=events
	report["rain_at_finish"]=main.sim.total_rain_rate
	report["safe_time_at_finish"]=main.sim.plot_safe_times[0]
	FileAccess.open("res://.godot/tutorial-review/"+report_name+"-route.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	report.erase("actions")
	print("AUTHORED ROUTE ",JSON.stringify(report))
	var passed: bool = main.sim.outcome=="success" and absf(main.sim.water_error())<.02 and input_pick_error<.001 and failures==0
	if tutorial: passed=passed and main.guide.phase==3 and not main.sim.star_level and phases==[0,1,2,3]
	else: passed=passed and main.sim.result_stars==3 and not main.sim.timed_out
	quit(0 if passed else 1)
