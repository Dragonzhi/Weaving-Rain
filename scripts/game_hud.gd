extends Control
signal restart_requested
signal sandbox_requested
signal cold_lab_requested
signal free_play_requested
signal lesson_requested
signal layout_requested(id: String)
signal finish_requested
signal next_requested
signal levels_requested
const Sim = preload("res://scripts/weather_simulation.gd")
const Layouts = preload("res://scripts/weather_layouts.gd")
var sim: Sim
var view: Node3D
var wind_input: Node
var paused := false
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
var plot_label_rects: Array[Rect2] = []
var compact_model: RefCounted
var tool_hint_until := 4.0
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
const GOLD := Color("997940")

func reset_feedback() -> void:
	menu_open = false
	source_pressed_ids.fill(-1)
	feedback_model = sim
	result_details.clear()
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
		return "已蓄满 · 溢流不损坏" if sim.target_complete(target) else "蓄水中 · 还差 %.1f" % (sim.required_water(target) - sim.water_for(target))
	match sim.plot_status(target):
		"destroyed": return "过量损坏 · 不计星" if final else "损坏 · 仍可照顾其他地块"
		"dry": return "缺水 · 还差 %.1f" % (sim.required_water(target) - sim.water_for(target)) if final else "缺水"
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
		wind_input.cancel()
		queue_redraw())
	add_child(menu_button)
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
	refresh_layouts()
	layout_selector.item_selected.connect(func(index): layout_requested.emit(layout_ids[index]))
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
	levels_button.text = "星级测试"
	levels_button.pressed.connect(func(): menu_open = false; levels_requested.emit())
	add_child(levels_button)
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
	arrows_button.text = "流向提示：开"
	arrows_button.pressed.connect(func(): view.arrows_enabled = not view.arrows_enabled)
	add_child(arrows_button)
	for index in 4:
		var remove := Button.new()
		remove.text = "×"
		remove.button_down.connect(func(): source_pressed_ids[index] = source_remove_ids[index])
		remove.pressed.connect(func():
			if source_pressed_ids[index] >= 0 and not paused and sim.outcome == "playing": sim.remove_wind_source(source_pressed_ids[index]))
		source_remove.append(remove)
		add_child(remove)
	for button in buttons():
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = Color("e2e9de")
		var pressed := style.duplicate()
		pressed.bg_color = Color("d8dfcd")
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
		button.add_theme_color_override("font_disabled_color", Color("82918b"))
		button.add_theme_color_override("font_color", INK)
		button.focus_mode = Control.FOCUS_NONE

