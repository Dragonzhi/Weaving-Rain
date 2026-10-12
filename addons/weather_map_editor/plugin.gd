@tool
extends EditorPlugin
const Gizmo = preload("res://addons/weather_map_editor/map_gizmo.gd")
var gizmo_plugin: EditorNode3DGizmoPlugin
var dock: VBoxContainer
var author: WRMapAuthor
var status: Label
var mountain_list: OptionButton
var air_list: OptionButton
var plot_list: OptionButton
var save_dialog: EditorFileDialog
var load_dialog: EditorFileDialog
var last_signature := 0

func _enter_tree() -> void:
	gizmo_plugin = Gizmo.new()
	gizmo_plugin.undo_manager = get_undo_redo()
	add_node_3d_gizmo_plugin(gizmo_plugin)
	dock = VBoxContainer.new()
	dock.name = "风织雨地图"
	var heading := Label.new()
	heading.text = "选中 MapAuthor 后拖动彩色手柄\n岛形预设及数值在属性面板编辑"
	dock.add_child(heading)
	button("打开地图属性", func(): if author != null: get_editor_interface().edit_resource(author.map_definition))
	button("加载地图…", func(): load_dialog.popup_centered_ratio(0.6))
	mountain_list = OptionButton.new()
	dock.add_child(mountain_list)
	button("添加山体", func(): add_entry("mountains"))
	button("删除所选山体", func(): remove_entry("mountains", mountain_list.selected))
	air_list = OptionButton.new()
	dock.add_child(air_list)
	button("添加湿空气", func(): add_entry("humidity_sources"))
	button("删除所选湿空气", func(): remove_entry("humidity_sources", air_list.selected))
	plot_list = OptionButton.new()
	dock.add_child(plot_list)
	button("添加地块（最多三处）", func(): change_plots(true))
	button("删除所选地块", func(): change_plots(false))
	button("保存地图", save_map)
	button("地图另存为…", func(): save_dialog.popup_centered_ratio(0.6))
	button("重置为原布局模板", func(): set_map(load("res://configs/maps/standard.tres").duplicate(true)))
	button("试玩当前地图", play_map)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 240
	dock.add_child(status)
	save_dialog = dialog(EditorFileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.file_selected.connect(save_as)
	load_dialog = dialog(EditorFileDialog.FILE_MODE_OPEN_FILE)
	load_dialog.file_selected.connect(load_map)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	status.text = "在场景树选中 MapAuthor 开始编辑。"
	if "--editor-map-check" in OS.get_cmdline_user_args(): call_deferred("editor_smoke")
	if "--editor-map-capture" in OS.get_cmdline_user_args(): call_deferred("editor_capture")

func button(text: String, action: Callable) -> void:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	dock.add_child(control)

func dialog(mode: EditorFileDialog.FileMode) -> EditorFileDialog:
	var control := EditorFileDialog.new()
	control.file_mode = mode
	control.access = EditorFileDialog.ACCESS_RESOURCES
	control.filters = PackedStringArray(["*.tres ; 地图资源"])
	control.current_dir = "res://configs/maps"
	dock.add_child(control)
	return control

func _exit_tree() -> void:
	if gizmo_plugin != null:
		remove_node_3d_gizmo_plugin(gizmo_plugin)
		gizmo_plugin = null
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null

func _handles(object: Object) -> bool:
	# Resource properties must remain in the Inspector instead of reopening our dock.
	return object is WRMapAuthor

func _edit(object: Object) -> void:
	if object is WRMapAuthor: author = object
	last_signature = 0

func _make_visible(visible: bool) -> void:
	if dock == null: return
	# Keep the dock's tab available; hiding its child also hides the parent dock slot.
	dock.show()
	if visible:
		last_signature = 0
		call_deferred("_show_dock")

func _show_dock() -> void:
	if dock != null and dock.is_inside_tree() and dock.get_parent().is_inside_tree(): dock.get_parent().call("make_visible")

func _process(_delta: float) -> void:
	if not is_instance_valid(author) or dock == null or not dock.visible: return
	var signature_value := author.signature()
	if signature_value == last_signature: return
	last_signature = signature_value
	var selected_mountain := mountain_list.selected
	var selected_air := air_list.selected
	var selected_plot := plot_list.selected
	mountain_list.clear()
	air_list.clear()
	plot_list.clear()
	for n in author.map_definition.mountains.size(): mountain_list.add_item("山 %d" % (n + 1))
	for n in author.map_definition.humidity_sources.size(): air_list.add_item("湿空气 %d" % (n + 1))
	for n in author.map_definition.plots.size(): plot_list.add_item("地块 " + String.chr(65 + n))
	if mountain_list.item_count > 0: mountain_list.select(clampi(selected_mountain, 0, mountain_list.item_count - 1))
	if air_list.item_count > 0: air_list.select(clampi(selected_air, 0, air_list.item_count - 1))
	if plot_list.item_count > 0: plot_list.select(clampi(selected_plot, 0, plot_list.item_count - 1))
	var settings := preload("res://scripts/config_loader.gd").settings("res://configs/weather.tres")
	var errors := author.map_definition.validation_errors(settings.resource.plot_half if settings.errors.is_empty() else 1.25)
	status.text = "地图有效，可保存并试玩。\n保存配置后，试玩中 F6 应用手感参数。" if errors.is_empty() else "需修正：\n" + "\n".join(errors)

func set_map(resource: WRMapDefinition) -> void:
	if not is_instance_valid(author): return
	var undo := get_undo_redo()
	undo.create_action("切换地图", UndoRedo.MERGE_DISABLE, author)
	undo.add_do_property(author, "map_definition", resource)
	undo.add_undo_property(author, "map_definition", author.map_definition)
	undo.commit_action()
	last_signature = 0

func add_entry(field: String) -> void:
	if not is_instance_valid(author): return
	var values: Array = author.map_definition.get(field).duplicate()
	if field == "mountains":
		var m := WRMountain.new()
		m.position = author.map_definition.island_center
		m.radius = 1.5
		m.height = 1.8
		values.append(m)
	else:
		var source := WRHumiditySource.new()
		source.position = author.map_definition.island_center
		values.append(source)
	change_collection(field, values)

func remove_entry(field: String, index: int) -> void:
	if not is_instance_valid(author): return
	var values: Array = author.map_definition.get(field).duplicate()
	if index < 0 or index >= values.size(): return
	values.remove_at(index)
	change_collection(field, values)

func change_collection(field: String, values: Array) -> void:
	var undo := get_undo_redo()
	undo.create_action("修改" + field, UndoRedo.MERGE_DISABLE, author.map_definition)
	undo.add_do_method(author, "apply_collection", field, values)
	undo.add_undo_method(author, "apply_collection", field, author.map_definition.get(field).duplicate())
	undo.commit_action()
	last_signature = 0

func change_plots(add: bool) -> void:
	if not is_instance_valid(author): return
	var points := author.map_definition.plots.duplicate()
	var regions: Array[WRPlotRegion] = author.map_definition.plot_regions.duplicate()
	while regions.size() < points.size(): regions.append(WRPlotRegion.new())
	if add:
		if points.size() >= 3: return
		points.append(author.map_definition.island_center)
		regions.append(WRPlotRegion.new())
	else:
		if points.size() <= 1 or plot_list.selected < 0: return
		regions.remove_at(plot_list.selected)
		points.remove_at(plot_list.selected)
	var undo := get_undo_redo()
	undo.create_action("修改地块", UndoRedo.MERGE_DISABLE, author.map_definition)
	undo.add_do_method(author, "apply_plots", points, regions)
	undo.add_undo_method(author, "apply_plots", author.map_definition.plots.duplicate(), author.map_definition.plot_regions.duplicate())
	undo.commit_action()
	last_signature = 0

func load_map(path: String) -> void:
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not resource is WRMapDefinition:
		status.text = "请选择 WRMapDefinition 地图资源。"
		return
	set_map(resource)

func save_map() -> void:
	if not is_instance_valid(author): return
	var path := author.map_definition.resource_path
	if path.is_empty() or "::" in path:
		save_dialog.popup_centered_ratio(0.6)
	else:
		save_as(path)

func save_as(path: String) -> void:
	if not is_instance_valid(author): return
	var tuning := preload("res://scripts/config_loader.gd").settings("res://configs/weather.tres")
	if not tuning.errors.is_empty() or not author.map_definition.validation_errors(tuning.resource.plot_half).is_empty():
		status.text = "地图无效，请先修正标出的区域。"
		return
	var resource: WRMapDefinition = author.map_definition.duplicate(true)
	resource.id = path.get_file().get_basename()
	var result := ResourceSaver.save(resource, path)
	if result != OK:
		status.text = "保存失败：" + error_string(result)
		return
	resource.take_over_path(path)
	set_map(resource)
	get_editor_interface().get_resource_filesystem().scan()
	status.text = "已保存：" + path

func play_map() -> void:
	if not is_instance_valid(author): return
	var settings := preload("res://scripts/config_loader.gd").settings("res://configs/weather.tres")
	if not settings.errors.is_empty():
		status.text = "配置无效：" + "；".join(settings.errors)
		return
	var errors := author.map_definition.validation_errors(settings.resource.plot_half)
	if not errors.is_empty():
		status.text = "地图无效：" + "；".join(errors)
		return
	var result := ResourceSaver.save(author.map_definition.duplicate(true), "res://.godot/map-playtest.tres")
	if result != OK:
		status.text = "试玩资源保存失败：" + error_string(result)
		return
	get_editor_interface().play_custom_scene("res://scenes/map_playtest.tscn")

func editor_smoke() -> void:
	await get_tree().process_frame
	var node := WRMapAuthor.new()
	node.map_definition = load("res://configs/maps/ridges.tres").duplicate(true)
	add_child(node)
	author = node
	var errors: Array[String] = []
	var before := node.map_definition.mountains.size()
	add_entry("mountains")
	if node.map_definition.mountains.size() != before + 1: errors.append("Add mountain")
	var history_id := get_undo_redo().get_object_history_id(node.map_definition)
	var history := get_undo_redo().get_history_undo_redo(history_id)
	history.undo()
	if node.map_definition.mountains.size() != before: errors.append("Undo mountain")
	history.redo()
	if node.map_definition.mountains.size() != before + 1: errors.append("Redo mountain")
	remove_entry("mountains", before)
	add_entry("humidity_sources")
	if node.map_definition.humidity_sources.size() != 3: errors.append("Add humidity")
	history.undo()
	if node.map_definition.humidity_sources.size() != 2: errors.append("Undo humidity")
	var handle := 3
	var previous = node.handle_value(handle)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 15, 20)
	camera.look_at(Vector3.ZERO)
	var gizmo := EditorNode3DGizmo.new()
	gizmo.set_node_3d(node)
	var screen := camera.unproject_position(Vector3(-2.8, 0.25, -1))
	gizmo_plugin._set_handle(gizmo, handle, false, camera, screen)
	if node.map_definition.mountains[0].position.distance_to(Vector2(-2.8, -1)) > 0.001: errors.append("Viewport ray handle drag")
	gizmo_plugin._commit_handle(gizmo, handle, false, previous, false)
	history.undo()
	if node.map_definition.mountains[0].position != previous: errors.append("Undo handle drag")
	history.redo()
	if node.map_definition.mountains[0].position.distance_to(Vector2(-2.8, -1)) > 0.001: errors.append("Redo handle drag")
	history.undo()
	if node.preview.get_child_count() < 6: errors.append("Actual preview geometry")
	var plot_count := node.map_definition.plots.size()
	change_plots(true)
	if node.map_definition.plots.size() != plot_count + 1: errors.append("Add third plot")
	history.undo()
	if node.map_definition.plots.size() != plot_count: errors.append("Undo plot")
	history.redo()
	if node.map_definition.plots.size() != plot_count + 1: errors.append("Redo plot")
	history.undo()
	var shape_map: WRMapDefinition = load("res://configs/maps/meadow.tres").duplicate(true)
	var old_signature := node.signature()
	node.map_definition = shape_map
	if node.signature() == old_signature or node.preview.get_child_count() < 6: errors.append("Shape preview refresh")
	if ResourceSaver.save(shape_map, "res://.godot/editor-shape-map.tres") != OK: errors.append("Save shape preview")
	var shape_loaded = ResourceLoader.load("res://.godot/editor-shape-map.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if shape_loaded.region(1).shape != "circle" or shape_loaded.region(2).shape != "ellipse": errors.append("Reload shapes")
	node.map_definition = load("res://configs/maps/ridges.tres").duplicate(true)
	camera.queue_free()
	if not node.map_definition.validation_errors().is_empty(): errors.append("Final map validation")
	var saved := ResourceSaver.save(node.map_definition, "res://.godot/editor-smoke-map.tres")
	var reloaded = ResourceLoader.load("res://.godot/editor-smoke-map.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if saved != OK or reloaded.mountains.size() != 2 or reloaded.mountains[1].height != node.map_definition.mountains[1].height: errors.append("Save/reload nested resources")
	var original: WRMapDefinition = load("res://configs/maps/ridges.tres")
	if original.mountains.size() != 2 or original.mountains[0].position != Vector2(-3, -1): errors.append("Editing leaves source resource unchanged until save")
	print("EDITOR MAP: 18 checks, ", errors.size(), " failures: ", errors)
	node.queue_free()
	get_tree().quit(0 if errors.is_empty() else 1)

func editor_capture() -> void:
	await get_tree().create_timer(2.0).timeout
	get_editor_interface().open_scene_from_path("res://scenes/map_editor.tscn")
	await get_tree().process_frame
	var node: WRMapAuthor = get_editor_interface().get_edited_scene_root()
	node.map_definition = load("res://configs/maps/ridges.tres").duplicate(true)
	get_editor_interface().edit_node(node)
	_edit(node)
	_make_visible(true)
	await get_tree().create_timer(0.5).timeout
	var viewport := get_editor_interface().get_editor_viewport_3d(0)
	await RenderingServer.frame_pre_draw
	var camera := viewport.get_camera_3d()
	camera.global_position = Vector3(11, 15, 18)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://docs/previews/map-editor.png")
	print("EDITOR CAPTURE ", result)
	author = null
	_exit_tree()
	await get_tree().process_frame
	get_tree().quit(0 if result == OK else 1)
