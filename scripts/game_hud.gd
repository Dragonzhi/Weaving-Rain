extends Control
signal menu_changed(open: bool)
signal front_requested(page: String)
var front_active := false
var use_front_menu := false
var front_buttons: Array[Button] = []
var result_home: Button
signal restart_requested
signal sandbox_requested
signal cold_lab_requested
signal free_play_requested
signal lesson_requested
signal layout_requested(id: String)
signal finish_requested
signal next_requested
signal levels_requested
signal sound_requested(sound: String)
signal audio_changed(enabled: bool, volume: float)
signal campaign_layout_requested(id: String)
signal selection_closed
signal development_requested
const Sim = preload("res://scripts/weather_simulation.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
const Visuals = preload("res://scripts/hud_visuals.gd")
var visuals := Visuals.new()
var shown_water := PackedFloat64Array()
var ui_time := 0.0
var rating_seen := -1
var rating_since := 0.0
var result_since := -1.0
var rating_rect := Rect2()
var plot_tooltip_rect := Rect2()
var plot_tooltip_text := ""
var plot_glyph_slots: Array = []
var result_row_rects: Array[Rect2] = []
var pointer_received := false
var pointer_position := Vector2(-1,-1)
var draw_ms := 0.0
var sim: Sim
var view: Node3D
var wind_input: Node
var paused := false
var transitioning := false
var strength_meter_rect := Rect2()
var debug_visible := false
var font := SystemFont.new()
var retry: Button
var sandbox_button: Button
var cold_button: Button
var frame_ms := 0.0
var simulation_ms := 0.0
var status_rect := Rect2()
var guide_rect := Rect2()
var guide: RefCounted
var play_mode := "free"
var free_button: Button
var lesson_button: Button
var dismiss_hint: Button
var layout_selector: OptionButton
var panel_styles: Dictionary = {}
var tuning_message := ""
var layout_ids: Array = []
var best_stars: Dictionary = {}
var finish_button: Button
var next_button: Button
var result_retry: Button
var levels_button: Button
var development_button: Button
var campaign: WRCampaign
var campaign_play := false
var development := false
var return_to_game := false
var selection_panel: Panel
var selection_title: Label
var selection_list: ItemList
var selection_start: Button
var selection_back: Button
var selection_ids: Array[String] = []
var selection_development := false
var result_rect := Rect2()
var timer_rect := Rect2()
var timer_label: Label
var reserve_rect := Rect2()
var reserve_message := ""
var feedback_model: RefCounted
var ground_model: RefCounted
var ground_view_id := 0
var ground_size := Vector2.ZERO
var ground_transform := Transform3D()
var ground_projection := Projection()
var ground_outlines: Dictionary = {}
var feedback_states: Array[String] = []
var feedback_adequate: Array[bool] = []
var feedback_left := PackedFloat32Array()
var feedback_texts: Array[String] = []
var result_details: Array[String] = []
var menu_button: Button
var menu_open := false
var menu_rect := Rect2()
var audio_button: Button
var audio_volume: HSlider
var audio_enabled := true
var audio_label: Label
var plot_label_rects: Array[Rect2] = []
var compact_model: RefCounted
var tool_hint_until := 4.0
var introduced_wind_tools := 1 # Session-only explanations; does not change save data or unlock tools.
var tool_introduction := PackedStringArray()
var tool_introduction_until := 0.0
var last_tool := ""
var last_status := ""
var status_until := 0.0
var wind_toolbar_rect := Rect2()
var brush_button: Button
var source_button: Button
var vortex_button: Button
var arrows_button: Button
var source_remove: Array[Button] = []
var source_remove_ids := PackedInt32Array([-1, -1, -1, -1])
var source_pressed_ids := PackedInt32Array([-1, -1, -1, -1])
const VAPOR_COLOR := Color("b7f0dc")
const CLOUD_WATER_COLOR := Color("a6bfcc")
const INK := Color("354e57")
const MUTED := Color("607b80")
const PANEL := Color(0.94, 0.96, 0.89, 0.88)
const GOLD := Visuals.GOLD

func _process(delta: float) -> void:
	if not paused: ui_time += minf(delta, 0.1)

func _input(event: InputEvent) -> void:
	# Read viewport-local input without consuming it. This also keeps replayed
	# mouse events consistent with physical hover, unlike the OS pointer alone.
	if event is InputEventMouse:
		pointer_received = true
		pointer_position = get_global_transform_with_canvas().affine_inverse() * event.position

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pointer_received = true
		pointer_position = Vector2(-1,-1)
	elif what == NOTIFICATION_RESIZED:
		pointer_received = false

func _pointer() -> Vector2:
	return pointer_position if pointer_received else get_local_mouse_position()

func reset_feedback() -> void:
	menu_open = false
	source_pressed_ids.fill(-1)
	feedback_model = sim
	shown_water.resize(sim.plot_centers.size())
	for target in sim.plot_centers.size(): shown_water[target] = sim.water_for(target)
	ui_time = 0.0
	rating_seen = -1
	result_since = -1.0
	plot_tooltip_rect = Rect2()
	plot_tooltip_text = ""
	visuals.clear_cache()
	result_details.clear()
	result_row_rects.clear()
	feedback_states.clear()
	feedback_adequate.clear()
	feedback_texts.clear()
	feedback_left.resize(sim.plot_centers.size())
	feedback_left.fill(0.0)
	for target in sim.plot_centers.size():
		feedback_states.append(sim.plot_status(target))
		feedback_adequate.append(sim.water_for(target) >= sim.required_water(target))
		feedback_texts.append("")

func update_feedback(dt: float) -> void:
	if feedback_model != sim: reset_feedback()
	for target in sim.plot_centers.size():
		shown_water[target] = lerpf(shown_water[target], sim.water_for(target), 1.0 - exp(-dt * 20.0))
		feedback_left[target] = maxf(0.0, feedback_left[target] - dt)
		var state := sim.plot_status(target)
		var text := ""
		if state == "destroyed" and feedback_states[target] != "destroyed": text = "雨量过多 · 土地损坏"
		elif state == "safe" and feedback_states[target] != "safe": text = "已蓄满 · 可继续承雨" if sim.is_reservoir(target) else "已保住 · 当前安全"
		elif not feedback_adequate[target] and sim.water_for(target) >= sim.required_water(target):
			text = "雨量已够 · 留意移云收尾"
		if not text.is_empty() and not sim.sandbox:
			feedback_texts[target] = text
			feedback_left[target] = 1.2
		feedback_adequate[target] = feedback_adequate[target] or sim.water_for(target) >= sim.required_water(target)
		feedback_states[target] = state

func status_text(target: int, final: bool = false) -> String:
	if sim.is_reservoir(target):
		return "已蓄满 · 溢流不损坏" if sim.target_complete(target) else "蓄水中 · 还差 " + _quantity(sim.required_water(target)-sim.water_for(target))
	match sim.plot_status(target):
		"destroyed": return "过量损坏 · 不计风纹" if final else "损坏 · 仍可照顾其他地块"
		"dry": return "缺水 · 还差 " + _quantity(sim.required_water(target)-sim.water_for(target)) if final else "缺水"
		"danger": return "水量已够 · 危险天气未解除" if final else "适量 · 附近仍有危险"
		"confirming": return "水量已够 · 安全确认 %.1f / %.1f 秒" % [sim.plot_safe_times[target], sim.settings.safe_seconds] if final else "适量 · 正在确认安全"
		_: return "已保住 · 当前安全"

func water_color(target: int) -> Color:
	if sim.plot_destroyed[target]: return Color("c76e60")
	return Color("7aaebc").lerp(Color("ddc775"), sim.plot_warning(target))

func setup(model: RefCounted, weather_view: Node3D, input: Node) -> void:
	sim = model
	view = weather_view
	wind_input = input
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().mouse_exited.connect(func(): pointer_received = true; pointer_position = Vector2(-1,-1))
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.allow_system_fallback = true
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	self.theme = theme
	menu_button = Button.new()
	menu_button.text = "菜单"
	menu_button.pressed.connect(func():
		menu_open = not menu_open
		menu_changed.emit(menu_open)
		wind_input.cancel()
		queue_redraw())
	add_child(menu_button)
	result_home = Button.new()
	result_home.text = "返回主界面"
	result_home.pressed.connect(func(): front_requested.emit("home"))
	add_child(result_home)
	for item in [["玩法说明","help"],["设置","settings"],["返回主界面","home"]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(func(): front_requested.emit(item[1]))
		add_child(button)
		front_buttons.append(button)
	audio_button = Button.new()
	audio_button.pressed.connect(func():
		audio_enabled = not audio_enabled
		audio_changed.emit(audio_enabled,audio_volume.value/100.0))
	add_child(audio_button)
	audio_volume = HSlider.new()
	audio_volume.min_value = 0
	audio_volume.max_value = 100
	audio_volume.step = 1
	audio_volume.focus_mode = Control.FOCUS_NONE
	audio_volume.value_changed.connect(func(value): audio_changed.emit(audio_enabled,value/100.0))
	add_child(audio_volume)
	audio_label = Label.new()
	audio_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_label.add_theme_color_override("font_color",INK)
	add_child(audio_label)
	retry = Button.new()
	retry.text = "重新开始  R"
	retry.pressed.connect(func(): menu_open = false; restart_requested.emit())
	add_child(retry)
	sandbox_button = Button.new()
	sandbox_button.text = "云交互小样  F2"
	sandbox_button.pressed.connect(func(): sandbox_requested.emit())
	add_child(sandbox_button)
	cold_button = Button.new()
	cold_button.text = "冷风交互小样 F4"
	cold_button.pressed.connect(func(): cold_lab_requested.emit())
	add_child(cold_button)
	free_button = Button.new()
	free_button.pressed.connect(func(): menu_open = false; free_play_requested.emit())
	add_child(free_button)
	lesson_button = Button.new()
	lesson_button.text = "重看入门"
	lesson_button.pressed.connect(func(): menu_open = false; lesson_requested.emit())
	add_child(lesson_button)
	dismiss_hint = Button.new()
	dismiss_hint.text = "知道了"
	dismiss_hint.pressed.connect(func(): guide.cold_hint_left = 0.0)
	add_child(dismiss_hint)
	layout_selector = OptionButton.new()
	layout_selector.fit_to_longest_item = false
	layout_selector.add_theme_font_size_override("font_size", 13)
	refresh_layouts()
	layout_selector.item_selected.connect(func(index):
		if campaign_play: campaign_layout_requested.emit(layout_ids[index])
		else: layout_requested.emit(layout_ids[index]))
	add_child(layout_selector)
	finish_button = Button.new()
	finish_button.pressed.connect(func(): finish_requested.emit())
	add_child(finish_button)
	next_button = Button.new()
	next_button.pressed.connect(func(): next_requested.emit())
	add_child(next_button)
	result_retry = Button.new()
	result_retry.text = "重试本关"
	result_retry.pressed.connect(func(): menu_open = false; restart_requested.emit())
	add_child(result_retry)
	levels_button = Button.new()
	levels_button.text = "选关"
	levels_button.pressed.connect(func(): levels_requested.emit())
	add_child(levels_button)
	development_button = Button.new()
	development_button.text = "开发地图"
	development_button.pressed.connect(func(): development_requested.emit())
	add_child(development_button)
	_create_level_selection()
	timer_label = Label.new()
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.add_theme_font_size_override("font_size", 20)
	add_child(timer_label)
	brush_button = Button.new()
	brush_button.text = "拨风"
	brush_button.toggle_mode = true
	brush_button.pressed.connect(func(): wind_input.select_tool("brush"))
	add_child(brush_button)
	source_button = Button.new()
	source_button.text = "持续风"
	source_button.toggle_mode = true
	source_button.pressed.connect(func(): wind_input.select_tool("source"))
	add_child(source_button)
	vortex_button = Button.new()
	vortex_button.text = "漩涡"
	vortex_button.toggle_mode = true
	vortex_button.pressed.connect(func(): wind_input.select_tool("vortex"))
	add_child(vortex_button)
	arrows_button = Button.new()
	arrows_button.text = "天气提示：开"
	arrows_button.tooltip_text = "统一显示流向／抬升箭头与实际降雨范围；白色风线、雨线和风源标记始终保留。"
	arrows_button.pressed.connect(func(): view.hints_enabled = not view.hints_enabled)
	add_child(arrows_button)
	for entry in [[brush_button, "brush"], [source_button, "source"], [vortex_button, "vortex"], [arrows_button, "hints"]]:
		entry[0].icon = Visuals.tool_icon(entry[1])
		entry[0].expand_icon = true
		entry[0].add_theme_constant_override("icon_max_width", 16)
	for index in 4:
		var remove := Button.new()
		remove.text = "×"
		remove.button_down.connect(func(): source_pressed_ids[index] = source_remove_ids[index])
		remove.pressed.connect(func():
			if source_pressed_ids[index] >= 0 and not paused and sim.outcome == "playing":
				var found: bool = sim.wind_sources.any(func(source): return source.id == source_pressed_ids[index])
				sim.remove_wind_source(source_pressed_ids[index])
				if found: sound_requested.emit("click"))
		source_remove.append(remove)
		add_child(remove)
	for button in buttons():
		if button != audio_button and not button in source_remove:
			if button is OptionButton: button.item_selected.connect(func(_index): sound_requested.emit("click"))
			else: button.pressed.connect(func(): sound_requested.emit("click"))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 7
		style.content_margin_right = 7
		button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = Color("e2e9de")
		var pressed := style.duplicate()
		pressed.bg_color = Color("d8dfcd")
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("hover_pressed", pressed)
		var disabled := style.duplicate()
		disabled.bg_color = Color(PANEL, 0.64)
		button.add_theme_stylebox_override("disabled", disabled)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
		button.add_theme_color_override("font_disabled_color", Color("82918b"))
		button.add_theme_color_override("font_color", INK)
		button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var primary := next_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		primary.bg_color = Color("507b89").lightened(0.06 if state=="hover" else 0.0)
		next_button.add_theme_stylebox_override(state, primary)
		var secondary := result_retry.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		secondary.set_border_width_all(1)
		secondary.border_color = Color(INK,0.32)
		result_retry.add_theme_stylebox_override(state,secondary)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		next_button.add_theme_color_override(state, Color("f5f6eb"))

func buttons() -> Array:
	return front_buttons + [result_home, menu_button, retry, sandbox_button, cold_button, free_button, lesson_button, dismiss_hint, layout_selector,
		finish_button, next_button, result_retry, levels_button, development_button, selection_start, selection_back, brush_button, source_button, vortex_button, arrows_button, audio_button] + source_remove

func set_audio_options(on: bool, volume: float) -> void:
	audio_enabled = on
	audio_volume.set_value_no_signal(volume*100.0)

func _text(at: Vector2, text: String, font_size: int = 16, color := INK) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _rounded(rect: Rect2, color: Color, radius: int = 12) -> void:
	if not panel_styles.has(radius):
		panel_styles[radius] = StyleBoxFlat.new()
	var style: StyleBoxFlat = panel_styles[radius]
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	draw_style_box(style, rect)

func _project(point: Vector3) -> Vector2:
	return view.camera.unproject_position(point)

func blocks_wind(point: Vector2) -> bool:
	if front_active: return true
	if selection_panel.visible: return true
	if wind_toolbar_rect.has_point(point) or (menu_open and menu_rect.has_point(point)) or result_rect.has_point(point): return true
	# Drawn labels, water bars, timer, reserve and teaching text are information.
	# Only real controls and the open menu/result consume weather gestures.
	for button in buttons():
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point): return true
	return debug_visible and Rect2(28, 140, 310, 166).has_point(point)

func _guide_marker(p: Vector2, label: String, cloud_height: bool = false) -> void:
	var height: float = Sim.CLOUD_TOP + 0.1 if cloud_height else sim.terrain.height(p) + 0.35
	var at := _project(Vector3(p.x, height, p.y))
	# Static gold brackets distinguish tutorial annotations from real moving wind.
	var color := Color(0.96, 0.84, 0.61, 0.8)
	for sign_x in [-1, 1]:
		for sign_y in [-1, 1]:
			var corner := at + Vector2(sign_x, sign_y) * 23.0
			draw_line(corner, corner - Vector2(sign_x * 9, 0), color, 2.0, true)
			draw_line(corner, corner - Vector2(0, sign_y * 9), color, 2.0, true)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var label_at := at + Vector2(-width * 0.5, 48)
	_rounded(Rect2(label_at + Vector2(-8, -19), Vector2(width + 16, 26)), PANEL, 6)
	_text(label_at, label, 14, GOLD)

func _draw_guide() -> void:
	guide_rect = Rect2()
	dismiss_hint.visible = guide != null and not sim.sandbox and not guide.lesson and guide.cold_hint_left > 0.0 and sim.outcome == "playing"
	if guide == null or sim.sandbox:
		return
	if guide.lesson:
		guide_rect = Rect2(Vector2((size.x - 560) * 0.5, 64), Vector2(560, 82))
		_rounded(guide_rect, PANEL)
		var at := guide_rect.position + Vector2(14, 19)
		_text(at, guide.title(sim), 14, GOLD)
		_text(at + Vector2(0, 24), guide.instruction(sim), 14)
		_text(at + Vector2(0, 48), guide.detail(sim), 12, MUTED)
		if sim.outcome != "playing":
			return
		var field: PackedFloat32Array = sim.humidity if guide.phase == 0 or sim.peak_density < 0.15 else sim.display_cloud
		if guide.phase < 2 or (guide.phase == 2 and sim.peak_density < 0.15):
			var index := 0
			for i in Sim.COUNT:
				if field[i] > field[index]:
					index = i
			if field[index] > 0.15:
				var p: Vector2 = sim.positions[index]
				var low_air: bool = guide.phase == 0 or sim.peak_density < 0.15
				_guide_marker(p, "浅色细丝 · 湿空气" if low_air else "轻拨云边，向内收拢", not low_air)
				if low_air:
					var mountain: Vector2 = sim.terrain.mountain
					var slope_point: Vector2 = mountain + (p - mountain).normalized() * 1.8
					_guide_marker(slope_point, "送向这侧山坡")
		elif guide.phase == 2:
			_guide_marker(sim.plot_centers[0], "雨线落进水库才蓄水" if sim.is_reservoir(0) else "雨线落进 A 才加水")
		elif guide.phase == 3:
			var square := _ground_square(sim.safe_half)
			for i in 4:
				draw_dashed_line(square[i], square[(i + 1) % 4], GOLD, 2.5, 9.0)
	elif guide.cold_hint_left > 0.0 and sim.outcome == "playing":
		guide_rect = Rect2(Vector2((size.x - 560) * 0.5, 64), Vector2(560, 82))
		_rounded(guide_rect, PANEL)
		var at := guide_rect.position + Vector2(14, 19)
		_text(at, "可选技巧 · 借冷风接力", 14, GOLD)
		_text(at + Vector2(0, 24), "灰蓝色薄层是雨产生的冷空气，可以拨动。", 14)
		_text(at + Vector2(0, 48), "把湿空气迎向它的前沿可造云；也可以继续借山坡。", 12, MUTED)
		dismiss_hint.position = guide_rect.position + Vector2(464, 8)
		dismiss_hint.size = Vector2(84, 27)
		var cold_index := 0
		for i in Sim.COUNT:
			if sim.display_cold[i] > sim.display_cold[cold_index]:
				cold_index = i
		if sim.display_cold[cold_index] > 0.15:
			_guide_marker(sim.positions[cold_index], "灰蓝薄层 · 冷空气")

func _ground_square(half: float, center: Vector2 = Sim.PLOT) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var p: Vector2 = center + offset
		result.append(_project(Vector3(p.x, sim.terrain.height(p) + 0.06, p.y)))
	return result

func _draw_world_feedback() -> void:
	for target in sim.plot_centers.size():
		var center: Vector2 = sim.plot_centers[target]
		var safety := PackedVector2Array() if sim.is_reservoir(target) else _ground_region(target, sim.safe_half - sim.plot_half)
		var safe_color := Color(0.98, 0.83, 0.57, 0.65) if sim.plot_threats[target] else Color(0.88, 0.97, 0.86, 0.46)
		for i in safety.size():
			if safety.size() == 4: draw_dashed_line(safety[i], safety[(i + 1) % safety.size()], safe_color, 1.5, 7.0)
			elif i % 4 < 2: draw_line(safety[i], safety[(i + 1) % safety.size()], safe_color, 1.5, true)
		var plot := _ground_region(target)
		var flash := feedback_left[target] if sim.outcome == "playing" and feedback_model == sim and target < feedback_left.size() else 0.0
		var outline_color := Color("f1b5a0") if sim.plot_status(target) == "destroyed" else Color(0.96, 0.89, 0.72, 0.85)
		if flash > 0.0: outline_color = outline_color.lerp(GOLD if sim.plot_status(target) != "destroyed" else Color("f17761"), flash / 1.2)
		for i in plot.size():
			draw_line(plot[i], plot[(i + 1) % plot.size()], outline_color, 2.0 + flash * 2.0, true)
		var label := _project(Vector3(center.x, 0.35, center.y))
		_text(label + Vector2(-8, 5), String.chr(65 + target), 16, INK)
	if not wind_input.hover_valid:
		return
	if wind_input.tool in ["source","vortex"] and wind_input.dragging: return
	var center: Vector3 = wind_input.brush_point
	var ring := PackedVector2Array()
	for i in 65:
		var angle := float(i) / 64.0 * TAU
		var p: Vector3 = center + Vector3(cos(angle), 0, sin(angle)) * sim.settings.brush_radius
		ring.append(_project(p))
	draw_polyline(ring, Color(0.95, 1, 0.91, 0.65 if wind_input.dragging else 0.35), 1.7, true)
	var projected := Vector3(center.x,view.display_surface_height(Vector2(center.x,center.z))+0.015,center.z)
	if center.y - projected.y > 0.8:
		draw_dashed_line(_project(center), _project(projected), Color(0.88, 0.98, 0.91, 0.45), 1.0, 4.0)
		draw_circle(_project(projected), 3.0, Color(0.93, 1, 0.91, 0.7))
	if wind_input.dragging:
		var index := Vector2i(((Vector2(center.x, center.z) - Sim.ORIGIN) / Sim.CELL).floor())
		var i := clampi(index.y, 0, Sim.DEPTH - 1) * Sim.WIDTH + clampi(index.x, 0, Sim.WIDTH - 1)
		var direction: Vector2 = sim.wind[i]
		if direction.length() > 0.1:
			var a := _project(center)
			var b := _project(center + Vector3(direction.x, 0, direction.y) * 0.22)
			draw_line(a, b, INK, 2.0, true)
			draw_circle(b, 2.4, INK)

func _draw_wind_tools() -> void:
	strength_meter_rect = Rect2()
	var active := sim.outcome == "playing"
	brush_button.visible = active and wind_input.tool_available("brush")
	source_button.visible = active and wind_input.tool_available("source")
	vortex_button.visible = active and wind_input.tool_available("vortex")
	arrows_button.visible = active
	# Keep a live button visible across redraws; hiding cancels a held click.
	for index in source_remove.size(): source_remove[index].visible = active and index < sim.wind_sources.size()
	source_remove_ids.fill(-1)
	wind_toolbar_rect = Rect2()
	if not active: return
	if last_tool != wind_input.tool:
		last_tool = wind_input.tool
		tool_hint_until = view.elapsed + 4.0
	var rows := ceili(sim.wind_sources.size() / 2.0)
	var buttons: Array = [[brush_button,78.0],[source_button,105.0],[vortex_button,85.0],[arrows_button,130.0]]
	var width := 10.0
	for entry in buttons:
		if entry[0].visible: width += entry[1]+4.0
	if rows > 0: width = maxf(width,384.0)
	wind_toolbar_rect = Rect2(Vector2((size.x - width) * 0.5, size.y - 58 - rows * 27), Vector2(width, 42 + rows * 27))
	_rounded(wind_toolbar_rect, PANEL, 9)
	var at := wind_toolbar_rect.position
	var x := 7.0
	for entry in buttons:
		if not entry[0].visible: continue
		entry[0].position = at+Vector2(x,5)
		entry[0].size = Vector2(entry[1],30)
		x += entry[1]+4.0
	brush_button.set_pressed_no_signal(wind_input.tool == "brush")
	source_button.set_pressed_no_signal(wind_input.tool == "source")
	vortex_button.set_pressed_no_signal(wind_input.tool == "vortex")
	brush_button.disabled = paused
	source_button.disabled = paused
	vortex_button.disabled = paused
	arrows_button.text = "天气提示：" + ("开" if view.hints_enabled else "关")
	for index in sim.wind_sources.size():
		var source: Dictionary = sim.wind_sources[index]
		source_remove_ids[index] = source.id
		var p := at + Vector2(12 + (index % 2) * 190, 42 + floori(index / 2.0) * 27)
		var text := "风带 %d · %.1fs" % [source.id, source.remaining]
		if source.get("kind", "band") == "vortex": text = "漩涡 %d · %s · %.1fs" % [source.id, ["弱", "中", "强"][source.tier], source.remaining]
		_text(p + Vector2(0, 16), text, 12)
		var remove := source_remove[index]
		remove.disabled = paused
		remove.position = p + Vector2(146, 0)
		remove.size = Vector2(24, 22)
	var message_active: bool = Time.get_ticks_msec() < wind_input.message_until
	var introduction_active: bool = not tool_introduction.is_empty() and view.elapsed < tool_introduction_until
	if view.elapsed < tool_hint_until or message_active or introduction_active:
		var text := "拖出方向，停住按住续吹；再拖动可调整" if wind_input.tool == "brush" else "拖出风带 · 滚轮调力度 · 松手吹 %.0f 秒" % sim.settings.source_lifetime
		if wind_input.tool == "vortex": text = "拖出范围 · 左顺右逆 · 滚轮三档 · 松手聚集"
		if message_active: text = wind_input.message
		var hint := Rect2(Vector2((size.x-380)*0.5,at.y-61), Vector2(380, 54))
		_rounded(hint, PANEL, 7)
		if introduction_active and not message_active:
			_text(hint.position+Vector2(10,19),tool_introduction[0],12,GOLD)
			_text(hint.position+Vector2(10,42),tool_introduction[1],12)
		else:
			_text(hint.position + Vector2(10, 19), text, 12)
			var legend := ["湿空气", "冷空气", "云移动", "抬升"]
			var colors := [view.WET_ARROW, view.COLD_ARROW, view.CLOUD_ARROW, view.LIFT_ARROW]
			for index in 4:
				_text(hint.position + Vector2(10 + index * 94, 42), "➜ " + legend[index], 12, colors[index].lerp(INK, 0.42))
	for source in sim.wind_sources:
		var point: Vector2 = source.position
		if source.get("kind", "band") == "vortex":
			var hovered: bool = wind_input.hover_valid and Vector2(wind_input.brush_point.x, wind_input.brush_point.z).distance_to(point) <= source.radius
			_draw_vortex_marker(point, source.radius, source.spin, source.remaining / source.lifetime, minf(1.0, source.remaining / source.fade), false, hovered)
		else: _draw_source_marker(source.position, source.end, source.direction, minf(1.0, source.remaining / source.fade), source.remaining / source.lifetime, false)
		var label := _project(Vector3(point.x, sim.terrain.height(point) + 0.35, point.y))
		_text(label + Vector2(14, -9), ("漩涡 %d" if source.get("kind", "band") == "vortex" else "风带 %d") % source.id, 12, GOLD)
	if wind_input.tool == "source" and wind_input.dragging:
		var end := Vector2(wind_input.brush_point.x, wind_input.brush_point.z)
		_draw_source_marker(wind_input.gesture_start, end, (end - wind_input.gesture_start).normalized(), 0.8, 1.0, true)
		_draw_wind_meter(_project(wind_input.brush_point))
	if wind_input.tool == "vortex" and wind_input.dragging:
		var gesture: Dictionary = wind_input.vortex_preview()
		_draw_vortex_marker(gesture.center, gesture.radius, gesture.spin, 1.0, 0.8, true, true, gesture.ok)
		var tip := _project(wind_input.brush_point)
		_draw_wind_meter(tip, gesture.tier, "滚轮")
		var text: String = gesture.reason
		var label := strength_meter_rect.position + Vector2(-88, -13)
		label.x = clampf(label.x, 8, size.x - 150)
		label.y = maxf(17, label.y)
		if not gesture.ok:
			var hint_width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+16
			label.x = clampf(label.x,8,size.x-hint_width)
			_rounded(Rect2(label+Vector2(-7,-17),Vector2(hint_width,24)),PANEL,5)
		_text(label, text, 12, INK if gesture.ok else Visuals.DAMAGE)

func _draw_vortex_marker(point: Vector2, radius: float, spin: int, fraction: float, alpha: float, preview: bool, show_range: bool, valid := true) -> void:
	var h: float = wind_input.reference_height if preview else sim.terrain.height(point) + 0.35
	var center := _project(Vector3(point.x, h, point.y))
	var color := GOLD if valid else Visuals.DAMAGE
	color.a = alpha
	draw_circle(center, 3.0, color)
	draw_arc(center, 11.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 32, color, 1.5, true)
	if not valid:
		draw_line(center+Vector2(-4,-4),center+Vector2(4,4),color,2.0,true)
		draw_line(center+Vector2(-4,4),center+Vector2(4,-4),color,2.0,true)
	if radius < 0.25: return # Avoid degenerate antialiased polylines at initial press.
	var p := point + Vector2(radius * 0.2, 0)
	var direction := _project(Vector3(p.x, h, p.y + spin * radius * 0.12)) - _project(Vector3(p.x, h, p.y))
	var d := direction.normalized()
	var tip := center + d * 9
	draw_line(center, tip, color, 1.5, true)
	draw_polyline(PackedVector2Array([tip - d.rotated(0.6) * 4, tip, tip - d.rotated(-0.6) * 4]), color, 1.5, true)
	if not show_range: return
	var ring := PackedVector2Array()
	for n in 65:
		var angle := TAU * n / 64.0
		var q := point + Vector2(cos(angle), sin(angle)) * radius
		var height: float = h if preview else sim.terrain.height(q) + 0.15
		ring.append(_project(Vector3(q.x, height, q.y)))
	color.a *= 0.35 if valid else 0.95
	draw_polyline(ring, color, 1.2 if valid else 2.2, true)
	if preview and radius >= 0.25:
		# Preview intent; after release, white ribbons read actual simulated velocity.
		for segment in 3:
			var curve := PackedVector2Array()
			for n in 7:
				var angle: float = view.elapsed * spin + segment * TAU / 3.0 + n * 0.1 * spin
				var q := point + Vector2(cos(angle), sin(angle)) * radius * 0.72
				curve.append(_project(Vector3(q.x, h, q.y)))
			var white := Color(0.93, 1.0, 0.95, 0.65) if valid else Color(Visuals.DAMAGE,0.8)
			draw_polyline(curve, white, 1.6, true)
			var curve_direction := (curve[-1] - curve[-2]).normalized()
			draw_polyline(PackedVector2Array([curve[-1] - curve_direction.rotated(0.6) * 5, curve[-1], curve[-1] - curve_direction.rotated(-0.6) * 5]), white, 1.6, true)

func _draw_source_marker(point: Vector2, end: Vector2, direction: Vector2, alpha: float, fraction: float, preview: bool) -> void:
	var h: float = wind_input.reference_height if preview else sim.terrain.height(point) + 0.35
	var center := _project(Vector3(point.x, h, point.y))
	var target := end if point.distance_to(end) > 0.0001 else point + direction * sim.settings.brush_radius
	var tip_height: float = wind_input.reference_height if preview else sim.terrain.height(target) + 0.35
	var tip := _project(Vector3(target.x, tip_height, target.y))
	var color := GOLD
	color.a = alpha
	if preview: draw_dashed_line(center, tip, color, 2.0, 5.0)
	else: draw_line(center, tip, color, 2.0, true)
	var d := (tip - center).normalized()
	var side := Vector2(-d.y, d.x)
	draw_polyline(PackedVector2Array([tip - d * 9 + side * 5, tip, tip - d * 9 - side * 5]), color, 2.0, true)
	draw_arc(center, 12.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 32, color, 2.0, true)
	draw_circle(center, 3.0, color)
	var ring := PackedVector2Array()
	# Same capsule radius as the simulation's distance-to-segment soft kernel.
	for cap in 2:
		for i in 17:
			var angle := direction.angle() - PI * 0.5 + cap * PI + i * PI / 16.0
			var p: Vector2 = (end if cap == 0 else point) + Vector2(cos(angle), sin(angle)) * sim.settings.brush_radius
			ring.append(_project(Vector3(p.x, sim.terrain.height(p) + 0.15, p.y)))
	ring.append(ring[0])
	var edge := color
	edge.a *= 0.45 if preview else 0.20
	draw_polyline(ring, edge, 1.2, true)

func _draw_wind_meter(tip: Vector2, tier: int = -1, caption: String = "滚轮") -> void:
	var at := tip + Vector2(18, -45)
	if at.x + 55 > size.x - 8: at.x = tip.x - 73
	at.x = clampf(at.x, 8, maxf(8, size.x - 63))
	at.y = clampf(at.y, 8, maxf(8, size.y - 96))
	strength_meter_rect = Rect2(at, Vector2(55, 88))
	_rounded(strength_meter_rect, PANEL, 7)
	var colors := [Color("d58178"), Color("80ab83"), Color("7dabc6")]
	var labels := ["强", "中", "弱"]
	for row in 3:
		var selected: bool = (wind_input.source_tier if tier < 0 else tier) == 2 - row
		var segment := Rect2(at + Vector2(8, 7 + row * 24), Vector2(14, 20))
		_rounded(segment, colors[row] if selected else colors[row].lerp(PANEL, 0.72), 3)
		for tick in 3 - row:
			draw_line(segment.position+Vector2(3,5+tick*4),segment.position+Vector2(11,5+tick*4), INK if selected else MUTED, 1.0, true)
		if selected: draw_rect(segment.grow(1), INK, false, 1.0)
		_text(at + Vector2(29, 23 + row * 24), labels[row], 12, INK if selected else MUTED)
	_text(at + Vector2(8, 82), caption, 9, MUTED)

func _ground_region(target: int, padding: float = 0.0) -> PackedVector2Array:
	# Land and target geometry are immutable for one simulation. Retain exact
	# projected contours; only values/colors change each frame. A new map, view,
	# window aspect or camera pose must invalidate these screen-space points.
	var transform: Transform3D = view.camera.global_transform
	var projection: Projection = view.camera.get_camera_projection()
	if ground_model != sim or ground_view_id != view.get_instance_id() or ground_size != size or ground_transform != transform or ground_projection != projection:
		ground_outlines.clear()
		visuals.clear_cache()
		ground_model = sim
		ground_view_id = view.get_instance_id()
		ground_size = size
		ground_transform = transform
		ground_projection = projection
	var key := Vector2(target, padding)
	if ground_outlines.has(key): return ground_outlines[key]
	var result := PackedVector2Array()
	for offset in sim.plot_regions[target].outline(sim.plot_half, padding):
		var p: Vector2 = sim.plot_centers[target] + offset
		var height: float = view.plot_display_height(target)+0.006 if is_zero_approx(padding) else sim.terrain.height(p)+0.06
		result.append(_project(Vector3(p.x,height,p.y)))
	ground_outlines[key] = result
	return result

func _draw() -> void:
	if sim == null:
		return
	var draw_start := Time.get_ticks_usec()
	if feedback_model != sim: reset_feedback()
	var w := size.x
	var h := size.y
	if compact_model != sim:
		compact_model = sim
		last_tool = ""
		last_status = ""
		tool_introduction.clear()
		tool_introduction_until = 0.0
		if campaign_play and play_mode == "free" and not sim.sandbox:
			var available: int = sim.layout.get("available_wind_tools",7)
			var fresh := available & ~introduced_wind_tools
			introduced_wind_tools |= available
			if (fresh & 6) == 6:
				tool_introduction = PackedStringArray(["新工具 · 风带与漩涡","风带留风输送；漩涡收拢水汽，撤源后再运送"])
			elif (fresh & 2) != 0:
				tool_introduction = PackedStringArray(["新工具 · 风带","拖出风带，滚轮调力度；松手后持续吹 %.0f 秒" % sim.settings.source_lifetime])
			elif (fresh & 4) != 0:
				tool_introduction = PackedStringArray(["新工具 · 漩涡","拖出半径，左顺右逆；聚集后撤源，再输送"])
			if not tool_introduction.is_empty(): tool_introduction_until = view.elapsed+8.0
	result_rect = Rect2()
	result_home.visible = false
	plot_label_rects.clear()
	var menu_base := 147 if development else 112
	menu_rect = Rect2(Vector2(w - 190, 56), Vector2(170, menu_base+105 if use_front_menu else menu_base+173))
	menu_button.position = Vector2(w - 82, 18)
	menu_button.size = Vector2(62, 30)
	menu_button.text = "继续" if menu_open else "菜单"
	if menu_open: _rounded(menu_rect, PANEL, 9)
	for index in front_buttons.size():
		front_buttons[index].visible = menu_open
		front_buttons[index].position = menu_rect.position+Vector2(8,menu_base+(0 if use_front_menu else 68)+index*33)
		front_buttons[index].size = Vector2(154,30)
	audio_button.visible = menu_open and not use_front_menu
	audio_button.text = "音效：开" if audio_enabled else "音效：关"
	audio_button.position = menu_rect.position+Vector2(8,menu_base)
	audio_button.size = Vector2(154,28)
	audio_volume.visible = menu_open and not use_front_menu
	audio_volume.position = menu_rect.position+Vector2(48,menu_base+36)
	audio_volume.size = Vector2(114,22)
	audio_label.visible = menu_open and not use_front_menu
	audio_label.text = "音量"
	audio_label.position = menu_rect.position+Vector2(10,menu_base+36)
	retry.visible = menu_open
	retry.position = menu_rect.position + Vector2(8, 7)
	retry.size = Vector2(154, 30)
	retry.text = "重试当前局面  R"
	lesson_button.visible = menu_open and play_mode != "lesson"
	lesson_button.position = menu_rect.position + Vector2(8, 42)
	lesson_button.size = Vector2(154, 30)
	var result_select := sim.star_level and not sim.sandbox and sim.outcome != "playing" and (sim.outcome != "success" or (campaign_play and campaign != null and not campaign.next_id(sim.layout_id).is_empty()))
	levels_button.visible = (menu_open and play_mode != "lesson") or result_select
	levels_button.position = menu_rect.position + Vector2(8, 77)
	levels_button.size = Vector2(154, 30)
	development_button.visible = menu_open and development
	development_button.position = menu_rect.position + Vector2(8,112)
	development_button.size = Vector2(154,30)
	free_button.visible = play_mode == "lesson" and (menu_open or sim.outcome == "success")
	free_button.text = ("返回当前关卡" if return_to_game else "开始挑战") if sim.outcome == "success" else ("返回当前关卡" if return_to_game else "跳过入门")
	free_button.position = menu_rect.position + Vector2(8, 42)
	free_button.size = Vector2(154, 30)
	if play_mode == "lesson" and sim.outcome == "success":
		free_button.position = Vector2(w * 0.5 - 90, h * 0.5 + 27)
		free_button.size = Vector2(180, 32)
	layout_selector.visible = play_mode == "free"
	layout_selector.position = Vector2(105, 17)
	layout_selector.size = Vector2(minf(245,w*0.21), 30)
	layout_selector.tooltip_text = sim.layout.title + (" · 最佳%d枚风纹" % int(best_stars.get(sim.layout_id,0)) if sim.star_level else "")
	if layout_selector.visible: layout_selector.select(layout_ids.find(sim.layout_id))
	timer_rect = Rect2()
	timer_label.visible = sim.timer_active()
	if timer_label.visible:
		var seconds := ceili(sim.time_remaining())
		timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
		timer_label.tooltip_text = "剩余关卡时间"
		timer_rect = Rect2(Vector2(layout_selector.position.x+layout_selector.size.x+12, 18), Vector2(76, 28))
		timer_label.position = timer_rect.position
		timer_label.size = timer_rect.size
		timer_label.add_theme_font_size_override("font_size", 14)
		timer_label.add_theme_color_override("font_color", GOLD if seconds <= 30 else INK)
	_draw_reserve()
	finish_button.visible = sim.star_level and not sim.sandbox and sim.outcome == "playing" and (sim.can_finish() or sim.can_end_shortage())
	finish_button.disabled = not sim.can_finish() and not sim.can_end_shortage()
	finish_button.text = "结束 · 当前 %d 枚风纹" % sim.earned_stars() if sim.can_end_shortage() else "收尾 · %d / 3 风纹" % sim.earned_stars()
	finish_button.tooltip_text = "只计当前已适量且安全的地块。" if sim.can_end_shortage() else "未损坏地块附近安全后可结算。"
	if sim.plot_needs.any(func(needs): return needs != null and needs.goal_kind == "reservoir"):
		finish_button.tooltip_text = "蓄水区蓄满即完成；农田仍须适量且持续安全。"
	if sim.three_star_remaining() >= 0.0:
		finish_button.text = "满风纹 · %d 秒后自动结算" % ceili(sim.three_star_remaining())
	finish_button.position = Vector2(w - 216, h - 52)
	finish_button.size = Vector2(196, 32)
	next_button.visible = sim.star_level and not sim.sandbox and sim.outcome == "success"
	if result_select:
		var result_width := minf(500,w-40)
		var result_height := 283.0+sim.plot_centers.size()*64.0
		levels_button.position = Vector2(w*0.5-40 if sim.outcome == "success" else (w+result_width)*0.5-192,(h+result_height)*0.5-83)
		levels_button.size = Vector2(80 if sim.outcome == "success" else 170,32)
	result_retry.visible = sim.star_level and not sim.sandbox and sim.outcome != "playing"
	sandbox_button.visible = debug_visible
	cold_button.visible = debug_visible
	sandbox_button.position = Vector2(w - 176, 223)
	sandbox_button.size = Vector2(148, 30)
	cold_button.position = Vector2(w - 176, 258)
	cold_button.size = Vector2(148, 30)
	_draw_wind_tools()
	_draw_world_feedback()
	if sim.tropical != null:
		var marker := _project(Vector3(sim.tropical.center.x, 0.12, sim.tropical.center.y))
		draw_circle(marker, 4.0, INK, false, 1.2, true)
		_text(marker + Vector2(10, -8), sim.tropical.stage, 12, INK)
	_draw_guide()
	_draw_rating()
	_text(Vector2(22, 38), "风织雨", 20)
	var status := "把湿空气推向山坡，再把厚云送到地块上方"
	if play_mode == "free":
		status = sim.layout.hint
	if sim.peak_density >= sim.settings.cloud_threshold and sim.total_rain_rate < 0.01:
		status = "厚云正在维持 · 轻拨修正，避免散开"
	elif sim.total_rain_rate > 0.01:
		status = "冷风正在形成 · 把湿空气迎向它的前沿" if sim.relay_mode else "已经开始下雨 · 留意落点与地块水量"
		for target in sim.plot_centers.size():
			if sim.water_for(target) > sim.required_water(target) * 0.7 and sim.water_for(target) < sim.required_water(target):
				status = ("%s 快蓄满了 · 满后仍可继续承雨" if sim.is_reservoir(target) else "%s 快够水了 · 提前移云，储水还会继续落下") % String.chr(65 + target)
	if sim.plot_centers.size() > 1 and sim.plot_water >= sim.required_water(0) and sim.second_water < sim.required_water(1):
		status = "A 水量已够 · 提早移云，借残留冷风照顾 B"
	elif sim.plot_centers.size() > 1 and sim.second_water >= sim.required_water(1) and sim.plot_water < sim.required_water(0):
		status = "B 水量已够 · 提早移云，借残留冷风照顾 A"
	elif sim.plot_water >= sim.required_water(0):
		status = "蓄水已满 · 可继续承雨" if sim.is_reservoir(0) else "水量已够 · 移开危险雨云，或切断补给后等储水耗尽"
	if play_mode == "lesson" and sim.is_reservoir(0):
		status = "把水汽送向山坡，让云雨填满水库" if sim.total_rain_rate <= 0.01 else "已经开始下雨 · 让雨线覆盖水库，观察水位"
	if sim.sandbox:
		status = "交互小样 · 试拨云边或迎向冷风前沿；R 回正式开局"
	elif sim.star_level:
		if sim.plot_destroyed.any(func(value): return value): status = "有地块已损坏 · 仍可挽救其他目标"
		if sim.earned_stars() > 0:
			status = "当前 %d 枚风纹 · 可以继续争取更多，也可安全收尾后结算" % sim.earned_stars()
			if sim.threat: status = "已有达标地块 · 清除未损坏土地附近的危险天气，才能结算"
		if sim.can_end_shortage(): status = "剩余水分不足 · 可继续整理天气，也可按当前风纹结束"
		if sim.three_star_remaining() >= 0.0: status = "已获满风纹 · 即将自动结算，失去安全会取消倒数"
	if paused and not transitioning:
		status = "正在选关 · 天气已暂停" if selection_panel.visible else ("已暂停 · 选择继续或按 Esc 返回" if menu_open else "已暂停 · 空格继续")
	if sim.star_level and sim.outcome != "playing":
		status = "本局已结算 · 可重试或选关" if sim.result_stars > 0 else "本局已结算 · 查看原因后重试或选关"
	if not tuning_message.is_empty(): status = tuning_message.left(48) + ("…" if tuning_message.length() > 48 else "")
	if status != last_status:
		last_status = status
		status_until = view.elapsed + 2.5
	status_rect = Rect2()
	var urgent := paused or sim.can_end_shortage() or sim.three_star_remaining() >= 0.0 or not tuning_message.is_empty()
	if (view.elapsed < status_until or urgent) and sim.outcome == "playing":
		var status_width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var status_y := maxf(54, guide_rect.end.y+7) if guide_rect.has_area() else 54.0
		if rating_rect.has_point(_pointer()): status_y = maxf(status_y,78)
		status_rect = Rect2(Vector2((w - status_width) * 0.5 - 10, status_y), Vector2(status_width + 20, 27))
		_rounded(status_rect, PANEL, 7)
		_text(status_rect.position + Vector2(10, 19), status, 13)
	_draw_plot_labels()
	if sim.outcome != "playing":
		if sim.star_level:
			_draw_star_result(w, h)
		else:
			_draw_legacy_result(w, h)
	if debug_visible:
		_rounded(Rect2(28, 140, 310, 166), PANEL)
		_text(Vector2(42, 164), "调试 · 测试参数，不代表最终平衡", 14)
		_text(Vector2(42, 190), "帧 %.1f ms · 模拟 %.1f ms" % [frame_ms, simulation_ms], 14)
		_text(Vector2(42, 214), "水分误差 %.5f · 最高厚度 %.2f" % [sim.water_error(), sim.peak_density], 14)
		_text(Vector2(42, 238), "成雨 %.2fs · 安全 %.2f / %.2fs" % [sim.settings.hold_seconds, sim.safe_time, sim.settings.safe_seconds], 14)
		_text(Vector2(42, 262), "冷风抬升 %.1f · 风线 %d" % [sim.total_cold_lift, view.visible_wind_lines], 14)
		_text(Vector2(42, 288), "F2 云 / F4 冷风小样，不计通关", 13, MUTED)
	draw_ms = (Time.get_ticks_usec()-draw_start)/1000.0

func _draw_reserve() -> void:
	reserve_rect = Rect2()
	reserve_message = ""
	if not sim.timer_active(): return
	reserve_rect = Rect2(Vector2(20, 54), Vector2(230, 23))
	_rounded(reserve_rect, PANEL, 6)
	var at := reserve_rect.position
	var baseline: float = maxf(sim.initial_water, 0.000001)
	var wet_fraction: float = clampf(sim.remaining_humidity / baseline, 0.0, 1.0)
	var cloud_fraction: float = clampf(sim.remaining_cloud / baseline, 0.0, 1.0 - wet_fraction)
	var percent: String = "<1%" if wet_fraction + cloud_fraction > 0.0 and wet_fraction + cloud_fraction < 0.01 else "%d%%" % floori((wet_fraction + cloud_fraction) * 100.0)
	_text(at + Vector2(9, 15), "储备 " + percent, 12)
	var bar := Rect2(at + Vector2(83, 9), Vector2(137, 5))
	_rounded(bar, Color("254f52"), 4)
	if wet_fraction > 0.0: draw_rect(Rect2(bar.position, Vector2(bar.size.x * wet_fraction, 5)), VAPOR_COLOR)
	if cloud_fraction > 0.0: draw_rect(Rect2(bar.position + Vector2(bar.size.x * wet_fraction, 0), Vector2(bar.size.x * cloud_fraction, 5)), CLOUD_WATER_COLOR)
	if sim.tropical != null and sim.tropical.has_supply(sim.settings):
		reserve_message = "暖海域仍在补给 · 当前储备不含未来蒸发"
	elif not is_finite(sim.minimum_water_needed()) and not sim.plot_destroyed.all(func(value): return value):
		reserve_message = "剩余地块水量已够，仍需安全收尾"
	elif sim.water_insufficient():
		reserve_message = "剩余水分不足以浇够新地块"
	elif sim.remaining_humidity <= baseline * 0.1 and sim.remaining_cloud > baseline * 0.01:
		reserve_message = "水汽所剩不多，云中仍有储水"
	else:
		reserve_message = "水汽成云后，储备仍可用于降雨"
	if reserve_rect.has_point(_pointer()):
		var detail := Rect2(reserve_rect.position + Vector2(0, 38), Vector2(282, 48))
		_rounded(detail, PANEL, 7)
		_text(detail.position + Vector2(9, 17), "浅青：水汽 · 灰蓝：云中储水", 12)
		_text(detail.position + Vector2(9, 37), reserve_message, 12)

func _draw_legacy_result(w: float, h: float) -> void:
	var result := "这场雨，刚刚好。" if sim.outcome == "success" else "雨水过量了。"
	var detail := "目标已得到适量雨水，危险天气已经解除。" if sim.outcome == "success" else "储水仍会继续落下；下次提早移云，或切断补给。"
	if play_mode == "lesson" and sim.outcome == "success" and sim.is_reservoir(0):
		result = "水库蓄满了。"
		detail = "你已经学会借山造雨；水库可以继续承雨，不怕溢出。"
	_rounded(Rect2(w * 0.5 - 265, h * 0.5 - 65, 530, 130), PANEL)
	_text(Vector2(w * 0.5 - 230, h * 0.5 - 20), result, 26)
	_text(Vector2(w * 0.5 - 230, h * 0.5 + 14), detail, 16)
	if play_mode != "lesson" or sim.outcome != "success":
		_text(Vector2(w * 0.5 - 230, h * 0.5 + 43), "按 R 重新开始同一个局面", 14, MUTED)

func _draw_star_result(w: float, h: float) -> void:
	var width := minf(500.0, w - 40)
	var height := 283.0 + sim.plot_centers.size() * 64.0
	result_rect = Rect2(Vector2((w-width)*0.5, (h-height)*0.5), Vector2(width, height))
	_rounded(result_rect, Color(0.96,0.96,0.90,0.97), 13)
	draw_rect(result_rect.grow(-1), Color(INK,0.35), false, 1.2)
	var at := result_rect.position
	if result_since < 0.0: result_since = ui_time
	var headline := "本局完成" if sim.result_stars > 0 else "本局结束"
	if sim.result_stars > 0 and campaign_play and campaign != null and campaign.ids().has(sim.layout_id) and campaign.next_id(sim.layout_id).is_empty(): headline = "本轮挑战完成"
	if sim.timed_out: headline = "时间到"
	_text(at+Vector2((width-font.get_string_size(headline,HORIZONTAL_ALIGNMENT_LEFT,-1,23).x)*0.5,35), headline, 23)
	for index in 3:
		var age := clampf((ui_time-result_since-index*0.12)/0.2,0,1)
		visuals.medal(self, at+Vector2(width*0.5+(index-1)*68,80), 24, index<sim.result_stars, age)
	_text(at+Vector2(width*0.5-64,125), "风纹评价 %d/3" % sim.result_stars, 15, GOLD)
	result_details.clear()
	result_row_rects.clear()
	for target in sim.plot_centers.size():
		var row := Rect2(at+Vector2(20,143+target*64),Vector2(width-40,64))
		result_row_rects.append(row)
		draw_line(row.position,Vector2(row.end.x,row.position.y),Color(INK,0.13),1.0)
		_text(row.position+Vector2(2,25),String.chr(65+target),15)
		_draw_water_row(target,row.position+Vector2(26,8),true)
		var name: String = sim.plot_name(target) if not sim.plot_name(target).is_empty() else "农田"
		var amount := "%s  %s/%s" % [name.left(8),_quantity(sim.water_for(target)),_quantity(sim.required_water(target)).trim_suffix(".0")]
		_text(row.position+Vector2(202,24),amount,14)
		var reason := status_text(target,true)
		_text(row.position+Vector2(2,52),reason,15,Visuals.DAMAGE if sim.plot_destroyed[target] else MUTED)
		result_details.append("%s %s %s/%s · %s" % [String.chr(65+target),name,_quantity(sim.water_for(target)),_quantity(sim.required_water(target)).trim_suffix(".0"),reason])
	result_home.visible = true
	result_home.position = at+Vector2(width*0.5-65,height-39)
	result_home.size = Vector2(130,27)
	var summary := "完成 %d/%d 个目标 · 最佳 %d 枚风纹" % [sim.result_saved_count,sim.plot_centers.size(),int(best_stars.get(sim.layout_id,0))]
	_text(at+Vector2(22,height-101),summary,14,MUTED)
	result_retry.position = at+Vector2(22,height-83)
	result_retry.size = Vector2(150,32)
	next_button.text = "下一关" if campaign_play and campaign != null and not campaign.next_id(sim.layout_id).is_empty() else "返回选关"
	next_button.position = at+Vector2(width-192,height-83)
	next_button.size = Vector2(170,32)

func _group_label(units: float) -> String:
	return "×%d" % int(units) if units < 10000 else "×"+String.num_scientific(units)

func _quantity(value: float, decimals := 1) -> String:
	if absf(value)>=1e6 or (value!=0 and absf(value)<0.1): return String.num_scientific(value)
	return String.num(value,decimals).pad_decimals(decimals)

func _water_width(target: int) -> float:
	if sim.is_reservoir(target): return 36.0
	var slots := Visuals.water_slots(sim.required_water(target),0)
	var width := slots.size()*16.0-4.0
	if slots[-1].units > 1:
		width += 4+font.get_string_size(_group_label(slots[-1].units),HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
	return width

func _draw_water_row(target: int, at: Vector2, exact := false) -> void:
	var water: float = sim.water_for(target) if exact else shown_water[target]
	if sim.is_reservoir(target):
		visuals.water_glyph(self,Rect2(at,Vector2(36,18)),clampf(water/sim.required_water(target),0,1),Visuals.WATER,true)
	else:
		var slots := Visuals.water_slots(sim.required_water(target),water)
		for index in slots.size():
			visuals.water_glyph(self,Rect2(at+Vector2(index*16,0),Vector2(12,18)),slots[index].fill,water_color(target))
			if slots[index].units > 1:
				_text(at+Vector2(index*16+16,15),_group_label(slots[index].units),10,MUTED)
	var progress := clampf(sim.plot_safe_times[target]/sim.settings.safe_seconds,0,1)
	visuals.state_glyph(self,at+Vector2(_water_width(target)+15,9),sim.plot_status(target),progress)

func _target_short(target: int) -> String:
	if sim.is_reservoir(target): return "已蓄满" if sim.target_complete(target) else "蓄水中"
	match sim.plot_status(target):
		"dry": return "还差"+_quantity(maxf(0,sim.required_water(target)-sim.water_for(target))).trim_suffix(".0")
		"danger": return "移云"
		"confirming": return "确认安全"
		"safe": return "已保住"
		_: return "过量损坏"

func _floating_rect(anchor: Rect2, width: float, height: float) -> Rect2:
	var candidates := [Vector2(anchor.position.x,anchor.position.y-height-7),
		Vector2(anchor.position.x,anchor.end.y+7),
		Vector2(anchor.position.x-width-7,anchor.position.y),
		Vector2(anchor.end.x+7,anchor.position.y)]
	var result := Rect2()
	for point in candidates:
		result = Rect2(Vector2(clampf(point.x,8,size.x-width-8),clampf(point.y,108,size.y-height-90)),Vector2(width,height))
		var clear := not result.intersects(wind_toolbar_rect) and not (menu_open and result.intersects(menu_rect))
		for other in plot_label_rects: clear = clear and not result.intersects(other.grow(3))
		if clear: return result
	return result

func _draw_plot_labels() -> void:
	plot_tooltip_rect = Rect2()
	plot_tooltip_text = ""
	plot_glyph_slots.clear()
	var mouse := _pointer()
	var hovered := -1
	var event_target := -1
	for target in sim.plot_centers.size():
		var outline := _ground_region(target)
		var bottom := -INF
		var center := Vector2.ZERO
		for p in outline:
			bottom = maxf(bottom,p.y)
			center += p
		center /= outline.size()
		var width := 20+_water_width(target)+31
		var rect := Rect2(Vector2(clampf(center.x-width*0.5,12,size.x-width-12),clampf(bottom+7,108,size.y-108)),Vector2(width,30))
		for attempt in 12:
			var overlap := rect.intersects(wind_toolbar_rect) or (menu_open and rect.intersects(menu_rect))
			for placed in plot_label_rects: overlap = overlap or rect.intersects(placed.grow(5))
			if not overlap: break
			rect.position.y = maxf(108,rect.position.y-36)
		plot_label_rects.append(rect)
		plot_glyph_slots.append([] if sim.is_reservoir(target) else Visuals.water_slots(sim.required_water(target),shown_water[target]))
		_rounded(rect,PANEL,7)
		_text(rect.position+Vector2(7,20),String.chr(65+target),13)
		_draw_water_row(target,rect.position+Vector2(23,6))
		if not blocks_wind(mouse) and (rect.has_point(mouse) or Geometry2D.is_point_in_polygon(mouse,outline)): hovered = target
		if feedback_left[target] > 0 and (event_target < 0 or sim.plot_destroyed[target]): event_target = target
	if sim.outcome != "playing": return
	var target := hovered if hovered >= 0 else event_target
	if target < 0: return
	var anchor := plot_label_rects[target]
	if hovered >= 0:
		var name: String = sim.plot_name(target) if not sim.plot_name(target).is_empty() else "农田"
		var first := "%s %s · %s/%s" % [String.chr(65+target),name.left(12),_quantity(sim.water_for(target)),_quantity(sim.required_water(target)).trim_suffix(".0")]
		var second := status_text(target,true)
		var third := "满后可继续承雨" if sim.is_reservoir(target) else "适量 %s–%s · 每滴%.0f" % [_quantity(sim.required_water(target)).trim_suffix(".0"),_quantity(sim.flood_limit(target)).trim_suffix(".0"),Visuals.DROP_WATER]
		if not sim.is_reservoir(target):
			var slots := Visuals.water_slots(sim.required_water(target),0)
			var tail: float = fmod(sim.required_water(target),Visuals.DROP_WATER)
			if slots[-1].units > 1: third += " · 叠滴"+_quantity(slots[-1].capacity).trim_suffix(".0")
			elif tail > 0: third += " · 末滴"+_quantity(tail).trim_suffix(".0")
		var width := maxf(235,maxf(font.get_string_size(first,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x,maxf(font.get_string_size(second,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x,font.get_string_size(third,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x))+18)
		plot_tooltip_rect = _floating_rect(anchor,width,68)
		plot_tooltip_text = first+"\n"+second+"\n"+third
		_rounded(plot_tooltip_rect,PANEL,7)
		_text(plot_tooltip_rect.position+Vector2(9,18),first,12)
		_text(plot_tooltip_rect.position+Vector2(9,39),second,12,MUTED)
		_text(plot_tooltip_rect.position+Vector2(9,59),third,11,MUTED)
	else:
		var text := _target_short(target)
		plot_tooltip_rect = _floating_rect(anchor,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+18,26)
		plot_tooltip_text = text
		_rounded(plot_tooltip_rect,PANEL,6)
		_text(plot_tooltip_rect.position+Vector2(9,18),text,12,Visuals.DAMAGE if sim.plot_destroyed[target] else INK)

func _draw_rating() -> void:
	rating_rect = Rect2()
	if not sim.star_level or sim.sandbox or sim.outcome != "playing": return
	var rating := sim.earned_stars()
	if rating_seen != rating:
		rating_seen = rating
		rating_since = ui_time
	rating_rect = Rect2(Vector2(size.x*0.5-56,15),Vector2(112,30))
	for index in 3:
		visuals.medal(self,rating_rect.position+Vector2(16+index*40,15),12,index<rating,clampf((ui_time-rating_since-index*0.12)/0.2,0,1))
	if rating_rect.has_point(_pointer()):
		var text := "当前 %d/3 · 最佳 %d 枚风纹" % [rating,int(best_stars.get(sim.layout_id,0))]
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+18
		var rect := Rect2(Vector2(size.x*0.5-width*0.5,46),Vector2(width,25))
		_rounded(rect,PANEL,6)
		_text(rect.position+Vector2(9,17),text,12)

func refresh_layouts() -> void:
	layout_ids = campaign.ids() if campaign_play and campaign != null else Layouts.get_ids()
	layout_selector.clear()
	layout_selector.clip_text = true
	for id in layout_ids:
		var definition := campaign.find_map(id) if campaign_play and campaign != null else Layouts.get_definition(id)
		var prefix := "%02d · " % (layout_selector.item_count+1) if campaign_play else "开发 · "
		layout_selector.add_item(prefix+definition.title+(" · 最佳%d风纹" % int(best_stars.get(id,0)) if definition.star_level else ""))
	if sim != null and not sim.layout_id in layout_ids:
		layout_ids.append(sim.layout_id)
		layout_selector.add_item(sim.layout.title)

func _create_level_selection() -> void:
	var shield := ColorRect.new()
	shield.color = Color(0.13,0.28,0.29,0.16)
	shield.z_index = 9
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.hide()
	add_child(shield)
	selection_panel = Panel.new()
	selection_panel.z_index = 10
	selection_panel.hide()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL,1.0)
	style.set_corner_radius_all(12)
	style.set_border_width_all(1)
	style.border_color = Color(INK,0.3)
	selection_panel.add_theme_stylebox_override("panel",style)
	add_child(selection_panel)
	selection_panel.visibility_changed.connect(func(): shield.visible = selection_panel.visible)
	selection_title = Label.new()
	selection_title.add_theme_font_size_override("font_size",20)
	selection_title.add_theme_color_override("font_color",INK)
	selection_panel.add_child(selection_title)
	selection_list = ItemList.new()
	selection_list.add_theme_color_override("font_color",INK)
	selection_list.add_theme_color_override("font_selected_color",INK)
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.89,0.93,0.87,0.7)
	list_style.set_corner_radius_all(6)
	selection_list.add_theme_stylebox_override("panel",list_style)
	selection_list.add_theme_constant_override("v_separation",14)
	selection_panel.add_child(selection_list)
	selection_list.item_selected.connect(func(_index): selection_start.disabled = false)
	selection_start = Button.new()
	selection_start.text = "开始本关"
	selection_start.pressed.connect(func():
		var selected := selection_list.get_selected_items()
		if selected.is_empty(): return
		layout_requested.emit(selection_ids[selected[0]]))
	selection_panel.add_child(selection_start)
	selection_back = Button.new()
	selection_back.text = "返回"
	selection_back.pressed.connect(func(): selection_closed.emit())
	selection_panel.add_child(selection_back)
	resized.connect(_layout_level_selection)
	_layout_level_selection()

func _layout_level_selection() -> void:
	var width := minf(460,size.x-40)
	var height := minf(360,size.y-100)
	selection_panel.size = Vector2(width,height)
	selection_panel.position = (size-selection_panel.size)*0.5
	selection_title.position = Vector2(22,15)
	selection_list.position = Vector2(22,57)
	selection_list.size = Vector2(width-44,height-123)
	selection_back.position = Vector2(22,height-49)
	selection_back.size = Vector2(100,32)
	selection_start.position = Vector2(width-152,height-49)
	selection_start.size = Vector2(130,32)

func show_level_selection(_developer_maps: bool) -> void:
	menu_open = false
	selection_development = true
	selection_title.text = "开发地图 · 独立试玩"
	selection_ids.assign(Layouts.get_ids())
	selection_list.clear()
	for index in selection_ids.size():
		var id := selection_ids[index]
		var definition := Layouts.get_definition(id)
		selection_list.add_item(definition.title+"   最佳%d风纹" % int(best_stars.get(id,0)))
	selection_start.disabled = selection_ids.is_empty()
	if not selection_ids.is_empty(): selection_list.select(maxi(selection_ids.find(sim.layout_id),0))
	selection_panel.show()
	selection_panel.move_to_front()
	_layout_level_selection()
	queue_redraw()
