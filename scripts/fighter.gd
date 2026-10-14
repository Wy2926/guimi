class_name DuelFighter
extends CharacterBody3D
## The normal three-move combo uses original KayKit poses and native animation events.

signal swing_started(heavy: bool)
signal swing_active(heavy: bool)
signal fabao_requested(skill_id: String, target: Node3D)
signal hit_confirmed(target: Node3D, point: Vector3, result: Dictionary, heavy: bool, source: String)
signal defeated
signal hurt(result: Dictionary)
signal stepped(point: Vector3)

const ATTACK := &"1H_Melee_Attack_Slice_Horizontal"
const SPIN := &"2H_Melee_Attack_Spin"
const COMBO_GRACE := 0.65

# Only this fighter's authored moves, not a general skill/animation framework.
# Knots align the original artist's anticipation and swing with the hit events.
const NORMAL_COMBO := [
	{"animation": ATTACK, "source": ATTACK, "label": "横扫", "duration": 0.60, "knots": [Vector2(0, 0), Vector2(0.2, 0.17), Vector2(0.333333, 0.27)], "strikes": [0.20], "damage": 25, "style": "horizontal", "round": false, "lunge": 3.8},
	{"animation": &"Combo_Rising", "source": &"1H_Melee_Attack_Slice_Diagonal", "label": "逆袈裟", "duration": 0.62, "knots": [Vector2(0, 0), Vector2(0.30, 0.17), Vector2(0.46, 0.29)], "strikes": [0.22], "damage": 28, "style": "rise", "round": false, "lunge": 4.6},
	{"animation": &"Combo_Cleave", "source": &"2H_Melee_Attack_Chop", "label": "坠刃", "duration": 0.76, "knots": [Vector2(0, 0), Vector2(0.70, 0.23), Vector2(0.90, 0.38)], "strikes": [0.30], "damage": 38, "style": "down", "round": false, "lunge": 5.4},
]
# Retain the authored multi-hit clips for reuse; character bonuses do not select them.
const DIVINITY_COMBO := [
	{"animation": &"Divinity_Reaping", "source": &"2H_Melee_Attack_Spinning", "label": "莲轮双击", "duration": 0.62, "knots": [Vector2(0, 0), Vector2(0.10, 0.10), Vector2(0.50, 0.40)], "strikes": [0.14, 0.33], "damage": 20, "style": "spin", "round": true, "lunge": 4.2},
	{"animation": &"Divinity_Rending", "source": &"2H_Melee_Attack_Slice", "label": "绫影横断", "duration": 0.56, "knots": [Vector2(0, 0), Vector2(0.30, 0.13), Vector2(0.45, 0.24)], "strikes": [0.18], "damage": 28, "style": "reverse", "round": false, "lunge": 5.8},
	{"animation": &"Divinity_Piercing", "source": &"2H_Melee_Attack_Stab", "label": "火尖突刺", "duration": 0.58, "knots": [Vector2(0, 0), Vector2(0.30, 0.13), Vector2(0.46, 0.25)], "strikes": [0.18], "damage": 26, "style": "thrust", "round": false, "lunge": 7.0},
	{"animation": &"Divinity_Whirlwind", "source": SPIN, "label": "八臂连环", "duration": 0.82, "knots": [Vector2(0, 0), Vector2(0.80, 0.16), Vector2(1.60, 0.59)], "strikes": [0.22, 0.37, 0.52], "damage": 16, "style": "spin", "round": true, "lunge": 3.4},
	{"animation": &"Divinity_Execution", "source": &"2H_Melee_Attack_Chop", "label": "乾坤镇落", "duration": 0.70, "knots": [Vector2(0, 0), Vector2(0.70, 0.20), Vector2(0.90, 0.34)], "strikes": [0.27], "damage": 38, "style": "down", "round": false, "lunge": 6.2},
]

var progression: RunProgression
var feedback: Node3D
var arena_radius := 15.8
var enabled := false
var auto_attack := true
@onready var visual: Node3D = $Visual
@onready var animation: AnimationPlayer = $Visual/Model/AnimationPlayer
@onready var hitbox: Area3D = $Hitbox
@onready var skill_hitbox := get_node_or_null("SkillHitbox") as Area3D
var stats: BattleStats:
	get: return progression.stats
