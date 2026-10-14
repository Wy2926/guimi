class_name ArenaEnemy
extends CharacterBody3D
## Three readable enemy attacks and one boss, using the existing authored skeleton.

signal defeated(enemy: Node3D)
signal attacked(enemy: Node3D)

const PROJECTILE = preload("res://scripts/enemy_projectile.gd")
const ELEMENT_COLORS := [Color("cb8263"), Color("ff7548"), Color("79cce8"), Color("ffe29a"), Color("b397ec")]
enum State { APPROACH, WINDUP, CHARGE, RECOVER, DEAD }

var stats: BattleStats
var health: float = 48.0
var dead := false
var kind := "chaser"
var elite := false
var boss := false
var affinity := DamageRules.Element.NONE
var experience_value := 6
var target: Node3D
var camera: Camera3D
var arena_radius := 15.8

@onready var visual: Node3D = $Visual
@onready var animation: AnimationPlayer = $Visual/Model/AnimationPlayer
@onready var footing: MeshInstance3D = $Footing
@onready var avoidance: NavigationAgent3D = $Avoidance

var flash_material: ShaderMaterial
var _flash_active := false
var _state := State.APPROACH
var _state_left := 0.0
var _attack_left := 0.6
var _stagger_left := 0.0
var _poise_left := 0.0
var _push := Vector3.ZERO
var _direction := Vector3.FORWARD
var _attack_point := Vector3.ZERO
var _charge_hit := false
var _boss_pattern := 0
var _warning: Node3D
var _meshes: Array[MeshInstance3D] = []
var _safe_velocity := Vector3.ZERO
var _avoidance_ready := false
var _gravity_wells: Array[Area3D] = []
# The receiver owns its abnormal states just as it owns health and control.
# No global timer/event bus or duplicate damage implementation.
const STATUS_RULES := {
	"burn": {"title": "灼烧", "duration": 4.0, "coefficient": 0.18},
	"bleed": {"title": "出血", "duration": 3.0, "coefficient": 0.12},
	"poison": {"title": "中毒", "duration": 5.0, "coefficient": 0.16},
	"shock": {"title": "感电", "duration": 3.0},
	"curse": {"title": "咒印", "duration": 4.0},
	"freeze": {"title": "冰冻", "duration": 1.5},
	"bind": {"title": "束缚", "duration": 2.0},
	"stun": {"title": "眩晕", "duration": 0.8},
}
const CONTROL_STATUSES := ["freeze", "bind", "stun"]
const DOT_INTERVAL := 0.5
var statuses: Dictionary = {}
var _control_recovery: Dictionary = {}
var _status_label: Label3D

func configure(kind_name: String, stage: int, element_id: int, is_elite := false, is_boss := false) -> void:
	kind = kind_name
	elite = is_elite
	boss = is_boss
	var level := maxi(stage, 0)
	stats = BattleStats.new()
	stats.max_health = 48.0 + level * 7.0
	stats.physical_attack = 9.0 + level * 1.25
	stats.magic_attack = 10.0 + level * 1.4
	stats.independent_attack = 8.0 + level
	stats.physical_defense = 5.0 + level * 1.5
	stats.magic_defense = 4.0 + level * 1.5
	stats.crit_chance = 0.0
	stats.crit_multiplier = 1.5
	stats.dodge_chance = 0.0
	stats.move_speed = 2.55 + minf(level * 0.045, 0.45)
	affinity = clampi(element_id, 0, 4)
	stats.resistances = [0.0, 0.0, 0.0, 0.0]
	if affinity > 0:
		stats.resistances[affinity - 1] = 0.35
		var opposite := [0, 2, 1, 4, 3]
		stats.resistances[opposite[affinity] - 1] = -0.20
	experience_value = 6
	if kind == "charger":
		stats.max_health *= 1.25
		stats.move_speed *= 0.82
		experience_value += 2
	elif kind == "ranged":
		stats.max_health *= 0.8
		stats.move_speed *= 0.7
		experience_value += 2
	if elite:
		stats.max_health *= 3.2
		stats.physical_attack *= 1.3
		stats.magic_attack *= 1.3
		stats.physical_defense += 12.0
		stats.magic_defense += 12.0
		experience_value = 35
	if boss:
		kind = "boss"
		stats.max_health = 2400.0 + level * 80.0
		stats.physical_attack = 22.0
		stats.magic_attack = 24.0
		stats.physical_defense = 35.0
		stats.magic_defense = 35.0
		stats.move_speed = 1.25
		experience_value = 250
	health = stats.max_health

