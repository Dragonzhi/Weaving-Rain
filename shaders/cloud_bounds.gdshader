shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D water_map : filter_nearest, repeat_disable;
void fragment() {
	ivec2 size = textureSize(water_map, 0);
	ivec2 cell = ivec2(floor(UV * vec2(size)));
	float maximum = 0.0;
	// Positive B-spline weights use exactly this 4x4 footprint.
	for (int z = -1; z <= 2; z++) {
		for (int x = -1; x <= 2; x++) {
			maximum = max(maximum, texelFetch(water_map, clamp(cell + ivec2(x,z), ivec2(0), size - ivec2(1)), 0).r);
		}
	}
	// HDR2D uses half floats. Round conservatively upward, including tiny values;
	// a larger bound only costs samples and cannot remove real cloud density.
	COLOR = vec4(maximum * 1.001 + 0.0001, 0.0, 0.0, 1.0);
}
