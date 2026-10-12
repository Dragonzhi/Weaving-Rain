extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
const InputBrush = preload("res://scripts/wind_input.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func replay(frequency: int) -> RefCounted:
	var sim := Sim.new()
	var brush := InputBrush.new()
	brush.sim = sim
	brush.dragging = true
	var next_frame := 1.0 / 60.0
	for i in frequency + 1:
		var t := float(i) / frequency
		var p := Vector2(-3 + t * 6, 0) if t <= 0.5 else Vector2(0, (t - 0.5) * 6)
		brush.append_point(p, t)
		if t >= next_frame:
			brush.flush()
			next_frame += 1.0 / 60.0
	brush.flush()
	brush.free()
	return sim

func _init() -> void:
	var low := replay(240)
	var high := replay(1000)
	var difference := 0.0
	var total := 0.0
	var capped := true
	for i in Sim.COUNT:
		difference += low.wind[i].distance_to(high.wind[i])
		total += low.wind[i].length()
		capped = capped and high.wind[i].length() <= high.settings.max_wind + 0.00001
	check(difference / maxf(total, 0.001) < 0.05, "Event frequency must not materially change the same timed path: " + str(difference / total))
	check(capped, "Resampled strokes respect the wind cap")
	check(high.sample_cloud(high.cloud, Vector2.ZERO) == 0.0, "Wind batching does not directly create clouds")
	check(high.wind[28 * Sim.WIDTH + 28].x > 0 and high.wind[33 * Sim.WIDTH + 32].y > 0, "A turning path retains both directions")
	var sim := Sim.new()
	var brush := InputBrush.new()
	brush.sim = sim
	brush.append_point(Vector2.ZERO, 0.0)
	brush.append_point(Vector2(0.01, 0), 0.1)
	brush.flush()
	check(sim.wind[28 * Sim.WIDTH + 32].x > 0.0, "Short final strokes are submitted without waiting for a full sample spacing")
	sim.reset()
	brush.append_point(Vector2(1, 0), 0.2)
	brush.cancel()
	brush.flush()
	check(sim.wind[28 * Sim.WIDTH + 32] == Vector2.ZERO and brush.path_points.is_empty(), "Cancellation discards pending input")
	brush.free()
	print("WIND PATH: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
