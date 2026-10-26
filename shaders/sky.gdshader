shader_type sky;
// The sky (gfx.gd sets every uniform from the clock): a colour gradient, the sun and the moon,
// stars at night and drifting clouds: since M4.7 rounder and thicker (billowing edges, darker
// where they are thick, bright rims), glowing warm from inside at sunset.

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
uniform float cloud_glow = 0.0;                // sunset: the clouds glow from inside (0..1)

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

// Cloud density: fbm swirled by two more fbm lookups (domain warping).
float clouds(vec2 uv) {
	vec2 q = vec2(fbm(uv), fbm(uv + vec2(5.2, 1.3)));
	return fbm(uv * 1.1 + 1.6 * q + vec2(cloud_offset.y, -cloud_offset.x) * 0.6);
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
		// Clouds on a high flat layer: swirled noise for their shapes, a look one step towards
		// the sun for shading (thick towards the sun = darker), bright thin edges near the sun.
		vec2 uv = d.xz / (h + 0.08) * 0.6 + cloud_offset;
		float fade = smoothstep(0.0, 0.22, h);
		float n = clouds(uv);
		// Billowing edges: small round lumps added where a cloud thins out.
		float lumps = vnoise(uv * 7.0 + cloud_offset * 3.0) * 0.6 + vnoise(uv * 15.0) * 0.4;
		float lo = 1.0 - cloud_cover;
		n += (lumps - 0.5) * 0.09 * (1.0 - smoothstep(lo, lo + 0.25, n));
		float c = smoothstep(lo - 0.02, lo + 0.13, n) * fade;
		if (c > 0.001) {
			vec2 to_sun = normalize(sun_dir.xz + vec2(1e-4)) * 0.06;
			float n2 = clouds(uv + to_sun);
			// Thick middles are darker underneath, thin parts let the light through.
			float thick = clamp((n - lo) * 3.2, 0.0, 1.0);
			float shade = clamp(0.92 - (n2 - n) * 5.0 - thick * 0.42, 0.12, 1.1);
			vec3 cc = mix(cloud_dark, cloud_light, shade);
			float rim = (1.0 - smoothstep(lo, lo + 0.16, n)) * pow(max(sd, 0.0), 6.0);
			cc += sun_color * rim * 1.8 * sun_glow;
			cc += sun_color * pow(max(sd, 0.0), 16.0) * 0.35 * sun_glow;
			// At sunset the clouds glow warm from inside, most where they are thin and towards the sun.
			cc += sun_color * cloud_glow * (0.35 + 0.65 * pow(max(sd, 0.0), 3.0)) * (1.0 - thick * 0.7) * 0.9;
			col = mix(col, cc, c * 0.97);
		}
	}
	COLOR = col;
}
