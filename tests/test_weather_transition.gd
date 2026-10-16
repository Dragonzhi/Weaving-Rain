extends SceneTree
## Native mouse navigation; state fixtures below test lifecycle, not a winning route.
var main: Node3D
var checks := 0
var failures := 0
var directory := "res://.godot/native-transition-review/"
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func draw() -> void:
	for n in 3: await process_frame
	await RenderingServer.frame_post_draw
func tap(control: BaseButton) -> void:
	check(control.is_visible_in_tree(),"Native control visible: "+control.text)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event,true)
func named(text: String) -> BaseButton:
	for child in main.front_menu.find_children("*","BaseButton",true,false):
		if child.text == text: return child
	return null
func settle() -> void:
	while main.transition_active(): await process_frame
	await draw()
func capture(name: String, phase: float) -> Image:
	while main.transition_active() and main.transition.progress < phase: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(directory+name+"-"+str(root.size.x)+"x"+str(root.size.y)+".png")
	return image
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	main.persist_progress = false
	root.add_child(main)
	main.set_process(false)
	await draw()
	check(not main.transition.visible and not main.transition_active(),"Startup has no curtain or input blocker")
	var original: RefCounted = main.sim
	await tap(named("选择关卡"))
	check(main.transition_active() and main.transition.kind=="wind" and main.front_menu.page=="home","Wind closes before changing home page")
	# Repeated pointer submissions and hotkeys cannot replace the requested destination.
	main._front_action("start","")
	key(KEY_R)
	key(KEY_ESCAPE)
	await capture("wind-closing",0.22)
	await settle()
	check(main.front_menu.page=="levels" and main.sim==original,"Repeated submissions cannot restart or redirect during sweep")
	check(not main.transition.visible and main.transition.fade_target==null,"Completed sweep releases overlay and page reference")
	main.front_menu.choose_level("level01")
	await tap(main.front_menu.start_button)
	check(main.transition_active() and main.transition.kind=="cloud" and main.sim==original,"Cloud closes before switching map")
	var frozen := true
	while main.transition_active():
		main._process(0.1)
		frozen = frozen and main.frame_steps==0 and main.sim.elapsed_seconds==0 and not main.wind_input.enabled
		if main.transition.progress>=0.5: break
		await process_frame
	check(frozen,"No old/new simulation steps during closing or covered load")
	var covered := await capture("cloud-covered",0.5)
	var opaque := true
	for x in [0.02,0.5,0.98]:
		for y in [0.02,0.5,0.98]:
			var pixel := covered.get_pixel(int(x*covered.get_width()),int(y*covered.get_height()))
			opaque = opaque and pixel.r>0.9 and pixel.g>0.9 and pixel.b>0.9
	check(opaque,"Real GPU frame is fully covered before loading, including corners")
	# The first covered GPU frame intentionally precedes the load callback.
	while main.transition_active() and main.sim==original: await process_frame
	check(main.sim.layout_id=="level01" and not main.front_active(),"Configured map is installed behind opaque cloud")
	check(main.accumulator==0 and main.sim.elapsed_seconds==0,"Loading does not create time debt")
	await capture("cloud-opening",0.74)
	while main.transition_active():
		main._process(0.1)
		frozen = frozen and main.frame_steps==0 and main.sim.elapsed_seconds==0
		await process_frame
	check(frozen and main.wind_input.enabled,"Timer remains zero until reveal finishes, then input resumes")
	main._process(1.0/60)
	check(is_equal_approx(main.sim.elapsed_seconds,1.0/60),"First controllable frame advances only its own fixed step")
	main.sim.add_wind_source(Vector2(-3,0),Vector2.RIGHT,0.5,Vector2(-1,0))
	var sources: Array = main.sim.wind_sources.duplicate(true)
	var water: float = main.sim.water_total()
	var seconds: float = main.sim.elapsed_seconds
	await tap(main.hud.menu_button)
	check(main.transition.kind=="light" and main.paused,"Game menu uses a short fade and pauses immediately")
	await settle()
	check(main.sim.wind_sources==sources and main.sim.water_total()==water and main.sim.elapsed_seconds==seconds,"Pause transition preserves weather, source lifetime and timer")
	check(main.transition.fade_target==null and is_equal_approx(main.hud.modulate.a,1),"Short fade releases its target and restores normal opacity")
	await tap(main.hud.front_buttons[0])
	await settle()
	check(main.front_active(),"Game menu opens an existing front page")
	# Direct page setup isolates a broken resource; actual button still invokes navigation.
	main.open_front_page("levels",true)
	await draw()
	var definition: WRMapDefinition = main.campaign.levels[0]
	var path: String = definition.resource_path
	var invalid: WRMapDefinition = definition.duplicate()
	invalid.available_wind_tools=0
	ResourceSaver.save(invalid,directory+"invalid.tres")
	definition.take_over_path(directory+"invalid.tres")
	original=main.sim
	await tap(main.front_menu.start_button)
	await settle()
	check(main.sim==original and main.front_menu.page=="levels" and main.front_menu.error_label.visible,"Failed load reveals original page and keeps existing weather")
	definition.take_over_path(path)
	var lesson_path: String = main.lesson_map_path
	main.lesson_map_path=directory+"invalid.tres"
	await tap(main.front_menu.tutorial_button)
	await settle()
	check(main.sim==original and main.front_menu.error_label.visible,"Invalid teaching map also preserves active session and reports its field")
	main.lesson_map_path=lesson_path
	main.open_front_page("home")
	await draw()
	await tap(named("设置"))
	check(main.transition.kind=="light","Settings use short fade")
	await settle()
	await tap(named("减少转场动态（本次运行）"))
	check(main.transition.reduced_motion,"Native setting enables reduced motion without touching audio preferences")
	await tap(main.front_menu.back_button)
	await settle()
	await tap(named("选择关卡"))
	check(main.transition.kind=="light","Reduced motion replaces wind curtain with short fade")
	await settle()
	main.transition.reduced_motion=false
	main.wind_input.dragging=true
	main.sim.set_held_wind(Vector2.ZERO,Vector2.RIGHT,1)
	main.navigate(func(): main.open_front_page("home"),"wind")
	check(not main.wind_input.dragging and main.sim.held_wind.is_empty(),"Navigation immediately cancels a held gesture without releasing a source")
	var previous_size := root.size
	root.size=Vector2i(1100,700)
	await draw()
	check(main.transition.size.is_equal_approx(root.get_visible_rect().size),"Curtain resizes with viewport while in flight")
	await settle()
	root.size=previous_size
	await draw()
	main.front_was_paused=true
	main.navigate(main.close_front_page,"cloud")
	await settle()
	check(main.paused and not main.wind_input.enabled,"Reveal restores a preexisting paused game")
	main.paused=false
	main.sim.outcome="success"
	main.sim.result_stars=3
	main.hud.queue_redraw()
	await draw()
	await tap(main.hud.next_button)
	check(main.transition.kind=="cloud","Result next-level control uses cloud curtain")
	await settle()
	check(main.sim.layout_id=="level02" and main.sim.elapsed_seconds==0,"Result navigation loads next ordered map without consuming time")
	check(not main.transition.visible and main.transition.mouse_filter==Control.MOUSE_FILTER_STOP and main.wind_input.enabled,"Invisible blocker releases weather input after completion")
	var report := {"checks":checks,"failures":failures,"size":str(root.size),"scope":"Lifecycle fixtures, native mouse input; normal route recorded separately"}
	FileAccess.open(directory+"review-"+str(root.size.x)+"x"+str(root.size.y)+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WEATHER TRANSITION: ",checks," checks, ",failures," failures; size=",root.size)
	quit(0 if failures==0 else 1)
