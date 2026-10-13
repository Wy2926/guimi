shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.28, 0.045, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.89, 0.57, 1.0);
uniform float width : hint_range(0.02, 0.35) = 0.19;
uniform bool thrust = false;
uniform bool ghost = false;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.x, p.y);
	float taper = smoothstep(-1.65, -0.7, a) * (1.0 - smoothstep(0.75, 1.55, a));
	float thickness = width * taper;
	float blade = smoothstep(0.91 - thickness, 0.93 - thickness, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float core = smoothstep(0.91, 0.95, r) * (1.0 - smoothstep(0.96, 0.99, r));
	// A faint inner wake keeps the broad blade readable without a solid white disc.
	float wake = exp(-abs(r - (0.88 - thickness * 0.65)) * 38.0) * 0.13;
	float alpha = (blade + wake) * taper;
	if (thrust) {
		float length_mask = smoothstep(-0.95, -0.55, p.y) * (1.0 - smoothstep(0.70, 0.98, p.y));
		float spear_width = width * smoothstep(-0.95, -0.20, p.y) * (1.0 - smoothstep(0.0, 0.98, p.y));
		alpha = (1.0 - smoothstep(spear_width, spear_width + 0.035, abs(p.x))) * length_mask;
		core = exp(-abs(p.x) * 70.0) * length_mask;
	}
	ALBEDO = mix(tint.rgb, edge.rgb, core);
	EMISSION = ALBEDO * (ghost ? 2.1 : 2.4);
	ALPHA = clamp(alpha, 0.0, 1.0) * opacity;
}
