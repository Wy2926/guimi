class_name RunProgression
extends Node
## One run's experience and choices. Definitions remain read-only.

signal changed
signal choice_requested(options: Array[Dictionary])

@export var base_stats: BattleStats = preload("res://data/classes/kensei_stats.tres")
@export var initial_skills: Dictionary = {"swords": 1, "huntian_ling": 0, "meteor": 0, "thunder_orb": 0, "taiji_aura": 0}
@export var divinity: SkillDefinition = preload("res://data/skills/nezha.tres")
@export var skill_definitions: Array[SkillDefinition] = [
	preload("res://data/skills/swords.tres"),
	preload("res://data/skills/huntian_ling.tres"),
	preload("res://data/skills/zhaotian_seal.tres"),
	preload("res://data/skills/thunder_orb.tres"),
	preload("res://data/skills/taiji_aura.tres"),
]
@export var fate_definitions: Array[SkillDefinition] = [
	preload("res://data/skills/fate_crit_seal.tres"),
]
@export var evolution_definitions: Array[SkillDefinition] = [
	preload("res://data/skills/evolution_swords_pierce.tres"),
]

const ELEMENT_NAMES: Array[String] = ["无属性", "火", "冰", "光", "暗"]
const DAMAGE_NAMES: Array[String] = ["物理", "魔法", "固定"]
const STATUS_NAMES: Dictionary = {"bleed": "出血", "poison": "中毒", "shock": "感电", "burn": "灼烧", "freeze": "冰冻", "bind": "束缚", "stun": "眩晕", "curse": "诅咒"}

var stats: BattleStats
var skills: Dictionary = {}
var fates: Dictionary = {}
var evolutions: Dictionary = {}
var level: int = 1
var xp: int = 0
var pending_levels: int = 0
var choices: Array[Dictionary] = []
var _resolving_choice: bool = false

func _ready() -> void:
	if stats == null:
		reset()

func reset() -> void:
	stats = base_stats.duplicate(true) as BattleStats if base_stats != null else BattleStats.new()
	skills.clear()
	for definition: SkillDefinition in skill_definitions:
		skills[definition.id] = clampi(int(initial_skills.get(definition.id, 0)), 0, definition.max_level)
	fates.clear()
	evolutions.clear()
	level = 1
	xp = 0
	pending_levels = 0
	choices.clear()
	_resolving_choice = false
	changed.emit()

func xp_required() -> int:
	var progress: float = float(level - 1)
	return roundi(14.0 + 6.0 * progress + 0.8 * pow(progress, 1.5))

func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	if stats == null:
		reset()
	xp += amount
	while xp >= xp_required():
		xp -= xp_required()
		level += 1
		pending_levels += 1
	var request_choice: bool = pending_levels > 0 and choices.is_empty()
	if request_choice:
		_roll_choices()
	changed.emit()
	if request_choice:
		choice_requested.emit(choices.duplicate(true))

func choose(index: int) -> bool:
	if _resolving_choice or pending_levels <= 0 or index < 0 or index >= choices.size():
		return false
	# Rebuild the candidate before applying it: stale gates, capped upgrades, and
	# injected stat fields/values must never bypass the authored growth pool.
	var requested: Dictionary = choices[index]
	var selected: Dictionary = {}
	for candidate: Dictionary in _available_choices():
		if candidate.id == requested.get("id", "") and candidate.category == requested.get("category", ""):
			selected = candidate
			break
	if selected.is_empty():
		return false
	_resolving_choice = true
	match String(selected.category):
		"skill":
			var skill_id: String = String(selected.id).trim_prefix("skill_")
			var definition: SkillDefinition = skill(skill_id)
			if definition == null or skill_level(skill_id) >= definition.max_level:
				_resolving_choice = false
				return false
			skills[skill_id] = skill_level(skill_id) + 1
		"stat":
			stats.set(String(selected.id), float(selected.value))
		"fate":
			fates[String(selected.id).trim_prefix("fate_")] = 1
		"evolution":
			evolutions[String(selected.id).trim_prefix("evolution_")] = 1
		_:
			_resolving_choice = false
			return false
	choices.clear()
	pending_levels -= 1
	if pending_levels > 0:
		_roll_choices()
	changed.emit()
	if pending_levels > 0:
		choice_requested.emit(choices.duplicate(true))
	_resolving_choice = false
	return true

