extends SceneTree
## Real pointer ownership/window checks plus isolated tutorial display fixtures.
var main: Node3D
var checks := 0
var failures := 0
var directory := "res://.godot/usability-refinement-20261020/"

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func draw() -> void:
	main.hud.queue_redraw()
	for frame in 4: await process_frame
	while main.front_menu.page_tween != null and main.front_menu.page_tween.is_running(): await process_frame
	await RenderingServer.frame_post_draw
func mouse(point: Vector2, pressed: bool, which := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = which
	event.pressed = pressed
	root.push_input(event,true)
func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func screen(point: Vector2) -> Vector2:
	return main.weather_view.camera.unproject_position(Vector3(point.x,main.sim.terrain.height(point)+0.3,point.y))
func click(control: BaseButton) -> void:
	var point := control.get_global_rect().get_center()
	mouse(point,true)
	await draw()
	mouse(point,false)
	await draw()
func f11(echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F11
	event.pressed = true
	event.echo = echo
	root.push_input(event,true)
	await draw()
	event = InputEventKey.new()
	event.keycode = KEY_F11
	root.push_input(event,true)
	await draw()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	main.persist_progress = false
	main.show_learning_briefings = false
	main.show_front_menu = false
	root.add_child(main)
	await draw()
	main.select_layout("needs_lab")
	await draw()
	main.guide.cold_hint_seen = true
	var hud: Control = main.hud
	var brush_point: Vector2 = hud.brush_button.get_global_rect().get_center()
	var hints: bool = main.weather_view.hints_enabled
	var wind: PackedVector2Array = main.sim.wind.duplicate()
	await click(hud.arrows_button)
	check(main.weather_view.hints_enabled != hints and not main.wind_input.dragging,"Fresh toolbar clicks act only on the UI")
	check(main.sim.wind == wind,"Clicking the toolbar creates no wind")
	var gap: Vector2 = hud.wind_toolbar_rect.position+Vector2(2,2)
	check(not hud.blocks_wind(gap),"Toolbar background and padding pass through")
	check(hud.blocks_wind(brush_point) and not hud.blocks_wind(brush_point,true),"Only an existing weather gesture may pass actual toolbar buttons")
	mouse(screen(Vector2(-4,1)),true)
	move(screen(Vector2(-3.5,1)))
	await draw()
	await create_timer(0.2).timeout
	check(hud.toolbar_alpha == 1.0 and not hud.toolbar_near_drag,"A distant scene drag leaves the toolbar fully visible")
	check(hud.arrows_button.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Distant drag still owns input before approaching the toolbar")
	var sources: int = main.sim.wind_sources.size()
	var tool: String = main.wind_input.tool
	var arrow_point: Vector2 = hud.arrows_button.get_global_rect().get_center()
	hints = main.weather_view.hints_enabled
	move(arrow_point)
	await draw()
	await create_timer(0.2).timeout
	check(main.wind_input.dragging and not main.wind_input.path_points.is_empty(),"Weather drag continues through toolbar controls")
	check(hud.arrows_button.self_modulate.a < 0.3 and hud.arrows_button.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Only nearby owned dragging fades the toolbar")
	move(Vector2(hud.wind_toolbar_rect.position.x-35,hud.wind_toolbar_rect.get_center().y))
	await draw()
	check(hud.toolbar_near_drag,"A small exit margin prevents fade flicker at the toolbar edge")
	move(screen(Vector2(-3.5,1)))
	await create_timer(0.2).timeout
	await draw()
	check(hud.toolbar_alpha == 1.0 and main.wind_input.dragging,"Moving away restores the bar without ending the gesture")
	move(arrow_point)
	await create_timer(0.2).timeout
	await draw()
	root.get_texture().get_image().save_png(directory+"near-toolbar-"+str(root.size.x)+".png")
	mouse(arrow_point,false)
	check(hud.source_button.mouse_filter == Control.MOUSE_FILTER_STOP and hud.source_button.self_modulate.a == 1,"Release restores toolbar synchronously before the next draw")
	await draw()
	check(not main.wind_input.dragging and main.sim.held_wind.is_empty(),"Release over toolbar ends the gesture and held force")
	check(main.weather_view.hints_enabled == hints and main.wind_input.tool == tool and main.sim.wind_sources.size() == sources,"Weather mouse-up cannot click hints, switch tools or remove sources")
	check(hud.arrows_button.self_modulate.a == 1 and hud.arrows_button.mouse_filter == Control.MOUSE_FILTER_STOP,"Native toolbar input restores after release")
	await click(hud.source_button)
	check(main.wind_input.tool == "source","Native source button remains usable after a crossing")
	var source_end: Vector2 = hud.vortex_button.get_global_rect().get_center()
	mouse(screen(Vector2(-3,1)),true)
	move(source_end)
	mouse(source_end,true,MOUSE_BUTTON_WHEEL_UP)
	check(main.wind_input.dragging and main.wind_input.source_tier == 2,"Wheel power works over toolbar during an owned band gesture")
	var expected_end: Vector3 = main.wind_input._on_plane(source_end,main.wind_input.reference_height)
	check(main.sim.contains(Vector2(expected_end.x,expected_end.z)),"Band endpoint behind toolbar is in the real weather domain")
	mouse(source_end,false)
	await draw()
	check(main.sim.wind_sources.size() == 1 and main.wind_input.tool == "source","Band can release over toolbar without clicking the vortex tool")
	if not main.sim.wind_sources.is_empty():
		check(main.sim.wind_sources[0].end.distance_to(Vector2(expected_end.x,expected_end.z)) < 0.01,"Band stores the actual endpoint behind UI")
		var before: float = main.sim.wind_sources[0].remaining
		check(absf(hud.toolbar_toggle.get_global_rect().get_center().x-hud.size.x*0.5)<1 and hud.toolbar_toggle.text.is_empty() and hud.toolbar_toggle.icon != null,"Expanded fold handle is a centered native chevron without text")
		check(hud.toolbar_toggle.get_rect().position.y>hud.wind_toolbar_rect.end.y and root.get_visible_rect().encloses(hud.toolbar_toggle.get_rect()),"Fold handle sits below the bar and stays inside the viewport")
		await click(hud.toolbar_toggle)
		check(hud.toolbar_collapsed and not hud.wind_toolbar_rect.has_area() and not hud.source_remove[0].visible,"Fold hides the bar and source rows, leaving an expand handle")
		check(not hud.blocks_wind(source_end) and not hud.blocks_wind(brush_point),"Collapsed toolbar releases its old footprint")
		check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].remaining < before,"Folding does not remove or freeze a real wind band")
		check(absf(hud.toolbar_toggle.get_global_rect().get_center().x-hud.size.x*0.5)<1 and hud.toolbar_toggle.icon == hud.toolbar_icons[1],"Collapsed handle stays centered and reverses its chevron")
		root.get_texture().get_image().save_png(directory+"folded-"+str(root.size.x)+".png")
		await click(hud.toolbar_toggle)
		check(not hud.toolbar_collapsed and hud.source_remove[0].visible,"Expand restores native close controls")
		await click(hud.source_remove[0])
		check(main.sim.wind_sources.is_empty(),"Cross-frame native close button still removes the source")
	await click(hud.vortex_button)
	var vortex_end: Vector2 = hud.brush_button.get_global_rect().get_center()
	var endpoint: Vector3 = main.wind_input._on_plane(vortex_end,0.4)
	var center := Vector2(endpoint.x,endpoint.z)-Vector2(1.6,1.6)
	mouse(screen(center),true,MOUSE_BUTTON_RIGHT)
	move(vortex_end)
	check(main.wind_input.dragging and main.wind_input.vortex_preview().ok,"Right-button vortex remains valid when crossing toolbar")
	mouse(vortex_end,false,MOUSE_BUTTON_RIGHT)
	await draw()
	check(main.sim.wind_sources.size() == 1 and main.sim.wind_sources[0].kind == "vortex" and main.sim.wind_sources[0].spin == -1,"Right-button vortex releases behind toolbar with its rotation preserved")
	await click(hud.source_remove[0])
	await click(hud.source_button)
	mouse(screen(Vector2(-4,1)),true)
	move(hud.menu_button.get_global_rect().get_center())
	check(not main.wind_input.dragging,"Menu controls remain outside the pass-through gesture region")
	mouse(hud.menu_button.get_global_rect().get_center(),false)
	check(not hud.menu_open and main.sim.wind_sources.is_empty(),"Canceled weather release does not open menu or place a band")
	mouse(screen(Vector2(-4,1)),true)
	move(Vector2(-10,50))
	check(not main.wind_input.dragging,"Viewport exit still cancels placement")
	mouse(Vector2(-10,50),false)
	mouse(screen(Vector2(-4,1)),true)
	main.wind_input._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not main.wind_input.dragging and main.sim.held_wind.is_empty(),"Focus loss still discards the gesture")
	mouse(screen(Vector2(-4,1)),false)
	var original_mode := root.mode
	var original_size := root.size
	var original_position := root.position
	main.set_process(false)
	var humidity: PackedFloat32Array = main.sim.humidity.duplicate()
	mouse(screen(Vector2(-4,1)),true)
	await f11()
	check(root.mode == Window.MODE_FULLSCREEN and not main.wind_input.dragging,"F11 enters borderless fullscreen and cancels a pending source")
	await f11(true)
	check(root.mode == Window.MODE_FULLSCREEN,"Held F11 does not repeat-toggle")
	await f11()
	check(root.mode == original_mode and root.size == original_size and root.position == original_position,"F11 restores original window mode, size and position")
	check(main.sim.humidity == humidity and main.sim.wind_sources.is_empty(),"Window switching preserves weather and cannot release a pending band")
	for page in ["home","levels","settings"]:
		main.open_front_page(page)
		await draw()
		await f11()
		check(root.mode == Window.MODE_FULLSCREEN and main.front_active(),"F11 works in front page "+page)
		await f11()
		check(root.mode == original_mode,"F11 restores from front page "+page)
	main.close_front_page()
	main.paused = false
	main.wind_input.enabled = true
	main.switch_mode("lesson")
	main.set_process(false)
	main._process(0)
	hud.paused = false
	await draw()
	var rect: Rect2 = hud.humidity_guide_rect
	check(rect.size.x > 120 and rect.size.y > 70,"Tutorial brackets provide a usable moisture focus instead of a tiny point")
	check(rect.size.x <= 260*hud._guide_scale()+0.1 and rect.size.y <= 160*hud._guide_scale()+0.1,"Tutorial core focus stays bounded instead of outlining faint parcel tails")
	check(root.get_visible_rect().encloses(rect) and hud.humidity_guide_cells.size() > 20,"Moisture region frame fits viewport and spans actual wet cells")
	check(root.get_visible_rect().encloses(hud.guide_rect) and hud.guide_rect.size.y>100,"Larger tutorial text wraps inside a responsive card")
	root.get_texture().get_image().save_png(directory+"tutorial-"+str(root.size.x)+".png")
	hud.set_process(false)
	hud.ui_time = 0.4
	var expanded_pulse: float = hud._guide_pulse()
	await draw()
	root.get_texture().get_image().save_png(directory+"pulse-large-"+str(root.size.x)+".png")
	hud.ui_time = 1.2
	check(expanded_pulse>1.05 and hud._guide_pulse()<0.95,"Teaching brackets breathe gently over a 1.6-second cycle")
	await draw()
	root.get_texture().get_image().save_png(directory+"pulse-small-"+str(root.size.x)+".png")
	hud.paused = true
	var paused_time: float = hud.ui_time
	hud._process(0.1)
	check(hud.ui_time == paused_time,"Pause freezes tutorial breathing")
	main.transition.reduced_motion = true
	check(hud._guide_pulse()==1.0,"Reduced motion keeps teaching brackets still")
	main.transition.reduced_motion = false
	hud.paused = false
	hud.set_process(true)
	if hud.humidity_guide_cells.is_empty():
		quit(1)
		return
	var cell: int = hud.humidity_guide_cells[0]
	var old_target: Rect2 = hud.humidity_guide_target
	main.weather_view.camera.size *= 0.8
	await draw()
	check(hud.humidity_guide_target != old_target and hud.humidity_guide_rect == hud.humidity_guide_target,"Tutorial bounds snap to changed camera projection")
	var old_humidity: PackedFloat32Array = main.sim.humidity.duplicate()
	main.sim.humidity.fill(0)
	# Display-only fixture: split wet parcels; keep the currently indicated parcel.
	for n in [cell, mini(cell+1,main.sim.COUNT-1)]: main.sim.humidity[n] = 1.0
	main.sim.humidity[main.sim.COUNT-100] = 3.0
	hud.ui_time += 0.2
	await draw()
	check(cell in hud.humidity_guide_cells and not (main.sim.COUNT-100 in hud.humidity_guide_cells),"A disconnected stronger parcel does not steal the active tutorial marker")
	for frame in 20: hud._process(0.05)
	check(hud.humidity_guide_rect.position.distance_to(hud.humidity_guide_target.position)<1,"Core focus settles smoothly after the indicated parcel shrinks")
	main.sim.humidity = old_humidity
	main.guide.phase = 2
	main.sim.peak_density = 1.0
	await draw()
	main.paused = true
	await f11()
	check(root.mode == Window.MODE_FULLSCREEN and main.paused,"Fullscreen switch preserves a paused game")
	await f11()
	main.select_campaign_level("level01")
	main.set_process(false)
	main.sim.outcome = "success"
	main.sim.result_stars = 3
	await draw()
	await f11()
	check(root.mode == Window.MODE_FULLSCREEN and main.sim.outcome == "success" and hud.result_home.visible,"F11 works from the result screen without changing its outcome")
	await f11()
	var theme := load("res://themes/front_menu.tres") as Theme
	var normal := theme.get_stylebox("normal","PrimaryButton") as StyleBoxFlat
	var hover := theme.get_stylebox("hover","PrimaryButton") as StyleBoxFlat
	var pressed := theme.get_stylebox("pressed","PrimaryButton") as StyleBoxFlat
	check(hover.bg_color.get_luminance() > normal.bg_color.get_luminance()*1.3 and pressed.bg_color.get_luminance() < normal.bg_color.get_luminance(),"Primary hover visibly brightens and pressed darkens")
	check(hover.border_width_left == 1 and normal.get_content_margin(SIDE_LEFT) == hover.get_content_margin(SIDE_LEFT),"Hover adds a clear outline without moving button content")
	main.open_front_page("home")
	await draw()
	var primary: Button = main.front_menu.primary
	move(primary.get_global_rect().get_center())
	await draw()
	check(primary.is_hovered(),"Primary native Button enters actual hover state")
	root.get_texture().get_image().save_png(directory+"primary-hover-"+str(root.size.x)+".png")
	FileAccess.open(directory+"checks-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"size":str(root.size),"scope":"native input/window and tutorial display fixtures; not gameplay or performance acceptance"},"  "))
	print("USABILITY FOLLOWUP: ",checks," checks, ",failures," failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
