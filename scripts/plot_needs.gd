@tool
class_name WRPlotNeeds
extends Resource
## 可复用的地块需求配置。本局水量、损坏与安全计时由模拟独立保存。
@export var id := "ordinary"
@export var display_name := "普通田"
## 目标用途。农田须适量并安全；蓄水区达到容量即完成，额外雨水流出，不损坏。R／切图生效。
@export_enum("farm", "reservoir") var goal_kind := "farm"
## 现有面积归一化雨量单位。农田够水后仍须安全；蓄水区将此值作为容量，蓄满即完成。R／切图生效。
## 调大需要更多补给；调小更早够水，也需要更早移云。修改不改变真实落雨量或地块面积。
@export var target_water := 100.0
## 农田超过此值永久损坏，恰等于仍未损坏；须大于target_water。蓄水区忽略过量上限。R／切图生效。
## 调大增加移云／断供余量，调小更怕涝。两值之差控制从蓝色到黄色的预警区间。
@export var flood_water := 150.0
## 仅改变占位植物外观，不改变接雨、消耗或计星规则。
@export_enum("ordinary", "seedling") var appearance := "ordinary"

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.strip_edges().is_empty(): errors.append("id：不能为空")
	if display_name.strip_edges().is_empty(): errors.append("display_name：不能为空")
	if not is_finite(target_water) or target_water <= 0.0: errors.append("target_water：须为有限正数")
	if goal_kind not in ["farm", "reservoir"]: errors.append("goal_kind：未知目标用途")
	if not is_finite(flood_water) or (goal_kind == "farm" and flood_water <= target_water): errors.append("flood_water：农田须为有限数且大于 target_water")
	if appearance not in ["ordinary", "seedling"]: errors.append("appearance：未知占位外观")
	return errors
