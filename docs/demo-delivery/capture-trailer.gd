extends "res://tests/replay_star_viewport.gd"
## Trailer-only native Movie Maker capture. Weather changes only through normal input.
var shot := "journey"
var duration := 43.0
var frame_zero := 0
var destination := ""
var samples: Array = []
var source_action: Dictionary = {}
var source_removal: Dictionary = {}
var sample_at := 0.0
var camera_offset := Vector3(11.7, 14.2, 18.0)
var recording := false
var capture_fps := 60.0
var capture_root := "res://.godot/trailer-20261020/"

func movie_time() -> float:
    return float(Engine.get_process_frames() - frame_zero) / capture_fps

func frame_note() -> void:
    if not recording: return
    # Recording runs without desktop focus; production focus behaviour is unchanged.
    main.weather_audio.set_focused(true)
    var t := movie_time()
    var target := Vector3(-1.5, 0.8, 0.9)
    var size := 16.0
    if shot == "journey":
        var progress := smoothstep(0.0, 32.0, t)
        target = Vector3(-3.1, 0.9, 1.0).lerp(Vector3(-0.8, 0.8, 0.8), progress)
        size = lerpf(13.0, 17.2, progress)
    elif shot == "garden":
        target = Vector3(-1.6, 0.9, 1.3)
        size = lerpf(14.5, 12.6, smoothstep(0.0, 32.0, t))
    elif shot == "storm":
        target = Vector3(-0.8, 1.0, -1.2)
        size = lerpf(21.0, 19.0, smoothstep(0.0, 12.0, t))
    var camera: Camera3D = main.weather_view.camera
    camera.position = target + camera_offset
    camera.look_at(target)
    camera.size = size
    if t >= sample_at:
        sample_at += 0.5
        samples.append({"movie_seconds": t, "simulation_seconds": main.sim.elapsed_seconds,
            "water": Array(main.sim.plot_waters), "rain_rate": main.sim.total_rain_rate,
            "cloud_peak": main.sim.peak_density, "outcome": main.sim.outcome,
            "sources": main.sim.wind_sources.size(), "wetness": Array(main.weather_view.plot_wetness),
            "destroyed": main.sim.plot_destroyed.duplicate(),
            "camera_size": size, "camera_target": [target.x, target.y, target.z]})

func close_source() -> void:
    # Use the real native close button; the few HUD frames are omitted from the edit.
    main.hud.show()
    await process_frame
    await RenderingServer.frame_post_draw
    var control: Button = main.hud.source_remove[0]
    assert(control.is_visible_in_tree() and not control.disabled)
    var point := control.get_global_rect().get_center()
    button(point, true)
    await process_frame
    await process_frame
    button(point, false)
    await process_frame
    main.hud.hide()
    source_removal = {"movie_seconds": movie_time(), "remaining": main.sim.wind_sources.size()}
    assert(source_removal.remaining == 0)

func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--shot="): shot = arg.trim_prefix("--shot=")
        if arg.begins_with("--duration="): duration = float(arg.trim_prefix("--duration="))
        if arg.begins_with("--record-root="): capture_root = arg.trim_prefix("--record-root=")
    destination = capture_root.path_join(shot) + "/"
    DirAccess.make_dir_recursive_absolute(destination)
    main = load("res://scenes/main.tscn").instantiate()
    main.persist_progress = false
    main.show_learning_briefings = false
    root.add_child(main)
    await process_frame
    if main.hud == null or main.weather_audio == null:
        push_error("Incomplete recording project; no valid footage recorded")
        quit(1)
        return
    var expected := {"journey": "level01", "garden": "level05", "storm": "level09"}
    assert(main.sim.layout_id == expected[shot] and not main.sim.sandbox)
    main.hud.hide()
    main.weather_audio.set_music_volume(0.0, false)
    main.guide.cold_hint_seen = true
    var initial_water: float = main.sim.water_total()
    var initial_peak: float = main.sim.peak_density
    frame_zero = Engine.get_process_frames()
    recording = true
    process_frame.connect(frame_note)
    var controller := Route.new([0] if shot == "journey" else ([0, 1] if shot == "garden" else [1, 0, 2]), "mountain")
    if shot == "garden":
        # Earlier player decisions, not modified simulation thresholds.
        controller.farm_lookahead = 7.0
        controller.farm_floor_fraction = 0.2
    var next_at := 0.45
    var band_attempted := false
    while movie_time() < duration:
        if shot == "garden" and not band_attempted and movie_time() >= 0.6:
            band_attempted = true
            assert(main.wind_input.select_tool("source"))
            await stroke({"from": Vector2(-8.0, 2.0), "to": Vector2(-2.7, 1.6), "speed": 9.0})
            source_action = {"movie_seconds": movie_time(), "created": main.sim.wind_sources.size() == 1}
            assert(source_action.created)
            assert(main.wind_input.select_tool("brush"))
        if shot == "garden" and source_removal.is_empty() and movie_time() >= 5.5:
            await close_source()
        if main.sim.outcome == "playing" and main.sim.elapsed_seconds >= next_at:
            var t: float = main.sim.elapsed_seconds
            next_at = t + 0.5
            var command := controller.next_command(main.sim, t)
            if not command.is_empty(): await stroke(command)
        await process_frame
    recording = false
    process_frame.disconnect(frame_note)
    var report := controller.report(main.sim)
    report.merge({"shot": shot, "movie_seconds": movie_time(), "movie_frame_zero": frame_zero,
        "events": events, "failures": failures, "blocked": blocked, "input_pick_error": input_pick_error,
        "initial_water": initial_water, "initial_cloud_peak": initial_peak,
        "weather_injected": false, "sandbox": main.sim.sandbox, "camera_changed": true,
        "hud_hidden": true, "native_movie_maker": true, "movie_fps": capture_fps,
        "source_action": source_action, "source_removal": source_removal, "samples": samples,
        "audio_events": main.weather_audio.event_counts.duplicate(),
        "audio_variants": main.weather_audio.brush_variant_counts.duplicate()})
    FileAccess.open(destination + "capture.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
    report.erase("samples")
    report.erase("actions")
    print("TRAILER CAPTURE ", JSON.stringify(report))
    main.queue_free()
    main = null
    await process_frame
    await process_frame
    quit(0 if failures == 0 and blocked == 0 and input_pick_error < 0.001 else 1)
