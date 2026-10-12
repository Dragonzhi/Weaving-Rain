extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.select_layout("meadow")
	var sim: RefCounted = main.sim
	check(sim.plot_status(0) == "dry", "Normal start is dry")
	sim.humidity.fill(0)
	sim.cloud.fill(0)
	sim.rain.fill(0)
	sim.charge.fill(0)
	sim.plot_waters[0] = 110
	sim.refresh_display()
	sim.update_goal(0.5)
	check(sim.plot_status(0) == "confirming", "Adequate water still requires continuous safety")
	main.hud.update_feedback(0.0)
	check(is_equal_approx(main.hud.feedback_left[0], 1.2) and "雨量已够" in main.hud.feedback_texts[0], "First adequate transition has feedback")
	main.hud.update_feedback(0.2)
	var before: float = main.hud.feedback_left[0]
	main.hud.update_feedback(0.0)
	check(main.hud.feedback_left[0] == before, "Unchanged adequate state does not retrigger feedback")
	sim.update_goal(2.0)
	main.hud.update_feedback(0.0)
	check(sim.plot_status(0) == "safe" and "已保住" in main.hud.feedback_texts[0], "Completed safety gives star feedback")
	var cell: int = sim.safety_indices[0][0]
	sim.cloud[cell] = 0.1
	sim.rain[cell] = 0.1
	sim.refresh_display()
	sim.update_goal(0.0)
	main.hud.update_feedback(0.3)
	check(sim.plot_status(0) == "danger", "New rain removes safe state through the shared query")
	sim.cloud.fill(0)
	sim.rain.fill(0)
	sim.refresh_display()
	sim.update_goal(0.5)
	main.hud.update_feedback(0.3)
	check("雨量已够" not in main.hud.feedback_texts[0], "Adequate notification does not repeat after a threat")
	sim.update_goal(2.0)
	main.hud.update_feedback(0.0)
	check(is_equal_approx(main.hud.feedback_left[0], 1.2) and "已保住" in main.hud.feedback_texts[0], "Recovered safe star can notify again")
	main.paused = true
	main._process(0.1)
	check(is_equal_approx(main.hud.feedback_left[0], 1.2), "Real pause freezes transition animation")
	main.paused = false
	sim.plot_waters[0] = 151
	sim.update_goal(0.0)
	main.hud.update_feedback(0.0)
	check(sim.plot_status(0) == "destroyed" and "土地损坏" in main.hud.feedback_texts[0], "Flood feedback has priority")
	sim.plot_waters[0] = 110
	sim.update_goal(3.0)
	check(sim.plot_status(0) == "destroyed", "Damaged field cannot appear safe after the rain stops")
	main.restart(false)
	check(main.hud.feedback_left[0] == 0.0 and not main.hud.feedback_adequate[0], "Retry clears pending and once-only feedback")
	sim = main.sim
	sim.humidity.fill(0)
	sim.plot_waters = PackedFloat64Array([80, 110, 151])
	sim.refresh_display()
	sim.update_goal(0.5)
	sim.elapsed_seconds = sim.time_limit_seconds - sim.FIXED_STEP
	main._process(sim.FIXED_STEP)
	await process_frame
	await RenderingServer.frame_post_draw
	check(main.hud.result_details.size() == 3, "Result has one line per field")
	check("80.0" in main.hud.result_details[0] and "缺水" in main.hud.result_details[0], "Result explains actual water shortage")
	check("安全确认" in main.hud.result_details[1] and "危险天气" not in main.hud.result_details[1], "Incomplete safety is distinguished from remaining danger")
	check("过量损坏" in main.hud.result_details[2], "Result explains irreversible loss")
	check(main.hud.blocks_wind(main.hud.result_rect.get_center()), "Expanded result panel still blocks wind")
	if "--capture" in OS.get_cmdline_user_args(): root.get_texture().get_image().save_png("res://.godot/star-result-reasons.png")
	main.restart(false)
	sim = main.sim
	sim.humidity.fill(0)
	sim.plot_waters.fill(110)
	sim.refresh_display()
	sim.update_goal(0.5)
	sim.cloud[sim.safety_indices[0][0]] = 0.1
	sim.rain[sim.safety_indices[0][0]] = 0.1
	sim.refresh_display()
	sim.update_goal(0.0)
	sim.plot_safe_times[2] = 2.1
	sim.elapsed_seconds = sim.time_limit_seconds - sim.FIXED_STEP
	main._process(sim.FIXED_STEP)
	await process_frame
	await RenderingServer.frame_post_draw
	check("危险天气未解除" in main.hud.result_details[0] and "安全确认" in main.hud.result_details[1] and "已保住" in main.hud.result_details[2] and sim.result_stars == 1, "Timed result distinguishes danger, incomplete confirmation and safe reward")
	print("PLOT FEEDBACK: ", checks, " checks, ", failures, " failures")
	quit(1 if failures > 0 else 0)
