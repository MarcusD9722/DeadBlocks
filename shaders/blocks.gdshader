shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Cubes, boxes and log trunks: one layer of the block texture array per face (UV2.x), with
// normal maps (blue = height). UV2.y is 1 on round trunks. The vertex colour's alpha is the sky
// light (dark under cover and in caves; only ambient light is dimmed, see SmoothMesher).
// Cube faces get softly rounded edges: the normal bends outwards near each block's border, except
// where the same face goes on into the next block (UV2.y below 0 holds those edges, M4.6).

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float bevel = 0.11;   // metres of rounding at each block edge
uniform float min_light = 0.12;  // ambient light left in caves (Settings: light in caves)
uniform bool own_space = false;  // the rounded edges by the model's own cells (an icon, M4.6)
// Cloud shadows (M4.7): the clouds' own noise drifting over the land (gfx.gd moves it).
uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_shift = vec2(0.0);   // how far the clouds have drifted (metres)
uniform float cloud_shade = 0.0;        // how much a cloud's shadow darkens (0 at night)
uniform float cloud_cover = 0.5;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	lpos = VERTEX;
	lnrm = NORMAL;
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
		vec3 on = own_space ? normalize(lnrm) : n;
		vec3 an = abs(on);
		vec3 f = fract((own_space ? lpos : wpos) - on * 0.01);
		vec3 e = vec3(edge(f.x), edge(f.y), edge(f.z)) * (1.0 - an);
		if (UV2.y < -0.001) {
			// Edges where the same face goes on into the next block stay flat (a wall looks like
			// one wall): bits -x +x -y +y -z +z.
			int j = int(round(-UV2.y * 64.0)) - 1;
			e.x *= (e.x < 0.0 ? float(1 - (j & 1)) : float(1 - ((j >> 1) & 1)));
			e.y *= (e.y < 0.0 ? float(1 - ((j >> 2) & 1)) : float(1 - ((j >> 3) & 1)));
			e.z *= (e.z < 0.0 ? float(1 - ((j >> 4) & 1)) : float(1 - ((j >> 5) & 1)));
		}
		float k = max(abs(e.x), max(abs(e.y), abs(e.z)));
		if (own_space && k > 0.0) {
			e = normalize(mat3(MODEL_MATRIX) * e) * length(e);
		}
		wn = normalize(wn + e * 0.9);
		alb *= 1.0 - k * k * 0.18;  // a hint of shade in the rounded edge
	}
	ALBEDO = alb * COLOR.rgb * (1.0 - cloud_shadow(wpos) * COLOR.a);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.82;
	SPECULAR = 0.35;
	AO = mix(min_light, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.0;
}
