extends RefCounted
## Static graphic shadow from the same max-combined hills as TerrainModel.
## Rebuilt with the view/map/light; never touches weather or runs in update_weather.
const SIZE := Vector2i(128, 112)
const ORIGIN := Vector2(-16, -14)
const EXTENT := Vector2(32, 28)

static func build(terrain: RefCounted, direction: Vector3) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)
	var sun := direction.normalized()
	if terrain.hill_data.is_empty() or Vector2(sun.x,sun.z).length_squared() < 0.000001: return image
	var boxes: Array[Rect2] = []
	var hills: PackedFloat64Array = terrain.hill_data
	for n in range(0,hills.size(),4):
		var center := Vector2(hills[n],hills[n+1])
		var radius := sqrt(hills[n+2])
		var offset := -Vector2(sun.x,sun.z) * minf(48.0,hills[n+3]/sun.y)
		var a := center-Vector2.ONE*radius
		var b := center+Vector2.ONE*radius
		boxes.append(Rect2(Vector2(minf(a.x,a.x+offset.x),minf(a.y,a.y+offset.y)),Vector2.ZERO).expand(b).expand(b+offset).grow(0.3))
	for z in SIZE.y:
		for x in SIZE.x:
			var p := ORIGIN+(Vector2(x,z)+Vector2.ONE*0.5)/Vector2(SIZE)*EXTENT
			var possible := false
			for box in boxes:
				if box.has_point(p):
					possible = true
					break
			if not possible: continue
			var base: float = terrain.height(p)
			if base < 0.0: continue # Land receivers only; the sea keeps its weak cloud shadow.
			var distance := minf(48.0,maxf(0.0,terrain.maximum_height-base)/sun.y)
			var blockage := 0.0
			# ponytail: a 0.18-world-unit fixed-light trace is an art mask, not
			# a physical penumbra. Linear filtering softens the 0.25-unit texels.
			for step in ceili(distance/0.18):
				var t := (step+1)*0.18
				var q := p+Vector2(sun.x,sun.z)*t
				var height := 0.22
				for n in range(0,hills.size(),4):
					var d2 := q.distance_squared_to(Vector2(hills[n],hills[n+1]))/hills[n+2]
					if d2 < 1.0: height = maxf(height,0.22+hills[n+3]*(1.0-d2)*(1.0-d2))
				blockage = maxf(blockage,height-base-sun.y*t)
				if blockage >= 0.15: break
			image.set_pixel(x,z,Color(smoothstep(0.025,0.15,blockage),0,0))
	return image
