extends Node
## `G.gfx`: the look of the world. The sky, the sun and moon, fog, post effects and the
## graphics quality the player picked (saved with the mouse sensitivity in user://settings.cfg).
## Not created on a dedicated server.

const SETTINGS := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
## Chunks drawn around the player, per quality.
const VIEW_RADIUS := [5, 6, 7, 8]

var quality := 2
var sens := 2.5
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var _cloud_t := 0.0
var _sky_wait := 0.0
## Forward+ (the effects below exist) rather than the OpenGL fallback.
var rich := false


func _init() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		quality = clampi(int(cf.get_value("graphics", "quality", quality)), 0, QUALITY_NAMES.size() - 1)
		sens = clampf(float(cf.get_value("controls", "mouse_sensitivity", sens)), 0.5, 6.0)
	if G.arg_value("--gfx=") != "":
		quality = clampi(int(G.arg_value("--gfx=")), 0, QUALITY_NAMES.size() - 1)  # screenshots


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "quality", quality)
	cf.set_value("controls", "mouse_sensitivity", sens)
	cf.save(SETTINGS)


func _ready() -> void:
	rich = RenderingServer.get_current_rendering_method() == "forward_plus"
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.7
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	apply_quality()


func _exit_tree() -> void:
	if G.gfx == self:
		G.gfx = null  # the scene is reloading (joining or leaving a server)


func set_quality(q: int) -> void:
	quality = clampi(q, 0, QUALITY_NAMES.size() - 1)
	save_settings()
	apply_quality()
	if G.world != null and G.world.render:
		G.world.set_render_radius(view_radius())


func view_radius() -> int:
	return VIEW_RADIUS[quality]


func apply_quality() -> void:
	var q := quality
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][q]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_16X, Viewport.ANISOTROPY_16X][q]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	RenderingServer.positional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	sun.directional_shadow_max_distance = [60.0, 80.0, 100.0, 130.0][q]
	sun.light_angular_distance = 0.0 if q < 2 else 0.6
	env.ssao_enabled = rich and q >= 1
	env.ssil_enabled = rich and q >= 2
	env.volumetric_fog_enabled = rich and q >= 2
	if rich:
		RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH, RenderingServer.ENV_SSAO_QUALITY_ULTRA][q], q < 2, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM if q < 3 else RenderingServer.ENV_SSIL_QUALITY_HIGH, true, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size(64 if q < 3 else 128, 64 if q < 3 else 96)
		RenderingServer.environment_set_volumetric_fog_filter_active(true)
	var far := view_radius() * 16.0
	env.fog_depth_end = far - 6.0
	env.fog_depth_begin = far * 0.5
	if G.player != null and G.player.flashlight != null:
		G.player.flashlight.shadow_enabled = q >= 1


# ------------------------------------------------------------ day and night

## Directions towards the sun and the moon at clock time t (hours).
static func sun_basis(t: float) -> Basis:
	return Basis.from_euler(Vector3(-(t - 6.0) / 12.0 * PI, deg_to_rad(35.0), 0.0))


static func moon_basis(t: float) -> Basis:
	return Basis.from_euler(Vector3(-fmod(t - 18.0 + 24.0, 24.0) / 12.0 * PI, deg_to_rad(-20.0), 0.0))


