shader_type spatial;
render_mode unshaded, blend_add, shadows_disabled;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.75, 0.36, 1.0);
uniform float ghost_strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.8) * ghost_strength;
	ALBEDO = mix(vec3(0.8, 0.035, 0.19), tint.rgb, flash / max(flash + rim, 0.0001));
	EMISSION = ALBEDO * 1.6;
	ALPHA = max(flash, rim * 0.7);
}
