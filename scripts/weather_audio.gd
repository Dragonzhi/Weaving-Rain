extends Node
## 只读声音表现：1条音乐、3层天气＋2个短音，不持有/修改天气规则。
const Settings = preload("res://scripts/audio_settings.gd")
const Loader = preload("res://scripts/config_loader.gd")
const Sim = preload("res://scripts/weather_simulation.gd")
const BRUSH_NAMES := ["brush", "brush_2", "brush_3", "brush_4", "brush_5"]
const SOUND_NAMES := ["wind", "rain", "rain_detail"] + BRUSH_NAMES + ["click", "source", "adequate", "safe", "full", "damage", "success", "failure"]
const PRIORITY := {"click":0, "brush":1, "source":1, "adequate":2, "safe":3, "full":3, "damage":4, "success":5, "failure":5}
var settings: Settings = Settings.new()
var settings_path := "res://configs/audio.tres"
var errors := PackedStringArray()
var preferences_path := "user://audio.cfg"
var enabled := true
var master_volume := 0.75
var music_volume := 0.70
var music: AudioStreamPlayer
var music_menu := true
var music_level := 0.0
var preference_timer: Timer
var focused := true
var suspended := false
var model: Sim
var camera: Camera3D
var loops: Array[AudioStreamPlayer] = []
var voices: Array[AudioStreamPlayer] = []
var voice_priorities := PackedInt32Array([0,0])
var streams: Dictionary = {}
var panners: Array[AudioEffectPanner] = []
var target_levels := Vector3.ZERO
var current_levels := Vector3.ZERO
var pan_target := Vector2.ZERO
var current_pan := Vector2.ZERO
var summary_wait := 0.0
var summary_ms := 0.0
var wind_measure := 0.0
var rain_measure := 0.0
var visible_cells := PackedInt32Array()
var screen_x := PackedFloat32Array()
var projection_transform := Transform3D()
var projection := Projection()
var viewport_rect := Rect2()
var projection_valid := false
var states: Array[String] = []
var adequate: Array[bool] = []
var seen_outcome := "playing"
var last_played: Dictionary = {}
# Small bounded counters allow tests to inspect actual decisions without a growing event log.
var event_counts: Dictionary = {}
var brush_rng := RandomNumberGenerator.new()
var brush_bag: Array[String] = []
var brush_variant_counts: Dictionary = {}
var last_brush_variant := ""
var last_brush_gesture := -1
var brush_voice := -1
var brush_pitch_target := 1.0
var field_target := 0.0
var field_presence := 0.0

func _ready() -> void:
	# Independent generator: never use Array.shuffle()/global game randomness.
	brush_rng.seed = Time.get_ticks_usec() ^ get_instance_id()
	preference_timer = Timer.new()
	preference_timer.one_shot = true
	preference_timer.wait_time = 0.25
	preference_timer.timeout.connect(_save_preferences)
	add_child(preference_timer)
	for bus_name in ["WRWind", "WRRain", "WRFeedback", "WRMusic"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count-1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
			if bus_name in ["WRWind", "WRRain"]: AudioServer.add_bus_effect(index, AudioEffectPanner.new())
	for bus_name in ["WRWind", "WRRain"]:
		panners.append(AudioServer.get_bus_effect(AudioServer.get_bus_index(bus_name),0))
	# Native protection for overlapping weather/feedback; applies only to this game's Master.
	var has_limiter := false
	for index in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0,index) is AudioEffectLimiter: has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -6.0
		AudioServer.add_bus_effect(0, limiter)
	for sound in SOUND_NAMES:
		var path: String = "res://assets/audio/"+sound+".wav"
		if ResourceLoader.exists(path): streams[sound] = load(path)
		else: push_warning("音效缺失，安静跳过："+path)
	for index in 3:
		var player := AudioStreamPlayer.new()
		player.bus = "WRWind" if index == 0 else "WRRain"
		var sound: String = SOUND_NAMES[index]
		if streams.has(sound):
			var stream := streams[sound].duplicate() as AudioStreamWAV
			var frame_count := roundi(stream.get_length()*stream.mix_rate)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = frame_count
			player.stream = stream
		player.volume_db = -80
		add_child(player)
		loops.append(player)
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "WRFeedback"
		add_child(player)
		voices.append(player)
	# This player belongs to the session; bind()/retry never replaces or restarts it.
	music = AudioStreamPlayer.new()
	music.bus = "WRMusic"
	music.volume_db = -80
	var music_path := "res://assets/audio/meadow_thoughts.ogg"
	if ResourceLoader.exists(music_path):
		var theme := load(music_path).duplicate() as AudioStreamOggVorbis
		theme.loop = true
		theme.loop_offset = 0
		music.stream = theme
	else: push_warning("音乐缺失，安静跳过："+music_path)
	add_child(music)
	if music.stream != null: music.play()

