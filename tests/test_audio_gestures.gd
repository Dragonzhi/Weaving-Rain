extends SceneTree
## Real viewport gestures. Audio assertions use private counters, never edit weather.
var main: Node3D
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func button(p: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = p
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event,true)
func motion(p: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = p
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func screen(p: Vector2, height := 0.3) -> Vector2:
	return main.weather_view.camera.unproject_position(Vector3(p.x,height,p.y))
func count() -> int: return int(main.weather_audio.event_counts.get("brush",0))
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	main.weather_audio.set_focused(true)
	main.guide.cold_hint_seen = true
	var audio: Node = main.weather_audio
	audio.brush_rng.seed = 12345
	check(audio.BRUSH_NAMES.all(func(name): return audio.streams.has(name)),"All five promoted samples are imported")
	check(audio.loops.size()==3 and audio.voices.size()==2,"No added playback voices")
	button(screen(Vector2(-5,2)),true)
	await create_timer(0.25).timeout
	check(count()==0,"Mouse down while stationary never sounds brush")
	button(screen(Vector2(-5,2)),false)
	await process_frame
	check(count()==0,"Click without movement stays silent")
	button(screen(Vector2(-5,2)),true)
	var height: float = main.wind_input.reference_height
	await create_timer(0.2).timeout
	motion(screen(Vector2(-4.875,2),height))
	main.wind_input.flush()
	check(count()==1,"First effective movement triggers exactly once")
	var first := String(audio.last_brush_variant)
	var voice: int = audio.brush_voice
	var slow_pitch: float = audio.voices[voice].pitch_scale
	var brush: Node = main.wind_input
	# Subsequent real motion in the same gesture changes speed while the native voice lives.
	await create_timer(0.025).timeout
	motion(screen(Vector2(-2,2),height))
	brush.flush()
	audio.update_audio(0.1,false)
	check(count()==1 and audio.last_brush_variant==first,"Rapid path segments do not restart or choose a new variation")
	check(audio.voices[voice].pitch_scale>slow_pitch and audio.voices[voice].pitch_scale<=audio.settings.brush_pitch_range.y,"Actual hand speed smoothly raises pitch within configured range")
	await create_timer(0.8).timeout
	motion(screen(Vector2(-1,2),height))
	brush.flush()
	check(count()==1,"Same held gesture never replays after the sample ends")
	button(screen(Vector2(-1,2),height),false)
	await process_frame
	var variants: Array[String] = [first]
	for index in 9:
		await create_timer(0.22).timeout
		button(screen(Vector2(-5,2)),true)
		height = brush.reference_height
		await create_timer(0.035).timeout
		motion(screen(Vector2(-4,2),height))
		brush.flush()
		button(screen(Vector2(-4,2),height),false)
		await process_frame
		variants.append(audio.last_brush_variant)
	check(count()==10,"Ten real drags produce ten brush sounds")
	check(variants.slice(0,5).all(func(v): return variants.slice(0,5).count(v)==1) and variants.slice(5,10).all(func(v): return variants.slice(5,10).count(v)==1),"Every bag contains each variation exactly once")
	var repeated := false
	for index in range(1,variants.size()): repeated = repeated or variants[index]==variants[index-1]
	check(not repeated,"No consecutive repeat, including bag boundaries")
	seed(7654)
	var expected_random := randf()
	seed(7654)
	audio._next_brush()
	check(randf()==expected_random,"Variant selection does not consume global weather randomness")
	audio.cue("success")
	for player in audio.voices:
		if player.stream==audio.streams.success: check(player.pitch_scale==1,"Feedback never inherits a brush pitch")
	# Cancel/pause/focus must not resume an old gesture or leave a playing brush voice.
	button(screen(Vector2(-5,2)),true)
	main.paused = true
	brush.cancel()
	audio.update_audio(0.1,true)
	check(audio.brush_voice==-1 and not brush.dragging,"Pause clears voice and gesture")
	main.paused = false
	audio.update_audio(0.1,false)
	motion(screen(Vector2(-3,2)))
	check(count()==10,"Resume without a new press does not start a sound")
	audio.set_focused(false)
	brush.cancel()
	audio.set_focused(true)
	check(audio.brush_voice==-1,"Focus return does not restore an old voice")
	audio.set_options(false,audio.master_volume,false)
	button(screen(Vector2(-5,2)),true)
	height = brush.reference_height
	motion(screen(Vector2(-4,2),height))
	brush.flush()
	audio.set_options(true,audio.master_volume,false)
	motion(screen(Vector2(-3,2),height))
	brush.flush()
	check(count()==10,"Unmuting mid-gesture does not retroactively play it")
	button(screen(Vector2(-3,2),height),false)
	# The summary is driven by actual water; equal-power rain handoff has no stale light drops at full rain.
	var i: int = audio.visible_cells[audio.visible_cells.size()/2]
	main.sim.ground_rain.fill(0)
	main.sim.ground_rain[i] = 2
	audio._sample_weather()
	check(audio.target_levels.y==0 and audio.target_levels.z>0,"Strong actual rain hands off fully to candidate A")
	main.sim.ground_rain[i] = 0.05
	audio._sample_weather()
	check(audio.target_levels.y>0 and audio.target_levels.z==0,"Light actual rain keeps separate fine droplets")
	main.sim.ground_rain.fill(0)
	audio._sample_weather()
	check(audio.target_levels.y==0 and audio.target_levels.z==0,"No released rain means both rain layers silent")
	main.sim.low_wind.fill(Vector2(2,0))
	main.sim.cold_flow.fill(Vector2.ZERO)
	audio._sample_weather()
	for frame in 20: audio.update_audio(0.1,false)
	var ordinary: float = audio.current_levels.x
	main.sim.add_wind_source(Vector2(-5,2),Vector2.RIGHT,0.5,Vector2(-3,2))
	for frame in 20: audio.update_audio(0.1,false)
	check(audio.current_levels.x>ordinary*2,"Persistent field gently expands beyond a light ordinary brush bed")
	var before: float = audio.current_levels.x
	main.sim.remove_wind_source(main.sim.wind_sources[0].id)
	audio.update_audio(0.1,false)
	check(audio.current_levels.x>before*.85,"Closing a source preserves a smooth audible residual tail")
	var invalid = audio.settings.duplicate()
	invalid.brush_pitch_range = Vector2(1.2,0.9)
	invalid.heavy_rain_range = Vector2(0.8,0.1)
	check(invalid.validation_errors().size()==2,"Invalid pitch and rain crossover ranges are rejected")
	main.restart(false)
	main.set_process(false)
	check(audio.last_brush_gesture==-1 and audio.brush_bag.is_empty() and audio.brush_voice==-1,"Retry resets gesture, bag and voice together")
	var report := {"checks":checks,"failures":failures,"variants":variants,"ordinary_bed":ordinary,"field_bed":before}
	FileAccess.open("res://.godot/audio-gestures-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	main.queue_free()
	await process_frame
	print("AUDIO GESTURES: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
