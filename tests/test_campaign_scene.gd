extends SceneTree
## Result/water injections below isolate navigation, not a gameplay completion claim.
class ReturningGame extends "res://scripts/main.gd":
	func initial_mode(_args: PackedStringArray) -> String:
		return super.initial_mode(PackedStringArray())
var checks := 0
var failures := 0
var main: Node3D
var directory := "res://.godot/campaign-review/"
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func draw() -> void:
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
func click(button: Button) -> void:
	await click_point(button.get_global_rect().get_center())
func click_point(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		for frame in 3:
			main.hud.queue_redraw()
			await process_frame
	await draw()
	while main.transition_active(): await process_frame
	await draw()
func save_campaign(ids: Array[String]) -> void:
	var resource := WRCampaign.new()
	resource.tutorial = load("res://configs/tutorial.tres")
	for id in ids: resource.levels.append(load("res://configs/maps/"+id+".tres"))
	ResourceSaver.save(resource,main.campaign_path)
func complete() -> void:
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.charge.fill(0)
	for target in main.sim.plot_centers.size(): main.sim.plot_waters[target] = main.sim.required_water(target)
	main.sim.refresh_display()
	main.sim.update_goal(3.0)
	main.finish_level()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	main.persist_progress = false
	main.preferences_path = directory+"onboarding.cfg"
	main.progress_path = directory+"stars.cfg"
	root.add_child(main)
	main.set_process(false)
	await draw()
	check(main.play_mode == "lesson" and not main.has_free_session,"Fresh first entry remains independent reservoir teaching")
	main.campaign_path = directory+"campaign.tres"
	save_campaign(["level01","meadow","storm_coast"])
	check(main.reload_campaign(),"Temporary three-map campaign loads")
	main.hud.menu_open = true
	await draw()
	await click(main.hud.free_button)
	check(main.sim.layout_id == "level01" and main.campaign_play and main.hud.layout_ids == ["level01","meadow","storm_coast"],"Actual skip enters the configured first map; formal selector uses array order")
	check(main.sim.plot_water == 0 and main.wind_input.sim == main.sim,"First map is normal wet-air start with current picking")
	main.next_level()
	check(main.sim.layout_id == "level01" and not main.selecting_levels,"No success cannot advance")
	main.switch_mode("lesson")
	main.sim.outcome = "success"
	await draw()
	check(main.hud.free_button.text == "返回当前关卡","Revisited teaching identifies the return destination")
	await click(main.hud.free_button)
	check(main.sim.layout_id == "level01" and main.campaign_play,"Leaving revisited teaching restores the formal context")
	main.sim.stroke(Vector2(-5,1),Vector2(-4,1),0.5)
	var before: RefCounted = main.sim
	var water: float = main.sim.water_total()
	main.wind_input.dragging = true
	main.open_level_selection()
	await draw()
	check(main.selecting_levels and main.paused and not main.wind_input.enabled and not main.wind_input.dragging,"Selection immediately pauses and cancels drag")
	check(main.hud.selection_ids == ["level01","meadow","storm_coast"] and main.hud.blocks_wind(Vector2(5,5)),"Selection is ordered, unlocked and blocks weather across the viewport")
	main._process(0.1)
	check(main.sim == before and main.sim.water_total() == water and main.frame_steps == 0,"Selection does not advance or reset the current weather")
	main.weather_view.reset_tracers()
	await draw()
	root.get_texture().get_image().save_png(directory+"selection-"+str(root.size.x)+".png")
	await click(main.front_menu.back_button if main.front_active() else main.hud.selection_back)
	check(not main.paused and main.wind_input.enabled and main.sim == before,"Back restores unpaused weather without restarting")
	main.paused = true
	main.open_level_selection()
	await draw()
	await click(main.front_menu.back_button if main.front_active() else main.hud.selection_back)
	check(main.paused and not main.wind_input.enabled,"Opening from pause preserves the prior pause")
	main.paused = false
	complete()
	await draw()
	check(main.sim.result_stars == 3 and main.hud.next_button.text == "下一关","Configured nonfinal success offers next")
	check(main.hud.levels_button.visible and main.hud.result_rect.encloses(main.hud.levels_button.get_global_rect()) and not main.hud.levels_button.get_global_rect().intersects(main.hud.next_button.get_global_rect()),"Nonfinal result keeps select, retry and next inside the panel without overlap")
	await click(main.hud.next_button)
	check(main.sim.layout_id == "meadow" and main.sim.plot_water == 0 and not main.selecting_levels,"Actual next button opens the second configured map")
	main.restart(false)
	check(main.sim.layout_id == "meadow" and main.campaign_play,"Retry preserves current map and formal context")
	complete()
	await draw()
	await click(main.hud.next_button)
	check(main.sim.layout_id == "storm_coast","Next follows the third resource reference")
	complete()
	await draw()
	check(main.hud.next_button.text == "返回选关","Final success does not offer a fictional next map")
	check(not main.hud.levels_button.visible,"Final result has one return-to-selection action without a duplicate outside the panel")
	root.get_texture().get_image().save_png(directory+"final-"+str(root.size.x)+".png")
	await click(main.hud.next_button)
	check(main.selecting_levels and main.sim.layout_id == "storm_coast" and main.sim.result_stars == 3,"Final return opens selection while keeping the result")
	await click(main.front_menu.cards[0])
	check(main.front_menu.selected_id == main.campaign.levels[0].id,"Native map card accepts real cross-frame mouse selection")
	await click(main.front_menu.start_button if main.front_active() else main.hud.selection_start)
	check(main.sim.layout_id == "level01" and not main.paused and not main.hud.selection_panel.visible,"Start selection builds fresh map and closes the panel")
	# Saved order changes wait until opening selection, not retry or F6.
	save_campaign(["meadow","level01"])
	water = main.sim.water_total()
	main.reload_tuning()
	check(main.campaign.ids() == ["level01","meadow","storm_coast"] and main.sim.water_total() == water,"F6 applies weather tuning without loading saved campaign edits")
	main.restart(false)
	check(main.campaign.ids() == ["level01","meadow","storm_coast"],"R leaves in-progress campaign order intact")
	main.open_level_selection()
	await draw()
	check(main.campaign.ids() == ["meadow","level01"] and main.hud.selection_ids == ["meadow","level01"],"Selection reloads saved ordering atomically")
	main.close_level_selection()
	var bad := WRCampaign.new()
	bad.tutorial = load("res://configs/tutorial.tres")
	bad.levels = [load("res://configs/maps/level01.tres"),null]
	ResourceSaver.save(bad,main.campaign_path)
	before = main.sim
	main.open_level_selection()
	await draw()
	check(main.campaign.ids() == ["meadow","level01"] and "levels[1]" in main.tuning_message and main.sim == before,"Invalid update retains weather and last valid order with a field error")
	await click(main.front_menu.back_button if main.front_active() else main.hud.selection_back)
	save_campaign(["meadow"])
	main.open_level_selection()
	await draw()
	check(main.hud.selection_ids == ["meadow"] and main.sim.layout_id == "level01","Removing current map affects the selection, not current weather")
	await click(main.front_menu.back_button if main.front_active() else main.hud.selection_back)
	complete()
	await draw()
	await click(main.hud.next_button)
	check(main.selecting_levels,"Unlisted current map safely returns to selection")
	await click(main.front_menu.start_button if main.front_active() else main.hud.selection_start)
	check(main.sim.layout_id == "meadow","Changed list can start its new first map")
	main.sim.elapsed_seconds = main.sim.time_limit_seconds
	main.sim.step(main.sim.FIXED_STEP)
	main.record_result()
	await draw()
	check(main.hud.levels_button.visible and main.hud.result_rect.encloses(main.hud.levels_button.get_global_rect()) and not main.hud.next_button.visible,"Zero-star timeout can retry or select inside the result without next access")
	await click(main.hud.levels_button)
	check(main.selecting_levels,"Failure selection is a real clickable button")
	await click(main.front_menu.back_button if main.front_active() else main.hud.selection_back)
	main.open_level_selection(true)
	await draw()
	check(main.hud.selection_development and "standard" in main.hud.selection_ids,"Development browser retains historical maps")
	main.hud.selection_list.select(main.hud.selection_ids.find("close"))
	await click(main.front_menu.start_button if main.front_active() else main.hud.selection_start)
	check(main.sim.layout_id == "close" and not main.campaign_play,"Development selection does not become a formal campaign step")
	main.switch_mode("lesson")
	main.enter_free_play()
	check(main.sim.layout_id == "close" and not main.campaign_play,"Revisited teaching preserves a development map too")
	var pref := ConfigFile.new()
	pref.set_value("onboarding","visited_free_play",true)
	pref.save(main.preferences_path)
	check(main.initial_mode(PackedStringArray()) == "free" and main.initial_mode(PackedStringArray(["--fresh-guide"])) == "lesson","Existing onboarding preference and fresh-guide isolation remain compatible")
	var returning := ReturningGame.new()
	returning.persist_progress = false
	returning.preferences_path = main.preferences_path
	root.add_child(returning)
	returning.set_process(false)
	check(returning.play_mode == "free" and returning.campaign_play and returning.sim.layout_id == "level01","Actual returning startup uses the first formal map rather than old standard")
	returning.queue_free()
	var unavailable := ReturningGame.new()
	unavailable.persist_progress = false
	unavailable.preferences_path = main.preferences_path
	unavailable.campaign_path = directory+"missing.tres"
	root.add_child(unavailable)
	unavailable.set_process(false)
	check(unavailable.play_mode == "lesson" and unavailable.campaign == null and "不可用" in unavailable.tuning_message,"Missing first-load campaign visibly falls back to teaching, never a fabricated formal list")
	unavailable.open_level_selection()
	check(unavailable.hud.selection_ids.is_empty() and unavailable.front_menu.start_button.disabled,"Unavailable first-load campaign cannot start an unconfigured map")
	unavailable.queue_free()
	check(not FileAccess.file_exists(main.progress_path),"Development test does not write formal highest records")
	var candidate: WRMapDefinition = load("res://configs/maps/level01.tres").duplicate(true)
	candidate.id = "candidate"
	ResourceSaver.save(candidate,directory+"candidate.tres")
	var one := WRCampaign.new()
	one.tutorial = load("res://configs/tutorial.tres")
	one.levels = [load(directory+"candidate.tres")]
	ResourceSaver.save(one,main.campaign_path)
	check(main.reload_campaign(),"A newly saved custom map can enter the campaign by resource reference")
	candidate.star_level = false
	ResourceSaver.save(candidate,directory+"candidate.tres")
	before = main.sim
	main.select_campaign_level("candidate")
	check(main.sim == before and "star_level" in main.tuning_message,"Changed on-disk map is checked again before starting; stale list cannot start an unrated formal map")
	FileAccess.open(directory+"scene-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"size":str(root.size),"highest":main.progress.best},"\t"))
	main.queue_free()
	await process_frame
	print("CAMPAIGN SCENE: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