func load_preferences() -> void:
	if preferences_path.is_empty() or not FileAccess.file_exists(preferences_path): return
	var config := ConfigFile.new()
	var error := config.load(preferences_path)
	if error != OK:
		push_warning("音效偏好未读取："+error_string(error))
		return
	var candidate_enabled = config.get_value("audio", "enabled", true)
	var candidate_volume = config.get_value("audio", "volume", 0.75)
	var candidate_music = config.get_value("audio", "music_volume", 0.70)
	if not candidate_enabled is bool or not _valid_volume(candidate_volume) or not _valid_volume(candidate_music):
		push_warning("声音偏好保留：enabled须为布尔，volume／music_volume须为0–1有限数")
		return
	enabled = candidate_enabled
	master_volume = candidate_volume
	music_volume = candidate_music
	_apply_master()

func _valid_volume(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0 and value <= 1

func set_music_volume(volume: float, save := true) -> void:
	if not _valid_volume(volume): return
	music_volume = volume
	_apply_master()
	if save and not preferences_path.is_empty(): preference_timer.start()

func set_options(on: bool, volume: float, save := true) -> void:
	if not is_finite(volume) or volume < 0 or volume > 1: return
	enabled = on
	master_volume = volume
	_apply_master()
	if not enabled or master_volume == 0: _stop_voices()
	if save and not preferences_path.is_empty():
		# Native debounce: slider motion updates sound immediately, writes once after rest.
		preference_timer.start()

func _save_preferences() -> void:
	if preferences_path.is_empty(): return
	var config := ConfigFile.new()
	config.set_value("audio", "enabled", enabled)
	config.set_value("audio", "volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	var error := config.save(preferences_path)
	if error != OK: push_warning("音效偏好保存失败："+error_string(error))

func _exit_tree() -> void:
	if preference_timer != null and not preference_timer.is_stopped(): _save_preferences()

func _apply_master() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume,0.0001)))
	AudioServer.set_bus_mute(0, not enabled or not focused or master_volume == 0)
	var bus := AudioServer.get_bus_index("WRMusic")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(music_volume,0.0001)))
		AudioServer.set_bus_mute(bus,music_volume == 0)
	if music != null: music.stream_paused = not focused

func bind(sim: Sim, view_camera: Camera3D) -> void:
	var loaded := Loader.audio(settings_path)
	settings = loaded.resource
	errors = loaded.errors
	model = sim
	camera = view_camera
	projection_valid = false
	summary_wait = 0
	target_levels = Vector3.ZERO
	current_levels = Vector3.ZERO
	last_played.clear()
	event_counts.clear()
	brush_variant_counts.clear()
	brush_bag.clear()
	last_brush_variant = ""
	last_brush_gesture = -1
	field_target = 0
	field_presence = 0
	_stop_voices()
	for player in loops:
		player.stop()
		player.volume_db = -80
	current_pan = Vector2.ZERO
	pan_target = Vector2.ZERO
	suspended = false
	_baseline()
	_apply_master()

func _baseline() -> void:
	states.clear()
	adequate.clear()
	if model == null: return
	for target in model.plot_centers.size():
		states.append(model.plot_status(target))
		adequate.append(model.water_for(target) >= model.required_water(target))
	seen_outcome = model.outcome

func observe_states() -> void:
	if model == null: return
	if not focused or suspended:
		_baseline()
		return
	var event := ""
	for target in model.plot_centers.size():
		var state := model.plot_status(target)
		var enough := model.water_for(target) >= model.required_water(target)
		var candidate := ""
		if state == "destroyed" and states[target] != state: candidate = "damage"
		elif state == "safe" and states[target] != state: candidate = "full" if model.is_reservoir(target) else "safe"
		elif enough and not adequate[target]: candidate = "adequate"
		if not candidate.is_empty() and (event.is_empty() or PRIORITY[candidate] > PRIORITY[event]): event = candidate
		states[target] = state
		adequate[target] = enough
	if model.outcome != seen_outcome:
		if model.outcome != "playing": event = "success" if model.outcome == "success" else "failure"
		seen_outcome = model.outcome
	if not event.is_empty(): cue(event)