func _ready() -> void:
	if stats == null:
		configure(kind, 0, 0, elite, boss)
	add_to_group("enemies")
	# Enemies collide with the arena, not one another or the player. Attacks are explicit.
	collision_layer = 4
	collision_mask = 1
	platform_floor_layers = 1
	visual.scale *= 1.65 if boss else (1.16 if elite else 1.0)
	var body_scale := 1.5 if boss else (1.1 if elite else 1.0)
	$CollisionShape3D.scale = Vector3.ONE * body_scale
	$CollisionShape3D.position.y = 0.83 * body_scale
	avoidance.radius *= body_scale
	avoidance.height *= body_scale
	avoidance.velocity_computed.connect(_cache_safe_velocity)
	flash_material = ShaderMaterial.new()
	flash_material.shader = preload("res://shaders/hit_flash.gdshader")
	flash_material.set_shader_parameter("flash", 0.0)
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		_meshes.append(mesh)
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = ELEMENT_COLORS[affinity]
	ring_material.emission_enabled = true
	ring_material.emission = ring_material.albedo_color
	ring_material.emission_energy_multiplier = 0.7
	footing.material_override = ring_material
	footing.scale *= 1.7 if boss else (1.2 if elite else 1.0)
	# Imported animation resources are shared, so only adjust private copies.
	var library := AnimationLibrary.new()
	for clip in ["Idle", "Walking_A", "Running_A", "Hit_A", "Death_B", "1H_Melee_Attack_Slice_Horizontal", "2H_Melee_Attack_Chop", "Spellcast_Shoot"]:
		if animation.has_animation(clip):
			var copied := animation.get_animation(clip).duplicate(true) as Animation
			copied.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Walking_A", "Running_A"] else Animation.LOOP_NONE
			library.add_animation(clip, copied)
	for name in animation.get_animation_library_list():
		animation.remove_animation_library(name)
	animation.add_animation_library("", library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_play("Idle")

func _physics_process(delta: float) -> void:
	if _flash_active:
		var flash := move_toward(float(flash_material.get_shader_parameter("flash")), 0.0, delta * 9.0)
		flash_material.set_shader_parameter("flash", flash)
		if flash <= 0.0:
			_set_flash_visible(false)
	if dead:
		_state_left -= delta
		for mesh in _meshes:
			mesh.transparency = clampf(1.0 - _state_left / 0.45, 0.0, 1.0)
		if _state_left <= 0.0:
			queue_free()
		return
	advance_statuses(delta)
	if dead:
		return
	if not is_instance_valid(target) or target.dead:
		velocity = Vector3.ZERO
		avoidance.velocity = Vector3.ZERO
		_clear_warning()
		_play("Idle")
		return
	_attack_left = maxf(0.0, _attack_left - delta)
	_poise_left = maxf(0.0, _poise_left - delta)
	_stagger_left = maxf(0.0, _stagger_left - delta)
	_push = _push.move_toward(Vector3.ZERO, delta * 16.0)
	var toward := target.global_position - global_position
	toward.y = 0.0
	var distance := toward.length()
	var desired := Vector3.ZERO
	var incapacitated := has_status("freeze") or has_status("stun")
	if incapacitated:
		desired = Vector3.ZERO
	elif _stagger_left > 0.0:
		desired = _push
	elif _state == State.WINDUP:
		_state_left -= delta
		if _state_left <= 0.0:
			_release_attack()
	elif _state == State.CHARGE:
		_state_left -= delta
		desired = _direction * 10.0
		if not _charge_hit and distance < 1.15:
			_charge_hit = true
			_damage_target(0, 1.45, _direction, true)
		if _state_left <= 0.0:
			_state = State.RECOVER
			_state_left = 0.45
	elif _state == State.RECOVER:
		_state_left -= delta
		if _state_left <= 0.0:
			_state = State.APPROACH
	else:
		_direction = toward.normalized()
		if distance > 0.01:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(_direction.x, _direction.z), minf(1.0, delta * 9.0))
		var reach := 10.0 if kind == "ranged" or boss else (7.0 if kind == "charger" else 1.55)
		var needs_cast_visibility := kind == "ranged" or (boss and _boss_pattern % 2 == 1)
		var cast_visible := not needs_cast_visibility or _cast_visible()
		if _attack_left <= 0.0 and distance <= reach and cast_visible:
			_begin_attack()
		elif kind == "ranged":
			desired = _direction * stats.move_speed * (1.0 if distance > 7.5 or not cast_visible else (-1.0 if distance < 4.0 else 0.0))
		else:
			desired = _direction * stats.move_speed if distance > (4.5 if boss else 1.25) or not cast_visible else Vector3.ZERO
		if _state == State.APPROACH:
			_play("Walking_A" if desired.length_squared() > 0.01 else "Idle")
	# Native areas register only their overlapping bodies. Multiple wells share one
	# capped movement contribution; they never mutate stats or teleport the body.
	var pull := Vector3.ZERO
	var pull_limit := 0.0
	var slow := 1.0
	var resistance := 0.35 if elite else 1.0
	for i in range(_gravity_wells.size() - 1, -1, -1):
		var well := _gravity_wells[i]
		if not is_instance_valid(well):
			_gravity_wells.remove_at(i)
			continue
		var influence: float = well.influence_at(global_position) if not boss else 0.0
		if influence <= 0.0:
			continue
		slow = minf(slow, 1.0 - well.SLOW_RATIO * resistance)
		pull_limit = maxf(pull_limit, well.PULL_SPEED * resistance)
		var inward: Vector3 = well.global_position - global_position
		inward.y = 0.0
		# Ease to a small central pocket without overshooting it in one physics tick.
		var speed: float = minf(well.PULL_SPEED * resistance * influence, maxf(0.0, inward.length() - 0.25) / delta)
		pull += inward.normalized() * speed
	pull = pull.limit_length(pull_limit)
	var requested := desired * (slow if _stagger_left <= 0.0 else 1.0) + pull + (_push if _stagger_left <= 0.0 else Vector3.ZERO)
	if incapacitated:
		requested = Vector3.ZERO
	elif has_status("bind"):
		# Bound enemies may attack in reach, and existing gravity wells can pull
		# them into a seal. Their own locomotion/charge cannot escape the bind.
		requested = pull
	requested.y = 0.0
	var can_avoid := not incapacitated and not has_status("bind") and _state == State.APPROACH and _stagger_left <= 0.0 and _push.length_squared() < 0.01 and is_equal_approx(slow, 1.0)
	# Native RVO works on the world's default map without a navigation mesh/path query.
	avoidance.target_position = target.global_position
	# Fixed windups, charge lanes and knockback are obstacles to approaching enemies.
	avoidance.avoidance_priority = 0.5 if can_avoid else 1.0
	avoidance.velocity = requested
	# The solver replies after physics; consume the previous tick only in free movement.
	var movement := _safe_velocity if can_avoid and _avoidance_ready else requested
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y = -0.1 if is_on_floor() else velocity.y - 18.0 * delta
	move_and_slide()
	var flat := Vector2(position.x, position.z)
	if flat.length() > arena_radius - 0.5:
		flat = flat.normalized() * (arena_radius - 0.5)
		position.x = flat.x
		position.z = flat.y

