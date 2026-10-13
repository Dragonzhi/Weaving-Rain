@tool
class_name WRWarmSea
extends Resource
## 主题海域。供能是0–1游戏代理量；海水不是会被抽干的库存。R／切图重建。
@export var position := Vector2(9.0, 0.0)
@export var half_axes := Vector2(2.8, 4.0)
## 调大可提供更久、更强的蒸发和对流支持；0关闭该海域的补给。
@export_range(0.0, 1.0, 0.01) var initial_energy := 1.0
## 背景引导风，世界单位/秒；与人工风共同引导中心，不包含系统自身旋转。
@export var background_wind := Vector2(-0.025, 0.01)
@export var seed_position := Vector2(9.0, 0.0)
## 开场弱扰动的组织度；0用于从纯湿空气验证组织过程。非零不是定时升级。
@export_range(0.0, 1.0, 0.01) var seed_organization := 0.4
## 主题局开场把这部分初始湿空气转为云，保持原水量预算；0为纯湿空气。
@export_range(0.0, 0.8, 0.01) var initial_cloud_fraction := 0.2
@export_enum("北半球", "南半球") var hemisphere := 0

func weight(p: Vector2) -> float:
	var q := (p - position) / half_axes
	return pow(maxf(0.0, 1.0 - q.length_squared()), 2)

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not position.is_finite() or not half_axes.is_finite() or half_axes.x <= 0.0 or half_axes.y <= 0.0:
		errors.append("position / half_axes：须为有限坐标和正范围")
		return errors
	if absf(position.x) + half_axes.x > 12.0 or absf(position.y) + half_axes.y > 10.0: errors.append("half_axes：海域须在24×20编辑范围内")
	if not seed_position.is_finite() or weight(seed_position) <= 0.0: errors.append("seed_position：须位于暖海域内")
	if not background_wind.is_finite() or background_wind.length() > 2.0: errors.append("background_wind：须为有限且不超过2单位/秒")
	for field in ["initial_energy", "seed_organization", "initial_cloud_fraction"]:
		var value: float = get(field)
		if not is_finite(value) or value < 0.0 or value > (0.8 if field == "initial_cloud_fraction" else 1.0): errors.append(field + "：超出有效比例范围")
	if hemisphere not in [0, 1]: errors.append("hemisphere：未知半球")
	return errors
