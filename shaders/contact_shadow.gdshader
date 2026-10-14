shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float contact_shadow_strength = 0.14;
void fragment() {
	float radius = length((UV-vec2(0.5))*2.0);
	ALBEDO = vec3(0.19,0.28,0.25);
	ALPHA = (1.0-smoothstep(0.15,1.0,radius))*contact_shadow_strength;
}
