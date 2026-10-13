shader_type spatial;
// Airborne strokes must not replace the ground depth used by clouds and rain-area projection.
render_mode unshaded, fog_disabled, depth_draw_never;
uniform float visual_time = 0.0;
uniform vec4 rain_color : source_color = vec4(0.65, 0.89, 0.91, 1.0);
uniform sampler2D water_map : filter_linear, repeat_disable;
uniform float threshold = 1.4;
uniform vec3 ray_direction = vec3(-0.5, -0.6, -0.6);
#include "res://shaders/cloud_field.gdshaderinc"
#include "res://shaders/cloud_occlusion.gdshaderinc"
varying float visibility;
void vertex() {
	// CPU chooses real rainy cells; GPU only animates a drop within its column.
	vec3 anchor = MODEL_MATRIX[3].xyz;
	float q = cloud_state(anchor.xz).r;
	float half_height = 0.12 + 0.58 * smoothstep(0.04, threshold * 1.8, q);
	// Keep the entire stroke below the same curved cloud base used by rendering/picking.
	float travel = max(0.0, 3.6 - half_height - 0.11 - anchor.y);
	VERTEX.y += fract(INSTANCE_CUSTOM.x - visual_time * 1.8) * travel;
	visibility = cloud_occludes((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz) ? 0.0 : 1.0;
}
void fragment() {
	if (visibility < 0.5) { discard; }
	ALBEDO = rain_color.rgb;
	// The transparent pass is ordered before clouds; rain never replaces ground depth.
	ALPHA = 1.0;
}
