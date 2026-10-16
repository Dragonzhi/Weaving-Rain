extends SceneTree
## Display/hover fixtures; complete natural weather route is checked separately.
var main: Node3D
var checks := 0
var failures := 0
var directory := "res://.godot/ui-polish/"
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func render(name := "") -> Image:
	main.hud.queue_redraw()
	for n in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not name.is_empty(): image.save_png(directory+name+"-"+str(root.size.x)+".png")
	return image
func move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
func click(control: BaseButton) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		# Reproduce real gameplay: redraws continue between press and release.
		for frame in 8:
			main.hud.queue_redraw()
			await process_frame
	while main.transition_active(): await process_frame
	await render()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(main.transition_active() and main.transition.progress>=0.5,"Startup is already covered before first visible frame")
	var water: float = main.sim.water_total()
	await render("startup")
	check(main.frame_steps==0 and not main.wind_input.enabled,"Cloud reveal cannot advance gameplay or accept wind")
	while main.transition_active(): await process_frame
	check(not main.transition.visible and main.front_menu.page=="home" and main.sim.water_total()==water,"Reveal leaves home ready and weather unchanged")
	main.select_campaign_level("level06")
	main.set_process(false)
	main.guide.cold_hint_seen = true
	main.guide.cold_hint_left = 0
	await render()
	var hud: Control = main.hud
	check(not main.weather_view.hints_enabled and hud.arrows_button.text.ends_with("关"),"Both actual weather hints and button default off")
	check(hud.find_children("*","OptionButton",true,false).is_empty(),"No gameplay dropdown remains in the scene")
	check(hud.timer_label.text=="03:00" and hud.timer_rect.has_area(),"Clock keeps an exact readable countdown")
	check(hud.reserve_rect.position==Vector2(20,16) and hud.reserve_rect.size.y>25,"Cloud reserve occupies compact top-left slot")
	check(not hud.blocks_wind(hud.reserve_rect.get_center()) and not hud.blocks_wind(hud.timer_rect.get_center()) and not hud.blocks_wind(hud.rating_rect.get_center()),"All three top indicators remain input-transparent")
	var before: PackedByteArray = main.sim.humidity.to_byte_array()
	move(Vector2(15,root.size.y-150))
	await render("play")
	var any_hovered := false
	for target in main.sim.plot_centers.size(): any_hovered = any_hovered or hud._plot_hovered(target)
	check(not any_hovered,"No range highlight away from all targets")
	check(hud.plot_label_rects.all(func(rect): return rect.size.y<=24),"World labels are smaller than old 30-pixel cards")
	check(hud.plot_tooltip_text.is_empty(),"ABC and numeric details stay collapsed without hover")
	var outline: PackedVector2Array = hud._ground_region(0)
	var point := Vector2.ZERO
	for p in outline: point += p
	point /= outline.size()
	move(point)
	await render("hover")
	check(hud._plot_hovered(0) and hud.plot_tooltip_text.begins_with("A "),"Actual terrain hover reveals its range and identifier")
	move(hud.plot_label_rects[1].get_center())
	await render()
	check(hud._plot_hovered(1) and hud.plot_tooltip_text.begins_with("B "),"Small label itself also activates target hover")
	check(not hud.blocks_wind(hud.plot_tooltip_rect.get_center()),"Expanded details do not steal weather input")
	main.wind_input.dragging = true
	main.wind_input.tool = "brush"
	check(not hud.brush_direction_visible(),"Black brush marker hidden with hints off")
	main.wind_input.dragging = false
	await click(hud.arrows_button)
	main.wind_input.dragging = true
	check(hud.brush_direction_visible(),"Black brush marker is opt-in with weather hints")
	main.wind_input.cancel()
	main.restart(false)
	main.set_process(false)
	check(main.weather_view.hints_enabled,"Retry preserves the player's hint choice")
	main.weather_view.hints_enabled = false
	# Isolated half-full HUD fixture; does not assert a normal rain route.
	for fraction in [0.0,0.000000001,0.5,1.0]:
		main.sim.remaining_humidity = main.sim.initial_water*fraction
		main.sim.remaining_cloud = 0
		await render()
	check(hud.reserve_rect.has_area(),"Empty, subpixel and full cloud reserves render without invalid geometry")
	main.sim.remaining_humidity = main.sim.initial_water*0.35
	main.sim.remaining_cloud = main.sim.initial_water*0.25
	await render("reserve")
	check(main.sim.humidity.to_byte_array()==before,"Hover, icons and reserve display do not modify weather")
	main.sim.plot_waters[0] = main.sim.required_water(0)
	main.sim.plot_safe_times[0] = main.sim.settings.safe_seconds
	main.sim.outcome = "success"
	main.sim.result_stars = 1
	main.sim.result_saved_count = 1
	await render("result")
	check(hud.result_home.theme==hud.result_retry.theme and hud.next_button.theme==hud.result_home.theme,"All result actions share the same existing theme")
	check(hud.next_button.theme_type_variation=="PrimaryButton","Next action uses the same primary style as home")
	for control in [hud.result_retry,hud.next_button,hud.result_home]:
		check(control.visible and root.get_visible_rect().encloses(control.get_global_rect()),"Result action fits and remains visible: "+control.text)
	check(hud.blocks_wind(hud.result_rect.get_center()),"Result still blocks weather gestures")
	var finished: RefCounted = main.sim
	await click(hud.result_home)
	check(main.front_active() and main.front_menu.page=="home" and main.sim==finished,"Real cross-frame result home button opens home without replacing weather")
	if main.front_active():
		check(main.front_menu.primary.text.begins_with("开始旅程"),"Completed session retains the existing start-new-journey action")
		# Restore the fixture directly to test its separate retry action below.
		main.close_front_page()
		await render()
		check(main.sim==finished and main.sim.outcome=="success" and hud.result_home.visible,"Preserved completed result has its return button again")
	await click(hud.result_retry)
	check(main.sim.outcome=="playing" and main.sim.plot_waters[0]==0,"Real restyled retry button starts a clean map")
	main.set_process(false)
	main.open_front_page("home")
	await render()
	await click(main.front_menu.primary)
	check(not main.front_active(),"Native continue still reaches the same game")
	FileAccess.open(directory+"review-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"size":str(root.size)},"\t"))
	print("UI POLISH: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
