@tool
class_name WRCampaign
extends Resource
## 独立教学地图；须有且仅有一个蓄水目标。容量与布局仍在该地图中编辑。
@export var tutorial: WRMapDefinition
## 正式游玩顺序。在属性面板拖动数组项排序，拖入地图.tres添加关卡。
## 只收录已准备好的计风纹地图；不需要连续文件名，开发地图不会自动加入。
## 保存后重新运行或打开正式选关重读；R／F6保留当前关序，调序不改变按地图ID保存的纪录。
@export var levels: Array[WRMapDefinition] = []

func validation_errors(plot_half: float) -> PackedStringArray:
	var errors := PackedStringArray()
	if tutorial == null:
		errors.append("tutorial：缺少教学地图")
	else:
		if tutorial.resource_path.is_empty() or not ResourceLoader.exists(tutorial.resource_path): errors.append("tutorial：请引用已保存的教学地图文件")
		for error in tutorial.validation_errors(plot_half): errors.append("tutorial：" + error)
		if tutorial.plots.size() != 1 or tutorial.plot_needs.is_empty() or tutorial.plot_needs[0] == null or tutorial.plot_needs[0].goal_kind != "reservoir":
			errors.append("tutorial：教学须为单水库地图")
	if levels.is_empty(): errors.append("levels：至少需要一张正式地图")
	var ids: Array[String] = []
	for index in levels.size():
		var map := levels[index]
		var field := "levels[%d]" % index
		if map == null:
			errors.append(field + "：地图资源为空或丢失")
			continue
		if map.resource_path.is_empty() or not ResourceLoader.exists(map.resource_path): errors.append(field + "：请引用已保存的地图文件")
		elif map.id != map.resource_path.get_file().get_basename(): errors.append(field + "：地图id须与文件名一致")
		if map.id in ids: errors.append(field + "：重复地图id：" + map.id)
		if tutorial != null and map.id == tutorial.id: errors.append(field + "：不能与教学共用id")
		ids.append(map.id)
		if not map.star_level: errors.append(field + "：正式地图须启用star_level（风纹评价）")
		for error in map.validation_errors(plot_half): errors.append(field + "：" + error)
	return errors

func ids() -> Array[String]:
	var result: Array[String] = []
	for map in levels: result.append(map.id)
	return result

func find_map(id: String) -> WRMapDefinition:
	for map in levels:
		if map.id == id: return map
	return null

func next_id(id: String) -> String:
	var index := ids().find(id)
	return levels[index + 1].id if index >= 0 and index + 1 < levels.size() else ""