func add_gravity_well(well: Area3D) -> void:
	if not dead and not _gravity_wells.has(well):
		_gravity_wells.append(well)

func remove_gravity_well(well: Area3D) -> void:
	_gravity_wells.erase(well)

func _cache_safe_velocity(safe_velocity: Vector3) -> void:
	# Never move from this callback: SceneTree pause must also freeze avoidance motion.
	_safe_velocity = safe_velocity
	_avoidance_ready = not dead

func _begin_attack() -> void:
	_state = State.WINDUP
	_attack_point = target.global_position
	_attack_point.y = 0.07
	visual.rotation.y = atan2(_direction.x, _direction.z)
	_state_left = 0.42
	if boss:
		_state_left = 1.15
		if _boss_pattern % 2 == 0:
			_circle_warning(_attack_point, 2.8)
		else:
			_fan_warning()
	elif kind == "charger":
		_state_left = 0.8
		_line_warning()
	elif kind == "ranged":
		_state_left = 0.65
		_circle_warning(global_position + Vector3.UP * 0.05, 0.8)
	else:
		_circle_warning(global_position + _direction * 0.8 + Vector3.UP * 0.06, 0.8)
	var clip := "Spellcast_Shoot" if kind == "ranged" or (boss and _boss_pattern % 2 == 1) else ("2H_Melee_Attack_Chop" if boss else "1H_Melee_Attack_Slice_Horizontal")
	_play(clip, 0.8)

