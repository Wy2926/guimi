shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.05,0.42,1.0,1.0);
instance uniform float power = 0.0;
instance uniform float phase = 0.0;
instance uniform float visual_time = 0.0;
void fragment() {
	float t = visual_time + phase;
	float y = UV.y;
	float curl = sin(y*17.0-t*2.0)*0.035 + sin(y*31.0+t*1.7)*0.017;
	float x = UV.x-0.5;
	float contour = 0.12+0.07*sin(y*3.14159);
	float filament = exp(-abs(abs(x+curl)-contour)*95.0);
	float soft = exp(-abs(x)*12.0)*0.12;
	float tips = smoothstep(0.0,0.12,y)*(1.0-smoothstep(0.88,1.0,y));
	float energy = (filament+soft)*tips*(0.22+power*0.65);
	ALBEDO = tint.rgb*energy*(1.2+power);
	ALPHA = clamp(energy,0.0,1.0);
}
