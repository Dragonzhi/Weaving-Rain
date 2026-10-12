extends RefCounted
## Validation is transactional: callers keep the previous resource on failure.
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
