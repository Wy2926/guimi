class_name RunProgression
extends Node
## One run's experience and choices. Definitions remain read-only.

signal changed
signal choice_requested(options: Array[Dictionary])

@export var base_stats: BattleStats = preload("res://data/classes/kensei_stats.tres")
@export var initial_skills: Dictionary = {"slash": 1, "ring": 1, "ghost": 0, "swords": 0, "meteor": 0, "thunder_orb": 0}
@export var skill_definitions: Array[SkillDefinition] = [
	preload("res://data/skills/slash.tres"),
	preload("res://data/skills/ring.tres"),
	preload("res://data/skills/ghost.tres"),
	preload("res://data/skills/swords.tres"),
	preload("res://data/skills/zhaotian_seal.tres"),
	preload("res://data/skills/thunder_orb.tres"),
	preload("res://data/skills/taiji_aura.tres"),
]

const ELEMENT_NAMES: Array[String] = ["无属性", "火", "冰", "光", "暗"]
const ELEMENT_IDS: Array[String] = ["", "fire", "ice", "light", "dark"]
const DAMAGE_NAMES: Array[String] = ["物理", "魔法", "固定"]
const ELEMENT_BONUS_CAP: float = 0.8

var stats: BattleStats
var skills: Dictionary = {"slash": 1, "ring": 1, "ghost": 0, "swords": 0, "meteor": 0, "thunder_orb": 0}
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
	skills = initial_skills.duplicate(true)
	for definition: SkillDefinition in skill_definitions:
		skills[definition.id] = clampi(int(skills.get(definition.id, 0)), 0, definition.max_level)
	level = 1
	xp = 0
	pending_levels = 0
	choices.clear()
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
	var selected: Dictionary = choices[index]
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
		"element":
			var new_element: int = int(selected.element)
			stats.element = new_element
			stats.element_bonus[new_element - 1] = float(selected.value)
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

func coefficient(id: String) -> float:
	var definition: SkillDefinition = skill(id)
	return definition.coefficient_at(skill_level(id)) if definition != null else 0.0

func _roll_choices() -> void:
	var candidates: Array[Dictionary] = _available_choices()
	candidates.shuffle()
	choices.clear()
	# Keep at least one skill available while any skill can still grow.
	for candidate: Dictionary in candidates:
		if candidate.category == "skill":
			choices.append(candidate)
			break
	for candidate: Dictionary in candidates:
		if choices.size() >= 3:
			break
		if not choices.has(candidate):
			choices.append(candidate)

func _available_choices() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var attack_kinds: Array[bool] = [false, false, false]
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
		elif definition.id == "ghost":
			card_description = "厉鬼持续时间 %.0f → %.0f 秒；强化倍率不变。" % [definition.duration_at(rank), definition.duration_at(rank + 1)]
		else:
			card_description = "%s伤害基础倍率 %.0f%% → %.0f%%。" % [DAMAGE_NAMES[definition.kind], definition.coefficient_at(rank) * 100.0, definition.coefficient_at(rank + 1) * 100.0]
		if not definition.counts.is_empty():
			card_description += "\n数量 %d" % definition.count_at(1) if rank == 0 else "\n数量 %d → %d" % [definition.count_at(rank), definition.count_at(rank + 1)]
		if definition.radius > 0.0:
			card_description += " · 范围半径 %.2f" % definition.radius_at(1) if rank == 0 else " · 范围半径 %.2f → %.2f" % [definition.radius_at(rank), definition.radius_at(rank + 1)]
		if not is_zero_approx(definition.visual_scale_growth):
			card_description += "\n球体大小 %.0f%%" % (definition.visual_scale_at(1) * 100.0) if rank == 0 else "\n球体大小 %.0f%% → %.0f%%" % [definition.visual_scale_at(rank) * 100.0, definition.visual_scale_at(rank + 1) * 100.0]
		if definition.category == "passive" and definition.cooldown > 0.0:
			card_description += " · 周期 %.1f 秒" % (definition.cooldown * stats.cooldown_multiplier)
		if definition.element >= 0 and definition.element < ELEMENT_NAMES.size():
			card_description += "\n固定%s%s，不受附魔覆盖。" % [ELEMENT_NAMES[definition.element], "属性" if definition.element > 0 else ""]
		candidates.append({"id": "skill_" + definition.id, "title": card_title, "description": card_description, "category": "skill"})
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
	for attack_element: int in range(1, 5):
		_add_element_option(candidates, attack_element)
	return candidates

func _add_stat_option(candidates: Array[Dictionary], id: String, title: String, step: float, limit: float, percentage: bool = false) -> void:
	var current: float = float(stats.get(id))
	var next: float = minf(current + step, limit) if step > 0.0 else maxf(current + step, limit)
	if absf(next - current) < 0.0001 or (step > 0.0 and current >= limit) or (step < 0.0 and current <= limit):
		return
	var description: String = "%s %s → %s。" % [title, _format_stat(current, percentage), _format_stat(next, percentage)]
	if id == "cooldown_multiplier":
		description += "数值越低，主动技能及周期技能的冷却越短。"
	elif id == "life_steal":
		description += "按实际扣血计算，受群攻恢复上限约束。"
	candidates.append({"id": id, "title": title, "description": description, "category": "stat", "value": next})

func _add_element_option(candidates: Array[Dictionary], attack_element: int) -> void:
	var current: float = stats.element_bonus[attack_element - 1]
	if stats.element == attack_element and current >= ELEMENT_BONUS_CAP - 0.0001:
		return
	var next: float = minf(ELEMENT_BONUS_CAP, current + 0.1)
	var title: String = ELEMENT_NAMES[attack_element] + ("属性强化" if stats.element == attack_element else "之附魔")
	var description: String = "%s属强 %.0f%% → %.0f%%，仅该元素命中生效。" % [ELEMENT_NAMES[attack_element], current * 100.0, next * 100.0]
	if stats.element != attack_element:
		description = "继承元素的攻击改为%s属性；" % ELEMENT_NAMES[attack_element] + description
	var fixed_elements: PackedStringArray = []
	for definition: SkillDefinition in skill_definitions:
		if skill_level(definition.id) > 0 and definition.element >= 0 and definition.element < ELEMENT_NAMES.size():
			fixed_elements.append("%s（%s）" % [definition.title, ELEMENT_NAMES[definition.element]])
	if not fixed_elements.is_empty():
		description += "\n固定元素不变：%s。" % "、".join(fixed_elements)
	candidates.append({"id": "element_" + ELEMENT_IDS[attack_element], "title": title, "description": description, "category": "element", "element": attack_element, "value": next})

func _format_stat(value: float, percentage: bool) -> String:
	if percentage:
		return ("%.1f" % (value * 100.0)).trim_suffix(".0") + "%"
	return ("%.1f" % value).trim_suffix(".0")