func cue(sound: String) -> void:
	_play_short(sound)

func brush_motion(gesture: int, speed: float) -> void:
	if model == null or not is_finite(speed) or speed < 0: return
	var strength := clampf(speed/model.settings.stroke_speed_full,0,1)
	brush_pitch_target = lerpf(settings.brush_pitch_range.x,settings.brush_pitch_range.y,strength)
	if gesture == last_brush_gesture: return
	# Consume the gesture even if muted/voice-limited; never replay it later mid-drag.
	last_brush_gesture = gesture
	_play_short("brush",brush_pitch_target)

func _next_brush() -> String:
	if brush_bag.is_empty():
		for name in BRUSH_NAMES:
			if streams.has(name): brush_bag.append(name)
		for index in range(brush_bag.size()-1,0,-1):
			var other := brush_rng.randi_range(0,index)
			var swap := brush_bag[index]
			brush_bag[index] = brush_bag[other]
			brush_bag[other] = swap
		if brush_bag.size()>1 and brush_bag[0]==last_brush_variant:
			var swap := brush_bag[0]
			brush_bag[0] = brush_bag[1]
			brush_bag[1] = swap
	if brush_bag.is_empty(): return ""
	return brush_bag.pop_front()

func _play_short(sound: String, pitch := 1.0) -> void:
	if not enabled or master_volume == 0 or not focused or not PRIORITY.has(sound): return
	if suspended and sound != "click": return
	if sound != "brush" and not streams.has(sound): return
	var now := Time.get_ticks_usec()/1000000.0
	var group := "gesture" if sound in ["brush", "source"] else sound
	var cooldown := settings.feedback_cooldown if group == "gesture" or sound == "click" else 0.4
	if now-float(last_played.get(group,-1000.0)) < cooldown: return
	var slot := -1
	for index in voices.size():
		if not voices[index].playing:
			slot = index
			break
	if slot < 0:
		slot = 0 if voice_priorities[0] <= voice_priorities[1] else 1
		if PRIORITY[sound] < voice_priorities[slot]: return
	var gain := settings.brush_gain if sound=="brush" else settings.feedback_gain
	if gain==0: return
	var stream_name := _next_brush() if sound=="brush" else sound
	if stream_name.is_empty(): return
	if slot==brush_voice: brush_voice = -1
	voices[slot].stop()
	voices[slot].stream = streams[stream_name]
	voices[slot].pitch_scale = pitch
	voices[slot].volume_db = linear_to_db(gain)
	voices[slot].play()
	if sound=="brush":
		brush_voice = slot
		last_brush_variant = stream_name
		brush_variant_counts[stream_name] = int(brush_variant_counts.get(stream_name,0))+1
	voice_priorities[slot] = PRIORITY[sound]
	last_played[group] = now
	event_counts[sound] = int(event_counts.get(sound,0))+1

func _stop_voices() -> void:
	for player in voices: player.stop()
	brush_voice = -1
	brush_pitch_target = 1.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: set_focused(true)

func set_focused(value: bool) -> void:
	focused = value
	_stop_voices()
	_baseline()
	summary_wait = 0
	_apply_master()

func update_audio(dt: float, paused: bool) -> void:
	if model == null: return
	set_paused(paused)
	observe_states()
	var active := not paused and focused and enabled and master_volume > 0 and model.outcome == "playing"
	summary_wait -= dt
	if active and summary_wait <= 0:
		var start := Time.get_ticks_usec()
		_sample_weather()
		summary_ms = (Time.get_ticks_usec()-start)/1000.0
		summary_wait = 0.1
	if not active: target_levels = Vector3.ZERO
	field_presence = lerpf(field_presence,field_target,1.0-exp(-dt/(0.35 if field_target>field_presence else settings.wind_tail_seconds)))
	var audible_target := target_levels
	audible_target.x *= lerpf(settings.brush_wind_gain,1.0,field_presence)
	var blend := 1.0-exp(-dt/(settings.fade_seconds if active else settings.stop_fade_seconds))
	for index in 3:
		var level_blend := blend
		if active and index > 0:
			var seconds: float = settings.rain_attack_seconds if audible_target[index] > current_levels[index] else settings.rain_release_seconds
			level_blend = 1.0-exp(-dt/seconds)
		current_levels[index] = lerpf(current_levels[index],audible_target[index],level_blend)
	if brush_voice>=0 and voices[brush_voice].playing:
		voices[brush_voice].pitch_scale = lerpf(voices[brush_voice].pitch_scale,brush_pitch_target,1.0-exp(-dt/settings.brush_pitch_seconds))
	current_pan = current_pan.lerp(pan_target,blend)
	for index in 2: panners[index].pan = current_pan[index]
	for index in 3:
		var player := loops[index]
		var gain := current_levels[index]
		player.volume_db = linear_to_db(maxf(gain,0.0001))
		if active and player.stream != null and not player.playing: player.play()
		player.stream_paused = not active and gain < 0.001
	_update_music(dt,paused)

