extends SceneTree
## Actual output aspect ratios and every existing map; UI geometry only.
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await RenderingServer.frame_post_draw
	main.set_process(false)
	for output in [Vector2i(1920, 1080), Vector2i(1280, 800), Vector2i(1024, 768)]:
		root.size = output
		await RenderingServer.frame_post_draw
		for id in ["standard", "far", "close", "ridges", "meadow", "valleys", "needs_lab"]:
			main.select_layout(id)
			main.hud.queue_redraw()
			await RenderingServer.frame_post_draw
			var rects: Array = main.hud.plot_label_rects
			var valid: bool = rects.size() == main.sim.plot_centers.size()
			for index in rects.size():
				valid = valid and root.get_visible_rect().encloses(rects[index]) and not rects[index].intersects(main.hud.wind_toolbar_rect) and not main.hud.blocks_wind(rects[index].get_center())
				for other in range(index): valid = valid and not rects[index].intersects(rects[other])
			checks += 1
			if not valid:
				failures += 1
				push_error("Plot water labels overlap, block input or leave viewport: %s / %s" % [id, output])
	print("HUD LAYOUTS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
