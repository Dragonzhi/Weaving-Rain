extends "res://tests/test_wind_tools_scene.gd"
const Visuals = preload("res://scripts/hud_visuals.gd")

func render() -> Image:
	main.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func update_fixture() -> void:
	main.sim.refresh_display()
	main.sim.update_goal(0.0)
	main.hud.reset_feedback()
	main.weather_view.update_weather(0.0, false)

func run() -> void:
	var slots := Visuals.water_slots(100,50)
	check(slots.size()==5 and slots[0].fill==1 and slots[2].fill==0.5 and slots[4].fill==0, "Fixed units show 50/100 as two and a half of five equal drops")
	slots = Visuals.water_slots(40,40)
	check(slots.size()==2 and slots[1].fill==1, "Seedlings use fewer same-size drops")
	slots = Visuals.water_slots(45,42.5)
	check(slots.size()==3 and slots[2].capacity==5 and slots[2].fill==0.5, "Remainder drop uses its actual five-unit capacity")
	slots = Visuals.water_slots(250,175)
	check(slots.size()==6 and slots[-1].units==8 and slots[-1].capacity==150 and slots[-1].fill==0.5, "Large farm needs use a clearly counted bounded group")
	check(Visuals.water_slots(1e30,0).size()==6 and Visuals.water_slots(100,151)[-1].fill==1, "Huge needs remain bounded and overflow never adds more drops")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await render()
	main.set_process(false)
	main.hud.set_process(false)
	main.guide.cold_hint_seen = true
	main.guide.cold_hint_left = 0
	main.sim.plot_waters[0] = 50
	main.sim.plot_waters[1] = 40
	var danger_cell: int = main.sim.safety_indices[1][0]
	main.sim.cloud[danger_cell] = 0.1
	main.sim.rain[danger_cell] = 0.1
	update_fixture()
	var picture := await render()
	check(main.hud.plot_glyph_slots[0].size()==5 and main.hud.plot_glyph_slots[1].size()==2, "Actual farm HUD uses each resource's fixed-unit demand")
	check(main.sim.plot_status(1)=="danger" and not main.sim.target_complete(1) and main.hud.rating_seen==0, "Full water under real rain does not light completion or rating")
	var scale := Vector2(picture.get_size())/root.get_visible_rect().size
	var row_origin: Vector2 = main.hud.plot_label_rects[0].get_center()-main.hud._water_row_center(0)*0.82
	var blue_point: Vector2 = (row_origin+Vector2(6,13)*0.82)*scale
	var empty_point: Vector2 = (row_origin+Vector2(6+4*16,13)*0.82)*scale
	var blue := picture.get_pixelv(Vector2i(blue_point))
	var empty := picture.get_pixelv(Vector2i(empty_point))
	check(blue.b-blue.r>0.12 and empty.r-blue.r>0.2, "GPU screenshot distinguishes a filled drop from an empty outlined drop")
	for amount in [0.00000001,19.99999999,20.00000001,40.00000001]:
		main.sim.plot_waters[0] = amount
		main.hud.shown_water[0] = amount
		await render()
	check(main.hud.shown_water[0]==40.00000001, "Subpixel and exact-vertex fills render without changing tiny real quantities")
	main.sim.plot_waters[0] = 50
	main.hud.shown_water[0] = 50
	move(main.hud.plot_label_rects[1].get_center())
	await render()
	check("危险天气" in main.hud.plot_tooltip_text and not main.hud.blocks_wind(main.hud.plot_tooltip_rect.get_center()), "Real hover expands one accurate pass-through explanation")
	button(main.hud.plot_tooltip_rect.get_center(),true)
	check(main.wind_input.dragging, "Press through floating text still starts a weather gesture")
	main.wind_input.cancel()
	button(main.hud.plot_tooltip_rect.get_center(),false)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.refresh_display()
	main.sim.update_goal(1.0)
	main.hud.reset_feedback()
	await render()
	check(main.sim.plot_status(1)=="confirming" and main.sim.plot_safe_times[1]==1.0 and main.hud.rating_seen==0, "Safety ring reads real incomplete confirmation, not full water")
	main.sim.update_goal(2.0)
	await render()
	check(main.hud.rating_seen==1 and main.sim.target_complete(1), "Actual safety lights one current wind medal")
	main.sim.plot_waters[0] = 151
	main.sim.update_goal(0.0)
	main.hud.reset_feedback()
	await render()
	check(main.hud.water_color(0)==Visuals.DAMAGE and main.sim.plot_status(0)=="destroyed", "Permanent loss is red independently of drop fill")
	main.sim.plot_waters[0] = 110
	main.sim.update_goal(3)
	await render()
	check(main.hud.water_color(0)==Visuals.DAMAGE, "Lowering fixture water cannot hide an existing damaged target")
	main.select_layout("reservoir_lab")
	main.set_process(false)
	main.sim.plot_waters[1] = 250
	danger_cell = main.sim.safety_indices[1][0]
	main.sim.cloud[danger_cell] = 0.1
	main.sim.rain[danger_cell] = 0.1
	update_fixture()
	await render()
	check(main.sim.target_complete(1) and main.sim.plot_safe_times[1]==0 and main.hud.plot_glyph_slots[1].is_empty(), "Reservoir uses its own completed container without waiting for a safety ring")
	var ordinary: Resource = main.sim.plot_needs[0].duplicate()
	ordinary.target_water = 145
	ordinary.flood_water = 200
	main.sim.plot_needs[0] = ordinary
	main.sim.plot_waters[0] = 122.5
	update_fixture()
	move(main.hud.plot_label_rects[0].get_center())
	await render()
	check(main.hud.plot_glyph_slots[0].size()==6 and "叠滴45" in main.hud.plot_tooltip_text, "Grouped remainder capacity is shown in real hover details")
	ordinary.target_water = 1e30
	ordinary.flood_water = 2e30
	main.sim.plot_waters[0] = 0
	update_fixture()
	await render()
	move(main.hud.plot_label_rects[0].get_center())
	await render()
	check(main.hud.plot_glyph_slots[0].size()==6 and root.get_visible_rect().encloses(main.hud.plot_tooltip_rect), "Extremely large valid needs keep grouped graphics and scientific-value hover inside viewport")
	main.hud.paused = true
	var time: float = main.hud.ui_time
	var water: PackedFloat64Array = main.hud.shown_water.duplicate()
	main.hud._process(1)
	main.hud.update_feedback(0)
	check(main.hud.ui_time==time and main.hud.shown_water==water, "Pause freezes UI clock and fill interpolation")
	main.hud.paused = false
	main.restart(false)
	main.set_process(false)
	await render()
	check(main.hud.shown_water==PackedFloat64Array([0,0]) and main.hud.result_since<0 and main.hud.feedback_left==PackedFloat32Array([0,0]) and not "叠滴45" in main.hud.plot_tooltip_text, "Retry clears old fill, result animation and messages while fresh hover stays available")
	var humidity: PackedFloat32Array = main.sim.humidity.duplicate()
	var cloud: PackedFloat32Array = main.sim.cloud.duplicate()
	var wind: PackedVector2Array = main.sim.wind.duplicate()
	for i in 8:
		move(main.hud.plot_label_rects[i%2].get_center())
		main.hud._process(0.05)
		await render()
	check(main.sim.humidity==humidity and main.sim.cloud==cloud and main.sim.wind==wind and main.sim.plot_waters==PackedFloat64Array([0,0]), "Floating explanations and animation leave actual weather and water unchanged")
	main.sim.layout.title = "自定义超长地图标题用于核对选择控件在小窗口内不扩张或遮挡其他信息"
	await render()
	check(main.hud.find_children("*","OptionButton",true,false).is_empty(), "Gameplay has no level dropdown even with a long title")
	main.select_layout("meadow")
	main.set_process(false)
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.charge.fill(0)
	main.sim.plot_waters = PackedFloat64Array([80,110,151])
	main.sim.refresh_display()
	main.sim.update_goal(0.5)
	main.sim.elapsed_seconds = main.sim.time_limit_seconds-main.sim.FIXED_STEP
	main._process(main.sim.FIXED_STEP)
	await render()
	check(main.hud.result_details.size()==3 and "缺水" in main.hud.result_details[0] and "安全确认" in main.hud.result_details[1] and "损坏" in main.hud.result_details[2], "Wind-medal results retain all distinct zero-rating reasons")
	check(root.get_visible_rect().encloses(main.hud.result_rect) and main.hud.result_rect.size.x<=520 and main.hud.blocks_wind(main.hud.result_rect.get_center()), "Compact result panel fits and blocks weather while its real controls remain available")
	print("UI VISUALS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
