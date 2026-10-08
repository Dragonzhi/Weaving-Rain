extends Resource
## Prototype tuning values, not confirmed balance or final game rules.

@export_group("Wind")
@export var brush_radius: float = 1.5
@export var max_wind: float = 6.0
@export var wind_decay: float = 1.1
@export var wind_spread: float = 0.65
@export var rain_response: float = 0.24
@export_group("Water")
@export var initial_humidity: float = 3.2
@export var lift_rate: float = 2.2
@export var cloud_threshold: float = 1.4
@export var hold_seconds: float = 2.0
@export var progress_retreat: float = 0.5
@export var rain_rate: float = 0.16
@export var rain_end_density: float = 0.025
@export var plot_water_scale: float = 6.0
@export_group("Goal")
@export var target_water: float = 100.0
@export var flood_water: float = 150.0
@export var safe_seconds: float = 2.0
