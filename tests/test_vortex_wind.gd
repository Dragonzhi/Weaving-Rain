extends SceneTree
const Sim = preload("res://scripts/weather_simulation.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run_source(tier: int, spin: int = 1, group: float = 0.1) -> RefCounted:
	var sim := Sim.new()
	sim.sandbox = true
	sim.add_vortex(Vector2(5, 3), 2.5, spin, tier)
	for n in roundi(1.0 / group): sim.step(group)
	return sim
func _init() -> void:
	var weak := run_source(0)
	var medium := run_source(1)
	var strong := run_source(2)
	var at := Vector2(6.25, 3)
	check(weak.velocity_at(at, false).x < 0 and medium.velocity_at(at, false).x < weak.velocity_at(at, false).x and strong.velocity_at(at, false).x < medium.velocity_at(at, false).x, "Three tiers give fixed and distinct inward force")
	check(medium.velocity_at(at, false).y > 0 and run_source(1, -1).velocity_at(at, false).y < 0, "Hand direction controls actual tangential wind")
	check(medium.last_lift == 0 and Array(medium.cloud).max() == 0, "Flat gathering alone cannot create cloud")
	check(absf(medium.water_total() - medium.initial_water) < 0.01, "Gathering conserves real water")
	check(Array(strong.wind).all(func(w): return w.length() <= strong.settings.max_wind + 0.00001), "Combined radial and tangential speed stays capped")
	var grouped := run_source(1, 1, 0.5)
	check(grouped.velocity_at(at, false).distance_to(medium.velocity_at(at, false)) < 0.0001 and absf(grouped.wind_sources[0].remaining - medium.wind_sources[0].remaining) < 0.00001, "Fixed-step catch-up preserves force and lifetime")
	var id: int = medium.wind_sources[0].id
	var before: float = medium.velocity_at(at, false).length()
	medium.remove_wind_source(id)
	medium.step(0.1)
	check(medium.wind_sources.is_empty() and medium.velocity_at(at, false).length() > 0 and medium.velocity_at(at, false).length() < before, "Closing stops force while residual wind decays")
	var sim := Sim.new()
	check(sim.add_vortex(Vector2(5, 3), 2, 1, 1).ok and sim.add_wind_source(Vector2(-5, 0), Vector2.RIGHT, 0.5).ok and not sim.add_vortex(Vector2(3, 3), 2, -1, 2).ok, "Band and vortex share source slots")
	check(not sim.add_vortex(Vector2.ZERO, 0, 1, 1).ok and not sim.add_vortex(Vector2.ZERO, 2, 0, 1).ok and not sim.add_vortex(Vector2.ZERO, 2, 1, 3).ok, "Invalid geometry and tier cannot create sources")
	sim = Sim.new()
	sim.sandbox = true
	sim.settings.source_lifetime = 1.0
	sim.settings.source_fade_seconds = 0.5
	sim.add_vortex(Vector2(5, 3), 2, 1, 1)
	sim.step(1.1)
	check(sim.wind_sources.is_empty(), "Vortex expires by simulation time")
	print("VORTEX WIND: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
