extends RefCounted
## Reads actual weather results. It never applies wind or modifies weather.
var settings := WROnboardingSettings.new()
var idle_seconds := 0.0
var wet_stroke := false
var cloud_stroke := false
var held_seen := false
var lesson := true
var phase := 0
var saw_rain := false
var cold_hint_seen := false
var cold_hint_left := 0.0

func reset(is_lesson: bool) -> void:
	idle_seconds = 0.0
	wet_stroke = false
	cloud_stroke = false
	held_seen = false
	lesson = is_lesson
	phase = 0
	saw_rain = false
	cold_hint_seen = false
	cold_hint_left = 0.0

func note_stroke(sim: RefCounted, a: Vector2, b: Vector2, hit_cloud: bool) -> void:
	if not lesson or sim.sandbox or a.distance_to(b) < 0.0001: return
	if hit_cloud:
		cloud_stroke = true
	else:
		# The brush has a soft footprint; the cursor need not hit a grid centre.
		for i in sim.COUNT:
			if sim.humidity[i] > 0.15 and sim.positions[i].distance_to(Geometry2D.get_closest_point_to_segment(sim.positions[i],a,b)) < sim.settings.brush_radius:
				wet_stroke = true
				break

func help_level() -> int:
	return 2 if idle_seconds >= settings.gesture_seconds else (1 if idle_seconds >= settings.reminder_seconds else 0)

func update(sim: RefCounted, delta: float) -> void:
	if sim.sandbox:
		return
	if lesson:
		var previous := phase
		idle_seconds += delta
		held_seen = held_seen or not sim.held_wind.is_empty()
		saw_rain = saw_rain or sim.total_rain_rate > 0.01
		if sim.is_reservoir(0):
			if wet_stroke: phase = maxi(phase,1)
			if sim.total_mountain_lift > 0.04 and sim.peak_density > 0.15: phase = maxi(phase,2)
			if saw_rain or sim.plot_water > 0.01: phase = maxi(phase,3)
			if (saw_rain and cloud_stroke) or sim.plot_water > 0.01: phase = maxi(phase,4)
			if sim.outcome == "success": phase = 5
			if phase != previous: idle_seconds = 0.0
			return
		if sim.total_mountain_lift > 0.04 and sim.peak_density > 0.15:
			phase = maxi(phase, 1)
		if saw_rain or sim.plot_water > 0.01:
			phase = maxi(phase, 2)
		if sim.is_reservoir(0):
			if sim.outcome == "success": phase = 3
		else:
			if sim.plot_water >= sim.required_water(0): phase = maxi(phase, 3)
			if sim.outcome == "success": phase = 4
	else:
		cold_hint_left = maxf(0.0, cold_hint_left - delta)
		if not cold_hint_seen:
			for strength in sim.display_cold:
				if strength > 0.15:
					cold_hint_seen = true
					cold_hint_left = 12.0
					break

func title(sim: RefCounted) -> String:
	if sim.is_reservoir(0):
		return "入门完成" if phase >= 5 else "%d / 5  %s" % [phase+1,settings.titles[phase]]
	if sim.outcome == "flood":
		return "雨水过量 · 可以重试这一步"
	return ["1 / 4  借山成云", "2 / 4  收厚成雨", "3 / 4  把雨送到土地", "4 / 4  安全收尾", "入门完成"][phase]

func instruction(sim: RefCounted) -> String:
	if sim.is_reservoir(0):
		if phase >= 5: return "水库已蓄满；水汽—山—云—雨—水库，连成了一场雨。"
		if phase > 1 and sim.peak_density < 0.15 and sim.total_rain_rate < 0.01:
			return "云已散薄：再把浅色湿空气推向山坡，补给云水。"
		if help_level() > 0:
			if phase <= 1: return "按住左键拖动浅色细丝，朝标记的山坡送；停住可续吹。"
			if phase == 2: return "沿山坡继续补给湿空气，等云变厚；雨线出现才开始下雨。"
			if sim.plot_water <= 0.01: return "已下雨但水位未升：直接按住云朵，拖向水库上方。"
		return settings.actions[phase]
	if sim.outcome == "flood":
		return "按 R 重试；接近适量前就开始移云。"
	if phase == 4:
		return "这场雨刚刚好。进入自由局后，也可选择风纹测试。"
	if phase == 3:
		return "移开虚线范围内的厚云与雨云，等待安全。"
	if phase > 0 and sim.peak_density < 0.15 and sim.total_rain_rate < 0.01:
		return "云已散薄：再把浅色湿空气推向山坡，补给云水。"
	if phase == 2:
		if sim.plot_water >= sim.required_water(0) * 0.7:
			return "快够水了：提前把雨云移开，储水还会继续落下。"
		return "把雨云慢慢送到 A 上方，观察地块旁的水量。"
	if phase == 1:
		return "从云边向内轻拨，收厚后保持片刻就会下雨。"
	return "拖出方向后按住续吹，把浅色湿空气送向山坡。"

func detail(sim: RefCounted) -> String:
	if sim.is_reservoir(0):
		if phase >= 5:
			return "下一关要把云送得更远；直接按住云拖动即可。" if not cloud_stroke else "水库可溢流；以后遇到农田，要控制雨量并移云收尾。"
		return settings.details[phase]
	if sim.outcome == "flood":
		return "切断补给不会立即停雨，已积存的云水仍会释放。"
	if phase == 3:
		return "保持适量，并让附近危险天气清除后维持 %.0f 秒。" % sim.settings.safe_seconds
	if phase == 2:
		return "淡蓝范围是实际落雨，悬停雨云可看清；移云期间仍会降雨。"
	if phase == 1:
		return "观察云的厚薄与雨线；拨动太猛会把云吹散。"
	if phase == 4:
		return "自由局还可借灰蓝色冷空气组织下一场雨，也可继续借山。"
	return "底部持续风可拖出风带，滚轮调力度；金色上升箭头表示实际造云。"
