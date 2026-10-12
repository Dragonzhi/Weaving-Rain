shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D air_map : filter_linear, repeat_disable;
uniform bool edge_fade = true;
uniform float visual_time = 0.0;
varying vec2 map_uv;
// Positive compact radial reconstruction: concentrated wet cells have rounded
// support rather than the rectangular footprint of bilinear interpolation.
float moisture_at(vec2 uv) {
	vec2 at = uv * vec2(64.0, 56.0) - 0.5;
	ivec2 cell = ivec2(floor(at));
	float value = 0.0;
	float weights = 0.0;
	for (int z = -2; z <= 3; z++) {
		for (int x = -2; x <= 3; x++) {
			ivec2 pos = cell + ivec2(x, z);
			vec2 delta = vec2(pos) - at;
			float base = max(0.0, 1.0 - dot(delta, delta) / 9.0);
			float weight = base * base * base;
			if (weight > 0.0) {
				value += texelFetch(air_map, clamp(pos, ivec2(0), ivec2(63, 55)), 0).r * weight;
			}
			weights += weight;
		}
	}
	return value / max(weights, 0.000001);
}
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = (world.xz + vec2(16.0, 14.0)) / vec2(32.0, 28.0);
}
void fragment() {
	vec2 p = map_uv * vec2(32.0, 28.0) - vec2(16.0, 14.0);
	float fade = edge_fade ? smoothstep(0.0, 2.0, min(16.0 - abs(p.x), 14.0 - abs(p.y))) : 1.0;
	vec2 field = vec2(moisture_at(map_uv), texture(air_map, map_uv).g) * fade;
	float breathing = 0.92 + 0.08 * sin(visual_time * 1.1 + map_uv.x * 17.0 + map_uv.y * 13.0);
	float wet = smoothstep(0.04, 2.8, field.r) * 0.22 * breathing;
	float cold = smoothstep(0.06, 2.5, field.g) * 0.46;
	ALBEDO = mix(vec3(0.88, 0.97, 0.84), vec3(0.46, 0.68, 0.79), smoothstep(0.06, 0.8, field.g));
	ALPHA = min(wet + cold, 0.38);
}
