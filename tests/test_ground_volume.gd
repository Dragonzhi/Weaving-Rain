extends "res://tests/test_scene_lighting.gd"
## Display fixtures, real meshes/GPU and viewport pointer checks. Not route evidence.
const Shadow = preload("res://scripts/terrain_shadow.gd")

func mask_sum(image: Image) -> int:
	var sum := 0
	for byte in image.get_data(): sum += byte
	return sum

func clockwise(mesh: ArrayMesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0,vertices.size(),3):
		var cross := (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i])
		if cross.dot(normals[i]) > 0.000001: return false
	return true

func run() -> void:
	var style := Style.new()
	for field in ["farm_top_height","bevel_width","reservoir_rim_height","terrain_shadow_strength"]:
		var bad := style.duplicate()
		bad.set(field,NAN)
		check(not bad.validation_errors().is_empty(),field+" rejects nonfinite values")
	style.reservoir_rim_height = 0.39
	check(not style.validation_errors().is_empty(),"Pool rim cannot meet or fall below the maximum water surface")
	style = Style.new()
	style.farm_top_height = 0.30
	style.bevel_width = 0.10
	check(not style.validation_errors().is_empty(),"Individually valid height/bevel values cannot put the soil shoulder under the land")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await render()
	main.set_process(false)
	main.hud.set_process(false)
	var shapes := {}
	for layout in ["meadow","needs_lab","reservoir_lab","ridges","storm_coast"]:
		main.select_layout(layout)
		var view: Node3D = main.weather_view
		var before := snapshot()
		var terrain_heights := PackedFloat64Array()
		for p in main.sim.positions: terrain_heights.append(main.sim.terrain.height(p))
		var shadow_bytes: PackedByteArray = view.terrain_shadow_texture.get_image().get_data()
		view.update_weather(0.5,true)
		await render()
		check(snapshot()==before,"Display geometry and shadow do not change weather/targets: "+layout)
		var after := PackedFloat64Array()
		for p in main.sim.positions: after.append(main.sim.terrain.height(p))
		check(after==terrain_heights,"Display heights never modify the terrain height field: "+layout)
		check(view.terrain_shadow_texture.get_image().get_data()==shadow_bytes,"Static mountain shadow is not regenerated per frame: "+layout)
		var all_faces := true
		for child in view.find_children("*","MeshInstance3D",true,false):
			if child.material_override is ShaderMaterial and (child.material_override in view.plot_materials or child.material_override in view.farm_side_materials or child.material_override in view.farm_ridge_materials):
				all_faces = all_faces and clockwise(child.mesh)
		check(all_faces,"Farm tops, bevels, sides and ridges have outward clockwise faces: "+layout)
		for target in main.sim.plot_centers.size():
			var center: Vector2 = main.sim.plot_centers[target]
			shapes[main.sim.plot_regions[target].shape] = true
			if main.sim.is_reservoir(target):
				var surface: MeshInstance3D = view.reservoir_surfaces[target]
				for progress in [0.0,0.5,1.0]:
					main.sim.plot_waters[target] = main.sim.required_water(target)*progress
					view.update_weather(2,true)
					check(surface.visible==(progress>0) and absf(surface.position.y-(0.27+0.12*progress))<0.001,"Empty/half/full water retains actual progress mapping: "+str(progress))
				check(view.plot_display_height(target)-surface.position.y>=0.07,"Full pool still exposes its inner wall")
				var water_height: float = surface.position.y
				view.update_weather(2,false)
				check(surface.position.y==water_height,"Paused pool level stays fixed")
			else:
				check(is_equal_approx(view.farm_top_meshes[target].position.y,view.scene_style.farm_top_height),"Farm top uses the configured display height")
				var outline: PackedVector2Array = main.hud._ground_region(target)
				var offset: Vector2 = main.sim.plot_regions[target].outline(main.sim.plot_half)[0]
				var expected: Vector2 = main.hud._project(Vector3(center.x+offset.x,view.plot_display_height(target)+0.006,center.y+offset.y))
				check(outline[0].distance_to(expected)<0.01,"Plot feedback projects onto the raised decorative top")
			# Existing low-air pick plane is terrain+0.30 and remains above the
			# default .36 farm/.52 rim. Pick its visible marker, preserving air coords.
			main.sim.cloud.fill(0)
			main.sim.refresh_display()
			var screen: Vector2 = view.camera.unproject_position(Vector3(center.x,main.sim.terrain.height(center)+0.30,center.y))
			var picked: Vector3 = main.wind_input.pick(screen)
			check(Vector2(picked.x,picked.z).distance_to(center)<0.015,"Low-air picking above target retains the same horizontal position")
			check(not main.hud.blocks_wind(screen),"Decorative geometry/feedback adds no input blocker")
	check(shapes.has("rectangle") and shapes.has("circle") and shapes.has("ellipse"),"Actual maps exercise all three target outlines")
	var terrain: RefCounted = main.sim.terrain
	var sun := Vector3(-0.6,0.65,0.3)
	var mask := Shadow.build(terrain,sun)
	var opposite := Shadow.build(terrain,Vector3(0.6,0.65,-0.3))
	check(mask_sum(mask)>1000 and mask.get_data()!=opposite.get_data(),"Mountain projection exists and changes sides with common light")
	var empty: RefCounted = preload("res://scripts/terrain_model.gd").new({"mountains":[]})
	check(mask_sum(Shadow.build(empty,sun))==0,"No mountain produces no false ground shadow")
	check(mask_sum(Shadow.build(terrain,Vector3.UP))==0,"Vertical sun has no offset mountain shadow")
	# Minimum allowed map target and maximum bevel must leave an open pool.
	var region := WRPlotRegion.new()
	region.half_axes = Vector2(0.5,0.5)
	var small_map: WRMapDefinition = preload("res://scripts/weather_layouts.gd").get_definition("reservoir_lab").duplicate(true)
	small_map.plot_regions.resize(2)
	small_map.plot_regions[1] = region
	var small_sim := Sim.new(main.weather_settings,true,false,"reservoir_lab",small_map)
	var small_view: Node3D = preload("res://scripts/weather_view.gd").new()
	root.add_child(small_view)
	style = Style.new()
	style.bevel_width = 0.10
	ResourceSaver.save(style,"res://.godot/ground-style-small.tres")
	small_view.style_path = "res://.godot/ground-style-small.tres"
	small_view.setup(small_sim)
	var pool_scale: float = small_view.reservoir_surfaces[1].scale.x
	check(pool_scale>0 and pool_scale<0.8,"Actual smallest pool has a nonzero inner opening inside the maximum-width bevel")
	small_view.queue_free()
	main.select_layout("reservoir_lab")
	var view: Node3D = main.weather_view
	var terrain_materials: Array = []
	main.hud.visible = false
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.cold.fill(0)
	main.sim.refresh_display()
	view.update_weather(0,false)
	for child in view.find_children("*","GeometryInstance3D",true,false):
		if child.material_override is ShaderMaterial and child.material_override.shader == view.TERRAIN_SHADER:
			terrain_materials.append(child.material_override)
			child.material_override.set_shader_parameter("terrain_shadow_strength",0)
	var unshadowed := await render()
	for material in terrain_materials: material.set_shader_parameter("terrain_shadow_strength",view.scene_style.terrain_shadow_strength)
	var shadowed := await render()
	check(changed(unshadowed,shadowed)>30,"Static mountain projection changes actual GPU ground pixels without any rain")
	check(main.sim.ground_rain.count(0.0)==Sim.COUNT,"Mountain shadow never creates a rainfall footprint")
	print("GROUND VOLUME: ",checks," checks, ",failures," failures; shadow_build_ms=",view.terrain_shadow_build_ms)
	quit(0 if failures==0 else 1)
