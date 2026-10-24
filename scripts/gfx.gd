extends Node
## `G.gfx`: the look of the world. The sky, the sun and moon, fog, post effects and the
## graphics quality the player picked (saved with the mouse sensitivity in user://settings.cfg).
## Not created on a dedicated server.

const SETTINGS := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const CUSTOM := 4
## What each quality preset sets (the Settings panel can change each one; then it is "Custom").
const PRESETS := [
	{"shadows": 1, "ssao": false, "ssil": false, "fog": false, "aa": 1, "view": 5},
	{"shadows": 2, "ssao": true, "ssil": false, "fog": false, "aa": 3, "view": 6},
	{"shadows": 3, "ssao": true, "ssil": true, "fog": true, "aa": 4, "view": 7},
	{"shadows": 4, "ssao": true, "ssil": true, "fog": true, "aa": 5, "view": 8},
]
const SHADOW_NAMES := ["Off", "Low", "Medium", "High", "Ultra"]
const AA_NAMES := ["Off", "FXAA", "SMAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"]
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240]
const WINDOW_NAMES := ["Windowed", "Fullscreen", "Exclusive fullscreen"]
## The drawn world reaches 4-8 chunks (the server sends 9, and drawing needs one more around).
const VIEW_MIN := 4
const VIEW_MAX := 8
const DEFAULTS := {
	"quality": 2, "shadows": 3, "ssao": true, "ssil": true, "fog": true, "aa": 4, "view": 7,
	"brightness": 50, "cave_light": 35, "fov": 75, "render_scale": 100, "vsync": true,
	"max_fps": 0, "window": 0, "show_fps": false, "sens": 2.5,
}

## Every setting (DEFAULTS has them all), saved in user://settings.cfg.
var opt := DEFAULTS.duplicate()
var quality: int:
	get:
		return opt["quality"]
var sens: float:
	get:
		return opt["sens"]
	set(v):
		opt["sens"] = clampf(v, 0.5, 6.0)
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var _cloud_t := 0.0
var _sky_wait := 0.0
var _lut_for := -1
## Forward+ (the effects below exist) rather than the OpenGL fallback.
var rich := false


func _init() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		for k in DEFAULTS:
			var v = cf.get_value("settings", k, null)
			if v != null and typeof(v) == typeof(DEFAULTS[k]):
				opt[k] = v
		# 0.10.0 kept only these two.
		if not cf.has_section("settings"):
			_use_preset(clampi(int(cf.get_value("graphics", "quality", 2)), 0, 3))
			opt["sens"] = float(cf.get_value("controls", "mouse_sensitivity", 2.5))
	if G.arg_value("--gfx=") != "":
		_use_preset(clampi(int(G.arg_value("--gfx=")), 0, 3))  # screenshots
	_clamp_all()


func _use_preset(q: int) -> void:
	opt["quality"] = q
	for k in PRESETS[q]:
		opt[k] = PRESETS[q][k]


func _clamp_all() -> void:
	opt["quality"] = clampi(opt["quality"], 0, CUSTOM)
	opt["shadows"] = clampi(opt["shadows"], 0, SHADOW_NAMES.size() - 1)
	opt["aa"] = clampi(opt["aa"], 0, AA_NAMES.size() - 1)
	opt["view"] = clampi(opt["view"], VIEW_MIN, VIEW_MAX)
	opt["brightness"] = clampi(opt["brightness"], 0, 100)
	opt["cave_light"] = clampi(opt["cave_light"], 0, 100)
	opt["fov"] = clampi(opt["fov"], 60, 110)
	opt["render_scale"] = clampi(opt["render_scale"], 50, 100)
	opt["window"] = clampi(opt["window"], 0, WINDOW_NAMES.size() - 1)
	opt["sens"] = clampf(opt["sens"], 0.5, 6.0)
	if not FPS_CAPS.has(opt["max_fps"]):
		opt["max_fps"] = 0


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in opt:
		cf.set_value("settings", k, opt[k])
	cf.save(SETTINGS)


