extends SceneTree
## Short diagnostics for the new entry layer, never a substitute for V1 weather stress acceptance.
var main: Node3D
func _init() -> void: call_deferred("run")
func sample(label: String) -> Dictionary:
	await create_timer(1.0).timeout
	var values: Array[float]=[]
	var start := Time.get_ticks_usec()
	var previous := start
	var simulation: float=main.sim.elapsed_seconds
	var preview: int=main.front_menu.preview_updates
	while Time.get_ticks_usec()-start<3000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		values.append((now-previous)/1000.0)
		previous=now
	values.sort()
	var p95: float=values[mini(values.size()-1,int(values.size()*0.95))]
	var p99: float=values[mini(values.size()-1,int(values.size()*0.99))]
	return {"label":label,"frames":values.size(),"p95_ms":p95,"p99_ms":p99,"max_ms":values[-1],"over_20_ms":values.filter(func(n):return n>20).size(),"wall_seconds":(previous-start)/1000000.0,"simulation_seconds":main.sim.elapsed_seconds-simulation,"accumulator_ms":main.accumulator*1000,"preview_updates":main.front_menu.preview_updates-preview,"frame_gate":p95<=16.7 and p99<=20}
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/front-menu-review")
	main=load("res://scenes/main.tscn").instantiate()
	main.persist_progress=false
	root.add_child(main)
	var results: Array[Dictionary]=[]
	results.append(await sample("home"))
	main.open_front_page("levels",true)
	results.append(await sample("levels"))
	main.select_campaign_level(main.campaign.levels[0].id)
	results.append(await sample("gameplay_preview_stopped"))
	main.open_front_page("settings")
	results.append(await sample("settings"))
	var result := {"size":str(root.size),"short_diagnostic":true,"samples":results}
	FileAccess.open("res://.godot/front-menu-review/performance.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("FRONT PERFORMANCE ",JSON.stringify(result))
	quit()
