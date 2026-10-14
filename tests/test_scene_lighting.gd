extends SceneTree
## Real GPU checks. Injected display fields are not normal-play completion evidence.
const Sim = preload("res://scripts/weather_simulation.gd")
const Style = preload("res://scripts/scene_style.gd")
const Loader = preload("res://scripts/config_loader.gd")
var main: Node3D
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func render() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func changed(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0,a.get_height(),3):
		for x in range(0,a.get_width(),3):
			var p := a.get_pixel(x,y)-b.get_pixel(x,y)
			if maxf(absf(p.r),maxf(absf(p.g),absf(p.b)))>0.025: count += 1
	return count
func snapshot() -> Array:
	var state: Array = []
	for field in ["humidity","cloud","rain","charge","cold","wind","ground_rain","plot_waters"]: state.append(main.sim.get(field).duplicate())
	return state
func set_cloud_field(amount: float, rain := false, center := Vector2.ZERO) -> void:
	main.sim.humidity.fill(0)
	main.sim.cloud.fill(0)
	main.sim.rain.fill(0)
	main.sim.cold.fill(0)
	for i in Sim.COUNT:
		var p: Vector2 = main.sim.positions[i]-center
		main.sim.cloud[i] = amount*exp(-p.x*p.x/5.0-p.y*p.y/2.4)
		if rain: main.sim.rain[i] = main.sim.cloud[i]
	main.sim.refresh_display()
	main.weather_view.update_weather(0,false)

