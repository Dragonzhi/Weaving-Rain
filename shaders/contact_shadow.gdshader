shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float contact_shadow_strength = 0.14;
uniform bool plot_shadow = false;
uniform bool ellipse = false;
uniform vec2 plot_axes = vec2(1.0);
varying vec2 local_position;
void vertex() { local_position = VERTEX.xz; }
void fragment() {
	float radius = length((UV-vec2(0.5))*2.0);
	ALBEDO = vec3(0.19,0.28,0.25);
	float alpha = 1.0-smoothstep(0.15,1.0,radius);
	if (plot_shadow) {
		float edge_distance = ellipse ? (length(local_position/plot_axes)-1.0)*min(plot_axes.x,plot_axes.y) : max(abs(local_position.x)-plot_axes.x,abs(local_position.y)-plot_axes.y);
		alpha = 1.0-smoothstep(-0.04,0.16,edge_distance);
	}
	ALPHA = alpha * contact_shadow_strength;
}
