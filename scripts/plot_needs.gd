@tool
class_name WRPlotNeeds
extends Resource
## 可复用的地块需求配置。本局水量、损坏与安全计时由模拟独立保存。
@export var id := "ordinary"
@export var display_name := "普通田"
## 现有面积归一化雨量单位；达到此值算够水，仍须连续安全才能获星。保存后 R／切图生效。
## 调大需要更多补给；调小更早够水，也需要更早移云。修改不改变真实落雨量或地块面积。
@export var target_water := 100.0
## 超过此值永久损坏，恰等于仍未损坏。须大于 target_water；保存后 R／切图生效。
## 调大增加移云／断供余量，调小更怕涝。两值之差控制从蓝色到黄色的预警区间。
@export var flood_water := 150.0
## 仅改变占位植物外观，不改变接雨、消耗或计星规则。
@export_enum("ordinary", "seedling") var appearance := "ordinary"

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.strip_edges().is_empty(): errors.append("id：不能为空")
	if display_name.strip_edges().is_empty(): errors.append("display_name：不能为空")
	if not is_finite(target_water) or target_water <= 0.0: errors.append("target_water：须为有限正数")
	if not is_finite(flood_water) or flood_water <= target_water: errors.append("flood_water：须为有限数且大于 target_water")
	if appearance not in ["ordinary", "seedling"]: errors.append("appearance：未知占位外观")
	return errors
