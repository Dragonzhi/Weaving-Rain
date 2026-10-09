shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D air_map : filter_linear, repeat_disable;
varying vec2 map_uv;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = (world.xz + vec2(12.0, 10.0)) / vec2(24.0, 20.0);
}
void fragment() {
	vec2 field = texture(air_map, map_uv).rg;
	float wet = smoothstep(0.04, 2.8, field.r) * 0.19;
	float cold = smoothstep(0.06, 2.5, field.g) * 0.46;
	ALBEDO = mix(vec3(0.88, 0.97, 0.84), vec3(0.46, 0.68, 0.79), smoothstep(0.06, 0.8, field.g));
	ALPHA = min(wet + cold, 0.38);
}
