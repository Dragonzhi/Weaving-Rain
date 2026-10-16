extends SceneTree
## Native pointer navigation; injected fields below isolate pause and result states only.
class ReturningGame extends "res://scripts/main.gd":
	func initial_mode(_args: PackedStringArray) -> String: return "free"
var main: Node3D
var checks := 0
var failures := 0
var directory := "res://.godot/front-menu-review/"
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func draw() -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
func click(button: BaseButton) -> void:
	check(button.is_visible_in_tree(),"Actual button visible: "+button.text)
	var point := button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await draw()
	while main.transition_active(): await process_frame
	await draw()
func key(code: int) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.pressed=pressed
		root.push_input(event,true)
		await draw()
	while main.transition_active(): await process_frame
	await draw()
func button_named(text: String, parent_node: Node = null) -> Button:
	var node: Node = parent_node if parent_node != null else main.front_menu
	for child in node.find_children("*","Button",true,false):
		if child.text == text: return child
	return null
func capture(name: String) -> void:
	await create_timer(0.22).timeout
	await draw()
	root.get_texture().get_image().save_png(directory+name+"-"+str(root.size.x)+"x"+str(root.size.y)+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	main.persist_progress = false
	main.preferences_path = directory+"onboarding.cfg"
	main.progress_path = directory+"stars.cfg"
	root.add_child(main)
	await draw()
	while main.transition_active(): await process_frame
	main.weather_audio.preferences_path = directory+"audio.cfg"
	check(main.front_active() and main.front_menu.page == "home" and not main.session_started,"Normal fresh startup presents home before gameplay")
	check(main.paused and not main.wind_input.enabled and main.hud.blocks_wind(Vector2(50,50)),"Home pauses and blocks weather")
	var water: float = main.sim.water_total()
	var before: RefCounted = main.sim
	var elapsed: float = main.sim.elapsed_seconds
	await create_timer(0.25).timeout
	check(main.sim == before and main.sim.water_total() == water and main.sim.elapsed_seconds == elapsed and main.frame_steps == 0,"Home animation never advances or replaces real weather")
	await key(KEY_SPACE)
	check(main.front_active() and not main.session_started,"Space cannot accept the focused start button")
	check(main.front_menu.hero_sim != main.sim and main.front_menu.preview_updates>0,"Procedural preview uses a separate unstepped model")
	await capture("home")
	await click(button_named("选择关卡"))
	check(main.front_menu.cards.size()==main.campaign.levels.size() and main.selecting_levels,"Native grid follows campaign size")
	check(main.front_menu.hero_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Leaving home stops preview rendering")
	for i in main.front_menu.cards.size():
		main.front_menu.choose_level(main.campaign.levels[i].id)
		check(main.front_menu.detail_title.text==main.campaign.levels[i].title,"Title and metadata follow map "+str(i))
	await click(main.front_menu.cards[0])
	check(main.front_menu.selected_id==main.campaign.levels[0].id,"Native card selects without starting")
	check(main.sim==before,"Selecting card does not reset weather")
	await capture("levels")
	await click(main.front_menu.back_button)
	await click(button_named("玩法说明"))
	await click(button_named("风工具"))
	check(main.front_menu.page=="help" and main.front_menu.help_index==2,"Help tabs accept actual input")
	await capture("help")
	await key(KEY_ESCAPE)
	check(main.front_menu.page=="home","Escape returns help to its source home")
	await click(button_named("设置"))
	var enabled: bool = main.weather_audio.enabled
	await click(main.front_menu.sound_toggle)
	check(main.weather_audio.enabled!=enabled,"Native sound toggle changes existing audio service")
	main.front_menu.volume.grab_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_HOME; event.pressed = true
	root.push_input(event,true)
	await draw()
	check(main.weather_audio.master_volume<0.02,"Native keyboard slider applies volume")
	main.front_menu.volume.value=42
	await draw()
	check(is_equal_approx(main.weather_audio.master_volume,0.42) and main.hud.audio_volume.value==42,"Both settings views share current preferences")
	await capture("settings")
	await click(main.front_menu.back_button)
	await click(main.front_menu.primary)
	check(not main.front_active() and main.play_mode=="lesson" and main.session_started,"Start enters real reservoir teaching")
	main.set_process(false)
	await key(KEY_ESCAPE)
	check(main.hud.menu_open and main.paused and not main.wind_input.enabled,"Escape opens a genuinely paused native game menu")
	await key(KEY_SPACE)
	check(main.hud.menu_open and main.paused,"Space does not resume through focused menu controls")
	await key(KEY_ESCAPE)
	check(not main.hud.menu_open and not main.paused,"Escape closes game menu and restores previous pause state")
	main.sim.stroke(Vector2(-3,0),Vector2(-2,0),0.5)
	var snapshot: PackedFloat32Array=main.sim.humidity.duplicate()
	before=main.sim
	main.open_front_page("home")
	await draw()
	for frame in 10: main._process(0.1)
	check(main.sim==before and main.sim.humidity==snapshot and main.frame_steps==0,"Returning home keeps exact active simulation")
	await click(main.front_menu.primary)
	check(main.sim==before and not main.paused and main.wind_input.enabled,"Continue restores same weather and input")
	main.paused=true
	main.open_front_page("settings")
	await draw()
	await click(main.front_menu.back_button)
	check(main.paused and not main.wind_input.enabled,"Settings back preserves preexisting pause")
	main.paused=false
	main.open_level_selection()
	await draw()
	main.front_menu.choose_level(main.campaign.levels[0].id)
	await click(main.front_menu.start_button)
	check(main.sim.layout_id==main.campaign.levels[0].id and main.sim.elapsed_seconds==0 and not main.front_active(),"Start selected map creates fresh normal weather")
	main.open_front_page("home")
	await draw()
	var updates: int=main.front_menu.preview_updates
	main.close_front_page()
	await draw()
	check(main.front_menu.preview_updates==updates and main.front_menu.hero_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Gameplay leaves no hidden preview updates")
	check(not main.hud.front_active and not main.hud.blocks_wind(Vector2(20,root.size.y*0.65)),"Hidden full-screen menu releases weather input")
	await key(KEY_ESCAPE)
	await click(main.hud.levels_button)
	await click(main.front_menu.back_button)
	check(not main.paused and main.wind_input.enabled,"Opening selection from the game menu restores its original running state")
	# Sources, countdown and safety confirmation must all freeze while browsing.
	main.sim.add_wind_source(Vector2(-3,0),Vector2.RIGHT,0.5,Vector2(-1,0))
	var source_state: Array=main.sim.wind_sources.duplicate(true)
	var elapsed_state: float=main.sim.elapsed_seconds
	var safe_state =main.sim.plot_safe_times.duplicate()
	var accumulator: float=main.accumulator
	main.open_front_page("settings")
	await draw()
	for frame in 20: main._process(0.1)
	check(main.sim.wind_sources==source_state and main.sim.elapsed_seconds==elapsed_state and main.sim.plot_safe_times==safe_state and main.accumulator==accumulator,"Settings freeze source lifetime, timer, safety and pending steps")
	await click(main.front_menu.back_button)
	# Missing thumbnail is nonfatal; more than nine ordered maps remain selectable.
	check(main.front_menu.thumbnail("nonexistent") == null,"Missing thumbnail has neutral fallback")
	var original_campaign: WRCampaign=main.campaign
	var many := WRCampaign.new()
	many.tutorial=original_campaign.tutorial
	for n in 12:
		var definition: WRMapDefinition=original_campaign.levels[0].duplicate()
		definition.id="preview_"+str(n)
		definition.title="额外地图 "+str(n)
		many.levels.append(definition)
	main.campaign=many
	main.open_front_page("help")
	main.front_menu.show_page("levels")
	await draw()
	check(main.front_menu.cards.size()==12 and main.front_menu.grid.columns==3,"Grid is not hardcoded to nine maps")
	main.front_menu.grid.get_parent().ensure_control_visible(main.front_menu.cards[-1])
	await draw()
	await click(main.front_menu.cards[-1])
	check(main.front_menu.detail_title.text=="额外地图 11" and main.front_menu.detail_image.texture==null,"Extra missing-image map still has valid selectable metadata")
	main.campaign=original_campaign
	main.close_front_page()
	# Bad map loading must not throw away the active weather or the page.
	main.open_level_selection()
	await draw()
	var original_path: String=main.campaign.levels[0].resource_path
	var bad_map: WRMapDefinition=main.campaign.levels[0].duplicate()
	bad_map.available_wind_tools=0
	ResourceSaver.save(bad_map,directory+"invalid-map.tres")
	main.campaign.levels[0].take_over_path(directory+"invalid-map.tres")
	before=main.sim
	await click(main.front_menu.start_button)
	check(main.sim==before and main.front_active() and main.front_menu.error_label.visible,"Failed selected map preserves session and reports field error")
	main.campaign.levels[0].take_over_path(original_path)
	main.close_front_page()
	var returning := ReturningGame.new()
	returning.persist_progress=false
	root.add_child(returning)
	returning.set_process(false)
	check(returning.front_active() and returning.play_mode=="free" and not returning.session_started,"Returning player still sees home; prepared first-map path is not an explicit bypass")
	check(returning.sim.layout_id==returning.campaign.levels[0].id,"Returning start prepares configured first level")
	returning.queue_free()
	await draw()
	var file := ConfigFile.new()
	check(file.load(main.weather_audio.preferences_path)==OK,"Native settings persist to isolated test file")
	print("FRONT MENU: ",checks," checks, ",failures," failures; size=",root.size)
	FileAccess.open(directory+"review-"+str(root.size.x)+"x"+str(root.size.y)+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"size":str(root.size)},"\t"))
	quit(0 if failures==0 else 1)
