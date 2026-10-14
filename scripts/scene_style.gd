@tool
class_name WRSceneStyle
extends Resource
## 只影响场景显示。保存后R／切图重读；F6仍只修改天气手感。

@export_group("共同受光")
## 指向太阳的世界方向。水平分量越大，侧面差异与影子偏移越明显；y必须为正。
@export var light_direction := Vector3(-0.6, 1.0, 0.3)
## 背光面的最低明度倍率。调大更柔和、更亮，调小转折更强；不改变天气。
@export_range(0.0, 1.0) var environment_floor := 0.74
## 0沿用旧云分色，1完全采用方向明暗；中间值混合。不会改变云轮廓或降雨。
@export_range(0.0, 1.0) var cloud_light_strength := 0.7
## 放大云表面坡度的视觉倍率。调大侧面更明显，过高会强化细小转折；不加高云。
@export_range(0.0, 6.0) var cloud_normal_gain := 2.5

@export_group("投影")
## 云影压暗强度。调大更容易看出云的地面位置，过强会遮住水汽与雨区。
@export_range(0.0, 1.0) var cloud_shadow_strength := 0.18
## 植物／石块脚下软影强度。调小更轻盈，调大更贴地；不影响危险天气判定。
@export_range(0.0, 1.0) var contact_shadow_strength := 0.14

@export_group("材料色板")
## 四档云色，从亮到暗。仅是显示色板，雨云仍由真实雨水子集决定。
@export var cloud_colors := PackedColorArray([Color(0.94,0.96,0.92), Color(0.78,0.85,0.87), Color(0.59,0.73,0.79), Color(0.38,0.59,0.69)])
@export var land_color := Color("9bbb83")
@export var shore_color := Color("e5d6a4")
@export var soil_color := Color("bf936e")
@export var bank_color := Color("c9c6a1")
@export var water_color := Color("79bac5")

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not light_direction.is_finite() or not is_finite(light_direction.length_squared()) or light_direction.length_squared() < 0.000001 or light_direction.y <= 0:
		errors.append("light_direction：须为来自上方的有限非零方向")
	for field in ["environment_floor", "cloud_light_strength", "cloud_shadow_strength", "contact_shadow_strength"]:
		var value: float = get(field)
		if not is_finite(value) or value < 0 or value > 1: errors.append(field+"：须在0–1内")
	if not is_finite(cloud_normal_gain) or cloud_normal_gain < 0 or cloud_normal_gain > 6: errors.append("cloud_normal_gain：须在0–6内")
	if cloud_colors.size() != 4: errors.append("cloud_colors：须有四档颜色")
	var colors := cloud_colors.duplicate()
	var names := PackedStringArray()
	for index in cloud_colors.size(): names.append("cloud_colors[%d]" % index)
	for field in ["land_color", "shore_color", "soil_color", "bank_color", "water_color"]:
		colors.append(get(field))
		names.append(field)
	for index in colors.size():
		var c: Color = colors[index]
		if not Vector4(c.r,c.g,c.b,c.a).is_finite() or minf(c.r,minf(c.g,c.b)) < 0 or maxf(c.r,maxf(c.g,c.b)) > 1 or c.a != 1:
			errors.append(names[index]+"：须为0–1内的有限不透明颜色")
	return errors

func apply(material: ShaderMaterial) -> void:
	for field in ["light_direction", "environment_floor", "cloud_light_strength", "cloud_normal_gain", "cloud_shadow_strength", "contact_shadow_strength"]:
		material.set_shader_parameter(field, get(field))
	# These cloud uniforms are numeric sRGB values, like the original shader literals.
	# Passing a Color would invoke the renderer's color conversion before pow(...,2.2).
	for index in 4:
		var c: Color = cloud_colors[index]
		material.set_shader_parameter("cloud_color"+str(index), Vector4(c.r,c.g,c.b,c.a))