var opponent: Node3D
var health := 120.0
var attacking := false
var active := false
var did_hit := false
var dead := false
var recovering := false
var hurt_protection := 0.0
var _target_refresh := 0.0
var _heal_budget := 0.0
var combo_index := 0
var combo_left := 0.0
var current_move: Dictionary = NORMAL_COMBO[0]
var strike_index := -1
var combo_total: int:
	get: return NORMAL_COMBO.size()
var combo_label: String:
	get: return current_move.label
var strike_total: int:
	get: return current_move.strikes.size()
var move_duration: float:
	get: return current_move.duration
var attack_speed: float:
	get: return stats.attack_speed
var combo_finisher: bool:
	get: return combo_index == combo_total - 1
var _combo_next := 0
var _hit_ids: Array[int] = []
var fate_cooldown := 0.0
var reaction_count := 0
var freeze_left := 0.0
var attack_count := 0
var facing := Vector3.FORWARD
var attack_direction := Vector3.FORWARD
var sword: MeshInstance3D
var flash_material: ShaderMaterial
var sword_glow: ShaderMaterial
var meshes: Array[MeshInstance3D] = []
var step_distance := 0.0
var _last_position := Vector3.ZERO

func _ready() -> void:
	# Other fighters are not moving platforms.
	platform_floor_layers = 1
	_dress_player()
	add_to_group("player")
	flash_material = ShaderMaterial.new()
	flash_material.shader = preload("res://shaders/hit_flash.gdshader")
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		meshes.append(mesh)
		mesh.material_overlay = flash_material
		if "Shield" in mesh.name or mesh.name == "1H_Sword" or mesh.name == "1H_Sword_Offhand":
			mesh.hide()
		if mesh.name == "2H_Sword":
			sword = mesh
			mesh.show()
			# Keep the broader blade inside the existing melee reach and grounded at rest.
			mesh.scale *= 0.70
			sword_glow = flash_material.duplicate() as ShaderMaterial
			sword_glow.set_shader_parameter("tint", Color("62ddff"))
			mesh.material_overlay = sword_glow
	_setup_animations()
	_last_position = position
	reset_fighter()

func _dress_player() -> void:
	# One fixed outfit, not an equipment system. Both KayKit rigs share all 41 binds.
	# Reuse the authored garment meshes/skins; keep this knight's head and animations.
	var outfit := preload("res://assets/characters/Rogue.glb").instantiate()
	var skeleton := $Visual/Model/Rig/Skeleton3D
	var garment_skeleton := outfit.get_node("Rig/Skeleton3D")
	for part in ["Body", "ArmLeft", "ArmRight", "LegLeft", "LegRight"]:
		var current := skeleton.get_node("Knight_" + part) as MeshInstance3D
		var garment := garment_skeleton.get_node("Rogue_" + part) as MeshInstance3D
		current.mesh = garment.mesh
		current.skin = garment.skin
		current.transform = garment.transform
	var cape := skeleton.get_node("chest/Knight_Cape") as MeshInstance3D
	var garment_cape := garment_skeleton.get_node("chest/Rogue_Cape") as MeshInstance3D
	cape.mesh = garment_cape.mesh
	cape.transform = garment_cape.transform
	outfit.free()

