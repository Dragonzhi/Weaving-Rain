@tool
class_name WRPlotRegion
extends Resource
## 接雨形状。尺寸为半边长／半轴；零向量沿用全局 plot_half，兼容旧地图。
@export_enum("rectangle", "circle", "ellipse") var shape := "rectangle"
@export var half_axes := Vector2.ZERO

func axes(default_half: float, padding: float = 0.0) -> Vector2:
	var result := Vector2.ONE * default_half if half_axes == Vector2.ZERO else half_axes
	if shape == "circle": result.y = result.x
	return result + Vector2.ONE * padding

func contains(offset: Vector2, default_half: float, padding: float = 0.0) -> bool:
	var size := axes(default_half, padding)
	if shape == "rectangle": return absf(offset.x) <= size.x and absf(offset.y) <= size.y
	return (offset / size).length_squared() <= 1.0

func area(default_half: float) -> float:
	var size := axes(default_half)
	return size.x * size.y * (4.0 if shape == "rectangle" else PI)

func outline(default_half: float, padding: float = 0.0) -> PackedVector2Array:
	var size := axes(default_half, padding)
	if shape == "rectangle":
		return PackedVector2Array([Vector2(-size.x, -size.y), Vector2(size.x, -size.y), size, Vector2(-size.x, size.y)])
	var result := PackedVector2Array()
	for i in 64: result.append(Vector2.from_angle(i * TAU / 64.0) * size)
	return result

func mesh(default_half: float) -> ArrayMesh:
	var points := outline(default_half)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size():
		for p in [Vector2.ZERO, points[i], points[(i + 1) % points.size()]]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(p.x, 0, p.y))
	return surface.commit()

func validation_error() -> String:
	if not shape in ["rectangle", "circle", "ellipse"]: return "未知形状"
	if not half_axes.is_finite() or (half_axes != Vector2.ZERO and (half_axes.x < 0.5 or half_axes.y < 0.5)):
		return "尺寸须为零向量（继承全局）或两个至少 0.5 的有限半轴"
	return ""
