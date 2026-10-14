extends SceneTree
## Rain gain envelopes use real released-rain fields; weather itself is not advanced.
var main: Node3D
var checks := 0
var failures := 0
var trace: Dictionary = {}
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func rise(dt: float, seconds: float) -> Vector3:
	var audio: Node = main.weather_audio
	audio.bind(main.sim,main.weather_view.camera)
	for tick in roundi(seconds/dt): audio.update_audio(dt,false)
	return audio.current_levels
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	var audio: Node = main.weather_audio
	audio.set_focused(true)
	audio.set_options(true,0.75,false)
	main.sim.low_wind.fill(Vector2(2,0))
	main.sim.cloud_wind.fill(Vector2.ZERO)
	main.sim.cold_flow.fill(Vector2.ZERO)
	main.sim.ground_rain.fill(0)
	audio._sample_weather()
	var i: int = audio.visible_cells[audio.visible_cells.size()/2]
	main.sim.ground_rain[i] = 2
	var original_rain: PackedByteArray = main.sim.ground_rain.to_byte_array()
	var first := rise(1.0/60,1.0/60)
	var tenth := rise(1.0/60,0.1)
	var third := rise(1.0/60,3.3)
	var target: float = audio.target_levels.z
	check(first.z>0 and first.z<target*0.02,"First audible rain frame is under2% of target")
	check(tenth.z>target*.07 and tenth.z<target*.1,"100ms onset stays gentle rather than jumping to full rain")
	check(third.z>target*.94 and third.z<target*.96,"Rain reaches about95% after3.3seconds")
	var half := rise(1.0/60,0.5)
	check(half.x>audio.target_levels.x*audio.settings.brush_wind_gain*.85 and half.z<target*.4,"Existing wind response remains fast while rain rises gradually")
	var reference := rise(1.0/60,3)
	var slower := rise(1.0/30,3)
	var catchup := rise(0.1,3)
	check(reference.distance_to(slower)<0.000001 and reference.distance_to(catchup)<0.000001,"Envelope matches at30/60Hz and100ms updates")
	main.sim.ground_rain.fill(0)
	audio.summary_wait = 0
	var before: float = audio.current_levels.z
	audio.update_audio(0.1,false)
	check(audio.current_levels.z>before*.85 and audio.current_levels.z<before,"Rain ends with a tail rather than an abrupt cut")
	for tick in 26: audio.update_audio(0.1,false)
	check(audio.current_levels.z<before*.051,"Rain tail has fallen95% after2.7seconds")
	main.sim.ground_rain[i] = 2
	rise(0.1,3)
	for tick in 10: audio.update_audio(0.1,true)
	check(audio.loops.all(func(player): return player.stream_paused),"Pause still uses fast stop, not the longer rain tail")
	var Settings = preload("res://scripts/audio_settings.gd")
	var bad = Settings.new()
	bad.rain_attack_seconds = NAN
	bad.rain_release_seconds = 0
	check(bad.validation_errors().size()==2,"Both rain timing fields reject invalid values by name")
	var Loader = preload("res://scripts/config_loader.gd")
	ResourceSaver.save(bad,"res://.godot/audio-bad-rain.tres")
	var fallback: Dictionary = Loader.audio("res://.godot/audio-bad-rain.tres")
	check(fallback.errors.size()==2 and is_equal_approx(fallback.resource.rain_attack_seconds,1.1),"Failed rain config retains previous valid settings")
	check(main.sim.ground_rain.to_byte_array()==original_rain,"Audio envelope never changes actual released rain")
	trace = {"checks":checks,"failures":failures,"first_frame_ratio":first.z/target,"100ms_ratio":tenth.z/target,"3_3seconds_ratio":third.z/target,"30vs60_error":reference.distance_to(slower),"100ms_vs60_error":reference.distance_to(catchup)}
	FileAccess.open("res://.godot/rain-audio-envelope.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
	main.queue_free()
	await process_frame
	print("RAIN AUDIO: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
