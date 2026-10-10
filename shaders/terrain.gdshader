shader_type spatial;
render_mode unshaded;
uniform sampler2D water_map : filter_linear, repeat_disable;
#include "res://shaders/cloud_field.gdshaderinc"
uniform vec4 base_color : source_color = vec4(0.55, 0.72, 0.51, 1.0);
uniform bool shore = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float light = dot(normalize(world_normal), normalize(vec3(-0.6, 1.0, 0.3)));
	float tone = light > 0.72 ? 1.04 : (light > 0.35 ? 0.91 : 0.73);
	vec3 color = base_color.rgb * tone;
	if (!shore && world_position.y > 0.65) {
		color = mix(color, vec3(0.39, 0.62, 0.48) * tone, smoothstep(0.65, 2.6, world_position.y) * 0.6);
	}
	float q = cloud_state(world_position.xz).r;
	color *= 1.0 - smoothstep(0.06, 1.5, q) * 0.22;
	ALBEDO = color;
}