func run() -> void:
	check(Style.new().validation_errors().is_empty(),"Default scene style is valid")
	var good := Style.new()
	good.cloud_normal_gain = 3.0
	ResourceSaver.save(good,"res://.godot/scene-style-check.tres")
	check(Loader.scene_style("res://.godot/scene-style-check.tres").resource.cloud_normal_gain == 3.0,"Saved display configuration deeply reloads")
	good.light_direction = Vector3.ZERO
	ResourceSaver.save(good,"res://.godot/scene-style-check.tres")
	var invalid := Loader.scene_style("res://.godot/scene-style-check.tres")
	check(invalid.resource.cloud_normal_gain == 3.0 and invalid.errors[0].contains("light_direction"),"Bad direction retains previous valid configuration and names field")
	good = Style.new()
	good.cloud_colors.resize(3)
	check(good.validation_errors().has("cloud_colors：须有四档颜色"),"Incomplete palette is rejected")
	good = Style.new()
	good.cloud_shadow_strength = NAN
	check(not good.validation_errors().is_empty(),"Nonfinite strength is rejected")
	good = Style.new()
	good.light_direction = Vector3(1e30,1,1e30)
	check(not good.validation_errors().is_empty(),"Overflowing direction length is rejected before GPU normalization")
	Loader.scene_style()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await render()
	main.set_process(false)
	main.hud.visible = false
	main.weather_view.hints_enabled = false
	var cloud_node: GeometryInstance3D
	for child in main.weather_view.find_children("*","GeometryInstance3D",true,false):
		child.visible = child.material_override == main.weather_view.cloud_material
		if child.visible: cloud_node = child
	check(cloud_node != null,"Actual volume cloud is rendered, not a fixed image")
	var material: ShaderMaterial = main.weather_view.cloud_material
	for amount in [0.8,3.0,4.0]:
		set_cloud_field(amount,amount==4.0)
		var before := snapshot()
		material.set_shader_parameter("light_direction",Vector3(-0.9,0.55,-0.5))
		var a := await render()
		material.set_shader_parameter("light_direction",Vector3(0.9,0.55,0.5))
		var b := await render()
		check(changed(a,b)>100,"Light direction changes visible thin/thick/raining cloud surfaces: "+str(amount))
		var screen: Vector2 = main.weather_view.camera.unproject_position(Vector3(0,Sim.CLOUD_HEIGHT,0))
		var ray: Vector3 = main.weather_view.camera.project_ray_origin(screen)
		var direction: Vector3 = main.weather_view.camera.project_ray_normal(screen)
		var hit = main.sim.pick_cloud(ray,direction)
		var original: Shader = material.shader
		var mask := Shader.new()
		mask.code = original.code.replace("ALBEDO = pow(color, vec3(2.2));","ALBEDO = vec3(1.0);")
		material.shader = mask
		material.set_shader_parameter("light_direction",Vector3(-0.9,0.55,-0.5))
		var ma := await render()
		material.set_shader_parameter("light_direction",Vector3(0.9,0.55,0.5))
		var mb := await render()
		check(ma.get_data()==mb.get_data(),"Light direction preserves the complete alpha silhouette: "+str(amount))
		check(main.sim.pick_cloud(ray,direction)==hit and hit!=null,"Light does not change visible-cloud picking: "+str(amount))
		check(snapshot()==before,"Lighting never changes weather, ground rain or target water: "+str(amount))
		material.shader = original
		main.weather_view.scene_style.apply(material)
		if "--capture" in OS.get_cmdline_user_args(): (await render()).save_png("res://.godot/scene-cloud-"+str(amount)+".png")
	# Check the exact shader derivative against CPU finite differences of the same field.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(24,20)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	var probe := Shader.new()
	probe.code = 'shader_type canvas_item; uniform sampler2D water_map:filter_linear,repeat_disable;\n#include "res://shaders/cloud_field.gdshaderinc"\n#include "res://shaders/cloud_lighting.gdshaderinc"\nvoid fragment(){vec2 p=UV*vec2(32.0,28.0)-vec2(16.0,14.0);COLOR=vec4(cloud_gradient(p,cloud_state(p).r)*0.10+vec2(0.5),0,1);}'
	var probe_material := ShaderMaterial.new()
	probe_material.shader = probe
	probe_material.set_shader_parameter("water_map",main.weather_view.water_texture)
	var rect := ColorRect.new()
	rect.size = viewport.size
	rect.material = probe_material
	viewport.add_child(rect)
	await render()
	var image := viewport.get_texture().get_image()
	var error := 0.0
	for z in viewport.size.y:
		for x in viewport.size.x:
			var p := Vector2((x+0.5)/viewport.size.x*32-16,(z+0.5)/viewport.size.y*28-14)
			var gradient := Vector2.ZERO
			for axis in 2:
				var offset := Vector2(0.002,0) if axis==0 else Vector2(0,0.002)
				gradient[axis] = (main.sim.sample_cloud(main.sim.display_cloud,p+offset)-main.sim.sample_cloud(main.sim.display_cloud,p-offset))/0.004
			var actual := image.get_pixel(x,z)
			error = maxf(error,gradient.distance_to(Vector2(actual.r-0.5,actual.g-0.5)/0.10))
	check(error<0.01,"GPU shape gradient agrees with CPU field derivative; error="+str(error))
	viewport.queue_free()
	main.select_layout("reservoir_lab")
	main.hud.visible = false
	main.weather_view.hints_enabled = false
	var view: Node3D = main.weather_view
	var p: Vector2 = main.sim.plot_centers[0]
	var sun: Vector3 = view.scene_style.light_direction
	set_cloud_field(4.0,false,p+Vector2(sun.x,sun.z)/sun.y*(3.6-0.255))
	for child in view.find_children("*","GeometryInstance3D",true,false):
		if child.material_override == view.cloud_material: child.visible = false
	var materials: Array = []
	for child in view.find_children("*","GeometryInstance3D",true,false):
		if child.material_override is ShaderMaterial and child.material_override.shader == view.TERRAIN_SHADER:
			materials.append(child.material_override)
			child.material_override.set_shader_parameter("cloud_shadow_strength",0.0)
	var no_shadow := await render()
	for m in materials: m.set_shader_parameter("cloud_shadow_strength",view.scene_style.cloud_shadow_strength)
	var shadow := await render()
	check(changed(no_shadow,shadow)>100,"Shared cloud projection is visible on actual ground/targets without rainfall")
	check(main.sim.ground_rain.count(0.0)==Sim.COUNT,"Cloud shadow does not create a ground-rain hint")
	main.sim.plot_waters[1] = main.sim.required_water(1)
	view.update_weather(1.0,true)
	await render()
	var height: float = view.reservoir_surfaces[1].position.y
	var time: float = view.elapsed
	view.update_weather(1.0,false)
	await render()
	check(view.elapsed==time and view.reservoir_surfaces[1].position.y==height,"Pause freezes water level and water animation")
	check(view.reservoir_surfaces[1].position.y<=0.39 and view.scene_style.reservoir_rim_height-view.reservoir_surfaces[1].position.y>=0.07,"Full water retains a visible inner wall without changing the water-level mapping")
	check(view.plot_materials[0] is ShaderMaterial and view.plant_materials[0] is ShaderMaterial,"Farm soil and leaves receive common direction instead of flat unlit colors")
	good = Style.new()
	good.cloud_shadow_strength = 0.10
	ResourceSaver.save(good,"res://.godot/scene-style-check.tres")
	view.style_path = "res://.godot/scene-style-check.tres"
	main.restart(false)
	check(is_equal_approx(main.weather_view.scene_style.cloud_shadow_strength,0.10),"Retry reloads a saved scene style")
	good.cloud_shadow_strength = 0.30
	ResourceSaver.save(good,"res://.godot/scene-style-check.tres")
	var state := snapshot()
	main.reload_tuning()
	check(is_equal_approx(main.weather_view.scene_style.cloud_shadow_strength,0.10) and snapshot()==state,"F6 preserves current display style and weather")
	main.restart(false)
	check(is_equal_approx(main.weather_view.scene_style.cloud_shadow_strength,0.30),"Next retry applies updated display values")
	good.cloud_colors.resize(3)
	ResourceSaver.save(good,"res://.godot/scene-style-check.tres")
	main.restart(false)
	check(is_equal_approx(main.weather_view.scene_style.cloud_shadow_strength,0.30) and main.tuning_message.contains("cloud_colors"),"Invalid scene style retains last valid values and reports field in actual HUD")
	main.weather_view.style_path = "res://configs/scene_style.tres"
	main.restart(false)
	if "--capture" in OS.get_cmdline_user_args(): shadow.save_png("res://.godot/scene-ground-shadow.png")
	print("SCENE LIGHTING: ",checks," checks, ",failures," failures; gradient_error=",error)
	quit(0 if failures==0 else 1)
