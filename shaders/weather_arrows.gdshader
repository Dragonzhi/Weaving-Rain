shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never;
uniform sampler2D water_map : filter_linear, repeat_disable;
uniform float threshold = 1.4;
uniform float visual_time = 0.0;
uniform vec3 ray_direction = vec3(-0.5, -0.6, -0.6);
#include "res://shaders/cloud_field.gdshaderinc"
#include "res://shaders/cloud_occlusion.gdshaderinc"
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
	visibility = cloud_occludes(point) ? 0.0 : 1.0;
}
void fragment() {
	if (visibility < 0.5) { discard; }
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * pulse;
}
