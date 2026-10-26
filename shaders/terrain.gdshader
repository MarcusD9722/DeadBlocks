shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// The smooth ground (SmoothMesher). Each vertex carries how much of each ground material is
// around it: grass, dirt, stone, sand in COLOR, coal and iron in UV, bedrock in UV2.x, snow and
// crystal ore in CUSTOM0 (M4.7); UV2.y is the sky light (dims ambient light under cover). The textures are projected from three sides
// (triplanar), grass shows on top and dirt on steep sides, and materials meet along the bumps of
// their height maps (the normal map's blue) instead of a straight fade.

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float blend_depth = 0.3;
uniform float normal_strength = 1.0;
uniform float min_light = 0.12;  // ambient light left in caves (Settings: light in caves)
// Cloud shadows (M4.7): the clouds' own noise drifting over the land (gfx.gd moves it).
uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_shift = vec2(0.0);   // how far the clouds have drifted (metres)
uniform float cloud_shade = 0.0;        // how much a cloud's shadow darkens (0 at night)
uniform float cloud_cover = 0.5;

const int LAYERS = 9;
const float ROUGH[9] = float[9](0.95, 0.95, 0.82, 0.92, 0.62, 0.7, 0.85, 0.75, 0.35);
// Texture repeats per metre, per material (rock pictures cover more ground).
const float SCALE[9] = float[9](0.5, 0.45, 0.33, 0.5, 0.33, 0.33, 0.33, 0.4, 0.33);

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 extra;  // snow, crystal ore

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	extra = CUSTOM0.xy;
}

// How much a cloud overhead shades this spot (0 none, cloud_shade under a thick one).
float cloud_shadow(vec3 p) {
	if (cloud_shade <= 0.0) {
		return 0.0;
	}
	float n = texture(cloud_tex, (p.xz + cloud_shift) / 700.0).r;
	float lo = 1.0 - cloud_cover;
	return smoothstep(lo - 0.04, lo + 0.16, n) * cloud_shade;
}


// A tangent-space normal from a normal map's red and green (blue holds the height).
vec3 unpack_n(vec3 t) {
	vec2 xy = (t.xy * 2.0 - 1.0) * normal_strength;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// One material seen from three sides: albedo (alpha = height) and the world-space normal.
void triplanar(int m, float side, float top, vec3 bw, vec3 n, vec3 p, out vec4 alb, out vec3 nw) {
	p *= SCALE[m];
	vec2 ux = p.zy;
	vec2 uy = p.xz;
	vec2 uz = p.xy;
	float ly = n.y > 0.0 ? top : side;
	alb.rgb = texture(albedo_tex, vec3(ux, side)).rgb * bw.x + texture(albedo_tex, vec3(uy, ly)).rgb * bw.y + texture(albedo_tex, vec3(uz, side)).rgb * bw.z;
	vec3 sx = texture(normal_tex, vec3(ux, side)).xyz;
	vec3 sy = texture(normal_tex, vec3(uy, ly)).xyz;
	vec3 sz = texture(normal_tex, vec3(uz, side)).xyz;
	alb.a = sx.z * bw.x + sy.z * bw.y + sz.z * bw.z;
	vec3 tx = unpack_n(sx);
	vec3 ty = unpack_n(sy);
	vec3 tz = unpack_n(sz);
	// Whiteout blend (Ben Golus, "Normal Mapping for a Triplanar Shader").
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	nw = normalize(tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 p = wpos;
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	// Grass reaches further down slopes than the plain blend would show.
	vec3 gw = pow(abs(n) * vec3(1.0, 1.7, 1.0), vec3(6.0));
	gw /= (gw.x + gw.y + gw.z);
	float wt[9] = float[9](COLOR.r, COLOR.g, COLOR.b, COLOR.a, UV.x, UV.y, UV2.x, extra.x, extra.y);
	vec4 albs[9];
	vec3 nrms[9];
	float score[9];
	float smax = -10.0;
	for (int m = 0; m < LAYERS; m++) {
		score[m] = -10.0;
		if (wt[m] < 0.004) {
			continue;
		}
		float side = m == 0 ? 1.0 : float(m);
		triplanar(m, side, float(m), m == 0 ? gw : bw, n, p, albs[m], nrms[m]);
		score[m] = wt[m] + albs[m].a * blend_depth;
		smax = max(smax, score[m]);
	}
	vec3 col = vec3(0.0);
	vec3 nw = vec3(0.0);
	float rough = 0.0;
	float total = 0.0;
	float glow = 0.0;
	for (int m = 0; m < LAYERS; m++) {
		float b = max(score[m] - smax + blend_depth, 0.0);
		if (b <= 0.0) {
			continue;
		}
		col += albs[m].rgb * b;
		nw += nrms[m] * b;
		rough += ROUGH[m] * b;
		total += b;
		if (m == 8) {
			glow += b;  // the crystals glow a little in the dark
		}
	}
	col /= max(total, 0.0001);
	nw = normalize(nw);
	// (Under cover, in a cave, no cloud's shadow: the sky's light is gone already.)
	ALBEDO = col * (1.0 - cloud_shadow(wpos) * UV2.y);
	// The crystal ore's bright bits (blue-violet in its picture) shine faintly.
	float cb = max(col.b - max(col.r, col.g) * 0.8, 0.0);
	EMISSION = col * cb * 2.5 * glow / max(total, 0.0001);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = rough / max(total, 0.0001);
	SPECULAR = 0.3;
	AO = mix(min_light, 1.0, UV2.y);
	AO_LIGHT_AFFECT = 0.0;
}
