extends RefCounted
## Validation is transactional: callers keep the previous resource on failure.
static var last_scene_style: WRSceneStyle
static var last_audio: WRAudioSettings
static var last_onboarding: WROnboardingSettings

static func campaign(path: String, plot_half: float) -> Dictionary:
	if not ResourceLoader.exists(path): return {"errors": PackedStringArray(["campaign：配置文件不存在：" + path])}
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not resource is WRCampaign: return {"errors": PackedStringArray(["campaign：资源类型须为WRCampaign：" + path])}
	return {"errors": resource.validation_errors(plot_half), "resource": resource}

static func audio(path := "res://configs/audio.tres") -> Dictionary:
	var candidate = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if ResourceLoader.exists(path) else null
	var errors: PackedStringArray = candidate.validation_errors() if candidate is WRAudioSettings else PackedStringArray(["audio：资源不存在或类型错误："+path])
	if errors.is_empty(): last_audio = candidate.duplicate(true)
	elif last_audio == null: last_audio = WRAudioSettings.new()
	return {"resource": last_audio.duplicate(true), "errors": errors}

static func scene_style(path := "res://configs/scene_style.tres") -> Dictionary:
	# Keep deep loading outside the resource script itself: it also reloads that script.
	var candidate = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if ResourceLoader.exists(path) else null
	var errors: PackedStringArray = candidate.validation_errors() if candidate is WRSceneStyle else PackedStringArray(["scene_style：资源不存在或类型错误："+path])
	if errors.is_empty(): last_scene_style = candidate.duplicate(true)
	elif last_scene_style == null: last_scene_style = WRSceneStyle.new()
	return {"resource": last_scene_style.duplicate(true), "errors": errors}

static func settings(path: String) -> Dictionary:
	if not ResourceLoader.exists(path): return {"errors": PackedStringArray(["配置文件不存在：" + path])}
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not resource is WRWeatherSettings: return {"errors": PackedStringArray(["配置类型须为 WRWeatherSettings：" + path])}
	var errors: PackedStringArray = resource.validation_errors()
	return {"errors": errors, "resource": resource}

static func map(path: String, plot_half: float) -> Dictionary:
	if not ResourceLoader.exists(path): return {"errors": PackedStringArray(["地图文件不存在：" + path])}
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not resource is WRMapDefinition: return {"errors": PackedStringArray(["地图类型须为 WRMapDefinition：" + path])}
	var errors: PackedStringArray = resource.validation_errors(plot_half)
	return {"errors": errors, "resource": resource}

static func onboarding(path := "res://configs/onboarding.tres") -> Dictionary:
	var candidate = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if ResourceLoader.exists(path) else null
	var errors: PackedStringArray = candidate.validation_errors() if candidate is WROnboardingSettings else PackedStringArray(["onboarding：资源不存在或类型错误："+path])
	if errors.is_empty(): last_onboarding = candidate.duplicate(true)
	elif last_onboarding == null: last_onboarding = WROnboardingSettings.new()
	return {"resource": last_onboarding.duplicate(true), "errors": errors}
