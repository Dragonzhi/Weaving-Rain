extends SceneTree
## UI fixtures below isolate state and pause; normal-start routes are separate.
const Guide = preload("res://scripts/onboarding.gd")
const Loader = preload("res://scripts/config_loader.gd")
var main: Node3D
var checks := 0
var failures := 0
var directory := "res://.godot/onboarding-20261019/"
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func draw() -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
func click(button: Button) -> void:
	check(button.is_visible_in_tree(),"Native button visible: "+button.text)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await draw()
	while main.transition_active(): await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	main.show_front_menu = false
	main.persist_progress = false
	root.add_child(main)
	await draw()
	main.set_process(false)
	check(main.hud.briefing_active() and main.paused and not main.wind_input.enabled,"Initial teaching explanation pauses before any input")
	check(not main.weather_view.hints_enabled,"Teaching does not force weather hints on")
	check(root.get_visible_rect().encloses(main.hud.briefing_panel.get_global_rect()),"Explanation fits viewport")
	root.get_texture().get_image().save_png(directory+"intro-"+str(root.size.x)+".png")
	var sim = main.sim
	var humidity: PackedFloat32Array = sim.humidity.duplicate()
	var cloud: PackedFloat32Array = sim.cloud.duplicate()
	var clock: float = main.guide.idle_seconds
	for frame in 90: main._process(1.0/60.0)
	check(sim.humidity==humidity and sim.cloud==cloud and main.guide.idle_seconds==clock and main.frame_steps==0,"Reading leaves weather and help clock unchanged")
	await click(main.hud.briefing_start)
	check(not main.paused and not main.hud.briefing_active() and main.wind_input.enabled,"Native start closes the card and resumes")
	check(not main.wind_input.dragging and not main.hud.blocks_wind(Vector2(40,280)),"Closed explanation releases input, without a held gesture")
	var guide = main.guide
	check(guide.phase==0 and "1 / 5" in guide.title(sim),"Five nodes begin by identifying wet air")
	guide.update(sim,8.1)
	check(guide.help_level()==1 and "左键" in guide.instruction(sim),"First inactivity help names the actual gesture")
	guide.update(sim,12.0)
	check(guide.help_level()==2,"Long inactivity enables the local animated ghost gesture")
	main.hud.queue_redraw()
	await draw()
	root.get_texture().get_image().save_png(directory+"help-"+str(root.size.x)+".png")
	var index := 0
	for i in sim.COUNT:
		if sim.humidity[i]>sim.humidity[index]: index=i
	var p: Vector2 = sim.positions[index]
	guide.note_stroke(sim,p,p,false)
	check(not guide.wet_stroke,"Click with no drag never completes discovery")
	guide.note_stroke(sim,p,p+Vector2(0.2,0),false)
	guide.update(sim,0)
	check(guide.phase==1 and guide.idle_seconds==0,"Valid wet brush footprint advances discovery and clears help")
	# Read-only result fixtures, never used as normal-start completion evidence.
	sim.total_mountain_lift=0.1
	sim.peak_density=0.3
	guide.update(sim,0)
	check(guide.phase==2,"Actual mountain lift plus visible cloud reaches cloud node")
	sim.total_rain_rate=0.1
	guide.update(sim,0)
	check(guide.phase==3 and "云朵" in guide.instruction(sim),"Rain away from the reservoir teaches cloud transport")
	guide.note_stroke(sim,p,p+Vector2(0.2,0),true)
	guide.update(sim,0)
	check(guide.phase==4 and guide.cloud_stroke,"Visible-cloud gesture reaches water observation")
	sim.outcome="success"
	guide.update(sim,0)
	check(guide.phase==5,"Real completion state, not gestures, ends teaching")
	guide.reset(true)
	guide.update(sim,0)
	check(guide.phase==5 and not guide.cloud_stroke and "云" in guide.detail(sim),"Early fill can complete directly, with transport recap")
	check(not "金色" in guide.detail(sim) and not "淡蓝" in guide.instruction(sim),"Hints-off copy never requires an invisible arrow or rain contour")
	for n in 4:
		main.select_campaign_level("level%02d"%(n+1))
		main._process(0)
		await draw()
		check(main.sim.time_limit_seconds==[360.0,420.0,420.0,360.0][n],"Per-map deadline "+str(n+1))
		check(main.hud.briefing_active() and main.paused,"First visit pauses explanation "+str(n+1))
		check(root.get_visible_rect().encloses(main.hud.briefing_panel.get_global_rect()),"Map explanation fits "+str(n+1))
		if n==2:
			check("适量" in main.hud.briefing_body.text and str(int(main.sim.required_water(0))) in main.hud.briefing_body.text,"Farm requirements read from actual plot resource")
		var water: float = main.sim.water_total()
		var elapsed: float = main.sim.elapsed_seconds
		main.sim.add_wind_source(Vector2(-5,0),Vector2(1,0),0.5,Vector2(-3,0))
		var source_left: float = main.sim.wind_sources[0].remaining
		var safety: PackedFloat32Array = main.sim.plot_safe_times.duplicate()
		for frame in 90: main._process(1.0/60.0)
		check(main.sim.elapsed_seconds==elapsed and main.sim.water_total()==water and main.sim.wind_sources[0].remaining==source_left and main.sim.plot_safe_times==safety,"Whole simulation pauses, including sources and safety "+str(n+1))
		if n==2: root.get_texture().get_image().save_png(directory+"farm-"+str(root.size.x)+".png")
		await click(main.hud.briefing_start)
		main.restart(false)
		main._process(0)
		check(not main.hud.briefing_active() and not main.paused and main.sim.time_remaining()==[360,420,420,360][n],"Retry restores timer without repeating the card "+str(n+1))
	main.select_campaign_level("level05")
	main._process(0)
	await draw()
	check(main.hud.briefing_active() and "风带" in main.hud.briefing_title.text,"First new wind band uses paused explanation")
	await click(main.hud.briefing_start)
	main.select_campaign_level("level07")
	main._process(0)
	await draw()
	check(main.hud.briefing_active() and "漩涡" in main.hud.briefing_title.text,"First vortex uses paused explanation")
	await click(main.hud.briefing_start)
	main.select_campaign_level("level05")
	main._process(0)
	check(not main.hud.briefing_active(),"Session revisit does not repeat tool explanation")
	main.hud.menu_open=true
	main._game_menu_changed(true)
	await draw()
	await click(main.hud.briefing_button)
	check(main.hud.briefing_active(),"Native menu offers current level explanation")
	await click(main.hud.briefing_start)
	check(not main.paused and not main.hud.menu_open,"Review from menu restores pre-menu gameplay pause state")
	main._toggle_pause()
	main.show_briefing(true)
	await click(main.hud.briefing_start)
	check(main.paused and not main.wind_input.enabled,"Review respects a prior manual pause")
	main._toggle_pause()
	main.select_layout("needs_lab")
	main._process(0)
	check(not main.hud.briefing_active(),"Development maps are not interrupted automatically")
	main.show_briefing(true)
	check(main.hud.briefing_active() and not main.campaign_play,"Manual development-map explanation uses map hint without entering campaign")
	await click(main.hud.briefing_start)
	main.select_campaign_level("level01")
	main._process(0)
	main.wind_input.dragging=true
	main.sim.set_held_wind(Vector2(-4,0),Vector2(1,0),0.5)
	main.show_briefing(true)
	check(not main.wind_input.dragging and main.sim.held_wind.is_empty(),"Opening instructions discards drag and held wind")
	main.wind_input._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.paused and main.hud.briefing_active() and not main.wind_input.dragging,"Focus loss does not dismiss reading or resume a gesture")
	await draw()
	await click(main.hud.briefing_start)
	check(not main.wind_input.dragging and main.sim.held_wind.is_empty(),"Resuming instructions requires a fresh press")
	main.show_briefing(true)
	await draw()
	await click(main.hud.menu_button)
	check(main.hud.menu_open and main.paused and not main.hud.briefing_active(),"Menu navigation closes the explanation before acquiring its pause scope")
	await click(main.hud.menu_button)
	check(not main.paused and not main.hud.menu_open and main.wind_input.enabled,"Closing menu restores gameplay without an orphaned briefing pause")
	main.show_briefing(true)
	for code in [KEY_R,KEY_ESCAPE]:
		if code == KEY_ESCAPE: main.show_briefing(true)
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.keycode=code
			event.pressed=pressed
			root.push_input(event,true)
			await draw()
		while main.transition_active(): await process_frame
		main._process(0)
		check(not main.hud.briefing_active() and not main.wind_input.dragging,"Reading keyboard navigation cancels card and gesture "+str(code))
		if code == KEY_R:
			check(not main.paused and main.sim.time_remaining()==360 and main.sim.wind_sources.is_empty(),"R from instructions retries directly, without repeating the card")
		else:
			check(main.paused and main.hud.menu_open,"Esc from instructions opens a paused menu")
			await click(main.hud.menu_button)
			check(not main.paused,"Menu after Esc restores its own prior gameplay state")
	var custom: WROnboardingSettings = main.guide.settings.duplicate(true)
	custom.actions[0]="测试：推动浅色湿空气。"
	ResourceSaver.save(custom,directory+"custom.tres")
	main.onboarding_path=directory+"custom.tres"
	var previous_copy: String = main.guide.settings.actions[0]
	main.reload_tuning()
	check(main.guide.settings.actions[0]==previous_copy,"F6 leaves tutorial copy unchanged")
	main.restart(false)
	check(main.guide.settings.actions[0]==custom.actions[0],"R reloads saved onboarding configuration")
	main.onboarding_path="res://configs/onboarding.tres"
	main._reload_onboarding()
	var valid := Loader.onboarding()
	var broken: WROnboardingSettings = valid.resource.duplicate(true)
	broken.gesture_seconds=1
	ResourceSaver.save(broken,directory+"invalid.tres")
	var loaded := Loader.onboarding(directory+"invalid.tres")
	check("gesture_seconds" in str(loaded.errors) and loaded.resource.gesture_seconds==valid.resource.gesture_seconds,"Invalid saved config preserves last valid copy and reports field")
	for n in range(5,10): check(load("res://configs/maps/level%02d.tres"%n).time_limit_seconds==180,"Later map retains original limit "+str(n))
	check(WRMapDefinition.new().time_limit_seconds==180,"Global default remains unchanged")
	FileAccess.open(directory+"review-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"resolution":str(root.size),"scope":"UI/state fixtures, not new-player or complete route validation"},"\t"))
	print("ONBOARDING PACING: ",checks," checks, ",failures," failures")
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
