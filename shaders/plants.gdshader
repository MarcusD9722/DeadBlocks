shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Plants and small things drawn as crossed pictures (torches, spikes, berry bushes, campfires):
// the pixel atlas (tex.gd). The vertex colour's alpha is the sky light.

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float min_light = 0.12;

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
	AO = mix(min_light, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.0;
}
