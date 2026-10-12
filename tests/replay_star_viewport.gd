extends SceneTree
## Complete normal-start route through actual picking, mouse events and main-loop timing.
const Sim = preload("res://scripts/weather_simulation.gd")
const Route = preload("res://tests/star_route.gd")
var main: Node3D
var failures := 0
var events := 0
var blocked := 0
var pick_error := 0.0
var input_pick_error := 0.0
var cloud_presses := 0

func _init() -> void:
	call_deferred("run")

func button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	root.push_input(event, true)
	events += 1

func stroke(command: Dictionary) -> void:
	var camera: Camera3D = main.weather_view.camera
	var a: Vector2 = command.from
	var b: Vector2 = command.to
	var height: float = main.sim.terrain.height(a) + 0.30
	var screen := Vector2.ZERO
	var closest := INF
	# Select a visible point along the intended column; foreground clouds may hide low air.
	# Picking remains the normal input path, with no forced height or weather alteration.
	for n in 36:
		var candidate := camera.unproject_position(Vector3(a.x, lerpf(height, Sim.CLOUD_TOP, n / 35.0), a.y))
		var hit: Vector3 = main.wind_input.pick(candidate)
		var error := Vector2(hit.x, hit.z).distance_to(a)
		if error < closest:
			closest = error
			screen = candidate
	if main.hud.blocks_wind(screen) or not root.get_visible_rect().has_point(screen):
		blocked += 1
		return
	var expected: Vector3 = main.wind_input.pick(screen)
	if main.sim.pick_cloud(camera.project_ray_origin(screen), camera.project_ray_normal(screen)) != null: cloud_presses += 1
	button(screen, true)
	if not main.wind_input.dragging:
		failures += 1
		return
	var actual: Vector2 = Vector2(main.wind_input.brush_point.x, main.wind_input.brush_point.z)
	input_pick_error = maxf(input_pick_error, main.wind_input.brush_point.distance_to(expected))
	pick_error = maxf(pick_error, actual.distance_to(a))
	height = main.wind_input.reference_height
	var started := Time.get_ticks_usec()
	var duration: float = a.distance_to(b) / command.speed
	while main.sim.outcome == "playing":
		var fraction := minf(1.0, (Time.get_ticks_usec() - started) / 1000000.0 / duration)
		var p := a.lerp(b, fraction)
		screen = camera.unproject_position(Vector3(p.x, height, p.y))
		var event := InputEventMouseMotion.new()
		event.position = screen
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)
		events += 1
		if fraction >= 1.0: break
		await process_frame
	button(screen, false)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await RenderingServer.frame_post_draw
	main.guide.cold_hint_seen = true
	var controller := Route.new([0, 1, 2], "mountain")
	var next_at := 0.5
	var captured_rain := false
	var captured_feedback := false
	while main.sim.outcome == "playing":
		if main.sim.elapsed_seconds >= next_at:
			var command := controller.next_command(main.sim, main.sim.elapsed_seconds)
			next_at += 0.5
			if not command.is_empty(): await stroke(command)
		if not captured_rain and main.sim.plot_waters[0] >= 60.0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/star-route-viewport-rain.png")
			captured_rain = true
		if not captured_feedback and Array(main.hud.feedback_left).max() > 0.0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/star-route-viewport-feedback.png")
			captured_feedback = true
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/star-route-viewport-result.png")
	var report := controller.report(main.sim)
	report["events"] = events
	report["blocked"] = blocked
	report["pick_error"] = pick_error
	report["input_pick_error"] = input_pick_error
	report["cloud_presses"] = cloud_presses
	report["input_disabled"] = not main.wind_input.enabled
	report["recorded"] = main.result_recorded
	var file := FileAccess.open("res://.godot/star-viewport.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	report.erase("actions")
	print("STAR VIEWPORT ", JSON.stringify(report))
	if main.sim.result_stars != 3 or main.sim.timed_out or main.sim.sandbox or main.wind_input.enabled or input_pick_error > 0.001 or cloud_presses == 0 or failures > 0: failures += 1
	quit(0 if failures == 0 else 1)
