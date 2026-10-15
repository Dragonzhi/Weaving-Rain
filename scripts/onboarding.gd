extends RefCounted
## Reads actual weather results. It never applies wind or modifies weather.
var lesson := true
var phase := 0
var saw_rain := false
var cold_hint_seen := false
var cold_hint_left := 0.0

func reset(is_lesson: bool) -> void:
	lesson = is_lesson
	phase = 0
	saw_rain = false
	cold_hint_seen = false
	cold_hint_left = 0.0

func update(sim: RefCounted, delta: float) -> void:
	if sim.sandbox:
		return
	if lesson:
		saw_rain = saw_rain or sim.total_rain_rate > 0.01
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
		return ["1 / 3  把水汽送上山", "2 / 3  成云降雨", "3 / 3  填满水库", "入门完成"][mini(phase,3)]
	if sim.outcome == "flood":
		return "雨水过量 · 可以重试这一步"
	return ["1 / 4  借山成云", "2 / 4  收厚成雨", "3 / 4  把雨送到土地", "4 / 4  安全收尾", "入门完成"][phase]

func instruction(sim: RefCounted) -> String:
	if sim.is_reservoir(0):
		if phase >= 3: return "水库已蓄满，你已经学会借山造雨。"
		if phase > 0 and sim.peak_density < 0.15 and sim.total_rain_rate < 0.01:
			return "云已散薄：再把浅色湿空气推向山坡，补给云水。"
		if phase == 2: return "让雨云覆盖水库，观察水位逐渐升高。"
		if phase == 1: return "继续补给云水，让云变厚并保持片刻，等待降雨。"
		return "拖出方向后按住续吹，把浅色湿空气推向山坡。"
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
		if phase >= 3: return "蓄满即完成；后面的农田关再学习控制雨量和安全收尾。"
		if phase == 2: return "水库满后可溢流，不会损坏；淡蓝轮廓表示实际落雨。"
		if phase == 1: return "金色上升箭头表示真实抬升，雨线出现才开始降雨。"
		return "鼠标拖动拨风，停住按住可以续吹；先试着推动一团水汽。"
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
