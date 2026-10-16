shader_type spatial;
render_mode unshaded;
uniform sampler2D water_map : filter_linear, repeat_disable;
#include "res://shaders/cloud_field.gdshaderinc"
#include "res://shaders/scene_lighting.gdshaderinc"
varying vec3 world_position;
uniform sampler2D sea_map : filter_linear, repeat_disable;
uniform bool warm_enabled = false;
uniform float visual_time = 0.0;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	float broad = sin(p.x * 0.18 + p.y * 0.12);
	vec3 color = mix(vec3(0.24, 0.61, 0.66), vec3(0.32, 0.68, 0.70), broad * 0.5 + 0.5);
	vec2 map_uv = (p + vec2(16.0, 14.0)) / vec2(32.0, 28.0);
	if (warm_enabled && all(greaterThanEqual(map_uv, vec2(0.0))) && all(lessThanEqual(map_uv, vec2(1.0)))) {
		float energy = texture(sea_map, map_uv).b;
		color = mix(color, vec3(0.48, 0.72, 0.64), energy * 0.6);
	}
	vec2 cell = floor(p / vec2(5.0, 4.0));
	vec2 local = fract(p / vec2(5.0, 4.0)) - 0.5;
	float hash = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float phase = hash * 6.28318;
	float time = visual_time * mix(0.15,0.35,hash);
	// Unequal strokes: long arcs, paired ripples and broken short threads.
	float x = local.x + 0.07 * sin(time + phase);
	float y = local.y + (hash - 0.5) * 0.30;
	float curve = y - mix(0.025,0.13,hash) * sin(x * mix(3.0,8.0,hash) + phase + time);
	float width = mix(0.0015,0.003,hash);
	float aa = max(fwidth(curve),0.0001);
	float line = 1.0 - smoothstep(width,width+aa,abs(curve));
	float length = mix(0.08,0.30,fract(hash*7.31));
	float length_mask = 1.0 - smoothstep(length*0.65,length,abs(x));
	float broken = hash > 0.86 ? smoothstep(0.10,0.30,abs(sin(x*24.0+phase))) : 1.0;
	float pair = (1.0-smoothstep(width,width+aa,abs(curve-0.048))) * step(0.77,hash) * (1.0-smoothstep(length*0.35,length*0.7,abs(x+0.025)));
	color += vec3(0.13,0.16,0.14) * (line*length_mask*broken+pair*0.45) * step(0.58,hash) * (0.55+0.35*sin(time*0.4+phase));
	color = receive_cloud_shadow(color,world_position,0.30);
	ALBEDO = pow(color, vec3(2.2));
}
