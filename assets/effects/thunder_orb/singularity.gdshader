shader_type spatial;
render_mode unshaded, shadows_disabled;

// Opaque event horizon: the black center must occlude particles behind it.
// Local time freezes with the skill; no global TIME or screen-copy dependency.
instance uniform float visual_time = 0.0;
instance uniform float power = 0.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 8.0);
	float corona = pow(1.0 - facing, 3.0) * 0.07;
	float pulse = 0.88 + 0.12 * sin(visual_time * 5.0);
	ALBEDO = vec3(0.0005, 0.0001, 0.0015);
	EMISSION = mix(vec3(0.28, 0.018, 0.65), vec3(0.72, 0.38, 1.0), rim)
		* (rim * 3.0 + corona) * (pulse + power * 0.8);
}
