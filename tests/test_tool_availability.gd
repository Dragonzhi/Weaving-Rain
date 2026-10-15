extends "res://tests/test_campaign_scene.gd"
## Native buttons and viewport events. Navigation fixtures are not completion evidence.
const Loader = preload("res://scripts/config_loader.gd")

func stroke(a: Vector2,b: Vector2,right := false) -> void:
	var input: Node = main.wind_input
	var camera: Camera3D = main.weather_view.camera
	var start := camera.unproject_position(Vector3(a.x,main.sim.terrain.height(a)+0.3,a.y))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	press.position = start
	press.pressed = true
	root.push_input(press,true)
	await draw()
	var end := camera.unproject_position(Vector3(b.x,input.reference_height,b.y))
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT if right else MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	await draw()
	press = press.duplicate()
	press.position = end
	press.pressed = false
	root.push_input(press,true)
	await draw()

func run() -> void:
	directory = "res://.godot/tool-availability/"
	DirAccess.make_dir_recursive_absolute(directory)
	var default := WRMapDefinition.new()
	check(default.available_wind_tools==7 and load("res://configs/maps/meadow.tres").available_wind_tools==7,"Missing fields in new/legacy resources default to all three tools")
	for mask in [0,-1,2,4,6,8]:
		var invalid := load("res://configs/maps/level01.tres").duplicate(true)
		invalid.available_wind_tools = mask
		check("available_wind_tools" in "；".join(invalid.validation_errors()),"Invalid/brush-less flags are rejected: "+str(mask))
	var resource: WRMapDefinition = load("res://configs/maps/level05.tres").duplicate(true)
	resource.id = "tools_test"
	var path := directory+"tools_test.tres"
	ResourceSaver.save(resource,path)
	var read := Loader.map(path,1.25)
	check(read.errors.is_empty() and read.resource.available_wind_tools==3 and read.resource.to_layout().available_wind_tools==3,"Saved tool flags survive deep reload and reach the layout snapshot")
	main = load("res://scenes/main.tscn").instantiate()
	main.persist_progress = false
	root.add_child(main)
	main.set_process(false)
	await draw()
	check(main.wind_input.tool_available("brush") and not main.wind_input.tool_available("source") and not main.wind_input.tool_available("vortex"),"Teaching allows only brush")
	check(main.hud.brush_button.visible and not main.hud.source_button.visible and not main.hud.vortex_button.visible,"Teaching hides unavailable native tool buttons")
	var rows: Array = []
	for index in 9:
		var id := "level%02d" % (index+1)
		main.select_campaign_level(id)
		await draw()
		var mask := 1 if index<4 else 3 if index<6 else 7
		var before: float = main.sim.water_total()
		check(main.sim.layout.available_wind_tools==mask,"Configured tool schedule: "+id)
		check(main.hud.source_button.visible==((mask&2)!=0) and main.hud.vortex_button.visible==((mask&4)!=0),"Toolbar follows this map's flags: "+id)
		check(root.get_visible_rect().encloses(main.hud.wind_toolbar_rect) and main.hud.wind_toolbar_rect.size.x==(226.0 if mask==1 else 335.0 if mask==3 else 424.0),"Toolbar shrinks to actual available controls: "+id)
		check(main.wind_input.tool=="brush" and main.sim.water_total()==before and main.sim.wind_sources.is_empty(),"Switching maps starts with brush and normal weather: "+id)
		if index==4: check("风带" in str(main.hud.tool_introduction),"First band opening gives a brief nonmodal explanation")
		if index==6: check("漩涡" in str(main.hud.tool_introduction),"First vortex opening gives a brief nonmodal explanation")
		root.get_texture().get_image().save_png(directory+id+"-"+str(root.size.x)+".png")
		rows.append({"id":id,"mask":mask,"toolbar_width":main.hud.wind_toolbar_rect.size.x,"introduction":Array(main.hud.tool_introduction)})
	main.select_campaign_level("level01")
	await draw()
	var brush: Node = main.wind_input
	check(not brush.select_tool("source") and not brush.select_tool("vortex") and not brush.select_tool("unknown") and brush.tool=="brush","Unavailable and unknown selections cannot enter a hidden tool")
	main.hud.source_button.pressed.emit()
	check(brush.tool=="brush","Calling a hidden button's signal cannot bypass input permission")
	await stroke(Vector2(-4,1),Vector2(-3,1))
	check(main.sim.wind.count(Vector2.ZERO)<main.sim.wind.size() and main.sim.wind_sources.is_empty(),"Real early-level brush still applies wind without placing a source")
	var point: Vector2 = main.hud.wind_toolbar_rect.position+Vector2(-12,10)
	check(not main.hud.blocks_wind(point),"Removed toolbar space is available for weather input")
	main.select_campaign_level("level05")
	await draw()
	check(main.hud.tool_introduction.is_empty(),"Revisiting the same tool in this session does not repeat its first-opening message")
	await click(main.hud.source_button)
	await stroke(Vector2(-4,1),Vector2(-2,1))
	check(main.wind_input.tool=="source" and main.sim.wind_sources.size()==1,"Native band button and real drag place a permitted wind band")
	main.restart(false)
	await draw()
	check(main.wind_input.tool=="source" and main.sim.wind_sources.is_empty(),"Retry retains a permitted tool and clears sources")
	main.select_campaign_level("level07")
	await draw()
	await click(main.hud.vortex_button)
	await stroke(Vector2(-4,1),Vector2(-2,1),true)
	check(main.wind_input.tool=="vortex" and main.sim.wind_sources.size()==1 and main.sim.wind_sources[0].spin==-1,"Native vortex selection retains real right-drag counterclockwise creation")
	await click(main.hud.source_remove[0])
	check(main.sim.wind_sources.is_empty(),"Existing stable-ID source-close button still works")
	var screen: Vector2 = main.weather_view.camera.unproject_position(Vector3(-4,0.52,1))
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	pressed.position = screen
	root.push_input(pressed,true)
	main.select_campaign_level("level02")
	await draw()
	pressed.pressed = false
	root.push_input(pressed,true)
	check(main.wind_input.tool=="brush" and not main.wind_input.dragging and main.sim.wind_sources.is_empty(),"Switching into a restricted map cancels the pending gesture without releasing its source")
	main.campaign_play = false
	main.custom_map_path = path
	main.custom_map = read.resource
	main.free_layout = "tools_test"
	main.switch_mode("free")
	main.wind_input.select_tool("source")
	resource.available_wind_tools = 1
	ResourceSaver.save(resource,path)
	main.reload_tuning()
	check(main.wind_input.tool_available("source") and main.wind_input.tool=="source","F6 does not reload map tool flags or change the current tool")
	main.restart(false)
	await draw()
	check(not main.wind_input.tool_available("source") and main.wind_input.tool=="brush" and not main.hud.source_button.visible,"R applies saved flags and falls back from a newly unavailable tool to brush")
	resource.available_wind_tools = 0
	ResourceSaver.save(resource,path)
	main.restart(false)
	check(main.sim.layout.available_wind_tools==1 and "available_wind_tools" in main.tuning_message,"Invalid tool configuration retains the last valid map and identifies the field")
	main.select_layout("meadow")
	await draw()
	check(main.hud.source_button.visible and main.hud.vortex_button.visible,"Legacy development map remains fully open")
	main.hud.introduced_wind_tools = 1
	main.select_campaign_level("level09")
	await draw()
	check("风带与漩涡" in str(main.hud.tool_introduction),"Direct selection of a late map explains both newly available tools")
	var until: float = main.hud.tool_introduction_until
	main.paused = true
	main._process(0.1)
	check(main.hud.tool_introduction_until==until and main.weather_view.elapsed==0,"Pause freezes the introduction's simulation-relative clock")
	main.weather_view.elapsed = until+0.1
	await draw()
	check(main.weather_view.elapsed>main.hud.tool_introduction_until,"Introduction expires without a modal acknowledgement")
	var report := {"checks":checks,"failures":failures,"size":str(root.size),"maps":rows,"scope":"tool configuration, native toolbar and real drag input; not nine successful routes"}
	FileAccess.open(directory+"review-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TOOL AVAILABILITY ",JSON.stringify({"checks":checks,"failures":failures,"size":str(root.size)}))
	quit(0 if failures==0 else 1)
