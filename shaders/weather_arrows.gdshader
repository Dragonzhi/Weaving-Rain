shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never;
uniform sampler2D water_map : filter_linear, repeat_disable;
uniform float threshold = 1.4;
uniform float visual_time = 0.0;
uniform vec3 ray_direction = vec3(-0.5, -0.6, -0.6);
#include "res://shaders/cloud_field.gdshaderinc"
varying float visibility;
varying float pulse;
void vertex() {
	// Stable cell phases survive the CPU field refresh. Fade both ends so
	// restarting at the tail is never seen as a backwards jump.
	float phase = fract(visual_time * 0.65 + INSTANCE_CUSTOM.z);
	vec3 movement = vec3(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.w, INSTANCE_CUSTOM.y);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * movement * phase;
	pulse = smoothstep(0.0, 0.18, phase) * (1.0 - smoothstep(0.76, 1.0, phase));
	vec3 point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	visibility = 1.0;
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
		if (opacity > 0.10) { visibility = 0.0; break; }
	}
}
void fragment() {
	if (visibility < 0.5) { discard; }
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * pulse;
}
