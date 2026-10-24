shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Leaves: a picture of leaves with see-through gaps, drawn on both sides, swaying a little in the
// wind and letting light shine through. The vertex colour's alpha is the sky light.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float min_light = 0.12;
uniform float sway = 0.05;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	VERTEX.x += (sin(t * 1.3 + w.x * 0.6 + w.y * 0.4) + 0.5 * sin(t * 2.9 + w.z * 1.3)) * sway;
	VERTEX.z += (cos(t * 1.1 + w.z * 0.6 + w.y * 0.3) + 0.5 * cos(t * 3.1 + w.x * 1.1)) * sway;
	VERTEX.y += sin(t * 1.7 + w.x + w.z) * sway * 0.3;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * COLOR.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = a.rgb * vec3(0.5, 0.6, 0.3);
	AO = mix(min_light, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.0;
}
