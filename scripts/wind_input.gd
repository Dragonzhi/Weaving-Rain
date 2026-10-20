extends Node
signal stroke_applied(from: Vector2, to: Vector2, height: float)
signal source_created
signal brush_motion(gesture: int, speed: float)
const Sim = preload("res://scripts/weather_simulation.gd")
var sim: Sim
var camera: Camera3D
var dragging := false
var enabled := true
var hover_valid := false
var hover_cloud := false
var gesture_cloud := false
var reference_height := 0.4
var brush_point := Vector3.ZERO
var last_point := Vector2.ZERO
var last_time := 0
var last_force := 0.0
var hud: Control
var path_points := PackedVector2Array()
var path_times := PackedFloat64Array()
var tool := "brush"
var source_tier := 1
var gesture_button: MouseButton = MOUSE_BUTTON_LEFT
var vortex_spin := 1
var vortex_radius_limits := Vector2(0.75, 5.0)
var gesture_start := Vector2.ZERO
var gesture_time := 0.0
var gesture_distance := 0.0
var gesture_direction := Vector2.ZERO
var gesture_strength := 0.0
var meaningful_distance := 0.0
var last_motion_seconds := 0.0
var gesture_id := 0
var message := ""
var message_until := 0

func setup(model: RefCounted, view_camera: Camera3D) -> void:
	cancel()
	sim = model
	camera = view_camera
	tool = "brush"
	if not get_viewport().mouse_exited.is_connected(_on_viewport_exit):
		get_viewport().mouse_exited.connect(_on_viewport_exit)

func _on_viewport_exit() -> void:
	flush()
	cancel()

func cancel() -> void:
	if sim != null: sim.clear_held_wind()
	dragging = false
	hover_cloud = false
	gesture_cloud = false
	gesture_distance = 0.0
	meaningful_distance = 0.0
	gesture_direction = Vector2.ZERO
	last_force = 0.0
	path_points.resize(0)
	path_times.resize(0)
	if is_instance_valid(hud): hud.sync_toolbar_input()

func append_point(point: Vector2, seconds: float) -> void:
	if tool == "vortex": return
	path_points.append(point)
	path_times.append(seconds)

func flush() -> void:
	if tool != "brush":
		path_points.resize(0)
		path_times.resize(0)
		return
	if path_points.size() < 2: return
	var emitted := path_points[0]
	var emitted_time := path_times[0]
	var carry := 0.0
	for i in range(1, path_points.size()):
		var a := path_points[i - 1]
		var b := path_points[i]
		var distance := a.distance_to(b)
		var along := 0.0
		while carry + distance - along >= 0.125:
			along += 0.125 - carry
			var fraction := along / distance
			var p := a.lerp(b, fraction)
			var time := lerpf(path_times[i - 1], path_times[i], fraction)
			apply_segment(emitted, p, emitted_time, time)
			emitted = p
			emitted_time = time
			carry = 0.0
		carry += distance - along
		var corner := false
		if i + 1 < path_points.size() and distance > 0.00001:
			var next := path_points[i + 1] - b
			corner = next.length() > 0.00001 and absf((b - a).angle_to(next)) > deg_to_rad(15.0)
		if corner or i == path_points.size() - 1:
			apply_segment(emitted, b, emitted_time, path_times[i])
			emitted = b
			emitted_time = path_times[i]
			carry = 0.0
	path_points = PackedVector2Array([emitted])
	path_times = PackedFloat64Array([emitted_time])

func apply_segment(a: Vector2, b: Vector2, from_time: float, to_time: float) -> void:
	if a.distance_to(b) < 0.00001: return
	var speed := a.distance_to(b) / maxf(to_time - from_time, 0.001)
	sim.stroke(a, b, speed)
	if a.distance_to(b) >= 0.0001: brush_motion.emit(gesture_id,speed)
	stroke_applied.emit(a, b, reference_height)
	last_force = minf(speed / sim.settings.stroke_speed_full, 1.0)
	meaningful_distance += a.distance_to(b)
	if meaningful_distance >= 0.125:
		gesture_direction = (b - a).normalized()
		gesture_strength = last_force

func tool_available(value: String) -> bool:
	return value in WRMapDefinition.WIND_TOOLS and (int(sim.layout.get("available_wind_tools",7)) & int(WRMapDefinition.WIND_TOOLS[value])) != 0

func select_tool(value: String) -> bool:
	if not tool_available(value): return false
	cancel()
	tool = value
	return true

func vortex_preview() -> Dictionary:
	var radius := gesture_start.distance_to(Vector2(brush_point.x, brush_point.z))
	var valid := radius >= vortex_radius_limits.x and radius <= vortex_radius_limits.y
	var reason := ("顺时针" if vortex_spin > 0 else "逆时针") + " · 半径 %.2f" % radius
	if radius < vortex_radius_limits.x: reason = "范围过小 · 半径 %.2f，至少 %.2f" % [radius,vortex_radius_limits.x]
	elif radius > vortex_radius_limits.y: reason = "范围过大 · 半径 %.2f，最多 %.1f" % [radius,vortex_radius_limits.y]
	return {"center": gesture_start, "radius": radius, "spin": vortex_spin, "tier": source_tier, "ok": valid, "reason": reason}

func update_held(now_seconds: float = -1.0) -> void:
	var now := Time.get_ticks_usec() / 1000000.0 if now_seconds < 0.0 else now_seconds
	if enabled and dragging and tool == "brush" and gesture_direction != Vector2.ZERO and now - last_motion_seconds >= 0.12:
		sim.set_held_wind(Vector2(brush_point.x, brush_point.z), gesture_direction, gesture_strength)
	else: sim.clear_held_wind()