func _release_attack() -> void:
	_clear_warning()
	# Do not finish an offscreen projectile cast after the follow camera has moved.
	if (kind == "ranged" or (boss and _boss_pattern % 2 == 1)) and not _cast_visible():
		_state = State.RECOVER
		_state_left = 0.25
		_attack_left = 0.4
		return
	attacked.emit(self)
	_state = State.RECOVER
	_state_left = 0.35
	_attack_left = 1.45
	if boss:
		if _boss_pattern % 2 == 0:
			var distance := Vector2(target.global_position.x - _attack_point.x, target.global_position.z - _attack_point.z).length()
			if distance <= 2.8:
				_damage_target(1, 1.35, (target.global_position - _attack_point).normalized(), true)
			_impact_ring(_attack_point, 2.8)
		else:
			for i in 7:
				_launch_projectile(_direction.rotated(Vector3.UP, (i - 3) * 0.22), 6.2, 1.0)
		_boss_pattern += 1
		_attack_left = 3.0
		_state_left = 0.75
	elif kind == "charger":
		_state = State.CHARGE
		_state_left = 0.6
		_charge_hit = false
		_attack_left = 3.0
		_play("Running_A", 1.4)
	elif kind == "ranged":
		_launch_projectile(_direction, 6.0, 1.0)
		_attack_left = 2.4
	else:
		var toward := target.global_position - global_position
		toward.y = 0.0
		if toward.length() <= 1.9 and toward.normalized().dot(_direction) > 0.2:
			_damage_target(0, 1.0, _direction)

func _damage_target(damage_kind: int, coefficient: float, direction: Vector3, heavy := false) -> void:
	if not is_instance_valid(target) or target.dead:
		return
	var result := DamageRules.calculate(stats, target.stats, damage_kind, coefficient, affinity)
	target.receive_damage(result, direction, heavy)

func _cast_visible() -> bool:
	if not is_instance_valid(camera):
		return true
	return camera.is_position_in_frustum(global_position + Vector3.UP * 0.1) and camera.is_position_in_frustum(global_position + Vector3.UP * 1.0)

func _launch_projectile(direction: Vector3, speed: float, coefficient: float) -> void:
	var projectile := PROJECTILE.new() as Area3D
	projectile.configure(stats, target, direction, speed, coefficient, affinity)
	add_child(projectile)
	projectile.top_level = true
	projectile.global_position = global_position + Vector3.UP * 0.95 + direction * 0.7

