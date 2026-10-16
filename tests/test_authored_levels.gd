extends SceneTree
const Loader = preload("res://scripts/config_loader.gd")
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/level-review")
	var settings = load("res://configs/weather.tres")
	var loaded := Loader.campaign("res://configs/campaign.tres",settings.plot_half)
	check(loaded.errors.is_empty(),"Authored campaign validates: "+str(loaded.errors))
	if not loaded.errors.is_empty(): quit(1); return
	var campaign: WRCampaign = loaded.resource
	var rows: Array[Dictionary] = []
	var main: Node3D
	if not "--audit-only" in OS.get_cmdline_user_args():
		main = load("res://scenes/main.tscn").instantiate()
		main.persist_progress = false
		root.add_child(main)
		main.set_process(false)
	for map in campaign.levels:
		check(map.validation_errors(settings.plot_half).is_empty(),"Map geometry is valid: "+map.id)
		check(not map.title in ["需水差异小样","山与两处土地","海上风暴 · 借雨蓄水"] and not map.hint.strip_edges().is_empty(),"Authored title and hint replace template copy: "+map.id)
		var sim := Sim.new(settings,true,false,map.id,map)
		var required := 0.0
		var kinds: Array[String] = []
		for target in sim.plot_centers.size():
			required += sim.required_water(target)/sim.plot_water_scales[target]
			kinds.append("reservoir" if sim.is_reservoir(target) else "farm")
		check(absf(sim.water_error()) < 0.001 and sim.plot_waters.count(0.0) == sim.plot_centers.size(),"Real opening budget balances and goals are empty: "+map.id)
		var row := {"id":map.id,"title":map.title,"hint":map.hint,"kinds":kinds,"initial_water":sim.initial_water,"minimum_for_all":required,"geometry_errors":map.validation_errors(settings.plot_half)}
		if main != null:
			main.select_campaign_level(map.id)
			main.hud.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			check(main.sim.layout_id == map.id and main.campaign_play and main.hud.campaign.ids() == campaign.ids(),"Real formal selection loads the right world/order: "+map.id)
			var valid: bool = main.hud.plot_label_rects.size() == map.plots.size()
			for index in main.hud.plot_label_rects.size():
				var rect: Rect2 = main.hud.plot_label_rects[index]
				valid = valid and root.get_visible_rect().encloses(rect) and not main.hud.blocks_wind(rect.get_center()) and not rect.intersects(main.hud.wind_toolbar_rect)
				for other in range(index): valid = valid and not rect.intersects(main.hud.plot_label_rects[other])
			check(valid,"Actual goal labels remain visible and let weather input through: "+map.id)
			root.get_texture().get_image().save_png("res://.godot/level-review/"+map.id+"-"+str(root.size.x)+".png")
		rows.append(row)
	var result := {"checks":checks,"failures":failures,"size":str(root.size),"maps":rows,"scope":"Configuration, initial budget and GPU readability only; not nine successful gameplay routes."}
	FileAccess.open("res://.godot/level-review/authored-"+("audit" if main == null else str(root.size.x))+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("AUTHORED LEVELS ",JSON.stringify({"checks":checks,"failures":failures,"maps":rows.size()}))
	quit(0 if failures == 0 else 1)
