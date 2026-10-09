extends Control
signal restart_requested
signal sandbox_requested
signal cold_lab_requested
signal free_play_requested
signal lesson_requested
const Sim = preload("res://scripts/weather_simulation.gd")
var sim: RefCounted
var view: Node3D
var wind_input: Node
var paused := false
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
const INK := Color("f0f6e9")
const MUTED := Color("d5e9db")
const PANEL := Color(0.12, 0.31, 0.34, 0.86)
const GOLD := Color("f1d39b")

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
	theme.default_font_size = 16
	self.theme = theme
	retry = Button.new()
	retry.text = "重新开始  R"
	retry.pressed.connect(func(): restart_requested.emit())
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
	free_button.pressed.connect(func(): free_play_requested.emit())
	add_child(free_button)
	lesson_button = Button.new()
	lesson_button.text = "重看入门"
	lesson_button.pressed.connect(func(): lesson_requested.emit())
	add_child(lesson_button)
	dismiss_hint = Button.new()
	dismiss_hint.text = "知道了"
	dismiss_hint.pressed.connect(func(): guide.cold_hint_left = 0.0)
	add_child(dismiss_hint)
	for button in [retry, sandbox_button, cold_button, free_button, lesson_button, dismiss_hint]:
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
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_color_override("font_color", INK)
		button.focus_mode = Control.FOCUS_NONE

func _text(at: Vector2, text: String, font_size: int = 16, color := INK) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _rounded(rect: Rect2, color: Color, radius: int = 12) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	draw_style_box(style, rect)

func _project(point: Vector3) -> Vector2:
	return view.camera.unproject_position(point)

func blocks_wind(point: Vector2) -> bool:
	if status_rect.has_point(point) or guide_rect.has_point(point):
		return true
	for button in [retry, sandbox_button, cold_button, free_button, lesson_button, dismiss_hint]:
		if button.visible and button.get_global_rect().has_point(point):
			return true
	for target in sim.plot_centers.size():
		var at := Vector2(28, size.y - 28 - (sim.plot_centers.size() - target) * 120)
		if Rect2(at, Vector2(340, 112)).has_point(point):
			return true
	return debug_visible and Rect2(28, 140, 310, 166).has_point(point)

func _guide_marker(p: Vector2, label: String, cloud_height: bool = false) -> void:
	var height := Sim.CLOUD_TOP + 0.1 if cloud_height else Sim.terrain_height(p) + 0.35
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
	dismiss_hint.visible = false
	if guide == null or sim.sandbox:
		return
	if guide.lesson:
		guide_rect = Rect2(Vector2((size.x - 640) * 0.5, 88), Vector2(640, 104))
		_rounded(guide_rect, PANEL)
		var at := guide_rect.position + Vector2(20, 25)
		_text(at, guide.title(sim), 16, GOLD)
		_text(at + Vector2(0, 30), guide.instruction(sim), 17)
		_text(at + Vector2(0, 56), guide.detail(sim), 14, MUTED)
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
					var slope_point: Vector2 = Sim.MOUNTAIN + (p - Sim.MOUNTAIN).normalized() * 1.8
					_guide_marker(slope_point, "送向这侧山坡")
		elif guide.phase == 2:
			_guide_marker(Sim.PLOT, "雨线落进 A 才加水")
		elif guide.phase == 3:
			var square := _ground_square(Sim.SAFE_HALF)
			for i in 4:
				draw_dashed_line(square[i], square[(i + 1) % 4], GOLD, 2.5, 9.0)
	elif guide.cold_hint_left > 0.0 and sim.outcome == "playing":
		guide_rect = Rect2(Vector2((size.x - 640) * 0.5, 88), Vector2(640, 104))
		_rounded(guide_rect, PANEL)
		var at := guide_rect.position + Vector2(20, 25)
		_text(at, "可选技巧 · 借冷风接力", 16, GOLD)
		_text(at + Vector2(0, 30), "灰蓝色薄层是雨产生的冷空气，可以拨动。", 17)
		_text(at + Vector2(0, 56), "把湿空气迎向它的前沿可造云；也可以继续借山坡。", 14, MUTED)
		dismiss_hint.visible = true
		dismiss_hint.position = guide_rect.position + Vector2(536, 10)
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
		result.append(_project(Vector3(p.x, Sim.terrain_height(p) + 0.06, p.y)))
	return result

