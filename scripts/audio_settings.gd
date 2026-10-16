@tool
class_name WRAudioSettings
extends Resource
## 独立音频配置，保存后R／切图读取；F6仍只调整天气。均不改变模拟。
@export_group("背景音乐")
## A1主题的线性倍率（0–4），再乘玩家音乐音量和总音量。素材已留音量余量，允许大于1补偿。
## 默认2比首版0.65提高约9.8dB，让音乐滑杆有足够上调空间；0仅关闭音乐，不影响风雨。
@export_range(0, 4) var music_gain := 2.0
## 游玩／暂停时相对主界面的音乐比例（0–1）。调小为操作与天气让位；暂停保留轻音乐。
@export_range(0, 1) var music_play_ratio := 0.70
@export_range(0, 1) var music_pause_ratio := 0.55
## 最大实际雨强时的音乐保留比例（0–1）；按平滑雨声强度渐变，调小强雨中音乐退得更多。
@export_range(0, 1) var music_rain_ratio := 0.80
## 音乐起音和场景混音变化的时间常数（秒，0.1–5）；调大更徐缓，不重启乐曲。
@export_range(0.1, 5) var music_fade_seconds := 1.0
@export_group("混音比例")
## 风、雨和反馈的线性倍率（0–1）。调大更明显，调小让出听觉空间；0关闭该层。
@export_range(0, 1) var wind_gain := 0.35
@export_range(0, 1) var rain_gain := 0.50
## A密雨层倍率（保留旧字段名）。调大强雨幕更明显；随真实雨强接替小雨，不添加合成噪声。
@export_range(0, 1) var rain_detail_gain := 0.65
@export_range(0, 1) var feedback_gain := 0.45
## 拨风差分的线性音量（0–1），独立于成果／按钮短音；调大动作更突出。
@export_range(0, 1) var brush_gain := 0.85
## 手速从慢到快对应的播放音高倍率（各0.5–2，须升序）。调宽差异更明显，也更容易夸张。
@export var brush_pitch_range := Vector2(0.92,1.10)
## 拨动中音高追随手速的时间常数，秒（0.01–0.5）；调大更平滑，调小更敏捷。
@export_range(0.01, 0.5) var brush_pitch_seconds := 0.06
## 只有普通拨风／残风时的风底比例（0–1）；调小突出单次风切，续吹和持续风场会展开到底声原幅。
@export_range(0, 1) var brush_wind_gain := 0.25
## 撤源／停止续吹后风场音色退回轻风底的时间常数，秒（0.1–10）；仍乘实际残风速度，不产生风。
@export_range(0.1, 10) var wind_tail_seconds := 2.0
@export_group("天气映射")
## 达到主风层满幅的空气速度，单位世界单位/秒（0.1–10）。调小弱风也显得强。
@export_range(0.1, 10) var wind_full_speed := 3.0
## 画面内总落雨速率达到雨层满幅的参考值，单位实际水量/秒（0.01–1000）。
## 调大整体雨声更克制；局部强雨仍由下面的峰值参数保留，不按空格平均稀释。
@export_range(0.01, 1000) var rain_full_rate := 20.0
## 单格落雨速率满幅参考值，同单位（0.001–100）。调小局部强雨更易听到。
@export_range(0.001, 100) var rain_peak_rate := 0.5
## 归一化实际雨强中开始／完全转入A密雨的区间（0–1，须升序）；调低更早出现厚雨幕。
@export var heavy_rain_range := Vector2(0.20,0.85)
@export_group("过渡与反馈")
## 风及声像响应时间常数，秒（0.05–2）。调小响应快，调大平滑；雨使用下面的独立起落。
@export_range(0.05, 2) var fade_seconds := 0.25
## 雨声变强的时间常数，秒（0.1–5）。默认约3.3秒到目标95%；调大起雨更徐缓，调小更贴近瞬间雨强。
@export_range(0.1, 5) var rain_attack_seconds := 1.1
## 雨声变弱的时间常数，秒（0.1–5）。默认约2.7秒退去95%；调大保留雨幕尾声，调小停雨更干净。
## 仅平滑听觉，不延长实际降雨；暂停／结算沿用下面更快的退声。
@export_range(0.1, 5) var rain_release_seconds := 0.9
## 暂停、结算退声时间常数，秒（0.05–2）；退到近静音后暂停流。
@export_range(0.05, 2) var stop_fade_seconds := 0.15
## 相邻操作短音的最短间隔，真实秒（0.05–2），与鼠标事件数量无关。
@export_range(0.05, 2) var feedback_cooldown := 0.18
## 左右声像最大偏移（0–0.5）。0居中；轻微偏移表达屏幕位置，不模拟逐格声源。
@export_range(0, 0.5) var pan_limit := 0.22

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in ["music_gain", "music_play_ratio", "music_pause_ratio", "music_rain_ratio", "music_fade_seconds", "wind_gain", "rain_gain", "rain_detail_gain", "feedback_gain", "brush_gain", "brush_wind_gain", "brush_pitch_seconds", "wind_tail_seconds", "wind_full_speed", "rain_full_rate", "rain_peak_rate", "fade_seconds", "rain_attack_seconds", "rain_release_seconds", "stop_fade_seconds", "feedback_cooldown", "pan_limit"]:
		var limits: Vector2 = {"music_gain":Vector2(0,4), "music_fade_seconds":Vector2(0.1,5), "brush_pitch_seconds":Vector2(0.01,0.5), "wind_tail_seconds":Vector2(0.1,10), "wind_full_speed": Vector2(0.1,10), "rain_full_rate":Vector2(0.01,1000), "rain_peak_rate":Vector2(0.001,100), "fade_seconds":Vector2(0.05,2), "rain_attack_seconds":Vector2(0.1,5), "rain_release_seconds":Vector2(0.1,5), "stop_fade_seconds":Vector2(0.05,2), "feedback_cooldown":Vector2(0.05,2), "pan_limit":Vector2(0,0.5)}.get(field, Vector2(0,1))
		var value: float = get(field)
		if not is_finite(value) or value < limits.x or value > limits.y: errors.append(field+"：须在"+str(limits.x)+"–"+str(limits.y)+"内")
	for field in ["brush_pitch_range", "heavy_rain_range"]:
		var value: Vector2 = get(field)
		var limits := Vector2(0.5,2) if field=="brush_pitch_range" else Vector2(0,1)
		if not value.is_finite() or value.x<limits.x or value.y>limits.y or value.x>=value.y: errors.append(field+"：须为有效范围内升序的两个有限值")
	return errors
