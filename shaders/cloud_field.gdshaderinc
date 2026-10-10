// Positive cubic B-spline reconstruction; CPU sample_cloud uses the same weights.
vec4 spline_weights(float f) {
	float f2 = f * f;
	float f3 = f2 * f;
	return vec4(pow(1.0 - f, 3.0), 3.0 * f3 - 6.0 * f2 + 4.0,
		-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0, f3) / 6.0;
}
vec4 cloud_state(vec2 p) {
	vec2 uv = (p + vec2(12.0, 10.0)) / vec2(24.0, 20.0);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { return vec4(0.0); }
	vec2 size = vec2(textureSize(water_map, 0));
	vec2 grid = uv * size - 0.5;
	vec2 base = floor(grid);
	vec4 wx = spline_weights(fract(grid.x));
	vec4 wz = spline_weights(fract(grid.y));
	vec2 gx = vec2(wx.x + wx.y, wx.z + wx.w);
	vec2 gz = vec2(wz.x + wz.y, wz.z + wz.w);
	vec2 x = (base.x + vec2(-1.0 + wx.y / gx.x, 1.0 + wx.w / gx.y) + 0.5) / size.x;
	vec2 z = (base.y + vec2(-1.0 + wz.y / gz.x, 1.0 + wz.w / gz.y) + 0.5) / size.y;
	return textureLod(water_map, vec2(x.x, z.x), 0.0) * gx.x * gz.x
		+ textureLod(water_map, vec2(x.y, z.x), 0.0) * gx.y * gz.x
		+ textureLod(water_map, vec2(x.x, z.y), 0.0) * gx.x * gz.y
		+ textureLod(water_map, vec2(x.y, z.y), 0.0) * gx.y * gz.y;
}