func _setup_animations() -> void:
	var library := AnimationLibrary.new()
	for clip in ["Idle", "Running_A", "Walking_A", "Hit_A", "Hit_B", "Death_B"]:
		var source := animation.get_animation(clip).duplicate(true) as Animation
		source.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Running_A", "Walking_A"] else Animation.LOOP_NONE
		library.add_animation(clip, source)
	for move in NORMAL_COMBO + DIVINITY_COMBO:
		_add_move_animation(library, move)
	for key in animation.get_animation_library_list():
		animation.remove_animation_library(key)
	animation.add_animation_library("", library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animation.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	animation.animation_finished.connect(_on_animation_finished)
	animation.play("Idle")

func _add_move_animation(library: AnimationLibrary, move: Dictionary) -> void:
	var source := animation.get_animation(move.source).duplicate(true) as Animation
	var knots: Array = move.knots.duplicate()
	knots.append(Vector2(source.length, move.duration))
	for track in source.get_track_count():
		for key in source.track_get_key_count(track):
			var time := source.track_get_key_time(track, key)
			for i in range(1, knots.size()):
				var before: Vector2 = knots[i - 1]
				var after: Vector2 = knots[i]
				if time <= after.x + 0.0001:
					source.track_set_key_time(track, key, remap(time, before.x, after.x, before.y, after.y))
					break
	source.length = move.duration
	source.loop_mode = Animation.LOOP_NONE
	var events := source.add_track(Animation.TYPE_METHOD)
	source.track_set_path(events, NodePath("../.."))
	for i in move.strikes.size():
		var contact: float = move.strikes[i]
		source.track_insert_key(events, contact - 0.03, {"method": &"_start_swing", "args": [i]})
		source.track_insert_key(events, contact, {"method": &"_open_hit_window", "args": []})
		source.track_insert_key(events, contact + 0.07, {"method": &"_close_hit_window", "args": []})
	source.track_insert_key(events, move.duration * 0.77, {"method": &"_allow_movement", "args": []})
	library.add_animation(move.animation, source)

func reset_fighter() -> void:
	collision_layer = 2
	collision_mask = 1
	health = stats.max_health
	dead = false
	attacking = false
	active = false
	did_hit = false
	recovering = false
	combo_index = 0
	_combo_next = 0
	combo_left = 0.0
	current_move = NORMAL_COMBO[0]
	strike_index = -1
	_hit_ids.clear()
	fate_cooldown = 0.0
	reaction_count = 0
	hurt_protection = 0.0
	_heal_budget = 0.0
	opponent = null
	attack_count = 0
	freeze_left = 0.0
	velocity = Vector3.ZERO
	position = Vector3(0, 0.04, 0)
	facing = Vector3(1, 0, -0.56).normalized()
	visual.rotation = Vector3(0, atan2(facing.x, facing.z), 0)
	hitbox.rotation.y = visual.rotation.y
	animation.speed_scale = 1.0
	animation.play("Idle", 0.10)
	flash_material.set_shader_parameter("flash", 0.0)
	if is_instance_valid(sword_glow):
		sword_glow.set_shader_parameter("flash", 0.0)
	for mesh in meshes:
		mesh.transparency = 0.0
	_last_position = position
	reset_physics_interpolation()
	_refresh_range()

func get_attack_phase() -> String:
	if not attacking:
		return "就绪"
	var time := animation.current_animation_position
	var first: float = current_move.strikes[0] - 0.03
	var last: float = current_move.strikes.back() + 0.07
	return "蓄势" if time < first else ("挥斩" if time < last else "收势")

func _begin_attack() -> void:
	attacking = true
	if combo_left <= 0.0:
		_combo_next = 0
	combo_index = _combo_next
	current_move = NORMAL_COMBO[combo_index]
	_combo_next = (combo_index + 1) % combo_total
	recovering = false
	active = false
	did_hit = false
	strike_index = -1
	_hit_ids.clear()
	attack_count += 1
	_acquire_target()
	if is_instance_valid(opponent) and not opponent.dead and opponent.is_visible_in_tree():
		var to_target := opponent.global_position - global_position
		to_target.y = 0
		if to_target.length() < _attack_reach() + 0.5:
			facing = to_target.normalized()
	attack_direction = facing
	visual.rotation.y = atan2(facing.x, facing.z)
	hitbox.rotation.y = visual.rotation.y
	_refresh_range()
	animation.speed_scale = attack_speed
	animation.play(current_move.animation, 0.045, 1.0)
	swing_started.emit(false)

func _start_swing(strike := 0) -> void:
	if not attacking or dead:
		return
	strike_index = strike
	swing_active.emit(false)

func _open_hit_window() -> void:
	if not attacking:
		return
	active = true
	did_hit = false
	_hit_ids.clear()
	_try_hit()

func _close_hit_window() -> void:
	active = false

func _allow_movement() -> void:
	recovering = true

func _try_hit() -> void:
	if not active or dead:
		return
	var round_attack: bool = current_move.round
	var area := skill_hitbox if round_attack else hitbox
	for body in area.get_overlapping_bodies():
		if body.is_in_group("enemies") and not body.dead and body.get_instance_id() not in _hit_ids:
			var toward: Vector3 = body.global_position - global_position
			toward.y = 0
			if not round_attack and toward.normalized().dot(attack_direction) < 0.2:
				continue
			_hit_ids.append(body.get_instance_id())
			var first_contact := not did_hit
			did_hit = true
			var coefficient := float(current_move.damage) / 25.0
			var linking := strike_index < strike_total - 1
			var heavy_hit := combo_finisher
			# Basic contact remains neutral; character bonuses belong to artifacts.
			var result := deal_damage(body, DamageRules.Kind.PHYSICAL, coefficient, DamageRules.Element.NONE, heavy_hit, linking, "近战")
			# One short animation accent per window. Movement never freezes with it.
			if first_contact and result.get("actual", 0) > 0:
				freeze_left = 0.035 if heavy_hit else 0.018
				animation.speed_scale = 0.0

func deal_fabao_damage(target: Node3D, skill_id: String, coefficient: float = -1.0, heavy: bool = false, spectral: bool = false, hit_direction: Vector3 = Vector3.ZERO, apply_control: bool = true, secondary: bool = false) -> Dictionary:
	var definition := progression.skill(skill_id)
	if definition == null or progression.skill_level(skill_id) <= 0:
		return {"actual": 0.0, "lethal": false}
	var power := progression.coefficient(skill_id) if coefficient < 0.0 else coefficient
	return deal_damage(target, definition.kind, power, definition.element, heavy, spectral, definition.title.get_slice("·", 1), hit_direction, apply_control, {"skill_id": skill_id, "secondary": secondary})

func deal_damage(target: Node3D, kind: int, coefficient: float, element := DamageRules.Element.NONE, heavy := false, spectral := false, source := "", hit_direction := Vector3.ZERO, apply_control := true, context: Dictionary = {}) -> Dictionary:
	if dead or not enabled or not is_instance_valid(target) or target.dead:
		return {"actual": 0, "lethal": false}
	var periodic := bool(context.get("periodic", false))
	var result := DamageRules.calculate(stats, target.stats, kind, coefficient, element, 1.0 if periodic else -1.0, 1.0 if periodic else -1.0)
	result["skill_id"] = String(context.get("skill_id", ""))
	result["secondary"] = bool(context.get("secondary", false))
	var prior_states: Dictionary = {}
	if not bool(result.secondary) and progression.skill(String(result.skill_id)) != null:
		prior_states = {"shock": target.get_status("shock"), "freeze": target.get_status("freeze")}
	var direction: Vector3 = hit_direction if hit_direction.length_squared() > 0.0001 else target.global_position - global_position
	direction.y = 0.0
	direction = direction.normalized()
	result = target.receive_damage(result, direction, heavy, spectral, apply_control)
	var actual := float(result.get("actual", 0.0))
	if actual > 0:
		var healing := minf(actual * stats.life_steal, _heal_budget)
		health = minf(stats.max_health, health + healing)
		_heal_budget -= healing
		hit_confirmed.emit(target, target.global_position + Vector3.UP * 1.1, result, heavy, source)
		# Accepted HP loss is the only proc entry. Misses, immunity and
		# overkill cannot apply status or spawn artifacts.
		if enabled and not dead:
			if not bool(result.secondary):
				_resolve_direct_hit(target, result, prior_states)
	return result

func _resolve_direct_hit(target: Node3D, result: Dictionary, prior_states: Dictionary) -> void:
	var id := String(result.skill_id)
	var definition := progression.skill(id)
	if definition != null:
		# Read existing states before this hit applies its own. This makes
		# cross-artifact ordering explicit and prevents a self-trigger loop.
		# A lethal hit clears receiver-owned states. Retain the accepted
		# contact's snapshot so killing a marked target still conducts/shatters.
		var shocked: Dictionary = prior_states.get("shock", {})
		if not shocked.is_empty() and String(shocked.skill_id) != id and float(shocked.reaction_left) <= 0.0:
			var shock_owner := (shocked.source as WeakRef).get_ref() as DuelFighter
			if is_instance_valid(shock_owner) and shock_owner.enabled and not shock_owner.dead:
				if not target.dead and target.has_status("shock"):
					target.statuses.shock.charges = int(shocked.charges) - 1
					target.statuses.shock.reaction_left = 0.35
					if int(target.statuses.shock.charges) <= 0:
						target.remove_status("shock")
				for neighbor: Node3D in reaction_targets(target, 3.0, 3):
					var conducted := shock_owner.deal_damage(neighbor, DamageRules.Kind.MAGICAL, 0.30 * float(shocked.potency), DamageRules.Element.LIGHT, false, false, "感电传导", Vector3.ZERO, false, {"secondary": true, "skill_id": String(shocked.skill_id)})
					if float(conducted.get("actual", 0.0)) > 0.0 and is_instance_valid(feedback):
						feedback.shock_chain(target.global_position + Vector3.UP * 0.8, neighbor.global_position + Vector3.UP * 0.8)
				reaction_count += 1
		if not Dictionary(prior_states.get("freeze", {})).is_empty() and (int(result.element) == DamageRules.Element.FIRE or int(result.kind) in [DamageRules.Kind.PHYSICAL, DamageRules.Kind.FIXED]):
			target.remove_status("freeze")
			if is_instance_valid(feedback):
				feedback.ice_shatter(target.global_position, 3.0)
			var victims := reaction_targets(target, 3.0, 3)
			victims.push_front(target)
			for victim: Node3D in victims:
				var shattered := deal_damage(victim, DamageRules.Kind.MAGICAL, 0.35, DamageRules.Element.ICE, false, false, "破冰", Vector3.ZERO, false, {"secondary": true, "skill_id": id})
				if float(shattered.get("actual", 0.0)) > 0.0 and is_instance_valid(feedback):
					feedback.ice_contact(victim.global_position + Vector3.UP * 0.8)
			reaction_count += 1
		if enabled and not target.dead and not definition.status.is_empty():
			target.apply_status(definition.status, self, id, definition.status_duration)
	if enabled and not target.dead and bool(result.get("critical", false)) and id != "meteor" and fate_cooldown <= 0.0 and progression.has_fate("crit_seal") and progression.skill_level("meteor") > 0:
		fate_cooldown = 1.5
		fabao_requested.emit("meteor", target)

func reaction_targets(origin: Node3D, radius: float, limit: int) -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if not is_instance_valid(origin) or not is_inside_tree():
		return candidates
	for candidate: Node3D in get_tree().get_nodes_in_group("enemies"):
		if candidate == origin or candidate.dead or not candidate.is_inside_tree():
			continue
		var offset := candidate.global_position - origin.global_position
		offset.y = 0.0
		if offset.length_squared() <= radius * radius:
			candidates.append(candidate)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var distance_a := a.global_position.distance_squared_to(origin.global_position)
		var distance_b := b.global_position.distance_squared_to(origin.global_position)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(distance_a, distance_b) else distance_a < distance_b)
	if candidates.size() > limit:
		candidates.resize(maxi(0, limit))
	return candidates

