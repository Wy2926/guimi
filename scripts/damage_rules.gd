class_name DamageRules
extends RefCounted
## Only arithmetic: the receiver owns invulnerability, actual HP loss and death.

enum Kind { PHYSICAL, MAGICAL, FIXED }
enum Element { NONE, FIRE, ICE, LIGHT, DARK }

static func calculate(attacker: BattleStats, defender: BattleStats, kind: int, coefficient: float, element: int = Element.NONE, critical_roll: float = -1.0, dodge_roll: float = -1.0) -> Dictionary:
	var attack_element: int = element
	if attack_element < Element.NONE or attack_element > Element.DARK:
		attack_element = Element.NONE
	var result: Dictionary = {"damage": 0, "critical": false, "dodged": false, "element": attack_element, "kind": kind}
	if attacker == null or defender == null or coefficient <= 0.0:
		return result
	var attack: float = 0.0
	var defense: float = 0.0
	match kind:
		Kind.PHYSICAL:
			attack = attacker.physical_attack
			defense = defender.physical_defense
		Kind.MAGICAL:
			attack = attacker.magic_attack
			defense = defender.magic_defense
		Kind.FIXED:
			attack = attacker.independent_attack
		_:
			return result
	if attack <= 0.0:
		return result
	var evade_roll: float = randf() if dodge_roll < 0.0 else dodge_roll
	if evade_roll < clampf(defender.dodge_chance, 0.0, 1.0):
		result.dodged = true
		return result
	var damage: float = attack * coefficient
	if kind != Kind.FIXED:
		damage *= 100.0 / (100.0 + maxf(0.0, defense))
	if attack_element != Element.NONE:
		var element_index: int = attack_element - 1
		var resistance: float = defender.resistances[element_index] if element_index < defender.resistances.size() else 0.0
		damage *= clampf(1.0 - resistance, 0.15, 3.0)
	var crit_roll: float = randf() if critical_roll < 0.0 else critical_roll
	result.critical = crit_roll < clampf(attacker.crit_chance, 0.0, 1.0)
	if result.critical:
		damage *= maxf(1.0, attacker.crit_multiplier)
	result.damage = maxi(1, roundi(damage))
	return result
