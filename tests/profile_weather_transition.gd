extends SceneTree
## Short UI diagnostics include covered map-construction frames, not V1 weather acceptance.
var main: Node3D
func _init() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/native-transition-review")
	main=load("res://scenes/main.tscn").instantiate()
	main.persist_progress=false
	root.add_child(main)
	await create_timer(1.0).timeout
	var results: Array[Dictionary]=[]
	for style in ["wind","cloud","light"]:
		var frames: Array[float]=[]
		var stepped := 0
		for n in 4:
			var target := "levels" if n%2==0 else "home"
			var change: Callable = func(): main.open_front_page(target,true)
			if style=="cloud" and n%2==0: change=func(): main.select_campaign_level("level01")
			elif style=="light" and n%2==0: change=func(): main.open_front_page("settings",true)
			var previous := Time.get_ticks_usec()
			var previous_sim: RefCounted = main.sim
			var previous_seconds: float = main.sim.elapsed_seconds
			main.navigate(change,style)
			while main.transition_active():
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				frames.append((now-previous)/1000.0)
				previous=now
				if main.transition_active() and main.sim==previous_sim:
					stepped+=int(round((main.sim.elapsed_seconds-previous_seconds)/main.Simulation.FIXED_STEP))
				previous_sim=main.sim
				previous_seconds=main.sim.elapsed_seconds
			await create_timer(0.2).timeout
		frames.sort()
		var p95: float=frames[mini(frames.size()-1,int(frames.size()*0.95))]
		var p99: float=frames[mini(frames.size()-1,int(frames.size()*0.99))]
		results.append({"style":style,"transitions":4,"frames":frames.size(),"p95_ms":p95,"p99_ms":p99,"max_ms":frames[-1],"over_20_ms":frames.filter(func(n):return n>20).size(),"over_33_ms":frames.filter(func(n):return n>33).size(),"simulation_steps_while_active":stepped,"frame_gate":p95<=16.7 and p99<=20})
	var result := {"size":str(root.size),"short_diagnostic":true,"includes_covered_map_loading":true,"samples":results}
	FileAccess.open("res://.godot/native-transition-review/performance.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("TRANSITION PERFORMANCE ",JSON.stringify(result))
	quit()