func receive_damage(result: Dictionary, direction: Vector3, heavy := false, spectral := false, apply_control := true) -> Dictionary:
	var applied := result.duplicate()
	applied["actual"] = 0.0
	applied["lethal"] = false
	if dead or bool(result.get("dodged", false)):
		return applied
	var amount := minf(health, maxf(0.0, float(result.get("damage", 0.0))))
	health -= amount
	applied["actual"] = amount
	if amount <= 0.0:
		return applied
	flash_material.set_shader_parameter("flash", 0.4 if spectral else 0.65)
	flash_material.set_shader_parameter("tint", Color("ffd6a0") if heavy else Color("bceeff"))
	_set_flash_visible(true)
	if not boss and apply_control:
		_push = direction.normalized() * ((0.7 if elite else 1.6) if spectral else (1.5 if elite else (4.3 if heavy else 2.1)))
		if _poise_left <= 0.0 and _state != State.CHARGE:
			_stagger_left = 0.035 if elite else (0.09 if spectral else 0.14)
			_poise_left = 0.65 if elite else 0.45
			if not elite and _state == State.WINDUP:
				_clear_warning()
				_state = State.RECOVER
				_state_left = 0.18
				_attack_left = maxf(_attack_left, 0.5)
			if not elite:
				_play("Hit_A")
	if health <= 0.0:
		dead = true
		applied["lethal"] = true
		_state = State.DEAD
		_state_left = 0.7
		collision_layer = 0
		collision_mask = 0
		avoidance.avoidance_enabled = false
		_avoidance_ready = false
		_clear_warning()
		footing.hide()
		_play("Death_B")
		_spread_cursed_death()
		statuses.clear()
		_control_recovery.clear()
		_refresh_status_label()
		defeated.emit(self)
	return applied

func has_status(id: String) -> bool:
	return statuses.has(id) and float(statuses[id].remaining) > 0.0

func get_status(id: String) -> Dictionary:
	return statuses[id].duplicate() if has_status(id) else {}

func apply_status(id: String, source: DuelFighter, skill_id: String, duration: float = -1.0, potency: float = 1.0, secondary: bool = false) -> bool:
	if dead or not STATUS_RULES.has(id) or not is_instance_valid(source) or source.dead or not source.enabled or potency <= 0.0:
		return false
	var lifetime: float = float(STATUS_RULES[id].duration) if duration < 0.0 else duration
	if lifetime <= 0.0:
		return false
	if id in CONTROL_STATUSES:
		# Repeated pulses cannot refresh a hard control forever. Each control
		# has one second of recovery after expiry/consumption; bosses are immune.
		if boss or has_status(id) or float(_control_recovery.get(id, 0.0)) > 0.0:
			return false
		lifetime *= 0.35 if elite else 1.0
	var previous := get_status(id)
	if not previous.is_empty():
		# Refresh does not reset the tick clock (fast hits must not starve DoT).
		previous.remaining = maxf(float(previous.remaining), lifetime)
		# A same-strength propagated copy must not overwrite an original
		# artifact application and silently take away its chaining eligibility.
		if potency > float(previous.potency) or (is_equal_approx(potency, float(previous.potency)) and (not secondary or bool(previous.secondary))):
			previous.potency = potency
			previous.source = weakref(source)
			previous.skill_id = skill_id
			previous.secondary = secondary
		if id == "shock":
			previous.charges = 3
		statuses[id] = previous
	else:
		statuses[id] = {"source": weakref(source), "skill_id": skill_id, "remaining": lifetime, "potency": potency, "secondary": secondary, "tick_left": DOT_INTERVAL, "charges": 3 if id == "shock" else 0, "reaction_left": 0.0}
	if id in ["freeze", "stun"]:
		_clear_warning()
		_state = State.RECOVER
		_state_left = 0.25
		_push = Vector3.ZERO
		velocity = Vector3.ZERO
		_safe_velocity = Vector3.ZERO
		_play("Idle")
	_refresh_status_label()
	return true

func remove_status(id: String) -> void:
	if statuses.erase(id) and id in CONTROL_STATUSES:
		_control_recovery[id] = 1.0
	_refresh_status_label()

func advance_statuses(delta: float) -> void:
	if dead or delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	for id: String in _control_recovery.keys():
		_control_recovery[id] = maxf(0.0, float(_control_recovery[id]) - delta)
		if is_zero_approx(float(_control_recovery[id])):
			_control_recovery.erase(id)
	for id: String in statuses.keys():
		if dead:
			break
		if not statuses.has(id):
			continue
		var status: Dictionary = statuses[id]
		var source := (status.source as WeakRef).get_ref() as DuelFighter
		if not is_instance_valid(source) or source.dead or not source.enabled:
			remove_status(id)
			continue
		var elapsed := minf(delta, float(status.remaining))
		status.remaining = maxf(0.0, float(status.remaining) - delta)
		status.reaction_left = maxf(0.0, float(status.reaction_left) - delta)
		if STATUS_RULES[id].has("coefficient"):
			status.tick_left = float(status.tick_left) - elapsed
			# Catch up the finite elapsed lifetime, not an unbounded proc loop.
			while float(status.tick_left) <= 0.00001 and not dead and source.enabled:
				status.tick_left += DOT_INTERVAL
				source.deal_status_damage(self, id, status)
		if not dead and float(status.remaining) <= 0.0:
			remove_status(id)

