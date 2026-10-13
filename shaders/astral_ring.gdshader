shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool warning = false;
uniform vec4 tint : source_color = vec4(0.13, 0.75, 1.0, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.88, 0.63, 1.0);

float stroke(float value, float center, float width) {
	return 1.0 - smoothstep(width * 0.35, width, abs(value - center));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float turn = angle + progress * (warning ? 0.3 : 0.8);
	float outside = stroke(r, 0.972, 0.012);
	float inner = stroke(r, 0.74, 0.009);
	float arcs = stroke(r, 0.85, 0.007) * smoothstep(-0.3, 0.1, sin(turn * 6.0));
	float teeth = pow(max(0.0, cos(turn * 24.0)), 22.0);
	teeth *= smoothstep(0.87, 0.90, r) * (1.0 - smoothstep(0.94, 0.96, r));
	float inlay = stroke(r, 0.56 + 0.045 * cos(turn * 6.0), 0.007) * 0.58;
	float spokes = pow(max(0.0, cos((angle - progress * 0.15) * 6.0)), 130.0);
	spokes *= smoothstep(0.54, 0.60, r) * (1.0 - smoothstep(0.75, 0.80, r));
	float closing = stroke(r, mix(0.92, 0.055, progress), 0.017);
	float halo = exp(-abs(r - (warning ? mix(0.92, 0.055, progress) : 0.75)) * 30.0) * 0.08;
	float fade = smoothstep(0.0, 0.10, progress);
	if (!warning) {
		fade *= 1.0 - smoothstep(0.38, 1.0, progress);
		closing *= 0.25;
	} else {
		// Keep the outer damage boundary fixed while the closing ring counts down.
		fade *= 0.78 + 0.22 * sin(progress * 19.0);
	}
	float gold = teeth + spokes + closing;
	float blue = outside * 0.75 + inner * 0.5 + arcs + inlay;
	ALBEDO = mix(tint.rgb, edge.rgb, clamp(gold / max(0.001, gold + blue), 0.0, 1.0));
	EMISSION = ALBEDO * (warning ? 1.25 : 1.6);
	ALPHA = clamp(blue + gold + halo, 0.0, 1.0) * fade;
}
