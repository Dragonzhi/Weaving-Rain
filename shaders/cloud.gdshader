shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_draw_never;
uniform sampler2D water_map : filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform float threshold = 1.4;
uniform vec3 ray_direction = vec3(-0.5, -0.6, -0.6);
#include "res://shaders/cloud_field.gdshaderinc"
varying vec3 world_front;
void vertex() { world_front = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float density(vec3 p, float q) {
	if (q < 0.04) { return 0.0; }
	float h = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, q);
	float y = (p.y - 3.6) / h;
	return q * max(0.0, 1.0 - y * y);
}
float surface_gap(vec3 p) {
	float q = cloud_state(p.xz).r;
	float h = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, q);
	return max(abs(p.y - 3.6) - h, (0.04 - q) * 0.5);
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
	float shade = 0.0;
	bool found_surface = false;
	for (int i = 0; i < 32; i++) {
		float distance = (float(i) + 0.5) * dt;
		if (distance >= travel) { break; }
		vec3 p = ray_top + dir * distance;
		vec4 s = cloud_state(p.xz);
		float d = density(p, s.r);
		if (d <= 0.0) { continue; }
		if (!found_surface) {
			// Refine the continuous surface, rather than shading the first occupied layer.
			float low = max(0.0, distance - dt);
			float high = distance;
			for (int j = 0; j < 5; j++) {
				float mid = (low + high) * 0.5;
				if (surface_gap(ray_top + dir * mid) > 0.0) { low = mid; } else { high = mid; }
			}
			float lo_gap = surface_gap(ray_top + dir * low);
			float hi_gap = surface_gap(ray_top + dir * high);
			float blend = clamp(lo_gap / max(lo_gap - hi_gap, 0.000001), 0.0, 1.0);
			vec3 surface = ray_top + dir * mix(low, high, blend);
			vec4 front = cloud_state(surface.xz);
			float h = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, front.r);
			float upper = clamp((surface.y - 3.6) / h, -1.0, 1.0);
			shade = clamp(front.r / (threshold * 2.0) * 0.64 + front.g / max(front.r, 0.001) * 0.16 - upper * 0.26, 0.0, 1.0);
			found_surface = true;
		}
		float a = (1.0 - opacity) * (1.0 - exp(-d * dt * 5.0));
		opacity += a;
		if (opacity > 0.985) { break; }
	}
	float edge = max(fwidth(shade) * 0.85, 0.002);
	vec3 color = mix(vec3(0.94, 0.96, 0.92), vec3(0.78, 0.85, 0.87), smoothstep(0.13 - edge, 0.13 + edge, shade));
	color = mix(color, vec3(0.59, 0.73, 0.79), smoothstep(0.28 - edge, 0.28 + edge, shade));
	color = mix(color, vec3(0.38, 0.59, 0.69), smoothstep(0.46 - edge, 0.46 + edge, shade));
	ALBEDO = pow(color, vec3(2.2));
	// A narrow antialiased edge, with graphic color bands inside.
	float rim = max(fwidth(opacity), 0.01);
	ALPHA = smoothstep(0.10 - rim, 0.10 + rim, opacity) * 0.97;
	// Derivatives above run before any transparent fragment is discarded.
	if (opacity < 0.08) { discard; }
}