func release_at(screen: Vector2) -> void:
	if not dragging: return
	var valid: bool = tool_available(tool) and get_viewport().get_visible_rect().has_point(screen) and (hud == null or not hud.blocks_wind(screen, true))
	if tool == "source" and valid and enabled:
		var hit: Variant = _on_plane(screen, reference_height)
		if hit != null and Sim.contains(Vector2(hit.x, hit.z)) and gesture_start.distance_to(Vector2(hit.x, hit.z)) >= 0.25:
			var end := Vector2(hit.x, hit.z)
			var result := sim.add_wind_source(gesture_start, end - gesture_start, source_tier / 2.0, end)
			if not result.ok:
				message = result.reason
				message_until = Time.get_ticks_msec() + 2500
			else: source_created.emit()
	elif tool == "vortex" and valid and enabled:
		var released: Variant = _on_plane(screen, reference_height)
		if released != null: brush_point = released
		var gesture := vortex_preview()
		var result := {"ok": false, "reason": gesture.reason}
		if gesture.radius < 0.25:
			cancel()
			return
		if gesture.ok and released != null and Sim.contains(Vector2(released.x, released.z)):
			result = sim.add_vortex(gesture.center, gesture.radius, gesture.spin, gesture.tier)
		elif gesture.ok:
			result.reason = "请在天气区域内松手"
		if not result.ok:
			message = result.reason
			message_until = Time.get_ticks_msec() + 2500
		else: source_created.emit()
	elif tool == "brush": flush()
	cancel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel()

func _on_plane(screen: Vector2, height: float) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func pick(screen: Vector2) -> Vector3:
	hover_cloud = false
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var cloud_hit: Variant = sim.pick_cloud(origin, direction)
	if cloud_hit != null:
		hover_cloud = true
		return cloud_hit
	# Trace the same terrain height function used to construct the visible island.
	var start: Variant = _on_plane(screen, 3.15)
	var end: Variant = _on_plane(screen, 0.20)
	if start == null or end == null:
		return Vector3(Sim.ORIGIN.x - 1.0, 0.0, Sim.ORIGIN.y - 1.0)
	var previous: Vector3 = start
	for i in 65:
		var p: Vector3 = start.lerp(end, float(i) / 64.0)
		var surface: float = sim.terrain.height(Vector2(p.x, p.z)) + 0.30
		if p.y <= surface:
			var high := previous
			var low := p
			for refinement in 7:
				var mid := high.lerp(low, 0.5)
				if mid.y > sim.terrain.height(Vector2(mid.x, mid.z)) + 0.30:
					high = mid
				else:
					low = mid
			return high.lerp(low, 0.5)
		previous = p
	return end

func update_hover() -> void:
	if not enabled or sim.outcome != "playing":
		hover_valid = false
		hover_cloud = false
		return
	if dragging:
		hover_valid = Sim.contains(Vector2(brush_point.x, brush_point.z))
		hover_cloud = gesture_cloud
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
	if not tool_available(tool):
		cancel()
		tool = "brush"
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if enabled and dragging and tool in ["source", "vortex"] and sim.outcome == "playing" and (hud == null or not hud.blocks_wind(event.position, true)):
			source_tier = clampi(source_tier + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, 2)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.button_index == MOUSE_BUTTON_RIGHT and tool != "vortex": return
		if not event.pressed:
			if event.button_index == gesture_button: release_at(event.position)
			return
		if dragging:
			get_viewport().set_input_as_handled()
			return
		if not enabled or sim.outcome != "playing":
			return
		if hud != null and hud.blocks_wind(event.position):
			return
		brush_point = pick(event.position)
		gesture_cloud = hover_cloud
		if not Sim.contains(Vector2(brush_point.x, brush_point.z)):
			return
		reference_height = brush_point.y
		last_point = Vector2(brush_point.x, brush_point.z)
		last_time = Time.get_ticks_usec()
		gesture_start = last_point
		gesture_id += 1
		gesture_button = event.button_index
		vortex_spin = 1 if gesture_button == MOUSE_BUTTON_LEFT else -1
		vortex_radius_limits = sim.settings.vortex_radius_limits
		source_tier = 1
		gesture_time = last_time / 1000000.0
		last_motion_seconds = gesture_time
		append_point(last_point, last_time / 1000000.0)
		dragging = true
		if is_instance_valid(hud): hud.sync_toolbar_input()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		if not get_viewport().get_visible_rect().has_point(event.position):
			flush()
			cancel()
			return
		if not enabled:
			cancel()
			return
		var hit: Variant = _on_plane(event.position, reference_height)
		if hit == null:
			return
		brush_point = hit
		var point := Vector2(brush_point.x, brush_point.z)
		if tool == "vortex" and not Sim.contains(point):
			cancel()
			message = "范围端点须在天气区域内"
			message_until = Time.get_ticks_msec() + 2500
			return
		var now := Time.get_ticks_usec()
		var distance := point.distance_to(last_point)
		gesture_distance += distance
		if distance > 0.00001:
			last_motion_seconds = now / 1000000.0
			sim.clear_held_wind()
		append_point(point, now / 1000000.0)
		last_point = point
		last_time = now
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not dragging: return
	# A gesture started in the scene owns input through the toolbar until release.
	# Menus/results still stop it; native controls never receive its mouse-up.
	if event is InputEventMouseMotion:
		if hud != null and hud.blocks_wind(event.position, true):
			flush()
			cancel()
			return
		_unhandled_input(event)
	elif event is InputEventMouseButton:
		if event.button_index == gesture_button and not event.pressed:
			release_at(event.position)
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_unhandled_input(event)
		get_viewport().set_input_as_handled()
