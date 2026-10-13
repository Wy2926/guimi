shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool inward = false;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float travel = 1.0 - pow(1.0 - progress, 2.0);
	float radius = inward ? mix(0.96, 0.24, progress) : mix(0.18, 0.96, travel);
	float width = inward ? 0.016 : mix(0.038, 0.012, progress);
	float gap = abs(r - radius);
	float edge = 1.0 - smoothstep(width * 0.35, width, gap);
	float halo = (1.0 - smoothstep(width, width * 5.0, gap)) * 0.19;
	float sweep = 0.65 + 0.35 * sin(a * 3.0 - progress * 9.0);
	float echo_r = radius * 0.81 + sin(a * 6.0 + progress * 4.0) * 0.018;
	float echo = (1.0 - smoothstep(0.003, 0.018, abs(r - echo_r))) * 0.32;
	float cuts = pow(max(0.0, cos(a * 12.0 + progress * 2.0)), 28.0);
	cuts *= smoothstep(radius - 0.2, radius - 0.03, r) * (1.0 - smoothstep(radius, radius + 0.015, r)) * 0.48;
	float fade = inward ? sin(progress * 3.14159) : pow(1.0 - progress, 1.15);
	ALBEDO = mix(vec3(0.06, 0.42, 0.85), vec3(0.67, 1.0, 0.94), edge);
	EMISSION = ALBEDO * (inward ? 1.4 : 2.1);
	ALPHA = (edge * sweep + halo + echo + cuts) * fade;
}
