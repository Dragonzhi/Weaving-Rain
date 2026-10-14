extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const Audio = preload("res://scripts/weather_audio.gd")
const Loader = preload("res://scripts/config_loader.gd")
var main: Node3D
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func count(name: String) -> int: return int(main.weather_audio.event_counts.get(name,0))
func tap(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	await create_timer(0.12).timeout
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await process_frame
func place_source(start: Vector2, end: Vector2) -> void:
	var camera: Camera3D = main.weather_view.camera
	var event := InputEventMouseButton.new()
	event.position = camera.unproject_position(Vector3(start.x,0.3,start.y))
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	await create_timer(0.06).timeout
	var height: float = main.wind_input.reference_height
	var tip := camera.unproject_position(Vector3(end.x,height,end.y))
	var motion := InputEventMouseMotion.new()
	motion.position = tip
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	await process_frame
	event = event.duplicate()
	event.position = tip
	event.pressed = false
	root.push_input(event,true)
	await process_frame
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	main.guide.cold_hint_seen = true
	var audio: Audio = main.weather_audio
	audio.set_focused(true)
	audio.preferences_path = "res://.godot/audio-test.cfg"
	if FileAccess.file_exists(audio.preferences_path): DirAccess.remove_absolute(audio.preferences_path)
	check(audio.loops.size()==3 and audio.voices.size()==2, "Constant 3 weather + 2 feedback players")
	for player in audio.loops:
		check(player.stream != null and player.stream.loop_end > 400000 and player.stream.get_length()>9, "Loop uses actual decoded frames, not compressed byte length")
	check(audio.settings.validation_errors().is_empty(),"Default audio resource valid")
	var original: float = audio.settings.wind_gain
	var bad := audio.settings.duplicate()
	bad.wind_gain = NAN
	check("wind_gain" in " ".join(bad.validation_errors()),"NaN validation names exact field")
	ResourceSaver.save(bad,"res://.godot/audio-bad.tres")
	var rejected := Loader.audio("res://.godot/audio-bad.tres")
	check(not rejected.errors.is_empty() and rejected.resource.wind_gain==original,"Invalid resource retains last valid settings")
	main.sim.low_wind.fill(Vector2.ZERO)
	main.sim.cloud_wind.fill(Vector2.ZERO)
	main.sim.ground_rain.fill(0)
	audio._sample_weather()
	check(audio.target_levels==Vector3.ZERO,"Quiet weather has no loop signal")
	main.sim.cloud.fill(5)
	main.sim.rain.fill(5)
	audio._sample_weather()
	check(audio.rain_measure==0,"Cloud water / activated subset without actual falling rain stay quiet")
	var index: int = audio.visible_cells[audio.visible_cells.size()/2]
	main.sim.low_wind[index] = Vector2(3,0)
	main.sim.ground_rain[index] = 0.5
	audio._sample_weather()
	check(audio.wind_measure>0.39 and audio.rain_measure>=0.45,"Local air and strong local actual rain remain audible without full-grid dilution")
	check(absf(audio.pan_target.x)<=audio.settings.pan_limit and absf(audio.pan_target.y)<=audio.settings.pan_limit,"Screen pan stays bounded")
	var old_cells := audio.visible_cells.duplicate()
	main.weather_view.camera.size *= 0.75
	audio._sample_weather()
	check(audio.visible_cells!=old_cells,"Camera projection invalidates screen candidate cache")
	# Actual mixer readback: this is technical output proof, not subjective listening acceptance.
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0,record)
	record.set_recording_active(true)
	for frame in 40:
		audio.update_audio(1.0/60,false)
		await process_frame
	audio.cue("safe")
	await create_timer(0.5).timeout
	record.set_recording_active(false)
	var recording := record.get_recording()
	check(recording != null and recording.data.size()>10000,"Native Master produces recorded audio")
	if recording != null: recording.save_to_wav("res://.godot/audio-mixer-check.wav")
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	var loop_player: AudioStreamPlayer = audio.loops[0]
	loop_player.seek(loop_player.stream.get_length()-0.15)
	await create_timer(0.35).timeout
	check(loop_player.playing and loop_player.get_playback_position()<2,"Native stream really loops across the end")
	audio.bind(main.sim,main.weather_view.camera)
	main.sim.plot_waters[0] = main.sim.required_water(0)
	main.sim.plot_threats[0] = true
	audio.observe_states()
	check(count("adequate")==1 and count("safe")==0,"Water sufficient while dangerous is distinct from safe")
	audio.observe_states()
	check(count("adequate")==1,"Repeated read never replays sufficient notice")
	main.sim.plot_threats[0] = false
	main.sim.plot_safe_times[0] = main.sim.settings.safe_seconds-0.5
	audio.observe_states()
	check(count("safe")==0,"Safety confirmation time is respected")
	main.sim.plot_safe_times[0] = main.sim.settings.safe_seconds
	audio.observe_states()
	check(count("safe")==1,"Safe transition sounds once")
	main.sim.plot_threats[0] = true
	audio.observe_states()
	await create_timer(0.42).timeout
	main.sim.plot_threats[0] = false
	audio.observe_states()
	check(count("safe")==2,"Lost safe state can sound again after recovering")
	main.sim.plot_destroyed[0] = true
	audio.observe_states()
	audio.observe_states()
	check(count("damage")==1,"Permanent damage sounds once")
	main.sim.outcome = "success"
	audio.update_audio(0.1,false)
	audio.update_audio(0.1,false)
	check(count("success")==1,"Real result sounds once")
	main.restart(false)
	main.set_process(false)
	check(audio.event_counts.is_empty() and audio.model==main.sim,"Retry resets event baseline and voices")
	var tuned := audio.settings.duplicate()
	tuned.wind_gain = 0.31
	ResourceSaver.save(tuned,"res://.godot/audio-tuning.tres")
	audio.settings_path = "res://.godot/audio-tuning.tres"
	main.restart(false)
	main.set_process(false)
	check(is_equal_approx(audio.settings.wind_gain,0.31),"Retry deep-reads saved audio config")
	var weather_before: PackedByteArray = main.sim.humidity.to_byte_array()
	var settings_before = audio.settings
	main.reload_tuning()
	check(audio.settings==settings_before and main.sim.humidity.to_byte_array()==weather_before,"F6 leaves audio configuration and weather state intact")
	tuned.wind_gain = INF
	ResourceSaver.save(tuned,"res://.godot/audio-tuning.tres")
	main.restart(false)
	main.set_process(false)
	check(is_equal_approx(audio.settings.wind_gain,0.31) and not audio.errors.is_empty(),"Bad reload retains previous audio configuration")
	audio.settings_path = "res://configs/audio.tres"
	main.restart(false)
	main.set_process(false)
	audio.set_options(true,0.37)
	await create_timer(0.3).timeout
	audio.set_options(false,0,false)
	audio.load_preferences()
	check(audio.enabled and is_equal_approx(audio.master_volume,0.37),"Independent preferences save and reload")
	check(audio.preferences_path.begins_with("res://.godot/"),"Checks isolate player preferences")
	await tap(main.hud.menu_button)
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(main.hud.audio_button.visible and main.hud.audio_volume.visible,"Audio controls only in opened menu")
	root.get_texture().get_image().save_png("res://.godot/audio-menu-%d.png" % root.get_texture().get_image().get_width())
	check(main.hud.blocks_wind(main.hud.audio_volume.get_global_rect().get_center()),"Slider consumes gestures inside menu")
	await tap(main.hud.audio_button)
	check(not audio.enabled,"Native cross-frame mute button executes")
	await tap(main.hud.audio_button)
	check(audio.enabled,"Native button restores audio")
	main.hud.audio_volume.value = 42
	check(is_equal_approx(audio.master_volume,0.42),"Native slider adjusts volume")
	await tap(main.hud.menu_button)
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(not main.hud.audio_volume.visible,"Closed menu frees weather area")
	audio.event_counts.clear()
	audio.last_played.clear()
	await tap(main.hud.source_button)
	await place_source(Vector2(-5,-2),Vector2(-3,-2))
	check(count("source")==1 and main.sim.wind_sources.size()==1,"Real band placement sounds only after success")
	await create_timer(0.2).timeout
	await place_source(Vector2(-5,1),Vector2(-3,1))
	check(count("source")==2 and main.sim.wind_sources.size()==2,"Second source confirmation")
	await create_timer(0.2).timeout
	await place_source(Vector2(-5,3),Vector2(-3,3))
	check(count("source")==2 and main.sim.wind_sources.size()==2,"Rejected source is silent")
	# One step generates less than the existing 0.06 visual/audible wind floor;
	# let the source genuinely establish air before checking post-removal residuals.
	for tick in 18: main.sim.step(Sim.FIXED_STEP)
	audio._sample_weather()
	main.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	await tap(main.hud.source_remove[0])
	check(main.sim.wind_sources.size()==1,"Real native close button removes displayed stable source")
	audio._sample_weather()
	check(audio.wind_measure>0,"Closing source leaves actual residual air audible")
	await tap(main.hud.vortex_button)
	await create_timer(0.2).timeout
	await place_source(Vector2(0,-3),Vector2(2,-3))
	check(count("source")==3 and main.sim.wind_sources[-1].kind=="vortex","Real vortex placement shares sound feedback")
	audio.cue("brush")
	audio.cue("brush")
	check(count("brush")<=1,"Repeated events share gesture cooldown")
	main.sim.low_wind.fill(Vector2(1,0))
	for frame in 15: audio.update_audio(0.1,false)
	check(audio.current_levels.x>0.01,"Active air establishes wind bed")
	for frame in 15: audio.update_audio(0.1,true)
	check(audio.loops.all(func(player): return player.stream_paused),"Pause fades then suspends streams")
	check(audio.voices.all(func(player): return not player.playing),"Pause clears pending short voices")
	audio.update_audio(0.1,false)
	check(audio.loops.all(func(player): return not player.stream_paused),"Resume unpauses current weather")
	audio.set_focused(false)
	check(AudioServer.is_bus_mute(0),"Focus out mutes Master immediately")
	main.sim.plot_waters[0] = main.sim.required_water(0)
	audio.observe_states()
	audio.set_focused(true)
	audio.observe_states()
	check(count("adequate")==0,"Focus return discards missed state events")
	# Determinism: same input, one simulation observed by audio, other not.
	var left := Sim.new(null,true,true,"standard")
	var right := Sim.new(null,true,true,"standard")
	audio.bind(left,main.weather_view.camera)
	for tick in 90:
		if tick%15==0:
			left.stroke(Vector2(-5,0),Vector2(-4,0),3)
			right.stroke(Vector2(-5,0),Vector2(-4,0),3)
		left.step(Sim.FIXED_STEP)
		right.step(Sim.FIXED_STEP)
		audio.observe_states()
		audio.update_audio(Sim.FIXED_STEP,false)
	check(left.humidity.to_byte_array()==right.humidity.to_byte_array() and left.cloud.to_byte_array()==right.cloud.to_byte_array() and left.rain.to_byte_array()==right.rain.to_byte_array(),"Audio leaves weather arrays exactly identical")
	check(left.water_total()==right.water_total() and left.earned_stars()==right.earned_stars(),"Audio leaves mass and rating identical")
	main.select_layout("storm_coast")
	main.set_process(false)
	check(audio.model==main.sim and audio.camera==main.weather_view.camera,"Map switching rebinds current model and camera")
	main.sim.step(Sim.FIXED_STEP)
	audio._sample_weather()
	check(audio.wind_measure>0,"Natural system air has wind sound without manual source")
	main.select_layout("reservoir_lab")
	main.set_process(false)
	var pool := 0 if main.sim.is_reservoir(0) else 1
	main.sim.plot_waters[pool] = main.sim.required_water(pool)
	audio.observe_states()
	audio.observe_states()
	check(count("full")==1,"Reservoir completion is distinct and does not repeat")
	main.sim.three_star_elapsed = 0
	audio.observe_states()
	check(count("success")==0,"Countdown alone never sounds victory")
	for name in ["adequate", "safe", "damage", "success", "brush", "source"]: audio.cue(name)
	check(audio.voices.filter(func(player): return player.playing).size()<=2,"Voice budget stays bounded under overlapping events")
	main.queue_free()
	await process_frame
	print("AUDIO: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
