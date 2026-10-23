shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Cubes, boxes and plants: the pixel-art atlas (tex.gd). The vertex colour's alpha is the
// sky light (dark under cover and in caves; only ambient light is dimmed, see SmoothMesher).
// Cube faces get softly rounded edges: the normal bends outwards near each block's border.

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float bevel = 0.08;   // metres of rounding at each block edge

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
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
	AO = mix(0.05, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.0;
	if (COLOR.r > 0.99) {  // plants (crosses) are drawn a little darker and keep their normal
		vec3 n = wnrm;
		vec3 an = abs(n);
		vec3 f = fract(wpos - n * 0.01);
		vec3 b = vec3(edge(f.x), edge(f.y), edge(f.z)) * (1.0 - an);
		float k = max(abs(b.x), max(abs(b.y), abs(b.z)));
		n = normalize(n + b * 0.9);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		// A hint of shade in the rounded edge, as on worn wood and stone.
		ALBEDO *= 1.0 - k * k * 0.18;
	}
}
