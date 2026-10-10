extends RefCounted
## Fixed normal starts. Layouts contain no preseeded clouds, rain, cold or wind.
const IDS := ["standard", "far", "close"]

static func get_layout(id: String) -> Dictionary:
	match id:
		"far":
			return {"id": "far", "title": "长岛输雨", "hint": "山在西侧 · 把雨送远，或在当地借冷风补给",
				"plots": PackedVector2Array([Vector2(-0.8, 1.4), Vector2(6.0, -1.2)]),
				"west_air": Vector2(-8.2, 1.0), "east_air": Vector2(6.0, 1.0),
				"island_center": Vector2.ZERO, "island_axes": Vector2(10.5, 4.5),
				"mountain": Vector2(-5.8, 0.0), "mountain_radius": 3.0, "shape": "long"}
		"close":
			return {"id": "close", "title": "双翼分雨", "hint": "山在中央 · 换迎坡方向，分别照顾两侧土地",
				"plots": PackedVector2Array([Vector2(-6.0, 1.5), Vector2(6.0, -1.5)]),
				"west_air": Vector2(-5.6, -1.1), "east_air": Vector2(5.6, 1.1),
				"island_center": Vector2.ZERO, "island_axes": Vector2(7.6, 5.2),
				"mountain": Vector2.ZERO, "mountain_radius": 2.2, "shape": "split"}
		_:
			return {"id": "standard", "title": "山与两处土地", "hint": "先借山坡造雨，再尝试把冷风用于接力",
				"plots": PackedVector2Array([Vector2(2.8, 1.2), Vector2(3.6, -2.2)]),
				"west_air": Vector2(-6.2, 1.4), "east_air": Vector2(5.6, 1.0),
				"island_center": Vector2(-0.6, 0.3), "island_axes": Vector2(8.5, 5.5),
				"mountain": Vector2(-1.7, -0.6), "mountain_radius": 3.0, "shape": "standard"}
