extends Node3D
## One authored automatic passive: visible targets, straight projectiles and shared control limits.

const ORB_SCRIPT = preload("res://scripts/thunder_orb.gd")
const SKILL_ID := "thunder_orb"
const TARGET_RANGE := 10.0
const MAX_ORBS := 9
const CONTROL_INTERVAL := 0.35
const SLOT_RADIUS_RATIO := 0.8

var player: DuelFighter
var progression: RunProgression
var feedback: Node3D
var camera: Camera3D
var orbs: Array[Node3D] = []
var cooldown_left := 0.0
var cast_count := 0
var hit_count := 0

var _level := 0
var _control_cooldowns: Dictionary = {}

func _ready() -> void:
	refresh_skills()

func refresh_skills() -> void:
	_level = progression.skill_level(SKILL_ID) if is_instance_valid(progression) else 0
	# Upgrades affect the next cast. Existing areas keep their cast-time dimensions and life.
	if _level <= 0:
		_clear_orbs()
		cooldown_left = 0.0

func reset() -> void:
	_clear_orbs()
	_control_cooldowns.clear()
	cooldown_left = 0.0
	cast_count = 0
	hit_count = 0
	refresh_skills()

func _clear_orbs() -> void:
	var previous := orbs.duplicate()
	orbs.clear()
	for orb in previous:
		if is_instance_valid(orb):
			orb.cancel()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.dead or not player.enabled:
		if not orbs.is_empty():
			_clear_orbs()
		return
	for target_id in _control_cooldowns.keys():
		var remaining: float = float(_control_cooldowns[target_id]) - delta
		if remaining <= 0.0:
			_control_cooldowns.erase(target_id)
		else:
			_control_cooldowns[target_id] = remaining
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if _level <= 0 or cooldown_left > 0.0 or orbs.size() >= MAX_ORBS:
		return
	var targets := _visible_targets()
	if targets.is_empty():
		return
	_cast(targets)

func _visible_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if not is_instance_valid(camera):
		return targets
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node3D or candidate.dead or not candidate.is_visible_in_tree():
			continue
		var flat: Vector3 = candidate.global_position - player.global_position
		flat.y = 0.0
		if flat.length_squared() > TARGET_RANGE * TARGET_RANGE:
			continue
		if not camera.is_position_in_frustum(candidate.global_position + Vector3.UP * 0.2) or not camera.is_position_in_frustum(candidate.global_position + Vector3.UP):
			continue
		targets.append(candidate)
	targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return player.global_position.distance_squared_to(a.global_position) < player.global_position.distance_squared_to(b.global_position))
	return targets

func _cast(targets: Array[Node3D]) -> void:
	var definition := progression.skill(SKILL_ID)
	if definition == null:
		return
	var amount := mini(definition.count_at(_level), MAX_ORBS - orbs.size())
	if amount <= 0:
		return
	var center_direction: Vector3 = targets[0].global_position - player.global_position
	center_direction.y = 0.0
	if center_direction.length_squared() < 0.001:
		center_direction = player.facing
	center_direction = center_direction.normalized()
	var side := center_direction.cross(Vector3.UP)
	var spacing := definition.radius_at(_level) * player.stats.range_multiplier * SLOT_RADIUS_RATIO
	var half_width := float(amount - 1) * spacing * 0.5
	var origin := player.global_position + Vector3.UP * 0.85 + center_direction * 0.65
	# Move the whole row inward near the arena rim; clamping slots separately would merge them.
	var flat_origin := Vector2(origin.x, origin.z).limit_length(maxf(0.1, player.arena_radius - half_width - 0.15))
	origin.x = flat_origin.x
	origin.z = flat_origin.y
	for i in amount:
		var lane := side * (float(i) - float(amount - 1) * 0.5) * spacing
		var start := origin + lane
		var target := targets[i % targets.size()]
		var aim: Vector3 = target.global_position
		# With few targets, retain nearby parallel lanes inside the orb's real hit radius.
		# Otherwise aim each separated origin at its own target, without an arbitrary fan miss.
		if targets.size() < amount:
			aim += lane
		var heading: Vector3 = aim - start
		heading.y = 0.0
		if heading.length_squared() < 0.001:
			heading = center_direction
		heading = heading.normalized()
		var orb := ORB_SCRIPT.new() as Area3D
		orb.configure(self, heading, definition, _level, player.stats.range_multiplier, player.arena_radius)
		orb.feedback = feedback
		orb.expired.connect(_on_orb_expired)
		orbs.append(orb)
		add_child(orb)
		orb.global_position = start
	cast_count += 1
	cooldown_left = definition.cooldown * player.stats.cooldown_multiplier

func contact(target: Node3D, orb: Node3D) -> void:
	if not is_instance_valid(player) or player.dead or not player.enabled or not is_instance_valid(target) or target.dead or not orbs.has(orb):
		return
	var target_id := target.get_instance_id()
	var apply_control := not _control_cooldowns.has(target_id)
	# No ghost multiplier and no swing event: auxiliary hits never roll other passives.
	var result := player.deal_damage(target, orb.kind, orb.coefficient, orb.element, true, false, "雷缚珠", orb.direction, apply_control)
	if float(result.get("actual", 0.0)) > 0.0:
		hit_count += 1
		if apply_control:
			_control_cooldowns[target_id] = CONTROL_INTERVAL
		if is_instance_valid(orb):
			orb.flash_hit()

func _on_orb_expired(orb: Node3D) -> void:
	orbs.erase(orb)
