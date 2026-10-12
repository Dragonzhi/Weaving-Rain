shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D air_map : filter_linear, repeat_disable;
uniform bool edge_fade = true;
uniform float visual_time = 0.0;
varying vec2 map_uv;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = (world.xz + vec2(16.0, 14.0)) / vec2(32.0, 28.0);
}
void fragment() {
	vec2 p = map_uv * vec2(32.0, 28.0) - vec2(16.0, 14.0);
	float fade = edge_fade ? smoothstep(0.0, 2.0, min(16.0 - abs(p.x), 14.0 - abs(p.y))) : 1.0;
	vec2 field = texture(air_map, map_uv).rg * fade;
	float breathing = 0.92 + 0.08 * sin(visual_time * 1.1 + map_uv.x * 17.0 + map_uv.y * 13.0);
	float wet = smoothstep(0.04, 2.8, field.r) * 0.22 * breathing;
	float cold = smoothstep(0.06, 2.5, field.g) * 0.46;
	ALBEDO = mix(vec3(0.88, 0.97, 0.84), vec3(0.46, 0.68, 0.79), smoothstep(0.06, 0.8, field.g));
	ALPHA = min(wet + cold, 0.38);
}
