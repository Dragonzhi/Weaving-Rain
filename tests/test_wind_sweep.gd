extends SceneTree
## GPU appearance fixture: decorative wind at fixed progress, no weather or player data.
var checks := 0
var failures := 0
var veil: Control
var background: ColorRect
var directory := "res://.godot/wind-sweep-review/"
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func frame(phase: float, color: Color) -> Image:
	background.color=color
	veil._set_progress(phase)
	for n in 3: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	background=ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	veil=load("res://scripts/weather_transition.gd").new()
	root.add_child(veil)
	veil.active=true
	veil.kind="wind"
	veil.show()
	var red := Color("ad2035")
	var blue := Color("1a3bbd")
	var start := await frame(0,red)
	check(start.get_pixel(start.get_width()/2,start.get_height()/2).is_equal_approx(red),"Wind is offscreen before the sweep")
	var covered_red := await frame(0.5,red)
	var covered_blue := await frame(0.5,blue)
	check(covered_red.get_data()==covered_blue.get_data(),"Covered GPU frame hides every pixel of either underlying page")
	var left := covered_blue.get_pixel(int(covered_blue.get_width()*0.12),covered_blue.get_height()/2)
	var pearl := covered_blue.get_pixel(int(covered_blue.get_width()*0.58),covered_blue.get_height()/2)
	var right := covered_blue.get_pixel(int(covered_blue.get_width()*0.94),covered_blue.get_height()/2)
	check(pearl.r-left.r>0.025 and pearl.r-right.r>0.025,"Pearl center stays visibly distinct from mint / blue outer bands")
	var samples := {}
	for n in 30:
		var c := covered_blue.get_pixel(int((n+0.5)/30*covered_blue.get_width()),int(covered_blue.get_height()*0.52))
		samples[c.to_html(false)]=true
	check(samples.size()>20,"Native vertex colors interpolate smoothly across the veil")
	covered_blue.save_png(directory+"covered-"+str(root.size.x)+"x"+str(root.size.y)+".png")
	var crossing_red := await frame(0.22,red)
	var crossing_blue := await frame(0.22,blue)
	var see_through := 0
	var total := 0
	for y in range(1,10):
		for x in range(1,10):
			var at := Vector2i(int(x/25.0*crossing_red.get_width()),int(y/10.0*crossing_red.get_height()))
			var a := crossing_red.get_pixelv(at)
			var b := crossing_blue.get_pixelv(at)
			if absf(a.r-b.r)+absf(a.b-b.b)>0.2: see_through+=1
			total+=1
	check(see_through>total*0.85,"Most of the moving veil reveals the underlying page before the covered swap")
	for phase in [0.22,0.72]:
		var shot := await frame(phase,Color("438f9a"))
		shot.save_png(directory+"wind-"+str(phase)+"-"+str(root.size.x)+"x"+str(root.size.y)+".png")
	var end := await frame(1,blue)
	check(end.get_pixel(end.get_width()/2,end.get_height()/2).is_equal_approx(blue),"Wind is offscreen when the sweep ends")
	var report := {"checks":checks,"failures":failures,"size":str(root.size),"scope":"Fixed-progress native GPU fixture, no playable route"}
	FileAccess.open(directory+"review-"+str(root.size.x)+"x"+str(root.size.y)+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WIND SWEEP: ",checks," checks, ",failures," failures; size=",root.size)
	quit(0 if failures==0 else 1)
