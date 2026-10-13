shader_type spatial;
render_mode specular_schlick_ggx;

varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	vec2 grid = p / vec2(1.48, 1.1);
	grid.x += mod(floor(grid.y), 2.0) * 0.5;
	vec2 edge = min(fract(grid), 1.0 - fract(grid));
	float grout = smoothstep(0.009, 0.025, min(edge.x, edge.y));
	float tile = hash(floor(grid));
	float grain = hash(floor(p * 95.0));
	vec3 stone = mix(vec3(0.055, 0.076, 0.088), vec3(0.098, 0.123, 0.133), tile);
	stone *= 0.94 + grain * 0.12;
	float r = length(p);
	float ring = 1.0 - smoothstep(0.012, 0.025, abs(r - 4.7));
	ring += 0.6 * (1.0 - smoothstep(0.012, 0.024, abs(r - 4.86)));
	ring += 0.55 * (1.0 - smoothstep(0.014, 0.025, abs(r - 2.5)));
	float diamond = abs(abs(p.x) + abs(p.y) - 1.15);
	ring += 0.4 * (1.0 - smoothstep(0.012, 0.024, diamond));
	ALBEDO = mix(vec3(0.018, 0.030, 0.036), stone, grout);
	ALBEDO = mix(ALBEDO, vec3(0.41, 0.32, 0.19), clamp(ring, 0.0, 0.85));
	ROUGHNESS = mix(0.87, 0.52, ring);
	METALLIC = clamp(ring * 0.45, 0.0, 1.0);
}
