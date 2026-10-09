shader_type spatial;
render_mode unshaded, fog_disabled;
uniform float visual_time = 0.0;
uniform vec4 rain_color : source_color = vec4(0.65, 0.89, 0.91, 1.0);
void vertex() {
	// CPU chooses real rainy cells; GPU only animates a drop within its column.
	VERTEX.y += fract(INSTANCE_CUSTOM.x - visual_time * 1.8) * INSTANCE_CUSTOM.y;
}
void fragment() { ALBEDO = rain_color.rgb; }