func _draw_world_feedback() -> void:
	for target in sim.plot_centers.size():
		var center: Vector2 = sim.plot_centers[target]
		var safety := _ground_square(Sim.SAFE_HALF, center)
		var safe_color := Color(0.98, 0.83, 0.57, 0.65) if sim.plot_threats[target] else Color(0.88, 0.97, 0.86, 0.46)
		for i in 4:
			draw_dashed_line(safety[i], safety[(i + 1) % 4], safe_color, 1.5, 7.0)
		var plot := _ground_square(Sim.PLOT_HALF, center)
		for i in 4:
			draw_line(plot[i], plot[(i + 1) % 4], Color(0.96, 0.89, 0.72, 0.85), 2.0, true)
		var label := _project(Vector3(center.x, 0.35, center.y))
		_text(label + Vector2(-8, 5), "A" if target == 0 else "B", 18, INK)
	if not wind_input.hover_valid:
		return
	var center: Vector3 = wind_input.brush_point
	var ring := PackedVector2Array()
	for i in 65:
		var angle := float(i) / 64.0 * TAU
		var p: Vector3 = center + Vector3(cos(angle), 0, sin(angle)) * sim.settings.brush_radius
		ring.append(_project(p))
	draw_polyline(ring, Color(0.95, 1, 0.91, 0.65 if wind_input.dragging else 0.35), 1.7, true)
	var projected := Vector3(center.x, Sim.terrain_height(Vector2(center.x, center.z)) + 0.05, center.z)
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

