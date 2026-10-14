extends RefCounted
## Optional native mixer capture of existing real-input routes, never injects weather.
var main: Node
var effect: AudioEffectRecord
var peak_levels := Vector3.ZERO
var peak_voices := 0
var focus_restorations := 0
func start(scene: Node) -> void:
	if not "--audio-review" in OS.get_cmdline_user_args(): return
	main = scene
	main.weather_audio.set_focused(true)
	effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0,effect)
	effect.set_recording_active(true)
func sample() -> void:
	if effect == null: return
	# Background automation can receive desktop focus-out. Audition capture alone
	# restores listening; production focus mute is covered by test_audio_scene.
	if not main.weather_audio.focused:
		main.weather_audio.set_focused(true)
		focus_restorations += 1
	var levels: Vector3 = main.weather_audio.current_levels
	for index in 3: peak_levels[index] = maxf(peak_levels[index],levels[index])
	peak_voices = maxi(peak_voices,main.weather_audio.voices.filter(func(player): return player.playing).size())
func finish(path: String) -> Dictionary:
	if effect == null: return {}
	effect.set_recording_active(false)
	var recording := effect.get_recording()
	var result := recording.save_to_wav(path)
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	return {"wav":path,"save_error":result,"event_counts":main.weather_audio.event_counts.duplicate(),"brush_variants":main.weather_audio.brush_variant_counts.duplicate(),"peak_wind":peak_levels.x,"peak_rain":peak_levels.y,"peak_detail":peak_levels.z,"max_short_voices":peak_voices,"focus_restorations":focus_restorations}