func buttons() -> Array:
	return [menu_button, retry, sandbox_button, cold_button, free_button, lesson_button, dismiss_hint, layout_selector,
		finish_button, next_button, result_retry, levels_button, brush_button, source_button, vortex_button, arrows_button] + source_remove

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
	if wind_toolbar_rect.has_point(point) or (menu_open and menu_rect.has_point(point)) or result_rect.has_point(point): return true
	# Drawn labels, water bars, timer, reserve and teaching text are information.
	# Only real controls and the open menu/result consume weather gestures.
	for button in buttons():
		if button.visible and button.get_global_rect().has_point(point): return true
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
			_guide_marker(Sim.PLOT, "雨线落进 A 才加水")
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
		var star := " ✓" if sim.star_level and sim.target_complete(target) else ""
		_text(label + Vector2(-8, 5), String.chr(65 + target) + star, 18, INK)
		if flash > 0.0:
			var text: String = feedback_texts[target]
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var at := label + Vector2(-width * 0.5, -30)
			_rounded(Rect2(at + Vector2(-8, -20), Vector2(width + 16, 28)), PANEL, 6)
			_text(at, text, 14, outline_color)
	if not wind_input.hover_valid:
		return
	if wind_input.tool == "source" and wind_input.dragging: return
	var center: Vector3 = wind_input.brush_point
	var ring := PackedVector2Array()
	for i in 65:
		var angle := float(i) / 64.0 * TAU
		var p: Vector3 = center + Vector3(cos(angle), 0, sin(angle)) * sim.settings.brush_radius
		ring.append(_project(p))
	draw_polyline(ring, Color(0.95, 1, 0.91, 0.65 if wind_input.dragging else 0.35), 1.7, true)
	var projected := Vector3(center.x, sim.terrain.height(Vector2(center.x, center.z)) + 0.05, center.z)
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
	brush_button.visible = active
	source_button.visible = active
	vortex_button.visible = active
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
	var width := 390.0
	wind_toolbar_rect = Rect2(Vector2((size.x - width) * 0.5, size.y - 58 - rows * 27), Vector2(width, 42 + rows * 27))
	_rounded(wind_toolbar_rect, PANEL, 9)
	var at := wind_toolbar_rect.position
	brush_button.position = at + Vector2(7, 5)
	brush_button.size = Vector2(70, 30)
	source_button.position = at + Vector2(81, 5)
	source_button.size = Vector2(90, 30)
	vortex_button.position = at + Vector2(175, 5)
	vortex_button.size = Vector2(80, 30)
	arrows_button.position = at + Vector2(259, 5)
	arrows_button.size = Vector2(124, 30)
	brush_button.set_pressed_no_signal(wind_input.tool == "brush")
	source_button.set_pressed_no_signal(wind_input.tool == "source")
	vortex_button.set_pressed_no_signal(wind_input.tool == "vortex")
	brush_button.disabled = paused
	source_button.disabled = paused
	vortex_button.disabled = paused
	arrows_button.text = "流向：" + ("开" if view.arrows_enabled else "关")
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
	if view.elapsed < tool_hint_until or message_active:
		var text := "拖出方向，停住按住续吹；再拖动可调整" if wind_input.tool == "brush" else "拖出风带 · 滚轮调力度 · 松手吹 %.0f 秒" % sim.settings.source_lifetime
		if wind_input.tool == "vortex": text = "拖出范围 · 左顺右逆 · 滚轮三档 · 松手聚集"
		if message_active: text = wind_input.message
		var hint := Rect2(at + Vector2(-15, -61), Vector2(380, 54))
		_rounded(hint, PANEL, 7)
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
		_draw_vortex_marker(gesture.center, gesture.radius, gesture.spin, 1.0, 0.8, true, true)
		var tip := _project(wind_input.brush_point)
		_draw_wind_meter(tip, gesture.tier, "滚轮")
		var text: String = gesture.reason
		var label := strength_meter_rect.position + Vector2(-88, -13)
		label.x = clampf(label.x, 8, size.x - 150)
		label.y = maxf(17, label.y)
		_text(label, text, 12, INK)

func _draw_vortex_marker(point: Vector2, radius: float, spin: int, fraction: float, alpha: float, preview: bool, show_range: bool) -> void:
	var h: float = wind_input.reference_height if preview else sim.terrain.height(point) + 0.35
	var center := _project(Vector3(point.x, h, point.y))
	var color := GOLD
	color.a = alpha
	draw_circle(center, 3.0, color)
	draw_arc(center, 11.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 32, color, 1.5, true)
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
	color.a *= 0.35
	draw_polyline(ring, color, 1.2, true)
	if preview and radius >= 0.25:
		# Preview intent; after release, white ribbons read actual simulated velocity.
		for segment in 3:
			var curve := PackedVector2Array()
			for n in 7:
				var angle: float = view.elapsed * spin + segment * TAU / 3.0 + n * 0.1 * spin
				var q := point + Vector2(cos(angle), sin(angle)) * radius * 0.72
				curve.append(_project(Vector3(q.x, h, q.y)))
			var white := Color(0.93, 1.0, 0.95, 0.65)
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
		result.append(_project(Vector3(p.x, sim.terrain.height(p) + 0.06, p.y)))
	ground_outlines[key] = result
	return result

