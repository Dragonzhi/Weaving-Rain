shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_draw_never;
uniform sampler2D water_map : filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform float threshold = 1.4;
uniform vec3 ray_direction = vec3(-0.5, -0.6, -0.6);
varying vec3 world_front;
void vertex() { world_front = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec4 state_at(vec2 p) {
	vec2 uv = (p + vec2(12.0, 10.0)) / vec2(24.0, 20.0);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return vec4(0.0); }
	return texture(water_map, uv);
}
float density(vec3 p, float q) {
	if (q < 0.04) { return 0.0; }
	float h = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, q);
	float y = (p.y - 3.6) / h;
	return q * max(0.0, 1.0 - y * y);
}
void fragment() {
	vec3 dir = normalize(ray_direction);
	// Use one sampling lattice from the cloud-layer top, including box side faces.
	// Changing sample spacing with the entry face created visible shade seams.
	vec3 ray_top = world_front + dir * ((4.4 - world_front.y) / dir.y);
	float travel = (2.8 - ray_top.y) / dir.y;
	float dt = travel / 32.0;
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vec3 opaque_point = scene_world.xyz / scene_world.w;
	travel = min(travel, dot(opaque_point - ray_top, dir));
	if (travel <= 0.0) { discard; }
	float opacity = 0.0;
	float shade_sum = 0.0;
	for (int i = 0; i < 32; i++) {
		float distance = (float(i) + 0.5) * dt;
		if (distance >= travel) { break; }
		vec3 p = ray_top + dir * distance;
		vec4 s = state_at(p.xz);
		float d = density(p, s.r);
		if (d < 0.002) { continue; }
		float a = (1.0 - opacity) * (1.0 - exp(-d * dt * 5.0));
		float h = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, s.r);
		float upper = clamp((p.y - 3.6) / h, -1.0, 1.0);
		float shade = clamp(s.r / (threshold * 2.0) * 0.64 + s.g / max(s.r, 0.001) * 0.16 - upper * 0.26, 0.0, 1.0);
		shade_sum += shade * a;
		opacity += a;
		if (opacity > 0.985) { break; }
	}
	if (opacity < 0.08) { discard; }
	float shade = shade_sum / max(opacity, 0.001);
	float edge = max(fwidth(shade) * 1.25, 0.003);
	vec3 color = mix(vec3(0.94, 0.96, 0.92), vec3(0.78, 0.85, 0.87), smoothstep(0.13 - edge, 0.13 + edge, shade));
	color = mix(color, vec3(0.59, 0.73, 0.79), smoothstep(0.28 - edge, 0.28 + edge, shade));
	color = mix(color, vec3(0.38, 0.59, 0.69), smoothstep(0.46 - edge, 0.46 + edge, shade));
	ALBEDO = pow(color, vec3(2.2));
	// A narrow antialiased edge, with graphic color bands inside.
	float rim = max(fwidth(opacity), 0.01);
	ALPHA = smoothstep(0.10 - rim, 0.10 + rim, opacity) * 0.97;
}
