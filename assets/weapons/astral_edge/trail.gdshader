shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float visual_time = 0.0;
void fragment() {
	float edge = pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),2.0);
	float thin = pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),18.0);
	float life = pow(UV.x,1.8);
	float ripple = 0.7+0.3*sin(UV.x*30.0-visual_time*14.0);
	ALBEDO = mix(vec3(0.015,0.19,0.9),vec3(0.5,0.85,1.0),thin)*(edge+thin)*life*ripple*1.8;
	ALPHA = edge*life;
}
