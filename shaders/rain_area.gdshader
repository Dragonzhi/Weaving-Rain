shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D rain_map : filter_linear, repeat_disable;
uniform bool outline_pass = false;
uniform float visual_time = 0.0;
uniform vec4 hint_color : source_color = vec4(0.40, 0.66, 0.76, 1.0);
uniform float idle_alpha = 0.10;
uniform float active_alpha = 0.23;
uniform float outline_width = 1.25;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	if (depth <= 0.0) { discard; }
	vec4 scene = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec2 p = scene.xz / scene.w;
	vec2 uv = (p + vec2(16.0, 14.0)) / vec2(32.0, 28.0);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { discard; }
	// Sample the cell-centered binary field directly. Bilinear reconstruction softens
	// the half-unit grid edge without changing which cells actually received rain.
	vec4 state = textureLod(rain_map, uv, 0.0);
	// Binary coverage, independent of intensity: even very weak real rain has an edge.
	float width = max(fwidth(state.g) * outline_width, 0.003);
	float mask = smoothstep(0.5 - width, 0.5 + width, state.g);
	float focus = clamp(state.b / max(state.g, 0.001), 0.0, 1.0);
	vec3 color = hint_color.rgb;
	float alpha;
	if (outline_pass) {
		float edge = 1.0 - smoothstep(width * 0.5, width * 1.5, abs(state.g - 0.5));
		alpha = edge * mix(0.25, 0.58, focus);
		color = mix(color, vec3(0.70, 0.86, 0.90), 0.55);
	} else {
		float intensity = clamp(state.r / 0.55, 0.0, 1.0);
		alpha = mask * mix(idle_alpha, active_alpha, focus) * mix(0.65, 1.0, intensity);
		vec2 tile = floor(p / 2.4);
		float seed = fract(sin(dot(tile, vec2(127.1, 311.7))) * 43758.5453);
		vec2 offset = fract(p / 2.4) - vec2(0.25 + seed * 0.5, 0.5);
		float phase = fract(visual_time * 0.85 + seed);
		float ripple = 1.0 - smoothstep(0.004, 0.014, abs(length(offset) - mix(0.015, 0.12, phase)));
		ripple *= step(0.77, seed) * sin(phase * 3.14159265) * mask;
		color = mix(color, vec3(0.78, 0.90, 0.94), ripple * 0.8);
		alpha = max(alpha, ripple * mix(0.15, 0.30, focus));
	}
	ALBEDO = color;
	ALPHA = alpha;
}
