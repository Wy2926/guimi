class_name BattleStats
extends Resource
## A battle instance duplicates its starting Resource before changing these values.

@export var max_health: float = 120.0
@export var physical_attack: float = 25.0
@export var magic_attack: float = 25.0
@export var independent_attack: float = 25.0
@export var physical_defense: float = 5.0
@export var magic_defense: float = 5.0
@export_range(0.0, 1.0) var crit_chance: float = 0.08
@export var crit_multiplier: float = 1.5
@export_range(0.0, 1.0) var dodge_chance: float = 0.0
@export var move_speed: float = 5.4
@export var attack_speed: float = 1.0
@export var cooldown_multiplier: float = 1.0
@export var range_multiplier: float = 1.0
@export var pickup_radius: float = 2.0
@export_range(0.0, 1.0) var life_steal: float = 0.0
@export_enum("无属性", "火", "冰", "光", "暗") var element: int = 0
## Ordered fire, ice, light, dark. 0.1 means ten percentage points.
@export var element_bonus: Array[float] = [0.0, 0.0, 0.0, 0.0]
@export var resistances: Array[float] = [0.0, 0.0, 0.0, 0.0]
