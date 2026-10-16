extends SceneTree
## Run with the fixed GPU renderer; writes menu images only, never maps or player data.
const Sim = preload("res://scripts/weather_simulation.gd")
const View = preload("res://scripts/weather_view.gd")
const Loader = preload("res://scripts/config_loader.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var settings := Loader.settings("res://configs/weather.tres")
	if not settings.errors.is_empty():
		push_error("；".join(settings.errors)); quit(1); return
	var loaded := Loader.campaign("res://configs/campaign.tres",settings.resource.plot_half)
	if not loaded.errors.is_empty():
		push_error("；".join(loaded.errors)); quit(1); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,540)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var output := "res://assets/ui/level_previews/"
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.make_dir_recursive_absolute("res://.godot/level-preview-build/")
	var count := 0
	for definition in [loaded.resource.tutorial]+Array(loaded.resource.levels):
		var model := Sim.new(settings.resource,true,false,definition.id,definition)
		var view := View.new()
		viewport.add_child(view)
		view.setup(model)
		view.hints_enabled = false
		view.update_weather(0,false)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.resize(640,360,Image.INTERPOLATE_LANCZOS)
		var temporary: String = "res://.godot/level-preview-build/"+definition.id+".png"
		var error := image.save_png(temporary)
		if error == OK: error = DirAccess.rename_absolute(temporary,output+definition.id+".png")
		if error != OK:
			push_error("缩略图保留："+definition.id+" "+error_string(error)); quit(1); return
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.remove_child(view)
		view.queue_free()
		count += 1
		print("PREVIEW ",definition.id)
	viewport.queue_free()
	print("LEVEL PREVIEWS: ",count," images; no simulation steps or player writes")
	quit()