func _draw() -> void:
	if sim == null:
		return
	var w := size.x
	var h := size.y
	if compact_model != sim:
		compact_model = sim
		last_tool = ""
		last_status = ""
	result_rect = Rect2()
	plot_label_rects.clear()
	menu_rect = Rect2(Vector2(w - 190, 56), Vector2(170, 112 if play_mode == "free" and not sim.star_level else 77))
	menu_button.position = Vector2(w - 82, 18)
	menu_button.size = Vector2(62, 30)
	menu_button.text = "收起" if menu_open else "菜单"
	if menu_open: _rounded(menu_rect, PANEL, 9)
	retry.visible = menu_open
	retry.position = menu_rect.position + Vector2(8, 7)
	retry.size = Vector2(154, 30)
	retry.text = "重试当前局面  R"
	lesson_button.visible = menu_open and play_mode != "lesson"
	lesson_button.position = menu_rect.position + Vector2(8, 42)
	lesson_button.size = Vector2(154, 30)
	levels_button.visible = menu_open and play_mode == "free" and not sim.star_level
	levels_button.position = menu_rect.position + Vector2(8, 77)
	levels_button.size = Vector2(154, 30)
	free_button.visible = play_mode == "lesson" and (menu_open or sim.outcome == "success")
	free_button.text = "进入自由局" if sim.outcome == "success" else "跳过入门"
	free_button.position = menu_rect.position + Vector2(8, 42)
	free_button.size = Vector2(154, 30)
	if play_mode == "lesson" and sim.outcome == "success":
		free_button.position = Vector2(w * 0.5 - 90, h * 0.5 + 27)
		free_button.size = Vector2(180, 32)
	layout_selector.visible = play_mode == "free"
	layout_selector.position = Vector2(20, 48)
	layout_selector.size = Vector2(220, 30)
	if layout_selector.visible: layout_selector.select(layout_ids.find(sim.layout_id))
	timer_rect = Rect2()
	timer_label.visible = sim.timer_active()
	if timer_label.visible:
		var seconds := ceili(sim.time_remaining())
		timer_label.text = "剩余 %02d:%02d" % [seconds / 60, seconds % 60]
		timer_rect = Rect2(Vector2(249, 48), Vector2(126, 30))
		timer_label.position = timer_rect.position
		timer_label.size = timer_rect.size
		timer_label.add_theme_font_size_override("font_size", 16)
		timer_label.add_theme_color_override("font_color", GOLD if seconds <= 30 else INK)
	_draw_reserve()
	finish_button.visible = sim.star_level and not sim.sandbox and sim.outcome == "playing" and (sim.can_finish() or sim.can_end_shortage())
	finish_button.disabled = not sim.can_finish() and not sim.can_end_shortage()
	finish_button.text = "结束 · 当前 %d 星" % sim.earned_stars() if sim.can_end_shortage() else "收尾 · %d / 3 星" % sim.earned_stars()
	finish_button.tooltip_text = "只计当前已适量且安全的地块。" if sim.can_end_shortage() else "未损坏地块附近安全后可结算。"
	if sim.plot_needs.any(func(needs): return needs != null and needs.goal_kind == "reservoir"):
		finish_button.tooltip_text = "蓄水区蓄满即完成；农田仍须适量且持续安全。"
	if sim.three_star_remaining() >= 0.0:
		finish_button.text = "三星 · %d 秒后自动结算" % ceili(sim.three_star_remaining())
	finish_button.position = Vector2(w - 216, h - 52)
	finish_button.size = Vector2(196, 32)
	next_button.visible = sim.star_level and not sim.sandbox and sim.outcome == "success"
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
	_text(Vector2(22, 36), "风织雨", 22)
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
	if sim.sandbox:
		status = "交互小样 · 试拨云边或迎向冷风前沿；R 回正式开局"
	elif sim.star_level:
		if sim.plot_destroyed.any(func(value): return value): status = "有地块已损坏 · 仍可挽救其他土地，争取剩余星星"
		if sim.earned_stars() > 0:
			status = "已有 %d 颗星 · 可以继续争取更多，也可安全收尾后结算" % sim.earned_stars()
			if sim.threat: status = "已有达标地块 · 清除未损坏土地附近的危险天气，才能结算"
		if sim.can_end_shortage(): status = "剩余水分不足 · 可继续整理天气争星，也可按当前星数结束"
		if sim.three_star_remaining() >= 0.0: status = "三星达成 · 即将自动结算，失星会取消倒数"
	if paused:
		status = "已暂停 · 空格继续"
	if sim.star_level and sim.outcome != "playing":
		status = "本局已结算 · 可重试或进入下一测试局" if sim.result_stars > 0 else "本局已结算 · 查看原因后重试"
	if not tuning_message.is_empty(): status = tuning_message.left(48) + ("…" if tuning_message.length() > 48 else "")
	if status != last_status:
		last_status = status
		status_until = view.elapsed + 2.5
	status_rect = Rect2()
	var urgent := paused or sim.can_end_shortage() or sim.three_star_remaining() >= 0.0 or not tuning_message.is_empty()
	if (view.elapsed < status_until or urgent) and sim.outcome == "playing":
		var status_width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		status_rect = Rect2(Vector2((w - status_width) * 0.5 - 10, 17), Vector2(status_width + 20, 27))
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