func _draw() -> void:
	if sim == null:
		return
	var w := size.x
	var h := size.y
	retry.position = Vector2(w - 192, 28)
	retry.size = Vector2(164, 36)
	retry.text = "重试入门  R" if play_mode == "lesson" else "重试当前局面  R"
	free_button.visible = play_mode == "lesson"
	free_button.text = "进入双目标自由局" if sim.outcome == "success" else "跳过入门 · 自由局"
	free_button.position = Vector2(w - 192, 72)
	free_button.size = Vector2(164, 36)
	if play_mode == "lesson" and sim.outcome == "success":
		free_button.position = Vector2(w * 0.5 - 90, h * 0.5 + 27)
		free_button.size = Vector2(180, 32)
	lesson_button.visible = play_mode != "lesson"
	lesson_button.position = Vector2(w - 192, 72)
	lesson_button.size = Vector2(164, 36)
	sandbox_button.visible = debug_visible
	cold_button.visible = debug_visible
	sandbox_button.position = Vector2(w - 176, 116)
	sandbox_button.size = Vector2(148, 36)
	cold_button.position = Vector2(w - 176, 160)
	cold_button.size = Vector2(148, 36)
	_draw_world_feedback()
	_draw_guide()
	_text(Vector2(32, 61), "风织雨", 34)
	_text(Vector2(34, 86), "W E A V I N G   R A I N", 12, MUTED)
	_text(Vector2(34, 112), "单目标入门" if play_mode == "lesson" else "双目标自由局" if sim.relay_mode else "单目标开发基线", 14, MUTED)
	var status := "把湿空气推向山坡，再把厚云送到地块上方"
	if sim.peak_density >= sim.settings.cloud_threshold and sim.total_rain_rate < 0.01:
		status = "厚云正在维持 · 轻拨修正，避免散开"
	elif sim.total_rain_rate > 0.01:
		status = "冷风正在形成 · 把湿空气迎向它的前沿" if sim.relay_mode else "已经开始下雨 · 留意落点与地块水量"
		if sim.plot_water > 70.0 and sim.plot_water < sim.settings.target_water:
			status = "A 快够水了 · 提前移云，储水还会继续落下"
	if sim.plot_water >= sim.settings.target_water and sim.relay_mode and sim.second_water < sim.settings.target_water:
		status = "A 水量已够 · 提早移云，借残留冷风照顾 B"
	elif sim.plot_water >= sim.settings.target_water:
		status = "水量已够 · 移开危险雨云，或切断补给后等储水耗尽"
	if sim.sandbox:
		status = "交互小样 · 试拨云边或迎向冷风前沿；R 回正式开局"
	if paused:
		status = "已暂停 · 空格继续"
	var status_width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	status_rect = Rect2(Vector2((w - status_width) * 0.5 - 18, 30), Vector2(status_width + 36, 40))
	_rounded(status_rect, PANEL)
	_text(Vector2((w - status_width) * 0.5, 56), status, 16)
	for target in sim.plot_centers.size():
		_draw_plot_card(target, Vector2(28, h - 28 - (sim.plot_centers.size() - target) * 120))
	_text(Vector2(w - 348, h - 94), "按住左键拖动拨风 · 快划更猛，慢划更柔", 15)
	_text(Vector2(w - 348, h - 68), "松手后风会衰减，云与水汽仍继续移动", 14, MUTED)
	_text(Vector2(w - 348, h - 40), "空格 暂停     F3 调试信息", 12, MUTED)
	if sim.peak_density > 0.15:
		var p := Vector2.ZERO
		var peak := 0.0
		for i in Sim.COUNT:
			if sim.display_cloud[i] > peak:
				peak = sim.display_cloud[i]
				p = sim.positions[i]
		var point := _project(Vector3(p.x, Sim.CLOUD_TOP + 0.15, p.y))
		var weather_text := "薄云 · 收拢可变厚"
		var local_rain: float = sim.sample(sim.display_rain, p)
		var local_progress: float = sim.sample(sim.display_charge, p) / maxf(peak * sim.settings.hold_seconds, 0.001)
		if local_rain > 0.015:
			weather_text = "降雨中 · 储水正在释放"
		elif local_progress > 0.01:
			weather_text = "成雨维持 %d%%" % roundi(local_progress * 100)
		var label_width := font.get_string_size(weather_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_rounded(Rect2(point + Vector2(-label_width * 0.5 - 10, -33), Vector2(label_width + 20, 29)), PANEL, 7)
		_text(point + Vector2(-label_width * 0.5, -13), weather_text, 14)
	if sim.outcome != "playing":
		var result := "这场雨，刚刚好。" if sim.outcome == "success" else "雨水过量了。"
		var detail := "目标已得到适量雨水，危险天气已经解除。" if sim.outcome == "success" else "储水仍会继续落下；下次提早移云，或切断补给。"
		_rounded(Rect2(w * 0.5 - 265, h * 0.5 - 65, 530, 130), PANEL)
		_text(Vector2(w * 0.5 - 230, h * 0.5 - 20), result, 26)
		_text(Vector2(w * 0.5 - 230, h * 0.5 + 14), detail, 16)
		if play_mode != "lesson" or sim.outcome != "success":
			_text(Vector2(w * 0.5 - 230, h * 0.5 + 43), "按 R 重新开始同一个局面", 14, MUTED)
	if debug_visible:
		_rounded(Rect2(28, 140, 310, 166), PANEL)
		_text(Vector2(42, 164), "调试 · 测试参数，不代表最终平衡", 14)
		_text(Vector2(42, 190), "帧 %.1f ms · 模拟 %.1f ms" % [frame_ms, simulation_ms], 14)
		_text(Vector2(42, 214), "水分误差 %.5f · 最高厚度 %.2f" % [sim.water_total() - sim.initial_water, sim.peak_density], 14)
		_text(Vector2(42, 238), "成雨 %.2fs · 安全 %.2f / %.2fs" % [sim.settings.hold_seconds, sim.safe_time, sim.settings.safe_seconds], 14)
		_text(Vector2(42, 262), "冷风抬升 %.1f · 风线 %d" % [sim.total_cold_lift, view.visible_wind_lines], 14)
		_text(Vector2(42, 288), "F2 云 / F4 冷风小样，不计通关", 13, MUTED)

func _draw_plot_card(target: int, at: Vector2) -> void:
	var amount: float = sim.water_for(target)
	var phase := "缺水"
	var accent := Color("b7f0dc")
	if amount >= sim.settings.target_water:
		phase = "适量 · 待安全收尾"
		accent = GOLD
	if amount > sim.settings.flood_water:
		phase = "过量 · 本次需重试"
		accent = Color("f1b5a0")
	elif sim.plot_safe_times[target] >= sim.settings.safe_seconds:
		phase = "适量 · 当前安全"
	_rounded(Rect2(at, Vector2(340, 112)), PANEL)
	_text(at + Vector2(16, 25), "地块 A" if target == 0 else "地块 B", 17)
	_text(at + Vector2(100, 25), phase, 14, accent)
	var bar := Rect2(at + Vector2(16, 40), Vector2(308, 12))
	_rounded(bar, Color(0.03, 0.20, 0.24, 0.6), 5)
	var target_x: float = bar.size.x * sim.settings.target_water / sim.settings.flood_water
	_rounded(Rect2(bar.position + Vector2(target_x, 0), Vector2(bar.size.x - target_x, 12)), Color(0.77, 0.86, 0.52, 0.36), 4)
	var fill: float = bar.size.x * clampf(amount / sim.settings.flood_water, 0.0, 1.0)
	if fill > 0:
		_rounded(Rect2(bar.position, Vector2(fill, 12)), accent, 4)
	draw_line(bar.position + Vector2(target_x, -2), bar.position + Vector2(target_x, 14), INK, 1.0)
	_text(at + Vector2(16, 76), "%.1f   ·   适量 %.0f–%.0f" % [amount, sim.settings.target_water, sim.settings.flood_water], 14)
	var safety_text := "危险天气仍在附近" if sim.plot_threats[target] else "缓冲区暂无危险天气"
	if amount >= sim.settings.target_water and amount <= sim.settings.flood_water and not sim.plot_threats[target]:
		safety_text = "缓冲区安全 %.1f / %.1f 秒" % [minf(sim.plot_safe_times[target], sim.settings.safe_seconds), sim.settings.safe_seconds]
	_text(at + Vector2(16, 99), safety_text, 13, MUTED)