func deal_status_damage(target: Node3D, status_id: String, status: Dictionary) -> Dictionary:
	var definition := progression.skill(String(status.skill_id))
	if definition == null or not ArenaEnemy.STATUS_RULES.has(status_id) or not ArenaEnemy.STATUS_RULES[status_id].has("coefficient"):
		return {"actual": 0.0, "lethal": false}
	var coefficient := float(ArenaEnemy.STATUS_RULES[status_id].coefficient) * float(status.potency)
	return deal_damage(target, definition.kind, coefficient, definition.element, false, false, String(ArenaEnemy.STATUS_RULES[status_id].title), Vector3.ZERO, false, {"secondary": true, "periodic": true, "skill_id": String(status.skill_id)})

func receive_damage(incoming: Dictionary, _direction: Vector3, _heavy := false, _spectral := false, _apply_control := true) -> Dictionary:
	var result := incoming.duplicate()
	result["actual"] = 0
	result["lethal"] = false
	if dead or not enabled or hurt_protection > 0.0:
		result["immune"] = true
		return result
	if result.get("dodged", false):
		hurt.emit(result)
		return result
	var actual := minf(health, float(result.get("damage", 0)))
	if actual <= 0:
		return result
	health -= actual
	result["actual"] = actual
	result["lethal"] = health <= 0
	hurt_protection = 0.65
	flash_material.set_shader_parameter("tint", Color("ff736d"))
	flash_material.set_shader_parameter("flash", 0.6)
	hurt.emit(result)
	if health <= 0:
		dead = true
		attacking = false
		active = false
		set_deferred("collision_layer", 0)
		animation.speed_scale = 1.0
		animation.play("Death_B", 0.06)
		defeated.emit()
	return result