func _draw_reserve() -> void:
	reserve_rect = Rect2()
	reserve_message = ""
	if not sim.timer_active(): return
	reserve_rect = Rect2(Vector2(20, 86), Vector2(220, 32))
	_rounded(reserve_rect, PANEL, 8)
	var at := reserve_rect.position
	var baseline: float = maxf(sim.initial_water, 0.000001)
	var wet_fraction: float = clampf(sim.remaining_humidity / baseline, 0.0, 1.0)
	var cloud_fraction: float = clampf(sim.remaining_cloud / baseline, 0.0, 1.0 - wet_fraction)
	var percent: String = "<1%" if wet_fraction + cloud_fraction > 0.0 and wet_fraction + cloud_fraction < 0.01 else "%d%%" % floori((wet_fraction + cloud_fraction) * 100.0)
	_text(at + Vector2(9, 15), "储备 " + percent, 12)
	var bar := Rect2(at + Vector2(9, 21), Vector2(202, 5))
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
	if reserve_rect.has_point(get_local_mouse_position()):
		var detail := Rect2(reserve_rect.position + Vector2(0, 38), Vector2(282, 48))
		_rounded(detail, PANEL, 7)
		_text(detail.position + Vector2(9, 17), "浅青：水汽 · 灰蓝：云中储水", 12)
		_text(detail.position + Vector2(9, 37), reserve_message, 12)

func _draw_legacy_result(w: float, h: float) -> void:
	var result := "这场雨，刚刚好。" if sim.outcome == "success" else "雨水过量了。"
	var detail := "目标已得到适量雨水，危险天气已经解除。" if sim.outcome == "success" else "储水仍会继续落下；下次提早移云，或切断补给。"
	_rounded(Rect2(w * 0.5 - 265, h * 0.5 - 65, 530, 130), PANEL)
	_text(Vector2(w * 0.5 - 230, h * 0.5 - 20), result, 26)
	_text(Vector2(w * 0.5 - 230, h * 0.5 + 14), detail, 16)
	if play_mode != "lesson" or sim.outcome != "success":
		_text(Vector2(w * 0.5 - 230, h * 0.5 + 43), "按 R 重新开始同一个局面", 14, MUTED)

func _draw_star_result(w: float, h: float) -> void:
	var height := 224.0 + sim.plot_centers.size() * 30.0
	result_rect = Rect2(w * 0.5 - 320, h * 0.5 - height * 0.5, 640, height)
	_rounded(result_rect, PANEL)
	var left := result_rect.position + Vector2(24, 34)
	var headline := "这场雨，保住了 %d/%d 块土地。" % [sim.result_saved_count, sim.plot_centers.size()] if sim.outcome == "success" else "土地都被浇坏了，再试一次。"
	if sim.timed_out:
		headline = "时间到 · 保住了 %d/%d 块土地。" % [sim.result_saved_count, sim.plot_centers.size()] if sim.result_stars > 0 else "时间到 · 本次未获得星星。"
	elif sim.ended_for_shortage:
		headline = "本局结束 · 保住了 %d/%d 块土地。" % [sim.result_saved_count, sim.plot_centers.size()] if sim.result_stars > 0 else "本局结束 · 本次未获得星星。"
	if sim.plot_needs.any(func(needs): return needs != null and needs.goal_kind == "reservoir"):
		headline = ("时间到 · " if sim.timed_out else "本局结束 · ") + "完成 %d/%d 个目标。" % [sim.result_saved_count, sim.plot_centers.size()]
	_text(left, headline, 23)
	_text(left + Vector2(0, 44), "★".repeat(sim.result_stars) + "☆".repeat(3 - sim.result_stars), 30, GOLD)
	result_details.clear()
	for target in sim.plot_centers.size():
		var text := "%s  %.1f  ·  %s" % [String.chr(65 + target), sim.water_for(target), status_text(target, true)]
		if not sim.plot_name(target).is_empty():
			text = "%s %s  %.1f/%.0f  ·  %s" % [String.chr(65 + target), sim.plot_name(target).left(4), sim.water_for(target), sim.required_water(target), status_text(target, true)]
		result_details.append(text)
		_text(left + Vector2(0, 80 + target * 30), text, 16)
	_text(left + Vector2(0, 92 + sim.plot_centers.size() * 30), "本局 %d 星 · 最佳 %d 星 · 重试不会降低纪录" % [sim.result_stars, int(best_stars.get(sim.layout_id, 0))], 14, MUTED)
	result_retry.position = result_rect.position + Vector2(24, height - 56)
	result_retry.size = Vector2(160, 36)
	var index := Layouts.LEVELS.find(sim.layout_id)
	next_button.text = "下一测试局" if index >= 0 and index + 1 < Layouts.LEVELS.size() else "返回三处田园"
	next_button.position = result_rect.position + Vector2(406, height - 56)
	next_button.size = Vector2(210, 36)