func skill(id: String) -> SkillDefinition:
	for definition: SkillDefinition in skill_definitions:
		if definition.id == id:
			return definition
	return null

func skill_level(id: String) -> int:
	return int(skills.get(id, 0))

func artifact_count(id: String, rank: int = -1) -> int:
	var definition: SkillDefinition = skill(id)
	var current_rank: int = skill_level(id) if rank < 0 else rank
	if definition == null or current_rank <= 0:
		return 0
	var count: int = definition.count_at(current_rank)
	if divinity != null and divinity.id == "nezha" and id in ["swords", "huntian_ling"]:
		count += 1
	return count

func has_fate(id: String) -> bool:
	return int(fates.get(id, 0)) > 0

func has_evolution(id: String) -> bool:
	return int(evolutions.get(id, 0)) > 0

func prerequisites_met(definition: SkillDefinition) -> bool:
	for requirement: String in definition.prerequisites:
		if requirement == "divinity":
			if divinity == null or divinity.id != String(definition.prerequisites[requirement]):
				return false
		elif skill(requirement) == null or skill_level(requirement) < int(definition.prerequisites[requirement]):
			return false
	return true

func signature(definition: SkillDefinition) -> String:
	var element_name: String = ELEMENT_NAMES[clampi(definition.element, 0, 4)]
	return "%s · %s" % [element_name, STATUS_NAMES.get(definition.status, "无异常")]

func coefficient(id: String) -> float:
	var definition: SkillDefinition = skill(id)
	return definition.coefficient_at(skill_level(id)) if definition != null else 0.0

func _roll_choices() -> void:
	var candidates: Array[Dictionary] = _available_choices()
	candidates.shuffle()
	choices.clear()
	# Open build-changing choices first, then a new artifact and a fate. Fill any
	# remaining slot from the existing pool; no parallel shop or loadout system.
	for candidate: Dictionary in candidates:
		if candidate.category == "evolution":
			choices.append(candidate)
			break
	for candidate: Dictionary in candidates:
		if candidate.category == "skill" and skill_level(String(candidate.id).trim_prefix("skill_")) == 0:
			choices.append(candidate)
			break
	for candidate: Dictionary in candidates:
		if candidate.category == "fate":
			choices.append(candidate)
			break
	# Keep an artifact upgrade available even after every artifact is learned.
	for candidate: Dictionary in candidates:
		if choices.size() < 3 and candidate.category == "skill" and not choices.has(candidate):
			choices.append(candidate)
			break
	for candidate: Dictionary in candidates:
		if choices.size() >= 3:
			break
		if not choices.has(candidate):
			choices.append(candidate)

