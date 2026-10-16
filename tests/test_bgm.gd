extends SceneTree
## Native music playback and settings lifecycle; weather injections only isolate mixing.
const Loader = preload("res://scripts/config_loader.gd")
var main: Node3D
var checks := 0
var failures := 0
var directory := "res://.godot/bgm-review/"
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func settle() -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
func click(button: BaseButton) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await create_timer(0.10).timeout
	while main.transition_active(): await process_frame
	await settle()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	while main.transition_active(): await process_frame
	var audio: Node = main.weather_audio
	check(audio.preferences_path.is_empty(),"Fresh guide isolates real player audio preferences")
	check(main.front_active(),"Normal startup starts on home")
	audio.preferences_path = directory+"preferences.cfg"
	audio.set_focused(true)
	audio.set_options(true,0.75,false)
	audio.set_music_volume(0.7,false)
	var player: AudioStreamPlayer = audio.music
	check(player.playing and player.stream is AudioStreamOggVorbis,"Actual Ogg plays through native player")
	check(player.stream.loop and player.stream.loop_offset==0,"Native full-file loop enabled")
	check(player.stream.get_length()>148 and player.stream.get_length()<149,"Complete phrasing retained in 148-second loop")
	check(audio.loops.size()==3 and audio.voices.size()==2,"Weather and feedback voice budget unchanged")
	check(audio.settings.validation_errors().is_empty() and audio.settings.music_gain>1,"Default mix supports compensating the quiet source above unity")
	var invalid = audio.settings.duplicate()
	invalid.music_gain = 4.1
	check("music_gain" in " ".join(invalid.validation_errors()),"Music compensation still validates upper bound")
	invalid.music_gain = 2.0
	invalid.wind_gain = 1.1
	check("wind_gain" in " ".join(invalid.validation_errors()),"Extra music range never expands weather gain range")
	await create_timer(0.3).timeout
	check(player.get_playback_position()>0.1 and audio.music_level>0,"Home starts music with gradual gain")
	player.seek(40)
	main.open_front_page("settings")
	await settle()
	check(audio.music==player and player.get_playback_position()>39,"Page switch preserves playback")
	var menu: Control = main.front_menu
	check(menu.music_volume.is_visible_in_tree(),"Native music slider appears in settings")
	check(menu.sound_toggle.get_theme_color("font_pressed_color").get_luminance()<0.4,"Checked sound label keeps dark ink on pale background")
	check(root.get_visible_rect().encloses(menu.music_volume.get_global_rect()),"Music slider fits viewport")
	check(root.get_visible_rect().encloses(menu.sound_toggle.get_global_rect()),"Sound toggle fits viewport")
	check(not menu.volume.get_global_rect().intersects(menu.music_volume.get_global_rect()),"Master and music sliders have separate hit areas")
	menu.music_volume.grab_focus()
	for code in [KEY_HOME,KEY_END]:
		for pressed in [true,false]:
			var key := InputEventKey.new()
			key.keycode = code
			key.pressed = pressed
			root.push_input(key,true)
			await settle()
		check(is_equal_approx(audio.music_volume,0.0 if code==KEY_HOME else 1.0),"Native music keyboard adjustment: "+str(code))
	menu.music_volume.value = 31
	check(is_equal_approx(audio.music_volume,0.31),"Music slider applies immediately")
	check(is_equal_approx(audio.master_volume,0.75),"Music slider leaves master unchanged")
	menu.volume.value = 42
	check(is_equal_approx(audio.master_volume,0.42) and is_equal_approx(audio.music_volume,0.31),"Master slider keeps independent music preference")
	menu.music_volume.value = 0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("WRMusic")) and not AudioServer.is_bus_mute(0),"Music zero silences only music bus")
	menu.music_volume.value = 70
	await click(menu.sound_toggle)
	check(not audio.enabled and AudioServer.is_bus_mute(0),"Native sound switch mutes music and weather together")
	await click(menu.sound_toggle)
	check(audio.enabled and not AudioServer.is_bus_mute(0),"Native sound switch restores sound")
	await create_timer(0.3).timeout
	var prefs := ConfigFile.new()
	check(prefs.load(audio.preferences_path)==OK and is_equal_approx(prefs.get_value("audio","music_volume"),0.7),"Music preference persists independently")
	root.get_texture().get_image().save_png(directory+"settings-"+str(root.size.x)+".png")
	# Older preference files have no music key; retain their existing master/mute.
	prefs.erase_section_key("audio","music_volume")
	prefs.set_value("audio","volume",0.37)
	prefs.save(audio.preferences_path)
	audio.load_preferences()
	check(is_equal_approx(audio.master_volume,0.37) and is_equal_approx(audio.music_volume,0.7),"Old preference defaults music without changing old master")
	prefs.set_value("audio","music_volume",NAN)
	prefs.set_value("audio","volume",0.9)
	prefs.save(audio.preferences_path)
	audio.load_preferences()
	check(is_equal_approx(audio.master_volume,0.37) and is_equal_approx(audio.music_volume,0.7),"Invalid music preference rejects whole candidate")
	audio.set_options(true,0.75,false)
	await click(main.front_menu.back_button)
	player.seek(50)
	await click(main.front_menu.primary)
	check(not main.front_active() and player.get_playback_position()>49,"Native start keeps music position")
	main.set_process(false)
	player.seek(60)
	main.restart(false)
	main.set_process(false)
	check(audio.music==player and player.playing and player.get_playback_position()>59,"Retry retains same player and position")
	main.select_layout("level01")
	main.set_process(false)
	check(player.get_playback_position()>59 and audio.model==main.sim,"Map change rebinds weather without restarting theme")
	var water: PackedByteArray = main.sim.humidity.to_byte_array()
	var cloud: PackedByteArray = main.sim.cloud.to_byte_array()
	var total: float = main.sim.water_total()
	main.sim.ground_rain.fill(0)
	main.sim.low_wind.fill(Vector2.ZERO)
	main.sim.cloud_wind.fill(Vector2.ZERO)
	audio.music_menu = true
	for tick in 100: audio.update_audio(0.1,true)
	var home_level: float = audio.music_level
	audio.music_menu = false
	for tick in 100: audio.update_audio(0.1,false)
	var play_level: float = audio.music_level
	check(play_level>0 and play_level<home_level*.8,"Gameplay music steps back from menu")
	for tick in 100: audio.update_audio(0.1,true)
	check(player.playing and not player.stream_paused and audio.music_level<play_level,"Pause keeps softer music playing")
	check(audio.loops.all(func(loop): return loop.stream_paused),"Paused music does not resume weather loops")
	audio.set_focused(false)
	var position := player.get_playback_position()
	await create_timer(0.2).timeout
	check(AudioServer.is_bus_mute(0) and player.stream_paused and absf(player.get_playback_position()-position)<0.05,"Focus loss mutes and holds music position")
	audio.set_focused(true)
	check(not player.stream_paused and not AudioServer.is_bus_mute(0),"Focus return resumes without restart")
	# Actual rain fixture tests ducking only; no claim of a natural weather route.
	main.sim.ground_rain.fill(0.5)
	audio.summary_wait = 0
	for tick in 100: audio.update_audio(0.1,false)
	check(audio.music_level<play_level*.9 and audio.music_level>play_level*.75,"Strong rain leaves audible music instead of over-ducking")
	check(main.sim.humidity.to_byte_array()==water and main.sim.cloud.to_byte_array()==cloud and main.sim.water_total()==total,"Music/mixing never changes weather water or cloud arrays")
	var settings_before = audio.settings
	main.reload_tuning()
	check(audio.settings==settings_before,"F6 leaves music settings and player unchanged")
	var tuned = audio.settings.duplicate()
	tuned.music_gain = 0.4
	ResourceSaver.save(tuned,directory+"audio.tres")
	audio.settings_path = directory+"audio.tres"
	player.seek(70)
	main.restart(false)
	main.set_process(false)
	check(is_equal_approx(audio.settings.music_gain,0.4) and player.get_playback_position()>69,"Retry reloads music mix without restarting track")
	tuned.music_fade_seconds = NAN
	ResourceSaver.save(tuned,directory+"audio.tres")
	main.restart(false)
	main.set_process(false)
	check(is_equal_approx(audio.settings.music_gain,0.4) and "music_fade_seconds" in " ".join(audio.errors),"Bad music config retains previous valid mix and names field")
	audio.settings_path = "res://configs/audio.tres"
	main.restart(false)
	main.set_process(false)
	audio.music_menu = false
	audio.set_focused(true)
	audio.set_options(true,0.75,false)
	for tick in 60: audio.update_audio(0.1,false)
	# Capture the real native music bus while crossing the loop boundary.
	var recorder := AudioEffectRecord.new()
	var bus := AudioServer.get_bus_index("WRMusic")
	AudioServer.add_bus_effect(bus,recorder)
	player.seek(player.stream.get_length()-1.0)
	recorder.set_recording_active(true)
	await create_timer(2.5).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	check(player.playing and player.get_playback_position()<4,"Native Ogg really loops through end")
	check(recording!=null and recording.data.size()>100000,"Native music bus emits actual recorded audio")
	if recording!=null: recording.save_to_wav(directory+"native-loop-"+str(root.size.x)+".wav")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	main.sim.outcome = "success"
	audio.update_audio(0.1,false)
	check(player.playing and audio.event_counts.get("success",0)==1,"Results preserve music and emit normal success feedback")
	var result := {"checks":checks,"failures":failures,"size":str(root.size),"home_level":home_level,"play_level":play_level,"duration":player.stream.get_length()}
	FileAccess.open(directory+"review-"+str(root.size.x)+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	main.queue_free()
	await process_frame
	print("BGM: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
