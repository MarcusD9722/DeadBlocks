shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Tools and weapons (M4.3, ToolModels): one material per part. Wood and stone take a layer of a
// photo texture array, mapped in the model's own space with the picture's grain running along
// the model's height (up a handle); metals are plain colours with a faint brushed streak.
// `held`: the tool in your own hand is drawn in front of the world (its depth squeezed towards
// the camera), so it never sinks into a wall you stand against.

uniform sampler2DArray tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float layer = -1.0;     // the texture array's layer; -1 = no picture
uniform float tex_scale = 1.0;  // picture repeats per metre
uniform vec3 tint : source_color = vec3(1.0);
uniform float metal = 0.0;
uniform float rough = 0.8;
uniform float streak = 0.0;     // brushed-metal or fibre streaks along the model's height
uniform vec3 glow : source_color = vec3(0.0);
uniform bool held = false;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	// (Once the shader writes POSITION, Godot always takes it: work it out every time.)
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (held) {
		// Reversed depth (1 at the near plane): keep the order within the model, but in the
		// last 2% in front of everything else.
		POSITION.z = mix(POSITION.w, POSITION.z, 0.02);
	}
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void fragment() {
	vec3 alb = tint;
	if (layer >= 0.0) {
		vec3 an = abs(normalize(onrm));
		vec3 q = opos * tex_scale;
		vec3 cx = texture(tex, vec3(q.y, q.z, layer)).rgb;
		vec3 cy = texture(tex, vec3(q.x, q.z, layer)).rgb;
		vec3 cz = texture(tex, vec3(q.y, q.x, layer)).rgb;
		vec3 w = an * an * an * an;
		w /= (w.x + w.y + w.z + 1e-5);
		alb *= cx * w.x + cy * w.y + cz * w.z;
	}
	if (streak > 0.0) {
		float n = vnoise(vec3(opos.x * 90.0, opos.y * 6.0, opos.z * 90.0)) * 0.7 + vnoise(opos * 30.0) * 0.3;
		alb *= 1.0 + streak * (n - 0.5);
	}
	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	EMISSION = glow;
}