## The light, sky and fog for clock time t (hours) on a day. Called every frame; the sky's own
## uniforms change a few times a second only (each change updates the sky's light).
func update_sky(t: float, blood: bool, delta: float) -> void:
	var day_f := clampf(smoothstep(5.0, 7.0, t) - smoothstep(18.5, 20.5, t), 0.0, 1.0)
	var dusk_f := maxf(0.0, 1.0 - absf(t - 19.0) / 1.6) + maxf(0.0, 1.0 - absf(t - 6.0) / 1.6)
	dusk_f = clampf(dusk_f, 0.0, 1.0)
	var sb := sun_basis(t)
	var mb := moon_basis(t)
	if day_f > 0.35:
		var ang := clampf((t - 6.0) / 12.0 * PI, 0.12, PI - 0.12)
		sun.rotation = Vector3(-ang, deg_to_rad(35.0), 0.0)
		sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.6, 0.36), dusk_f)
		sun.light_energy = 1.6 * day_f
		sun.light_volumetric_fog_energy = 1.0
	else:
		var mt := fmod(t - 18.0 + 24.0, 24.0)
		var ang2 := clampf(mt / 12.0 * PI, 0.25, PI - 0.25)
		sun.rotation = Vector3(-ang2, deg_to_rad(-20.0), 0.0)
		sun.light_color = Color(1.0, 0.32, 0.26) if blood else Color(0.58, 0.68, 1.0)
		sun.light_energy = (0.38 if blood else 0.26) * (1.0 - day_f)
		sun.light_volumetric_fog_energy = 2.5
	var top_day := Color(0.24, 0.45, 0.86)
	var hor_day := Color(0.68, 0.8, 0.93)
	var hor_dusk := Color(0.98, 0.52, 0.3)
	var top_night := Color(0.012, 0.018, 0.05)
	var hor_night := Color(0.05, 0.07, 0.13)
	if blood:
		top_night = Color(0.12, 0.0, 0.015)
		hor_night = Color(0.42, 0.05, 0.03)
		hor_dusk = Color(0.85, 0.2, 0.1)
	var top := top_night.lerp(top_day, day_f)
	var hor := hor_night.lerp(hor_day, day_f).lerp(hor_dusk, dusk_f * 0.75)
	env.fog_light_color = hor
	var amb_day := Color(0.6, 0.67, 0.8)
	var amb_night := Color(0.36, 0.1, 0.08) if blood else Color(0.2, 0.25, 0.45)
	env.ambient_light_color = amb_night.lerp(amb_day, day_f)
	env.ambient_light_energy = lerpf(0.3, 0.6, day_f)
	var fog_col := Color(0.55, 0.08, 0.05) if blood and day_f < 0.5 else hor.lerp(Color(0.8, 0.85, 0.9), 0.3)
	env.volumetric_fog_albedo = fog_col
	env.volumetric_fog_density = lerpf(0.014 if blood else 0.01, 0.006, day_f) + dusk_f * 0.006
	_cloud_t += delta
	_sky_wait -= delta
	if _sky_wait > 0.0:
		return
	_sky_wait = 0.25
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.55))
	sky_mat.set_shader_parameter("sun_dir", sb.z)
	sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.92, 0.78).lerp(Color(1.0, 0.5, 0.25), dusk_f))
	sky_mat.set_shader_parameter("sun_glow", clampf(sb.z.y * 4.0 + 0.3, 0.0, 1.0))
	sky_mat.set_shader_parameter("moon_dir", mb.z)
	sky_mat.set_shader_parameter("moon_color", Color(1.0, 0.25, 0.18) if blood else Color(0.85, 0.88, 1.0))
	sky_mat.set_shader_parameter("moon_size", 0.9975 if blood else 0.9991)
	sky_mat.set_shader_parameter("stars", 1.0 - day_f)
	sky_mat.set_shader_parameter("cloud_cover", 0.62 if blood else 0.5)
	sky_mat.set_shader_parameter("cloud_offset", Vector2(_cloud_t * 0.004, _cloud_t * 0.0015))
	var cl := Color(1.0, 0.98, 0.95).lerp(Color(1.0, 0.7, 0.5), dusk_f)
	var night_cl := Color(0.25, 0.04, 0.04) if blood else Color(0.09, 0.1, 0.16)
	sky_mat.set_shader_parameter("cloud_light", night_cl.lerp(cl, day_f))
	sky_mat.set_shader_parameter("cloud_dark", (night_cl * 0.5).lerp(Color(0.52, 0.56, 0.66).lerp(Color(0.55, 0.35, 0.4), dusk_f), day_f))
