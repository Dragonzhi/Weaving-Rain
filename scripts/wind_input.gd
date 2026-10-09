extends Node
signal stroke_applied(from: Vector2, to: Vector2, height: float)
const Sim = preload("res://scripts/weather_simulation.gd")
var sim: RefCounted
var camera: Camera3D
var dragging := false
var enabled := true
var hover_valid := false
var reference_height := 0.4
var brush_point := Vector3.ZERO
var last_point := Vector2.ZERO
var last_time := 0
var last_force := 0.0
var hud: Control

func setup(model: RefCounted, view_camera: Camera3D) -> void:
	sim = model
	camera = view_camera

func cancel() -> void:
	dragging = false
	last_force = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel()

func _on_plane(screen: Vector2, height: float) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func pick(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var cloud_hit: Variant = sim.pick_cloud(origin, direction)
	if cloud_hit != null:
		return cloud_hit
	# Trace the same terrain height function used to construct the visible island.
	var start: Variant = _on_plane(screen, 3.15)
	var end: Variant = _on_plane(screen, 0.20)
	if start == null or end == null:
		return Vector3(Sim.ORIGIN.x - 1.0, 0.0, Sim.ORIGIN.y - 1.0)
	var previous: Vector3 = start
	for i in 65:
		var p: Vector3 = start.lerp(end, float(i) / 64.0)
		var surface := Sim.terrain_height(Vector2(p.x, p.z)) + 0.30
		if p.y <= surface:
			var high := previous
			var low := p
			for refinement in 7:
				var mid := high.lerp(low, 0.5)
				if mid.y > Sim.terrain_height(Vector2(mid.x, mid.z)) + 0.30:
					high = mid
				else:
					low = mid
			return high.lerp(low, 0.5)
		previous = p
	return end

func update_hover() -> void:
	if not enabled or sim.outcome != "playing":
		hover_valid = false
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		hover_valid = false
		return
	var screen := get_viewport().get_mouse_position()
	if hud != null and hud.blocks_wind(screen):
		hover_valid = false
		return
	if not get_viewport().get_visible_rect().has_point(screen):
		hover_valid = false
		return
	if dragging:
		var point: Variant = _on_plane(screen, reference_height)
		if point != null:
			brush_point = point
	else:
		brush_point = pick(screen)
	hover_valid = Sim.contains(Vector2(brush_point.x, brush_point.z))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			cancel()
			return
		if not enabled or sim.outcome != "playing":
			return
		if hud != null and hud.blocks_wind(event.position):
			return
		brush_point = pick(event.position)
		if not Sim.contains(Vector2(brush_point.x, brush_point.z)):
			return
		reference_height = brush_point.y
		last_point = Vector2(brush_point.x, brush_point.z)
		last_time = Time.get_ticks_usec()
		dragging = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		if not enabled:
			cancel()
			return
		var hit: Variant = _on_plane(event.position, reference_height)
		if hit == null:
			return
		brush_point = hit
		var point := Vector2(brush_point.x, brush_point.z)
		var now := Time.get_ticks_usec()
		var dt := maxf(float(now - last_time) / 1000000.0, 0.001)
		var speed := point.distance_to(last_point) / dt
		sim.stroke(last_point, point, speed)
		if point.distance_to(last_point) > 0.001:
			stroke_applied.emit(last_point, point, reference_height)
		last_force = minf(speed / 16.0, 1.0)
		last_point = point
		last_time = now
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragging and hud != null and hud.blocks_wind(event.position):
		cancel()
	# Release is observed even if the cursor finishes over a UI button.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel()
