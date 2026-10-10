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
	print("RENDER FIELD TESTS: ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
