shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Cubes, boxes and log trunks: one layer of the block texture array per face (UV2.x), with
// normal maps (blue = height). UV2.y is 1 on round trunks. The vertex colour's alpha is the sky
// light (dark under cover and in caves; only ambient light is dimmed, see SmoothMesher).
// Cube faces get softly rounded edges: the normal bends outwards near each block's border.

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float bevel = 0.11;   // metres of rounding at each block edge
uniform float min_light = 0.12;  // ambient light left in caves (Settings: light in caves)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float edge(float f) {
	// -1..0 near the low border, 0 in the middle, 0..1 near the high border.
	return -clamp(1.0 - f / bevel, 0.0, 1.0) + clamp(1.0 - (1.0 - f) / bevel, 0.0, 1.0);
}

void fragment() {
	vec3 uvl = vec3(UV, UV2.x);
	vec3 alb = texture(albedo_tex, uvl).rgb;
	vec3 nh = texture(normal_tex, uvl).xyz;
	vec2 nxy = nh.xy * 2.0 - 1.0;
	vec3 tn = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
	vec3 n = normalize(wnrm);
	// The directions the picture runs along on this face (as world.gd lays the UVs out).
	vec3 t;
	vec3 b;
	if (abs(n.y) > 0.7) {
		t = vec3(1.0, 0.0, 0.0);
		b = vec3(0.0, 0.0, -1.0);
	} else if (UV2.y > 0.5) {
		t = normalize(cross(n, vec3(0.0, 1.0, 0.0)));
		b = vec3(0.0, 1.0, 0.0);
	} else if (abs(n.x) > 0.5) {
		t = vec3(0.0, 0.0, 1.0);
		b = vec3(0.0, 1.0, 0.0);
	} else {
		t = vec3(1.0, 0.0, 0.0);
		b = vec3(0.0, 1.0, 0.0);
	}
	vec3 wn = normalize(t * tn.x + b * tn.y + n * tn.z);
	if (UV2.y < 0.5) {
		vec3 an = abs(n);
		vec3 f = fract(wpos - n * 0.01);
		vec3 e = vec3(edge(f.x), edge(f.y), edge(f.z)) * (1.0 - an);
		float k = max(abs(e.x), max(abs(e.y), abs(e.z)));
		wn = normalize(wn + e * 0.9);
		alb *= 1.0 - k * k * 0.18;  // a hint of shade in the rounded edge
	}
	ALBEDO = alb * COLOR.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.82;
	SPECULAR = 0.35;
	AO = mix(min_light, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.0;
}