func _spread_cursed_death() -> void:
	if not has_status("curse") or bool(statuses.curse.secondary):
		return
	var source := (statuses.curse.source as WeakRef).get_ref() as DuelFighter
	if not is_instance_valid(source) or not source.enabled or source.dead:
		return
	for recipient: Node3D in source.reaction_targets(self, 3.0, 3):
		for id: String in ["burn", "poison", "bleed"]:
			var carried := get_status(id)
			if carried.is_empty() or bool(carried.secondary):
				continue
			var owner := (carried.source as WeakRef).get_ref() as DuelFighter
			recipient.apply_status(id, owner, String(carried.skill_id), float(carried.remaining), float(carried.potency), true)

func _refresh_status_label() -> void:
	if statuses.is_empty():
		if is_instance_valid(_status_label):
			_status_label.hide()
		return
	if not is_instance_valid(_status_label):
		_status_label = Label3D.new()
		_status_label.font = preload("res://assets/fonts/interface.tres")
		_status_label.font_size = 28
		_status_label.pixel_size = 0.007
		_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_status_label.no_depth_test = true
		_status_label.modulate = Color("eee7d7")
		_status_label.position.y = 2.0 if not boss else 3.2
		add_child(_status_label)
	var names := PackedStringArray()
	for id: String in statuses:
		names.append(String(STATUS_RULES[id].title))
	_status_label.text = " · ".join(names)
	_status_label.show()

func _set_flash_visible(enabled: bool) -> void:
	if _flash_active == enabled:
		return
	_flash_active = enabled
	# Invisible additive overlays still cost a draw call; attach only across a hit flash.
	for mesh in _meshes:
		mesh.material_overlay = flash_material if enabled else null

func _play(clip: String, speed := 1.0) -> void:
	if animation.has_animation(clip) and animation.current_animation != clip:
		animation.play(clip, 0.08, speed)

func _warning_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ff6d47")
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 1.0
	return material

func _circle_warning(point: Vector3, radius: float) -> void:
	_clear_warning()
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.055
	mesh.outer_radius = radius
	mesh.rings = 40
	mesh.ring_segments = 4
	ring.mesh = mesh
	ring.material_override = _warning_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.top_level = true
	ring.global_position = Vector3(point.x, 0.065, point.z)
	_warning = ring

func _line_warning() -> void:
	_clear_warning()
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.035, 6.0)
	line.mesh = mesh
	line.material_override = _warning_material()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	line.top_level = true
	line.global_position = global_position + _direction * 3.0
	line.global_position.y = 0.05
	line.rotation.y = atan2(_direction.x, _direction.z)
	_warning = line

func _fan_warning() -> void:
	_clear_warning()
	var fan := Node3D.new()
	add_child(fan)
	fan.top_level = true
	fan.global_position = Vector3(global_position.x, 0.05, global_position.z)
	for i in 3:
		var direction := _direction.rotated(Vector3.UP, (i - 1) * 0.66)
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 0.025, 7.0)
		line.mesh = mesh
		line.material_override = _warning_material()
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fan.add_child(line)
		line.position = direction * 3.5
		line.rotation.y = atan2(direction.x, direction.z)
	_warning = fan

func _impact_ring(point: Vector3, radius: float) -> void:
	_circle_warning(point, radius)
	var ring := _warning
	_warning = null
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(1.08, 1.0, 1.08), 0.12)
	tween.tween_callback(ring.queue_free)

func _clear_warning() -> void:
	if is_instance_valid(_warning):
		_warning.queue_free()
	_warning = null
