// Same 32-step density lattice as the visible cloud. Used by airborne effects,
// because the volume never writes a solid cloud surface to the scene depth.
bool cloud_occludes(vec3 point) {
	vec3 dir = normalize(ray_direction);
	vec3 top = point + dir * ((4.4 - point.y) / dir.y);
	float end = min((2.8 - top.y) / dir.y, dot(point - top, dir));
	float dt = (2.8 - 4.4) / dir.y / 32.0;
	float opacity = 0.0;
	for (int i = 0; i < 32; i++) {
		float distance = (float(i) + 0.5) * dt;
		if (distance >= end) { break; }
		vec3 p = top + dir * distance;
		if (abs(p.y - 3.6) > 0.70001) { continue; }
		float q = cloud_state(p.xz).r;
		if (q < 0.04) { continue; }
		float h = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, q);
		float y = (p.y - 3.6) / h;
		float d = q * max(0.0, 1.0 - y * y);
		opacity += (1.0 - opacity) * (1.0 - exp(-d * dt * 5.0));
		if (opacity > 0.10) { return true; }
	}
	return false;
}