func _update_music(dt: float, paused: bool) -> void:
	var ratio := 1.0 if music_menu else (settings.music_pause_ratio if paused or model.outcome != "playing" else settings.music_play_ratio)
	# Read smoothed audible rain, avoiding jumps when new ground_rain starts/stops.
	var rain_level := clampf(maxf(current_levels.y/maxf(settings.rain_gain,0.0001),current_levels.z/maxf(settings.rain_detail_gain,0.0001)),0,1)
	if not music_menu: ratio *= lerpf(1.0,settings.music_rain_ratio,rain_level)
	music_level = lerpf(music_level,settings.music_gain*ratio,1.0-exp(-dt/settings.music_fade_seconds))
	music.volume_db = linear_to_db(maxf(music_level,0.0001))

func set_paused(value: bool) -> void:
	if value and not suspended: _stop_voices()
	suspended = value

func _refresh_projection() -> void:
	var rect := camera.get_viewport().get_visible_rect()
	var transform := camera.global_transform
	var current_projection := camera.get_camera_projection()
	if projection_valid and rect == viewport_rect and transform == projection_transform and current_projection == projection: return
	viewport_rect = rect
	projection_transform = transform
	projection = current_projection
	projection_valid = true
	visible_cells.clear()
	screen_x.resize(Sim.COUNT)
	for index in Sim.COUNT:
		var p: Vector2 = model.positions[index]
		var low := camera.unproject_position(Vector3(p.x,model.terrain.height(p)+0.3,p.y))
		var cloud := camera.unproject_position(Vector3(p.x,3.6,p.y))
		if rect.has_point(low) or rect.has_point(cloud): visible_cells.append(index)
		screen_x[index] = clampf((low.x-rect.position.x)/maxf(rect.size.x,1.0)*2-1,-1,1)

func _sample_weather() -> void:
	if not is_instance_valid(camera): return
	_refresh_projection()
	var wind_sum := 0.0
	var wind_peak := 0.0
	var wind_x := 0.0
	var rain_sum := 0.0
	var rain_peak := 0.0
	var rain_x := 0.0
	var cold_flowing := false
	for index in visible_cells:
		var speed := maxf(model.low_wind[index].length(),model.cloud_wind[index].length())
		cold_flowing = cold_flowing or model.cold_flow[index].length_squared()>=0.0036
		if speed >= 0.06:
			wind_sum += speed
			wind_peak = maxf(wind_peak,speed)
			wind_x += speed*screen_x[index]
		var rate: float = model.ground_rain[index]
		rain_sum += rate
		rain_peak = maxf(rain_peak,rate)
		rain_x += rate*screen_x[index]
	wind_measure = clampf((0.4*wind_peak+0.6*wind_sum/maxi(visible_cells.size(),1))/settings.wind_full_speed,0,1)
	rain_measure = clampf(maxf(rain_sum/settings.rain_full_rate,0.45*rain_peak/settings.rain_peak_rate),0,1)
	field_target = 1.0 if not model.wind_sources.is_empty() or not model.held_wind.is_empty() or model.tropical!=null or cold_flowing else 0.0
	var heavy_mix := smoothstep(settings.heavy_rain_range.x,settings.heavy_rain_range.y,rain_measure)
	# Equal-power handoff: strong rain becomes A's rain curtain, not louder light drops.
	target_levels = Vector3(sqrt(wind_measure)*settings.wind_gain,sqrt(rain_measure*(1.0-heavy_mix))*settings.rain_gain,sqrt(rain_measure*heavy_mix)*settings.rain_detail_gain)
	pan_target = Vector2(wind_x/maxf(wind_sum,0.0001),rain_x/maxf(rain_sum,0.0001))*settings.pan_limit
