extends Control
signal restart_requested
signal sandbox_requested
const Sim = preload("res://scripts/weather_simulation.gd")
var sim: RefCounted
var view: Node3D
var wind_input: Node
var paused := false
var debug_visible := false
var font := SystemFont.new()
var retry: Button
var sandbox_button: Button
var frame_ms := 0.0
var simulation_ms := 0.0
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
	for button in [retry, sandbox_button]:
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

func _ground_square(half: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var p: Vector2 = Sim.PLOT + offset
		result.append(_project(Vector3(p.x, Sim.terrain_height(p) + 0.06, p.y)))
	return result

func _draw_world_feedback() -> void:
	var safety := _ground_square(Sim.SAFE_HALF)
	var safe_color := Color(0.98, 0.83, 0.57, 0.65) if sim.threat else Color(0.88, 0.97, 0.86, 0.46)
	for i in 4:
		draw_dashed_line(safety[i], safety[(i + 1) % 4], safe_color, 1.5, 7.0)
	var plot := _ground_square(Sim.PLOT_HALF)
	for i in 4:
		draw_line(plot[i], plot[(i + 1) % 4], Color(0.96, 0.89, 0.72, 0.85), 2.0, true)
	var label := _project(Vector3(Sim.PLOT.x, 0.32, Sim.PLOT.y + Sim.SAFE_HALF + 0.2))
	_text(label + Vector2(-35, 18), "安全缓冲区", 13, MUTED)
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
	retry.position = Vector2(w - 176, 28)
	retry.size = Vector2(148, 36)
	sandbox_button.position = Vector2(w - 176, 72)
	sandbox_button.size = Vector2(148, 36)
	_draw_world_feedback()
	_text(Vector2(32, 61), "风织雨", 34)
	_text(Vector2(34, 86), "W E A V I N G   R A I N", 12, MUTED)
	_text(Vector2(34, 112), "拨风 · 借山成云 · 适量落雨", 14, MUTED)
	var status := "把湿空气推向山坡，再把厚云送到地块上方"
	if sim.peak_density >= sim.settings.cloud_threshold and sim.total_rain_rate < 0.01:
		status = "厚云正在维持 · 轻拨修正，避免散开"
	elif sim.total_rain_rate > 0.01:
		status = "已经开始下雨 · 留意落点与地块水量"
	if sim.plot_water >= sim.settings.target_water:
		status = "水量已够 · 移开危险雨云，或切断补给后等储水耗尽"
	if sim.sandbox:
		status = "云交互小样 · 试着轻拨云边、收拢或拉散；R 回到正式开局"
	if paused:
		status = "已暂停 · 空格继续"
	var status_width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_rounded(Rect2(Vector2((w - status_width) * 0.5 - 18, 30), Vector2(status_width + 36, 40)), PANEL)
	_text(Vector2((w - status_width) * 0.5, 56), status, 16)
	var box := Rect2(28, h - 155, 360, 127)
	_rounded(box, PANEL)
	var phase := "缺水"
	var accent := Color("b7f0dc")
	if sim.plot_water >= sim.settings.target_water:
		phase = "适量 · 待安全收尾"
		accent = GOLD
	if sim.outcome == "flood":
		phase = "过量 · 本次需重试"
		accent = Color("f1b5a0")
	if sim.outcome == "success":
		phase = "适量 · 安全完成"
	_text(box.position + Vector2(18, 28), "地块水量", 18)
	_text(box.position + Vector2(122, 28), phase, 15, accent)
	var bar := Rect2(box.position + Vector2(18, 45), Vector2(324, 14))
	_rounded(bar, Color(0.03, 0.20, 0.24, 0.6), 6)
	var target_x: float = bar.size.x * sim.settings.target_water / sim.settings.flood_water
	_rounded(Rect2(bar.position + Vector2(target_x, 0), Vector2(bar.size.x - target_x, 14)), Color(0.77, 0.86, 0.52, 0.36), 5)
	var fill: float = bar.size.x * clampf(sim.plot_water / sim.settings.flood_water, 0.0, 1.0)
	if fill > 0:
		_rounded(Rect2(bar.position, Vector2(fill, 14)), accent, 5)
	draw_line(bar.position + Vector2(target_x, -3), bar.position + Vector2(target_x, 17), INK, 1.2)
	_text(box.position + Vector2(18, 86), "%.1f / %.0f   ·   适量 %.0f–%.0f" % [sim.plot_water, sim.settings.target_water, sim.settings.target_water, sim.settings.flood_water], 15)
	_text(box.position + Vector2(18, 110), "危险天气仍在附近" if sim.threat else "缓冲区暂无危险天气", 13, MUTED)
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
		if sim.total_rain_rate > 0.01:
			weather_text = "降雨中 · 储水正在释放"
		elif sim.max_progress > 0.01:
			weather_text = "成雨维持 %d%%" % roundi(sim.max_progress * 100)
		var label_width := font.get_string_size(weather_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_rounded(Rect2(point + Vector2(-label_width * 0.5 - 10, -33), Vector2(label_width + 20, 29)), PANEL, 7)
		_text(point + Vector2(-label_width * 0.5, -13), weather_text, 14)
	if sim.outcome != "playing":
		var result := "这场雨，刚刚好。" if sim.outcome == "success" else "雨水过量了。"
		var detail := "地块已得到适量雨水，危险天气已经解除。" if sim.outcome == "success" else "储水仍会继续落下；下次提早移云，或切断补给。"
		_rounded(Rect2(w * 0.5 - 265, h * 0.5 - 65, 530, 130), PANEL)
		_text(Vector2(w * 0.5 - 230, h * 0.5 - 20), result, 26)
		_text(Vector2(w * 0.5 - 230, h * 0.5 + 14), detail, 16)
		_text(Vector2(w * 0.5 - 230, h * 0.5 + 43), "按 R 重新开始同一个局面", 14, MUTED)
	if debug_visible:
		_rounded(Rect2(28, 140, 310, 140), PANEL)
		_text(Vector2(42, 164), "调试 · 测试参数，不代表最终平衡", 14)
		_text(Vector2(42, 190), "帧 %.1f ms · 模拟 %.1f ms" % [frame_ms, simulation_ms], 14)
		_text(Vector2(42, 214), "水分误差 %.5f · 最高厚度 %.2f" % [sim.water_total() - sim.initial_water, sim.peak_density], 14)
		_text(Vector2(42, 238), "成雨 %.2fs · 安全 %.2f / %.2fs" % [sim.settings.hold_seconds, sim.safe_time, sim.settings.safe_seconds], 14)
		_text(Vector2(42, 262), "F2 仅为云形态测试，不计通关", 13, MUTED)