## One setting changed in the Settings panel: apply it at once and save. Changing a part of a
## preset makes the quality "Custom"; picking a preset sets its parts.
func set_opt(key: String, value) -> void:
	if key == "quality":
		if int(value) < CUSTOM:
			_use_preset(int(value))
		else:
			opt["quality"] = CUSTOM
	else:
		opt[key] = value
		if PRESETS[0].has(key):
			opt["quality"] = CUSTOM
	_clamp_all()
	save_settings()
	apply_all(key == "window")


func reset_settings() -> void:
	opt = DEFAULTS.duplicate()
	save_settings()
	apply_all(true)


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
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	apply_all(opt["window"] != 0)


func _exit_tree() -> void:
	if G.gfx == self:
		G.gfx = null  # the scene is reloading (joining or leaving a server)


func view_radius() -> int:
	return opt["view"]


## Ambient light left in caves and under roofs (the shaders' floor for the sky light).
func min_light() -> float:
	return 0.03 + opt["cave_light"] / 100.0 * 0.67


func apply_all(window := false) -> void:
	var vp := get_viewport()
	var aa: int = opt["aa"]
	var rs: float = opt["render_scale"] / 100.0
	var upscale := rs < 0.999
	vp.scaling_3d_scale = rs
	vp.scaling_3d_mode = (Viewport.SCALING_3D_MODE_FSR2 if rich else Viewport.SCALING_3D_MODE_BILINEAR) if upscale else Viewport.SCALING_3D_MODE_BILINEAR
	# FSR 2 smooths edges itself and doesn't work together with MSAA.
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][aa] if not (upscale and rich) else Viewport.MSAA_DISABLED
	vp.screen_space_aa = [Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA, Viewport.SCREEN_SPACE_AA_SMAA, Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED][aa]
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	var sh: int = opt["shadows"]
	var soft := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
	sun.shadow_enabled = sh > 0
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 4096, 8192][sh], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft[sh])
	RenderingServer.positional_soft_shadow_filter_set_quality(soft[sh])
	sun.directional_shadow_max_distance = [60.0, 60.0, 80.0, 100.0, 130.0][sh]
	sun.light_angular_distance = 0.6 if sh >= 3 else 0.0
	env.ssao_enabled = rich and opt["ssao"]
	env.ssil_enabled = rich and opt["ssil"]
	env.volumetric_fog_enabled = rich and opt["fog"]
	if rich:
		var high: bool = sh >= 4
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA if high else RenderingServer.ENV_SSAO_QUALITY_HIGH, false, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if high else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size(128 if high else 64, 96 if high else 64)
		RenderingServer.environment_set_volumetric_fog_filter_active(true)
	var far := view_radius() * 16.0
	env.fog_depth_end = far - 6.0
	env.fog_depth_begin = far * 0.5
	_apply_brightness()
	if G.player != null and is_instance_valid(G.player) and G.player.cam != null:
		G.player.flashlight.shadow_enabled = sh >= 1
		G.player.cam.fov = opt["fov"]
		G.player.sens = opt["sens"] * 0.001
	if G.world != null and is_instance_valid(G.world) and G.world.render:
		G.world.set_render_radius(view_radius())
		G.world.set_min_light(min_light())
	if not G.server_mode:
		Engine.max_fps = opt["max_fps"]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if opt["vsync"] else DisplayServer.VSYNC_DISABLED)
		if window:
			DisplayServer.window_set_mode([DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][opt["window"]])


## Brightness is a gamma curve after tonemapping: it lifts (or deepens) the dark parts far more
## than the bright ones, so night and caves get easier to see without washing out the day.
func _apply_brightness() -> void:
	var b: int = opt["brightness"]
	if b == _lut_for:
		return
	_lut_for = b
	if b == 50:
		env.adjustment_color_correction = null
		return
	var g := pow(2.0, (b - 50) / 50.0)
	var img := Image.create(256, 1, false, Image.FORMAT_RGB8)
	for i in 256:
		var v := pow(i / 255.0, 1.0 / g)
		img.set_pixel(i, 0, Color(v, v, v))
	env.adjustment_color_correction = ImageTexture.create_from_image(img)


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
	env.ambient_light_energy = lerpf(0.36, 0.6, day_f)
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
