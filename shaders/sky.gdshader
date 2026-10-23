shader_type sky;
// The sky (gfx.gd sets every uniform from the clock): a colour gradient, the sun and the moon,
// stars at night and two layers of drifting clouds.

uniform vec3 top_color : source_color = vec3(0.3, 0.52, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.78, 0.92);
uniform vec3 ground_color : source_color = vec3(0.2, 0.25, 0.3);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // towards the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_glow = 1.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_color : source_color = vec3(0.8, 0.85, 1.0);
uniform float moon_size = 0.9992;              // cosine of the moon's angular radius
uniform float stars = 0.0;                     // 0 by day, 1 at night
uniform float cloud_cover = 0.5;
uniform vec2 cloud_offset = vec2(0.0);
uniform vec3 cloud_light : source_color = vec3(1.0);
uniform vec3 cloud_dark : source_color = vec3(0.55, 0.6, 0.7);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(h, 0.55));
	} else {
		col = mix(horizon_color, ground_color, clamp(pow(-h, 0.35), 0.0, 1.0));
	}
	float sd = dot(d, sun_dir);
	// A haze around the sun, brightest near the horizon (sunsets).
	col += sun_color * (pow(max(sd, 0.0), 8.0) * 0.25 + pow(max(sd, 0.0), 90.0) * 0.6) * sun_glow;
	if (!AT_CUBEMAP_PASS) {
		col += sun_color * smoothstep(0.99955, 0.9997, sd) * 18.0 * sun_glow;
	}
	float md = dot(d, moon_dir);
	float disc = smoothstep(moon_size - 0.00025, moon_size, md);
	if (disc > 0.0) {
		// Some craters on the moon's face.
		vec3 m = d - moon_dir;
		float cr = vnoise(m.xy * 900.0 + m.z * 300.0);
		col = mix(col, moon_color * (2.2 - cr * 0.9), disc);
	}
	col += moon_color * pow(max(md, 0.0), 300.0) * 0.35;
	if (stars > 0.0 && h > 0.0) {
		vec3 sp = d * 420.0;
		vec3 cell = floor(sp);
		float r = hash3(cell);
		if (r > 0.9965) {
			float tw = length(fract(sp) - 0.5);
			col += vec3(0.9, 0.92, 1.0) * stars * (1.0 - smoothstep(0.05, 0.4, tw)) * (r - 0.9965) * 900.0 * smoothstep(0.0, 0.25, h);
		}
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12);
		float fade = smoothstep(0.0, 0.18, h);
		float n1 = fbm(uv * 1.3 + cloud_offset);
		float n2 = fbm(uv * 3.1 - cloud_offset * 1.7 + vec2(5.0, 3.0));
		float n = n1 * 0.75 + n2 * 0.35;
		float c = smoothstep(1.0 - cloud_cover, 1.25 - cloud_cover, n) * fade;
		// Lit from the sun's side, darker underneath.
		float lit = clamp(0.55 + 0.45 * dot(normalize(vec3(d.x, 0.25, d.z)), sun_dir), 0.0, 1.0);
		vec3 cc = mix(cloud_dark, cloud_light, clamp(lit * (1.15 - n2 * 0.6), 0.0, 1.0));
		cc += sun_color * pow(max(sd, 0.0), 12.0) * 0.5 * sun_glow;
		col = mix(col, cc, c * 0.92);
	}
	COLOR = col;
}
