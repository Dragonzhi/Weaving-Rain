extends SceneTree
var main: Node3D
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/tutorial-review")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	var sim = main.sim
	check(main.play_mode=="lesson" and sim.layout_id=="tutorial" and sim.plot_centers.size()==1 and sim.is_reservoir(0),"Live tutorial loads its independent single reservoir map")
	check(not sim.star_level and not sim.timer_active() and not sim.sandbox,"Teaching has no timer or stored rating")
	check(sim.peak_density==0 and Array(sim.cold).max()==0 and sim.plot_water==0,"Normal teaching begins with wet air only")
	check(sim.required_water(0)==100 and main.guide.phase==0,"Independent tutorial capacity and initial step")
	check("5" in main.guide.title(sim) and "湿空气" in main.guide.instruction(sim),"First instruction identifies interactive wet air")
	var i := 0
	var distance := INF
	for cell in sim.COUNT:
		var d: float = sim.positions[cell].distance_squared_to(sim.plot_centers[0])
		if d<distance:
			distance=d
			i=cell
	# Isolate completion rule: real rain step fills the last fraction while a dense cloud remains.
	# This is a rule fixture, not the normal-start route below.
	sim.plot_waters[0]=sim.required_water(0)-0.000001
	sim.cloud[i]=3
	sim.rain[i]=3
	sim.refresh_display()
	sim.initial_water=sim.water_total()
	sim.step(sim.FIXED_STEP)
	main.guide.update(sim,sim.FIXED_STEP)
	check(sim.outcome=="success" and sim.target_complete(0),"Actual released rain completes teaching immediately at full pool")
	check(sim.rain[i]>0 and sim.cloud[i]>0 and sim.plot_safe_times[0]==0,"No cloud removal or safety hold required")
	check(sim.overflow_water>0 and not sim.plot_destroyed[0] and absf(sim.water_error())<.01,"Pool accepts excess rain without damage or lost accounting")
	check(main.guide.phase==5 and "入门完成"==main.guide.title(sim),"Five teaching nodes finish without a hidden safety phase")
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(main.hud.free_button.visible and not main.hud.next_button.visible,"Completion offers existing continue action without a star result")
	root.get_texture().get_image().save_png("res://.godot/tutorial-review/rule-completion.png")
	main.restart(false)
	main.set_process(false)
	check(main.sim.plot_water==0 and main.guide.phase==0 and main.sim.peak_density==0,"Retry clears pool/weather/teaching progression")
	var map = load("res://configs/tutorial.tres").duplicate(true)
	map.plot_needs[0]=map.plot_needs[0].duplicate(true)
	map.plot_needs[0].target_water=80
	map.plots[0]=Vector2(3,1)
	map.star_level=true
	main.lesson_map_path="res://.godot/tutorial-review/reload-map.tres"
	ResourceSaver.save(map,main.lesson_map_path)
	main.restart(false)
	main.set_process(false)
	check(main.sim.required_water(0)==80 and main.sim.plot_centers[0]==Vector2(3,1),"R reloads saved teaching geometry and capacity")
	check(not main.sim.star_level and not main.sim.timer_active(),"Lesson mode protects no-rating/no-timer even if map flag checked")
	map.plots[0]=map.mountains[0].position
	ResourceSaver.save(map,main.lesson_map_path)
	main.restart(false)
	main.set_process(false)
	check(main.sim.plot_centers[0]==Vector2(3,1) and main.sim.required_water(0)==80 and "plots[0]" in main.tuning_message,"Invalid changed teaching map keeps last valid version")
	main.lesson_map_path="res://configs/tutorial.tres"
	main.select_layout("level01")
	main.set_process(false)
	check(main.sim.layout_id=="level01" and main.sim.plot_centers.size()==1 and main.sim.is_reservoir(0) and main.sim.star_level,"Authored level01 is now a separate timed single reservoir")
	main.switch_mode("lesson")
	main.set_process(false)
	check(main.sim.layout_id=="tutorial" and main.sim.is_reservoir(0) and main.sim.required_water(0)==100,"Revisit does not inherit selected level01 or temporary teaching changes")
	main.enter_free_play()
	main.set_process(false)
	check(main.sim.layout_id=="level01" and main.sim.is_reservoir(0) and main.sim.star_level,"Leaving revisited teaching preserves the selected timed reservoir map")
	var report={"checks":checks,"failures":failures,"level01_title":main.sim.layout.title,"level01_time":main.sim.time_limit_seconds,"level01_initial_water":main.sim.initial_water}
	FileAccess.open("res://.godot/tutorial-review/scene.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	main.queue_free()
	await process_frame
	print("TUTORIAL RESERVOIR: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
