shader_type spatial;
render_mode unshaded, blend_add, shadows_disabled;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.75, 0.36, 1.0);
void fragment() {
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 1.6;
	ALPHA = flash;
}
