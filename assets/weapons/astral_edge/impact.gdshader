shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float progress = 0.0;
uniform float strike_angle = -0.65;
void fragment() {
	vec2 p = (UV-0.5)*2.0;
	p.y = -p.y;
	float r = length(p);
	float angle = atan(p.y,p.x);
	float fade = pow(1.0-progress,2.0);
	float snap = exp(-progress*12.0);
	vec2 axis = vec2(cos(strike_angle),sin(strike_angle));
	float along = dot(p,axis);
	float across = dot(p,vec2(-axis.y,axis.x));
	float cut = exp(-abs(across)*65.0-abs(along)*2.4)*snap*3.0;
	float spike = pow(abs(sin(angle*2.0+0.25)),32.0)*exp(-r*4.0);
	float splinter = pow(abs(sin(angle*13.0+sin(angle*7.0))),18.0);
	float ring_r = 0.08+progress*0.86;
	float ring = exp(-abs(r-ring_r)*90.0)*(0.35+splinter*0.65)*(1.0-progress);
	float core = exp(-r*18.0)*(fade+snap*4.0);
	float rays = splinter*exp(-r*5.0)*fade*0.7;
	float value = (core+cut+spike*fade*2.0+rays+ring)*(1.0-smoothstep(0.8,1.0,r));
	vec3 color = mix(vec3(0.025,0.33,1.0),vec3(0.95,0.98,1.0),clamp(exp(-r*10.0)+snap*0.75,0.0,1.0));
	ALBEDO = color*value*3.0;
	ALPHA = clamp(value,0.0,1.0);
}
