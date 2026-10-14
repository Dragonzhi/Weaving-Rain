shader_type spatial;
render_mode unshaded;
uniform sampler2D water_map : filter_linear, repeat_disable;
#include "res://shaders/cloud_field.gdshaderinc"
#include "res://shaders/scene_lighting.gdshaderinc"
uniform vec4 base_color : source_color = vec4(0.55, 0.72, 0.51, 1.0);
uniform bool shore = false;
uniform bool ground_material = true;
uniform bool soil_rows = false;
uniform bool water_surface = false;
uniform vec2 plot_center = vec2(0.0);
uniform float visual_time = 0.0;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float tone = scene_tone(world_normal);
	vec3 color = base_color.rgb * tone;
	if (ground_material && !shore && world_position.y > 0.65) {
		color = mix(color, vec3(0.39, 0.62, 0.48) * tone, smoothstep(0.65, 2.6, world_position.y) * 0.6);
	}
	if (soil_rows) {
		float groove = abs(fract((world_position.x-plot_center.x)/0.60)-0.5);
		color *= 1.0 - (1.0-smoothstep(0.025,0.075,groove))*0.045;
	}
	if (water_surface) {
		vec2 p = world_position.xz-plot_center;
		float wave = abs(fract(length(p)*1.7-visual_time*0.08)-0.5);
		color += vec3(0.015,0.018,0.017)*(1.0-smoothstep(0.010,0.030,wave));
	}
	color = receive_cloud_shadow(color,world_position,water_surface ? 0.5 : 1.0);
	ALBEDO = color;
}
