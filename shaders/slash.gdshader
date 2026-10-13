shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.28, 0.045, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.89, 0.57, 1.0);
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.x, p.y);
	float taper = smoothstep(-1.65, -0.7, a) * (1.0 - smoothstep(0.75, 1.55, a));
	float width = 0.19 * taper;
	float blade = smoothstep(0.91 - width, 0.93 - width, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float core = smoothstep(0.91, 0.95, r) * (1.0 - smoothstep(0.96, 0.99, r));
	ALBEDO = mix(tint.rgb, edge.rgb, core);
	EMISSION = ALBEDO * 2.4;
	ALPHA = blade * taper * opacity;
}
