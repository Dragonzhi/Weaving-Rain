@tool
class_name WRHumiditySource
extends Resource
## Initial density = global initial_humidity * concentration. Not a continual source.
@export var position := Vector2.ZERO
@export var spread := Vector2(3.0, 3.6)
@export_range(0.0, 4.0, 0.05) var concentration := 1.0
@export_range(0.1, 4.0, 0.05) var falloff := 1.4
