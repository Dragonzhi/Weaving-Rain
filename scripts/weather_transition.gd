extends Control
## UI decoration only. The host freezes gameplay until the new viewport is ready.
var active := false
var reduced_motion := false
var kind := ""
var progress := 0.0
var fade_target: CanvasItem

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func _input(_event: InputEvent) -> void:
	if active: get_viewport().set_input_as_handled()

func play(style: String, change: Callable, reveal_only := false) -> void:
	if active: return
	active = true
	kind = "light" if reduced_motion else style
	progress = 0.5 if reveal_only else 0.0
	show()
	queue_redraw()
	var duration := 0.12 if reduced_motion else (0.65 if kind == "wind" else (0.85 if kind == "cloud" else 0.18))
	if kind != "light" and not reveal_only:
		var closing := create_tween()
		closing.tween_method(_set_progress,0.0,0.5,duration*0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await closing.finished
		await RenderingServer.frame_post_draw
	change.call()
	if kind == "light" and is_instance_valid(fade_target): fade_target.modulate.a = 0
	# Allow containers, new meshes and GPU uploads to reach the actual viewport.
	for frame in 2: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var opening := create_tween()
	opening.tween_method(_set_progress,progress,1.0,duration if kind == "light" else duration*0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if kind == "light" and is_instance_valid(fade_target): opening.parallel().tween_property(fade_target,"modulate:a",1.0,duration)
	await opening.finished
	hide()
	fade_target = null
	active = false

func _set_progress(value: float) -> void:
	progress = value
	queue_redraw()

func _draw() -> void:
	if not active: return
	if kind == "light":
		return # Native controls fade directly; no GPU readback or screenshot texture.
	elif kind == "cloud":
		var cover := minf(1.0,(progress if progress < 0.5 else 1.0-progress)/0.44)
		for side in [-1,1]:
			_bank(side,cover,0.035,Color("c9dce0"))
			_bank(side,cover,0.016,Color("dee8e5"))
			_bank(side,cover,0.0,Color("f0f3e9"))
	else:
		# Sea glass, mint and pearl follow one curved sheet; the center stays opaque.
		var center := lerpf(-1.2,2.2,progress)*size.x
		var half := size.x*0.78
		# Mostly translucent in motion; only the short covered interval hides the swap.
		var opacity := 0.4+0.6*smoothstep(0.18,0.46,progress)*(1-smoothstep(0.54,0.82,progress))
		_wind_sheet(center,half+size.x*0.055,-1,1,Color(0.65,0.82,0.84,0.10*opacity),Color(0.65,0.82,0.84,0.10*opacity))
		_wind_sheet(center,half+size.x*0.026,-1,1,Color(0.79,0.89,0.87,0.20*opacity),Color(0.79,0.89,0.87,0.20*opacity))
		var stops := [-1.0,-0.84,-0.45,0.12,0.62,0.84,1.0]
		var colors := [Color("aacbd1"),Color("bad6d4"),Color("d1e5d8"),Color("f1f1df"),Color("c4e0d3"),Color("afd1d0"),Color("9cc8cd")]
		for n in colors.size(): colors[n].a = opacity if n>0 and n<colors.size()-1 else 0.0
		for n in 6: _wind_sheet(center,half,stops[n],stops[n+1],colors[n],colors[n+1])
		# Fine moving arcs lead the veil; unequal lengths and phases avoid ruled lines.
		for n in 13:
			var phase := fposmod(progress*1.12+n*0.097,1.0)
			var tip := Vector2((-0.25+phase*1.65)*size.x,(0.08+fposmod(n*0.143,0.84))*size.y)
			var length := size.x*(0.12+0.035*(n%4))
			var line := PackedVector2Array()
			for j in 25:
				var t := float(j)/24
				line.append(tip+Vector2((t-1)*length,(sin(t*TAU)*0.008+(t-1)*0.014)*size.y))
			var alpha := 0.86*sin(PI*progress)*sin(PI*phase)
			draw_polyline(line,Color(1,1,0.96,alpha),maxf(1.0,size.y/650)*(1.2 if n%4==0 else 0.75),true)

func _wind_sheet(center: float, half: float, left: float, right: float, a: Color, b: Color) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for side in [left,right]:
		for n in 33:
			var v := float(n if side == left else 32-n)/32
			var bend := sin(v*PI)*0.085+sin(v*TAU+0.3)*0.025
			points.append(Vector2(center+half*side+bend*size.x,v*size.y))
			colors.append(a if side == left else b)
	draw_polygon(points,colors)

func _bank(side: int, cover: float, offset: float, color: Color) -> void:
	var edge := (-0.28+cover*0.86+offset)*size.x
	var back := edge-size.x*0.05
	if back > 0:
		draw_rect(Rect2(0 if side == -1 else size.x-back,-size.y*0.2,back,size.y*1.4),color)
	for n in 9:
		var bulge := sin(n*2.3)*0.018
		var x := edge+bulge*size.x
		var center := Vector2(x if side == -1 else size.x-x,(-0.06+n*0.14)*size.y)
		var radius := size.x*(0.088+0.012*cos(n*1.7))
		draw_set_transform(center,0,Vector2(1,size.y*0.13/radius))
		draw_circle(Vector2.ZERO,radius,color,true,-1,true)
	draw_set_transform(Vector2.ZERO)
