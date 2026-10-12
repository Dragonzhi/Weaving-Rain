@tool
extends EditorNode3DGizmoPlugin
var undo_manager: EditorUndoRedoManager

func _init() -> void:
	create_handle_material("handles")
	create_material("boundary", Color(0.8, 0.9, 0.8))

func _has_gizmo(node: Node3D) -> bool:
	return node is WRMapAuthor

func _get_gizmo_name() -> String:
	return "风织雨地图"

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node: WRMapAuthor = gizmo.get_node_3d()
	var points := PackedVector3Array()
	for data in node.handle_data(): points.append(data.p)
	gizmo.add_handles(points, get_material("handles", gizmo), PackedInt32Array())
	var lines := PackedVector3Array([Vector3(-12, 0.3, -10), Vector3(12, 0.3, -10), Vector3(12, 0.3, -10), Vector3(12, 0.3, 10), Vector3(12, 0.3, 10), Vector3(-12, 0.3, 10), Vector3(-12, 0.3, 10), Vector3(-12, 0.3, -10)])
	gizmo.add_lines(lines, get_material("boundary", gizmo))

func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return gizmo.get_node_3d().handle_data()[id].label

func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().handle_value(id)

func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node: WRMapAuthor = gizmo.get_node_3d()
	var data := node.handle_data()[id]
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var local_origin := node.to_local(origin)
	var local_direction := node.global_basis.inverse() * direction
	if data.kind == "mountain_height":
		var m := node.map_definition.mountains[data.index]
		var closest := Geometry3D.get_closest_points_between_segments(Vector3(m.position.x, 0.25, m.position.y), Vector3(m.position.x, 8, m.position.y), local_origin, local_origin + local_direction * 100)
		node.apply_handle(id, clampf(closest[0].y - 0.25, 0.1, 2.5))
		return
	var hit = Plane(Vector3.UP, data.p.y).intersects_ray(local_origin, local_direction)
	if hit == null: return
	var p := Vector2(hit.x, hit.z)
	match data.kind:
		"axis_x": node.apply_handle(id, Vector2(maxf(0.5, absf(p.x - node.map_definition.island_center.x)), node.map_definition.island_axes.y))
		"axis_z": node.apply_handle(id, Vector2(node.map_definition.island_axes.x, maxf(0.5, absf(p.y - node.map_definition.island_center.y))))
		"mountain_radius": node.apply_handle(id, clampf(p.distance_to(node.map_definition.mountains[data.index].position), 0.25, 5.0))
		_: node.apply_handle(id, p)

func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node: WRMapAuthor = gizmo.get_node_3d()
	if cancel:
		node.apply_handle(id, restore)
		return
	var value = node.handle_value(id)
	undo_manager.create_action("调整" + node.handle_data()[id].label, UndoRedo.MERGE_DISABLE, node.map_definition)
	undo_manager.add_do_method(node, "apply_handle", id, value)
	undo_manager.add_undo_method(node, "apply_handle", id, restore)
	undo_manager.commit_action(false)
