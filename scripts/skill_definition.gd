class_name SkillDefinition
extends Resource
## Authored skill data, not an executable skill graph.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export_enum("basic", "active", "passive") var category: String = "basic"
@export_enum("物理", "魔法", "固定") var kind: int = 0
@export var coefficient: float = 1.0
@export var coefficient_growth: float = 0.2
@export_enum("继承:-1", "无属性:0", "火:1", "冰:2", "光:3", "暗:4") var element: int = -1
@export var cooldown: float = 0.0
@export_range(1, 10) var max_level: int = 5
@export var duration: float = 0.0
@export var duration_growth: float = 0.0
@export var damage_multiplier: float = 1.0
@export var attack_speed_multiplier: float = 1.0
@export var counts: Array[int] = []
@export var radius: float = 0.0
@export var radius_growth: float = 0.0
@export var visual_scale: float = 1.0
@export var visual_scale_growth: float = 0.0

func coefficient_at(level: int) -> float:
	if level <= 0:
		return 0.0
	return coefficient * (1.0 + coefficient_growth * float(clampi(level, 1, max_level) - 1))

func duration_at(level: int) -> float:
	if level <= 0:
		return 0.0
	return duration + duration_growth * float(clampi(level, 1, max_level) - 1)

func count_at(level: int) -> int:
	if level <= 0 or counts.is_empty():
		return 0
	return maxi(0, counts[mini(clampi(level, 1, max_level) - 1, counts.size() - 1)])

func radius_at(level: int) -> float:
	if level <= 0:
		return 0.0
	return maxf(0.0, radius + radius_growth * float(clampi(level, 1, max_level) - 1))

func visual_scale_at(level: int) -> float:
	if level <= 0:
		return 0.0
	return maxf(0.0, visual_scale + visual_scale_growth * float(clampi(level, 1, max_level) - 1))
