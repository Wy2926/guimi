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
## Ordered fire, ice, light, dark. Attack elements belong to authored artifacts,
## never to the character's stat upgrades or an inherited enchantment.
@export var resistances: Array[float] = [0.0, 0.0, 0.0, 0.0]