func _available_choices() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	# Native melee always uses physical attack; it is not a sixth ability system.
	var attack_kinds: Array[bool] = [true, false, false]
	for definition: SkillDefinition in skill_definitions:
		var rank: int = skill_level(definition.id)
		if rank > 0 and definition.coefficient_at(rank) > 0.0 and definition.kind >= 0 and definition.kind < attack_kinds.size():
			attack_kinds[definition.kind] = true
		if rank >= definition.max_level:
			continue
		var card_title: String = "%s · Lv.%d" % [definition.title, rank + 1]
		var card_description: String = definition.description
		if rank == 0:
			card_title = "解锁 · " + definition.title
		else:
			card_description = definition.description.get_slice("；", 0) + "。"
			card_description += "\n%s倍率 %.0f%% → %.0f%%。" % [DAMAGE_NAMES[definition.kind], definition.coefficient_at(rank) * 100.0, definition.coefficient_at(rank + 1) * 100.0]
		if not definition.counts.is_empty():
			var count_label := "连锁目标" if definition.id == "huntian_ling" else "数量"
			card_description += "\n%s %d" % [count_label, artifact_count(definition.id, 1)] if rank == 0 else "\n%s %d → %d" % [count_label, artifact_count(definition.id, rank), artifact_count(definition.id, rank + 1)]
		if definition.radius > 0.0:
			card_description += " · 范围半径 %.2f" % definition.radius_at(1) if rank == 0 else " · 范围半径 %.2f → %.2f" % [definition.radius_at(rank), definition.radius_at(rank + 1)]
		if not is_zero_approx(definition.visual_scale_growth):
			card_description += "\n球体大小 %.0f%%" % (definition.visual_scale_at(1) * 100.0) if rank == 0 else "\n球体大小 %.0f%% → %.0f%%" % [definition.visual_scale_at(rank) * 100.0, definition.visual_scale_at(rank + 1) * 100.0]
		if definition.category == "passive" and definition.cooldown > 0.0:
			card_description += " · 周期 %.1f 秒" % (definition.cooldown * stats.cooldown_multiplier)
		card_description += "\n固有：%s。" % signature(definition)
		candidates.append({"id": "skill_" + definition.id, "title": card_title, "description": card_description, "category": "skill"})
	for definition: SkillDefinition in fate_definitions:
		if not has_fate(definition.id) and prerequisites_met(definition):
			candidates.append({"id": "fate_" + definition.id, "title": definition.title, "description": definition.description, "category": "fate"})
	for definition: SkillDefinition in evolution_definitions:
		if not has_evolution(definition.id) and prerequisites_met(definition):
			candidates.append({"id": "evolution_" + definition.id, "title": definition.title, "description": definition.description, "category": "evolution"})
	_add_stat_option(candidates, "max_health", "生命上限", 25.0, 620.0)
	if attack_kinds[DamageRules.Kind.PHYSICAL]:
		_add_stat_option(candidates, "physical_attack", "物理攻击", 5.0, 300.0)
	if attack_kinds[DamageRules.Kind.MAGICAL]:
		_add_stat_option(candidates, "magic_attack", "魔法攻击", 5.0, 300.0)
	if attack_kinds[DamageRules.Kind.FIXED]:
		_add_stat_option(candidates, "independent_attack", "独立攻击", 5.0, 300.0)
	_add_stat_option(candidates, "physical_defense", "物理防御", 5.0, 100.0)
	_add_stat_option(candidates, "magic_defense", "魔法防御", 5.0, 100.0)
	_add_stat_option(candidates, "crit_chance", "暴击率", 0.05, 0.75, true)
	_add_stat_option(candidates, "crit_multiplier", "暴击总倍率", 0.2, 3.0, true)
	_add_stat_option(candidates, "dodge_chance", "闪避率", 0.04, 0.4, true)
	_add_stat_option(candidates, "move_speed", "移动速度", 0.3, 8.0)
	_add_stat_option(candidates, "attack_speed", "攻击速度", 0.1, 2.0, true)
	_add_stat_option(candidates, "cooldown_multiplier", "冷却时长系数", -0.06, 0.4, true)
	_add_stat_option(candidates, "range_multiplier", "攻击范围", 0.1, 1.8, true)
	_add_stat_option(candidates, "pickup_radius", "经验拾取半径", 0.5, 7.0)
	_add_stat_option(candidates, "life_steal", "生命偷取", 0.015, 0.12, true)
	return candidates

func _add_stat_option(candidates: Array[Dictionary], id: String, title: String, step: float, limit: float, percentage: bool = false) -> void:
	var current: float = float(stats.get(id))
	var next: float = minf(current + step, limit) if step > 0.0 else maxf(current + step, limit)
	if absf(next - current) < 0.0001 or (step > 0.0 and current >= limit) or (step < 0.0 and current <= limit):
		return
	var description: String = "%s %s → %s。" % [title, _format_stat(current, percentage), _format_stat(next, percentage)]
	if id == "cooldown_multiplier":
		description += "数值越低，法宝的冷却越短；常驻神通没有冷却。"
	elif id == "life_steal":
		description += "按实际扣血计算，受群攻恢复上限约束。"
	candidates.append({"id": id, "title": title, "description": description, "category": "stat", "value": next})

func _format_stat(value: float, percentage: bool) -> String:
	if percentage:
		return ("%.1f" % (value * 100.0)).trim_suffix(".0") + "%"
	return ("%.1f" % value).trim_suffix(".0")
