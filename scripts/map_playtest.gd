extends "res://scripts/main.gd"

func _ready() -> void:
	if custom_map_path.is_empty(): custom_map_path = "res://.godot/map-playtest.tres"
	persist_progress = false
	super._ready()

func initial_mode(_args: PackedStringArray) -> String:
	return "free"

func enter_free_play() -> void:
	switch_mode("free")
