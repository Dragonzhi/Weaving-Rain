extends "res://tests/replay_star_viewport.gd"
## Complete teaching -> configured first formal map -> next/selection via real mouse input.
var route_time := 0.0
var audio_record = preload("res://tests/audio_route_record.gd").new()
func click(control: Button) -> void:
	var point := control.get_global_rect().get_center()
	button(point,true)
	for frame in 3: await process_frame
	button(point,false)
	await RenderingServer.frame_post_draw
	while main.transition_active(): await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/campaign-review")
	main = load("res://scenes/main.tscn").instantiate()
	main.persist_progress = false
	root.add_child(main)
	await RenderingServer.frame_post_draw
	while main.transition_active(): await process_frame
	audio_record.start(main)
	var used_front_entry: bool = main.front_active()
	if used_front_entry: await click(main.front_menu.primary)
	process_frame.connect(func(): route_time += main.frame_steps*Sim.FIXED_STEP)
	var reports: Array[Dictionary] = []
	var first: String = main.campaign.levels[0].id
	var following: String = main.campaign.next_id(first)
	var passed: bool = main.play_mode == "lesson"
	for stage in 2:
		if main.hud.briefing_active(): await click(main.hud.briefing_start)
		var start := route_time
		var controller := Route.new([0],"mountain")
		var next_at := 0.5
		var phases: Array[int] = [main.guide.phase]
		while main.sim.outcome == "playing" and route_time-start < 180:
			var elapsed := route_time-start
			if elapsed >= next_at:
				var command := controller.next_command(main.sim,elapsed)
				next_at += 0.5
				if not command.is_empty(): await stroke(command)
			if not main.guide.phase in phases: phases.append(main.guide.phase)
			await process_frame
			audio_record.sample()
		await RenderingServer.frame_post_draw
		if not main.guide.phase in phases: phases.append(main.guide.phase)
		var report := controller.report(main.sim)
		report.erase("actions")
		report["route_seconds"] = route_time-start
		report["phases"] = phases
		report["campaign_play"] = main.campaign_play
		reports.append(report)
		passed = passed and main.sim.outcome == "success" and absf(main.sim.water_error()) < 0.02
		root.get_texture().get_image().save_png("res://.godot/campaign-review/normal-"+main.sim.layout_id+"-result.png")
		if stage == 0:
			passed = passed and main.guide.phase == 5 and phases[0] == 0 and not main.sim.star_level
			await click(main.hud.free_button)
			passed = passed and main.sim.layout_id == first and main.campaign_play and main.sim.plot_water == 0
		else:
			passed = passed and main.sim.result_stars == 3 and not main.sim.timed_out and main.hud.next_button.text == ("返回选关" if following.is_empty() else "下一关")
			await click(main.hud.next_button)
			passed = passed and (main.selecting_levels if following.is_empty() else (main.sim.layout_id == following and main.sim.plot_water == 0))
			root.get_texture().get_image().save_png("res://.godot/campaign-review/normal-final-selection.png")
	if main.hud.briefing_active(): await click(main.hud.briefing_start)
	passed = passed and failures == 0 and input_pick_error < 0.001
	var result := {"front_entry":used_front_entry,"passed":passed,"stages":reports,"mouse_events":events,"blocked":blocked,"input_failures":failures,"pick_error":input_pick_error,"selection":main.hud.selection_ids,"following":following}
	result["audio"] = audio_record.finish("res://.godot/campaign-review/bgm-mix.wav")
	FileAccess.open("res://.godot/campaign-review/normal-route.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("CAMPAIGN VIEWPORT ",JSON.stringify(result))
	quit(0 if passed else 1)
