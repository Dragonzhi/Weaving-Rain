shader_type spatial;
render_mode unshaded;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	float broad = sin(p.x * 0.18 + p.y * 0.12);
	vec3 color = mix(vec3(0.24, 0.61, 0.66), vec3(0.32, 0.68, 0.70), broad * 0.5 + 0.5);
	vec2 cell = floor(p / vec2(5.0, 4.0));
	vec2 local = fract(p / vec2(5.0, 4.0)) - 0.5;
	float hash = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float curve = local.y - 0.09 * sin(local.x * 7.0 + TIME * 0.3);
	float line = 1.0 - smoothstep(0.003, 0.003 + fwidth(curve), abs(curve));
	float length_mask = 1.0 - smoothstep(0.16, 0.21, abs(local.x));
	color += vec3(0.13, 0.16, 0.14) * line * length_mask * step(0.68, hash);
	ALBEDO = pow(color, vec3(2.2));
}
