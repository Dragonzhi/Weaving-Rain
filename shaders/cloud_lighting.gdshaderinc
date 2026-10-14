// Exact derivative of the same cubic reconstruction, only at the visible surface.
// Two groups per axis retain bilinear merging; no secondary raymarch.
vec4 spline_derivative(float f) {
	return vec4(-0.5*(1.0-f)*(1.0-f),1.5*f*f-2.0*f,-1.5*f*f+f+0.5,0.5*f*f);
}
float weighted_cloud(vec2 base, vec2 size, vec4 wx, vec4 wz) {
	vec2 gx = vec2(wx.x+wx.y,wx.z+wx.w);
	vec2 gz = vec2(wz.x+wz.y,wz.z+wz.w);
	vec2 x = (base.x+vec2(-1.0+wx.y/gx.x,1.0+wx.w/gx.y)+0.5)/size.x;
	vec2 z = (base.y+vec2(-1.0+wz.y/gz.x,1.0+wz.w/gz.y)+0.5)/size.y;
	return textureLod(water_map,vec2(x.x,z.x),0.0).r*gx.x*gz.x
		+ textureLod(water_map,vec2(x.y,z.x),0.0).r*gx.y*gz.x
		+ textureLod(water_map,vec2(x.x,z.y),0.0).r*gx.x*gz.y
		+ textureLod(water_map,vec2(x.y,z.y),0.0).r*gx.y*gz.y;
}
vec2 cloud_gradient(vec2 p, float q) {
	vec2 size = vec2(textureSize(water_map,0));
	vec2 grid = (p+vec2(16.0,14.0))/vec2(32.0,28.0)*size-0.5;
	vec2 f = fract(grid);
	vec4 wx = spline_weights(f.x);
	vec4 wz = spline_weights(f.y);
	vec2 result = vec2(weighted_cloud(floor(grid),size,spline_derivative(f.x),wz),
		weighted_cloud(floor(grid),size,wx,spline_derivative(f.y))) * size/vec2(32.0,28.0);
	if (edge_fade) {
		vec2 edges = vec2(16.0,14.0)-abs(p);
		float t = clamp(min(edges.x,edges.y)/2.0,0.0,1.0);
		float fade = smoothstep(0.0,2.0,min(edges.x,edges.y));
		vec2 edge_normal = edges.x<edges.y ? vec2(-sign(p.x),0.0) : vec2(0.0,-sign(p.y));
		result = result*fade + q/max(fade,0.000001)*3.0*t*(1.0-t)*edge_normal;
	}
	return result;
}