func _physics_process(delta: float) -> void:
	if not enabled or dead:
		return
	fate_cooldown = maxf(0.0, fate_cooldown - delta)
	hurt_protection = maxf(0.0, hurt_protection - delta)
	_heal_budget = minf(stats.max_health * 0.12, _heal_budget + stats.max_health * 0.12 * delta)
	if freeze_left > 0.0:
		freeze_left = maxf(0.0, freeze_left - delta)
		if freeze_left == 0.0:
			animation.speed_scale = attack_speed if attacking else 1.0
	var flash: float = flash_material.get_shader_parameter("flash")
	flash_material.set_shader_parameter("flash", move_toward(flash, 0.0, delta * 12.0))
	if not attacking:
		combo_left = maxf(0.0, combo_left - delta)
	_target_refresh -= delta
	if _target_refresh <= 0.0:
		_target_refresh = 0.10
		_acquire_target()
	if not attacking and auto_attack and is_instance_valid(opponent) and not opponent.dead and global_position.distance_to(opponent.global_position) <= _attack_reach():
		_begin_attack()
	_player_motion(delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if active:
		_try_hit()
	# Physical ring colliders are the primary boundary. This catches reset/teleport edge cases.
	var flat := Vector2(position.x, position.z)
	if flat.length() > arena_radius - 0.5:
		flat = flat.normalized() * (arena_radius - 0.5)
		position.x = flat.x
		position.z = flat.y
	step_distance += (position - _last_position).length()
	if step_distance > 1.3:
		step_distance = 0.0
		stepped.emit(global_position)
	_last_position = position

func _player_motion(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x
	var forward := camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var direction := right * input.x + forward * input.y
	var speed := stats.move_speed
	velocity.x = move_toward(velocity.x, direction.x * speed, 32.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 32.0 * delta)
	if direction.length() > 0.1:
		facing = direction.normalized()
		if not attacking:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, 20.0 * delta))
	if not attacking:
		_play_locomotion(direction.length() > 0.1, "Running_A", 1.25)

func _attack_reach() -> float:
	return 2.25 * stats.range_multiplier

func _acquire_target() -> void:
	var reach := _attack_reach()
	if is_instance_valid(opponent) and not opponent.dead and global_position.distance_to(opponent.global_position) <= reach:
		return
	opponent = null
	var nearest := reach + 0.35
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate.dead:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < nearest:
			nearest = distance
			opponent = candidate

func _refresh_range() -> void:
	var reach := stats.range_multiplier
	hitbox.scale = Vector3(reach, 1, reach)
	skill_hitbox.scale = Vector3(reach, 1, reach)

func _play_locomotion(moving: bool, walk: String, speed: float) -> void:
	var clip := walk if moving else "Idle"
	if animation.current_animation != clip:
		animation.speed_scale = 1.0
		animation.play(clip, 0.14, speed if moving else 1.0)

func _on_animation_finished(clip: StringName) -> void:
	if attacking and clip == current_move.animation:
		attacking = false
		active = false
		recovering = false
		combo_left = COMBO_GRACE
		animation.speed_scale = 1.0
		animation.play("Idle", 0.1)
