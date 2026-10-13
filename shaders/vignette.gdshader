shader_type canvas_item;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float shade = smoothstep(0.32, 1.45, length(p * vec2(0.84, 1.0)));
	COLOR = vec4(0.018, 0.029, 0.04, shade * 0.57);
}
