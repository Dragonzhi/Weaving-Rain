// Shared graphic lighting. Projection is a single-layer approximation, not a rain mask.
uniform vec3 light_direction = vec3(-0.6, 1.0, 0.3);
uniform float environment_floor = 0.74;
uniform float cloud_shadow_strength = 0.18;
float scene_tone(vec3 normal) {
	float facing = dot(normalize(normal), normalize(light_direction));
	float edge = max(fwidth(facing), 0.006);
	float middle = max(environment_floor,0.91);
	return mix(environment_floor,middle,smoothstep(0.35-edge,0.35+edge,facing))
		+ (max(1.04,middle)-middle)*smoothstep(0.72-edge,0.72+edge,facing);
}
float scene_shadow(vec3 receiver) {
	if (cloud_shadow_strength <= 0.0) { return 0.0; }
	vec2 position = receiver.xz + light_direction.xz / max(light_direction.y,0.001) * max(0.0,3.6-receiver.y);
	return smoothstep(0.06,1.5,cloud_state(position).r) * cloud_shadow_strength;
}
vec3 receive_cloud_shadow(vec3 color, vec3 receiver, float strength) {
	return color * (vec3(1.0) - scene_shadow(receiver) * strength * vec3(0.90,0.76,0.66));
}
