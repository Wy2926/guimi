shader_type spatial;
render_mode cull_disabled;

uniform vec4 tint : source_color = vec4(0.04, 0.48, 0.92, 1.0);
uniform float layer = 0.0;
instance uniform float power = 0.0;
instance uniform float phase = 0.0;
instance uniform float visual_time = 0.0;
varying vec3 local_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
void vertex() { local_position = VERTEX; }
void fragment() {
	float t = visual_time + phase;
	float height = local_position.y;
	float flow = noise(vec2(local_position.x*48.0 + sin(height*9.0-t*2.0), height*8.0-t*(1.0+power*3.0)));
	float vein = pow(max(0.0, 1.0-abs(flow*2.0-1.0)), 12.0);
	float sweep = pow(max(0.0, sin(height*5.5-t*3.2)), 18.0);
	float pulse = 0.8 + 0.2*sin(t*2.0+height*4.0);
	vec3 blue = mix(tint.rgb*0.12, tint.rgb, flow);
	ALBEDO = mix(blue, vec3(0.60,0.83,0.91), clamp(layer*0.5,0.0,1.0));
	METALLIC = layer < 0.5 ? 0.48 : 0.2;
	ROUGHNESS = 0.24;
	if (layer < 0.5) {
		EMISSION = tint.rgb*(0.20+vein*0.95+sweep*0.65+power*1.2);
	} else {
		EMISSION = mix(tint.rgb,vec3(0.63,0.91,1.0),0.5)*(0.65+pulse*0.8+sweep*1.1+power*2.0);
	}
}