func _draw_plot_labels() -> void:
	var hovered := -1
	for target in sim.plot_centers.size():
		var outline := _ground_region(target)
		var bottom := -INF
		var center := Vector2.ZERO
		for p in outline:
			bottom = maxf(bottom, p.y)
			center += p
		center /= outline.size()
		var at := Vector2(clampf(center.x - 78, 12, size.x - 168), clampf(bottom + 7, 122, size.y - 108))
		var rect := Rect2(at, Vector2(156, 42))
		for attempt in 6:
			var overlap := rect.intersects(wind_toolbar_rect) or (menu_open and rect.intersects(menu_rect))
			for placed in plot_label_rects: overlap = overlap or rect.intersects(placed.grow(4))
			if not overlap: break
			rect.position.y = maxf(122, rect.position.y - 48)
		plot_label_rects.append(rect)
		_rounded(rect, PANEL, 7)
		var state := sim.plot_status(target)
		var short := {"dry": "缺水", "danger": "留意移云", "confirming": "确认安全", "safe": "已保住", "destroyed": "损坏"}
		if sim.is_reservoir(target): short = {"dry": "蓄水中", "safe": "已蓄满 · 可继续承雨"}
		var amount: float = sim.water_for(target)
		var accent := water_color(target)
		var typed: bool = not sim.plot_name(target).is_empty()
		if typed:
			_text(rect.position + Vector2(8, 14), "%s %s · %.1f/%.0f" % [String.chr(65 + target), sim.plot_name(target).left(4), amount, sim.required_water(target)], 11)
			_text(rect.position + Vector2(8, 38), short.get(state, ""), 10, Color("c76e60") if state == "destroyed" else MUTED)
		else:
			_text(rect.position + Vector2(8, 16), String.chr(65 + target), 13)
			_text(rect.position + Vector2(27, 16), short.get(state, ""), 12, accent)
		var bar := Rect2(rect.position + Vector2(8, 21 if typed else 25), Vector2(140, 6 if typed else 7))
		_rounded(bar, Color("cdd8d3"), 3)
		var fill: float = sim.plot_progress(target)
		if fill > 0: draw_rect(Rect2(bar.position, Vector2(140 * fill, bar.size.y)), accent)
		draw_line(bar.position + Vector2(140, -2), bar.position + Vector2(140, bar.size.y + 2), INK, 1)
		if rect.has_point(get_local_mouse_position()): hovered = target
	if hovered >= 0:
		var rect := plot_label_rects[hovered]
		var at := Vector2(clampf(rect.position.x - 42, 12, size.x - 288), rect.position.y - 62)
		_rounded(Rect2(at, Vector2(276, 56)), PANEL, 7)
		var detail := "%s %.1f · 适量 %.0f–%.0f" % [sim.plot_name(hovered), sim.water_for(hovered), sim.required_water(hovered), sim.flood_limit(hovered)]
		if sim.is_reservoir(hovered): detail = "蓄水 %.1f / %.0f · 满后溢流不损坏" % [sim.water_for(hovered), sim.required_water(hovered)]
		_text(at + Vector2(9, 19), detail, 12)
		_text(at + Vector2(9, 42), status_text(hovered, true), 12)

func refresh_layouts() -> void:
	layout_ids = Layouts.get_ids()
	layout_selector.clear()
	for id in layout_ids:
		var definition := Layouts.get_definition(id)
		layout_selector.add_item(definition.title + (" · %d星" % int(best_stars.get(id, 0)) if definition.star_level else ""))
	if sim != null and not sim.layout_id in layout_ids:
		layout_ids.append(sim.layout_id)
		layout_selector.add_item(sim.layout.title)
