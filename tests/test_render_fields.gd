extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await RenderingServer.frame_post_draw
	main.set_process(false)
	main.restart(false)
	var view: Node3D = main.weather_view
	var wet := Vector2(-6.2, 1.4)
	view.vapor_positions.fill(wet)
	var water: float = main.sim.water_total()
	view.update_weather(0.0, false)
	var initial_vertices: PackedVector3Array = view.line_vertices.duplicate()
	view.update_weather(0.5, true)
	check(view.line_vertices != initial_vertices, "Still moist air has a local visible animation")
	var stationary := true
	for p in view.vapor_positions:
		stationary = stationary and p == wet
	check(stationary and main.sim.water_total() == water, "Idle moisture animation adds neither horizontal wind nor simulated water")
	var frozen_vertices: PackedVector3Array = view.line_vertices.duplicate()
	var frozen_time: float = view.elapsed
	view.update_weather(1.0, false)
	check(view.elapsed == frozen_time and view.line_vertices == frozen_vertices, "Pause freezes moisture motion and breathing")
	# More rainy cells than the visual budget, spanning both targets.
	main.sim.cloud.fill(2.0)
	main.sim.rain.fill(2.0)
	main.sim.sandbox = true
	main.sim.refresh_display()
	view.update_weather(0.1, true)
	check(view.rainfall.visible_instance_count == view.RAIN_COUNT, "Large rain fields respect the fixed visual budget")
	var inside := true
	var near_a := false
	var near_b := false
	for drop in view.rain_indices:
		var cell := int(drop / 9)
		var p: Vector2 = main.sim.positions[cell]
		var anchor: Vector3 = view.rain_anchors[drop]
		inside = inside and main.sim.rain[cell] > 0.0 and absf(anchor.x - p.x) <= Sim.CELL * 0.5 and absf(anchor.z - p.y) <= Sim.CELL * 0.5
		near_a = near_a or (absf(p.x - Sim.PLOT.x) <= Sim.PLOT_HALF and absf(p.y - Sim.PLOT.y) <= Sim.PLOT_HALF)
		near_b = near_b or (absf(p.x - Sim.SECOND_PLOT.x) <= Sim.PLOT_HALF and absf(p.y - Sim.SECOND_PLOT.y) <= Sim.PLOT_HALF)
	check(inside, "Every GPU rain column remains inside an actually rainy simulation cell")
	check(near_a and near_b, "Capped heavy rain still represents both target areas")
	var shared_drop: Mesh = view.rainfall.mesh
	var original_drop := BoxMesh.new()
	original_drop.size = Vector3(0.018,0.22,0.018)
	var shared_arrays := shared_drop.surface_get_arrays(0)
	var original_arrays := original_drop.surface_get_arrays(0)
	check(shared_arrays[Mesh.ARRAY_VERTEX].size()==8 and shared_arrays[Mesh.ARRAY_INDEX].size()==36,"Rain occlusion runs on eight shared corners while keeping all twelve box triangles")
	var same_triangles := true
	for index in 36:
		same_triangles = same_triangles and shared_arrays[Mesh.ARRAY_VERTEX][shared_arrays[Mesh.ARRAY_INDEX][index]] == original_arrays[Mesh.ARRAY_VERTEX][original_arrays[Mesh.ARRAY_INDEX][index]]
	check(same_triangles,"Shared rain vertices retain every original triangle position and winding")
	main.hud.visible = false
	view.rainfall.mesh = original_drop
	await process_frame
	await RenderingServer.frame_post_draw
	var original_pixels: PackedByteArray = root.get_texture().get_image().get_data()
	view.rainfall.mesh = shared_drop
	await process_frame
	await RenderingServer.frame_post_draw
	var shared_pixels: PackedByteArray = root.get_texture().get_image().get_data()
	check(shared_pixels==original_pixels,"Actual GPU rain pixels are byte-identical with shared vertices")
	var visible_drops: int = view.rainfall.visible_instance_count
	view.rainfall.visible_instance_count = 0
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data()!=shared_pixels,"GPU equality comparison includes actually visible rain")
	view.rainfall.visible_instance_count = visible_drops
	main.hud.visible = true
	var uploads: int = view.rain_uploads
	var anchors: PackedFloat32Array = view.rainfall.buffer.duplicate()
	view.update_weather(0.3, true)
	check(view.rain_uploads == uploads and view.rainfall.buffer == anchors, "GPU drop motion reuses unchanged column data")
	check(is_equal_approx(view.rain_material.get_shader_parameter("visual_time"), view.elapsed), "Rain animation reads the actual visual clock")
	frozen_time = view.elapsed
	view.update_weather(1.0, false)
	check(view.rain_material.get_shader_parameter("visual_time") == frozen_time, "Paused rain animation also freezes on GPU")
	main.sim.rain.fill(0.0)
	main.sim.refresh_display()
	view.update_weather(0.0, false)
	check(view.rainfall.visible_instance_count == 0 and view.rain_indices.is_empty(), "Stopped rain removes all displayed drops without leftover particles")
	await process_frame
	await RenderingServer.frame_post_draw
	# Bound must never underestimate the full B-spline footprint, including edges.
	for i in Sim.COUNT:
		main.sim.cloud[i] = fposmod(i * 0.071, 3.2) if i % 7 == 0 else 0.0
	main.sim.refresh_display()
	view.update_weather(0.0, false)
	await process_frame
	await RenderingServer.frame_post_draw
	var bounds_image: Image = view.cloud_bounds_viewport.get_texture().get_image()
	var conservative := true
	for z in Sim.DEPTH:
		for x in Sim.WIDTH:
			var maximum := 0.0
			for dz in range(-1, 3):
				for dx in range(-1, 3):
					maximum = maxf(maximum, main.sim.display_cloud[clampi(z + dz, 0, Sim.DEPTH - 1) * Sim.WIDTH + clampi(x + dx, 0, Sim.WIDTH - 1)])
			conservative = conservative and bounds_image.get_pixel(x, z).r >= maximum
	check(conservative, "GPU empty-space bounds never underestimate any current cloud footprint")
	for scenario in ["zero","nonzero","zero_again","signed_zero"]:
		main.sim.charge.fill(0.0)
		if scenario == "nonzero": main.sim.charge[13] = 0.6
		if scenario == "signed_zero": main.sim.charge[13] = -0.0
		main.sim.refresh_display()
		var expected: PackedFloat32Array = main.sim._smooth(main.sim.charge)
		check(main.sim.display_charge.to_byte_array() == expected.to_byte_array(),"Charge smoothing preserves exact zero/nonzero transitions and development injection: " + scenario)
	print("RENDER FIELD TESTS: ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
