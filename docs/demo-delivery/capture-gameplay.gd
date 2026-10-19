extends "res://tests/replay_star_viewport.gd"
## Marketing capture only: official maps, ordinary viewport input, no field injection.
var shot := "mountain"
var destination := ""
var recording := false
var photo_pause := false
var started_us := 0
var previous_frame_us := -1000000
var frames: Array = []
var photos: Array = []
var mixer := preload("res://tests/audio_route_record.gd").new()
var actions: Array = []
func tap(control: Control) -> void:
    var p := control.get_global_rect().get_center()
    button(p,true)
    await create_timer(0.12).timeout
    button(p,false)
    await process_frame
func button(point: Vector2, pressed: bool) -> void:
    super.button(point,pressed)
    if pressed and main.wind_input.dragging and main.wind_input.tool in ["source","vortex"]:
        var wheel := InputEventMouseButton.new()
        wheel.position=point
        wheel.button_index=MOUSE_BUTTON_WHEEL_UP
        wheel.pressed=true
        root.push_input(wheel,true)
        events+=1
func record_frame() -> void:
    if not recording or photo_pause: return
    var now := Time.get_ticks_usec()-started_us
    if now-previous_frame_us < 1000000.0/24.0: return
    previous_frame_us=now
    var name := "frame-%05d.jpg" % frames.size()
    var image := root.get_texture().get_image()
    if image.save_jpg(destination+name,0.95)!=OK:
        failures+=1
        return
    frames.append({"file":name,"wall_seconds":now/1000000.0,"simulation_seconds":main.sim.elapsed_seconds})
    mixer.sample()
func photo(index: int) -> void:
    var hover := InputEventMouseMotion.new()
    hover.position=Vector2(70,root.get_visible_rect().size.y*0.55)
    root.push_input(hover,true)
    await process_frame
    photo_pause=true
    main.set_process(false)
    await RenderingServer.frame_post_draw
    var name := "photo-%02d" % index
    root.get_texture().get_image().save_png(destination+name+"-hud.png")
    main.hud.visible=false
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    assert(image.get_size()==Vector2i(1920,1080))
    image.save_png(destination+name+"-clean.png")
    photos.append({"name":name,"wall_seconds":(Time.get_ticks_usec()-started_us)/1000000.0,"simulation_seconds":main.sim.elapsed_seconds,"water":Array(main.sim.plot_waters),"rain_rate":main.sim.total_rain_rate,"sources":main.sim.wind_sources.size()})
    main.hud.visible=true
    main.set_process(true)
    photo_pause=false
func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--shot="): shot=arg.trim_prefix("--shot=")
    destination="res://.godot/demo-media/"+shot+"/"
    DirAccess.make_dir_recursive_absolute(destination)
    main=load("res://scenes/main.tscn").instantiate()
    main.persist_progress=false
    root.add_child(main)
    await process_frame
    await RenderingServer.frame_post_draw
    assert(not main.sim.sandbox)
    var expected_map := {"mountain":"level03","tools":"level07","storm":"level08"}
    if main.sim.layout_id!=expected_map[shot]:
        push_error("Capture map mismatch: "+main.sim.layout_id)
        quit(1)
        return
    var cloud_at_start: float=main.sim.peak_density
    main.weather_audio.set_music_volume(0,false)
    mixer.start(main)
    started_us=Time.get_ticks_usec()
    recording=true
    RenderingServer.frame_post_draw.connect(record_frame)
    var controller := Route.new([1,0] if shot=="storm" else ([1,0,2] if shot=="tools" else [0,1]),"mountain")
    var next_at := 0.5
    var photo_times := [5.0,9.0,13.0,18.0,23.0]
    var photo_index := 0
    var vortex_created := false
    var band_created := false
    var hints_opened := false
    var limit := 26.0 if shot=="mountain" else 22.0
    while main.sim.outcome=="playing" and main.sim.elapsed_seconds<limit and Time.get_ticks_usec()-started_us<120000000:
        if main.hud.dismiss_hint.visible:
            await tap(main.hud.dismiss_hint)
        var t: float=main.sim.elapsed_seconds
        if shot=="tools":
            if not vortex_created and t>=0.6:
                await tap(main.hud.vortex_button)
                await stroke({"from":Vector2(-6.1,0.93),"to":Vector2(-3.7,0.93),"speed":7.0})
                vortex_created=main.sim.wind_sources.size()==1
                actions.append({"kind":"vortex","created":vortex_created,"time":main.sim.elapsed_seconds})
                if not vortex_created: failures+=1; break
            if not band_created and t>=6.0:
                await tap(main.hud.source_button)
                await stroke({"from":Vector2(-6.1,0.93),"to":Vector2(0.75,0.66),"speed":12.0})
                band_created=main.sim.wind_sources.size()==2
                actions.append({"kind":"band","created":band_created,"time":main.sim.elapsed_seconds})
                await tap(main.hud.brush_button)
                if not band_created: failures+=1; break
        if shot=="storm" and not hints_opened and t>=4.0:
            await tap(main.hud.arrows_button)
            hints_opened=true
        if t>=next_at and (shot!="tools" or t>=9.0):
            next_at=t+0.5
            var command := controller.next_command(main.sim,t)
            if not command.is_empty(): await stroke(command)
        if photo_index<photo_times.size() and main.sim.elapsed_seconds>=photo_times[photo_index]:
            await photo(photo_index)
            photo_index+=1
        await process_frame
    recording=false
    RenderingServer.frame_post_draw.disconnect(record_frame)
    var audio: Dictionary=mixer.finish(destination+"weather.wav")
    var report := {"shot":shot,"layout":main.sim.layout_id,"sandbox":main.sim.sandbox,"weather_injected":false,"camera_changed":false,"initial_cloud_peak":cloud_at_start,"frames":frames,"photos":photos,"events":events,"failures":failures,"blocked":blocked,"input_pick_error":input_pick_error,"water_error":main.sim.water_error(),"outcome":main.sim.outcome,"wall_seconds":(Time.get_ticks_usec()-started_us)/1000000.0,"sim_seconds":main.sim.elapsed_seconds,"vortex_created":vortex_created,"band_created":band_created,"actions":actions,"audio":audio}
    FileAccess.open(destination+"capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
    report.erase("frames")
    print("DEMO MEDIA ",JSON.stringify(report))
    quit(0 if failures==0 and blocked==0 and frames.size()>100 and input_pick_error<0.001 and main.sim.elapsed_seconds>=limit else 1)
