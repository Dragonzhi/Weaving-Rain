@tool
class_name WRMountain
extends Resource
## Height above flat ground; the summit must stay below the cloud layer.
@export var position := Vector2.ZERO
@export_range(0.25, 5.0, 0.05) var radius := 2.0
@export_range(0.1, 2.5, 0.05) var height := 2.5
