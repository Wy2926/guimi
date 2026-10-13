class_name DuelFighter
extends CharacterBody3D
## Two fixed combo strings, using the original KayKit poses and native animation events.

signal swing_started(heavy: bool)
signal swing_active(heavy: bool)
signal skill_released
signal hit_confirmed(target: DuelFighter, point: Vector3, lethal: bool, damage: int, heavy: bool)
signal defeated
signal ghost_changed(enabled: bool)

const ATTACK := &"1H_Melee_Attack_Slice_Horizontal"
const SKILL := &"2H_Melee_Attack_Spin"
const DAMAGE := 25
const SKILL_DAMAGE := 55
const SKILL_COOLDOWN := 3.0
const SKILL_DURATION := 1.04
const SKILL_SWING := 0.34
const SKILL_RELEASE := 0.44
const SKILL_ACTIVE_END := 0.52
const MAX_HEALTH := 100
const MOVE_SPEED := 4.4
const BUFFER_TIME := 0.15
const ATTACK_DURATION := 0.60
const SWING_START := 0.17
const ACTIVE_START := 0.20
const ACTIVE_END := 0.27
const COMBO_GRACE := 0.65
const GHOST_DAMAGE := 1.5
const GHOST_SPEED := 1.25

# Only this fighter's authored moves, not a general skill/animation framework.
# Knots align the original artist's anticipation and swing with the hit events.
const NORMAL_COMBO := [
	{"animation": ATTACK, "source": ATTACK, "label": "横扫", "duration": 0.60, "knots": [Vector2(0, 0), Vector2(0.2, 0.17), Vector2(0.333333, 0.27)], "strikes": [0.20], "damage": 25, "style": "horizontal", "round": false, "lunge": 3.8},
	{"animation": &"Combo_Rising", "source": &"1H_Melee_Attack_Slice_Diagonal", "label": "逆袈裟", "duration": 0.62, "knots": [Vector2(0, 0), Vector2(0.30, 0.17), Vector2(0.46, 0.29)], "strikes": [0.22], "damage": 28, "style": "rise", "round": false, "lunge": 4.6},
	{"animation": &"Combo_Cleave", "source": &"2H_Melee_Attack_Chop", "label": "坠刃", "duration": 0.76, "knots": [Vector2(0, 0), Vector2(0.70, 0.23), Vector2(0.90, 0.38)], "strikes": [0.30], "damage": 38, "style": "down", "round": false, "lunge": 5.4},
]
const GHOST_COMBO := [
	{"animation": &"Ghost_Reaping", "source": &"2H_Melee_Attack_Spinning", "label": "鬼旋双斩", "duration": 0.62, "knots": [Vector2(0, 0), Vector2(0.10, 0.10), Vector2(0.50, 0.40)], "strikes": [0.14, 0.33], "damage": 20, "style": "spin", "round": true, "lunge": 4.2},
	{"animation": &"Ghost_Rending", "source": &"2H_Melee_Attack_Slice", "label": "血月横断", "duration": 0.56, "knots": [Vector2(0, 0), Vector2(0.30, 0.13), Vector2(0.45, 0.24)], "strikes": [0.18], "damage": 28, "style": "reverse", "round": false, "lunge": 5.8},
	{"animation": &"Ghost_Piercing", "source": &"2H_Melee_Attack_Stab", "label": "穿魂突刺", "duration": 0.58, "knots": [Vector2(0, 0), Vector2(0.30, 0.13), Vector2(0.46, 0.25)], "strikes": [0.18], "damage": 26, "style": "thrust", "round": false, "lunge": 7.0},
	{"animation": &"Ghost_Whirlwind", "source": SKILL, "label": "狱轮三裂", "duration": 0.82, "knots": [Vector2(0, 0), Vector2(0.80, 0.16), Vector2(1.60, 0.59)], "strikes": [0.22, 0.37, 0.52], "damage": 16, "style": "spin", "round": true, "lunge": 3.4},
	{"animation": &"Ghost_Execution", "source": &"2H_Melee_Attack_Chop", "label": "厉鬼断狱", "duration": 0.70, "knots": [Vector2(0, 0), Vector2(0.70, 0.20), Vector2(0.90, 0.34)], "strikes": [0.27], "damage": 38, "style": "down", "round": false, "lunge": 6.2},
]

@export var player_controlled := false
@export var home_position := Vector3(1.15, 0.04, -0.6)
@onready var visual: Node3D = $Visual
@onready var animation: AnimationPlayer = $Visual/Model/AnimationPlayer
@onready var hitbox: Area3D = $Hitbox
@onready var skill_hitbox := get_node_or_null("SkillHitbox") as Area3D
@onready var arena: Node3D = get_parent()

var opponent: DuelFighter
var health := MAX_HEALTH
var attacking := false
var active := false
var did_hit := false
var dead := false
var recovering := false
var using_skill := false
var ghost_active := false
var ghost_requested := false
var ghost_aura: Node3D
var combo_index := 0
var combo_left := 0.0
var current_move: Dictionary = NORMAL_COMBO[0]
var strike_index := -1
var combo_total: int:
	get: return GHOST_COMBO.size() if ghost_active else NORMAL_COMBO.size()
var combo_label: String:
	get: return "裂环斩" if using_skill else current_move.label
var strike_total: int:
	get: return 1 if using_skill else current_move.strikes.size()
var move_duration: float:
	get: return SKILL_DURATION if using_skill else current_move.duration
var attack_speed: float:
	get: return GHOST_SPEED if ghost_active else 1.0
var damage_multiplier: float:
	get: return GHOST_DAMAGE if ghost_active else 1.0
var combo_finisher: bool:
	get: return not using_skill and combo_index == combo_total - 1
var _combo_next := 0
var _hit_ids: Array[int] = []
var skill_cooldown := 0.0
var buffered := 0.0
var buffered_skill := false
var stagger := 0.0
var freeze_left := 0.0
var respawn_left := 0.0
var return_delay := 0.0
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
	# Other fighters are not moving platforms, including immediately after respawn.
	platform_floor_layers = 1
	if player_controlled:
		_dress_player()
	else:
		add_to_group("enemies")
	flash_material = ShaderMaterial.new()
	flash_material.shader = preload("res://shaders/hit_flash.gdshader")
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		meshes.append(mesh)
		mesh.material_overlay = flash_material
		if player_controlled and ("Shield" in mesh.name or mesh.name == "1H_Sword" or mesh.name == "1H_Sword_Offhand"):
			mesh.hide()
		if player_controlled and mesh.name == "2H_Sword":
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
	if player_controlled:
		for move in NORMAL_COMBO + GHOST_COMBO:
			_add_move_animation(library, move)
		_add_move_animation(library, {"animation": SKILL, "source": SKILL, "duration": SKILL_DURATION, "knots": [Vector2(0, 0), Vector2(0.8, SKILL_SWING), Vector2(1.6, 0.66)], "strikes": [SKILL_RELEASE]}, true)
	for key in animation.get_animation_library_list():
		animation.remove_animation_library(key)
	animation.add_animation_library("", library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animation.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	animation.animation_finished.connect(_on_animation_finished)
	animation.play("Idle")

func _add_move_animation(library: AnimationLibrary, move: Dictionary, heavy := false) -> void:
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
		source.track_insert_key(events, SKILL_SWING if heavy else contact - 0.03, {"method": &"_start_swing", "args": [i]})
		source.track_insert_key(events, contact, {"method": &"_open_hit_window", "args": []})
		source.track_insert_key(events, contact + (0.08 if heavy else 0.07), {"method": &"_close_hit_window", "args": []})
	source.track_insert_key(events, 0.78 if heavy else move.duration * 0.77, {"method": &"_allow_movement", "args": []})
	library.add_animation(move.animation, source)

func reset_fighter() -> void:
	_clear_ghost()
	collision_layer = 2 if player_controlled else 4
	collision_mask = 5 if player_controlled else 7
	health = MAX_HEALTH
	dead = false
	attacking = false
	active = false
	did_hit = false
	recovering = false
	using_skill = false
	combo_index = 0
	_combo_next = 0
	combo_left = 0.0
	current_move = NORMAL_COMBO[0]
	strike_index = -1
	_hit_ids.clear()
	skill_cooldown = 0.0
	buffered = 0.0
	buffered_skill = false
	attack_count = 0
	stagger = 0.0
	freeze_left = 0.0
	respawn_left = 0.0
	return_delay = 0.6
	velocity = Vector3.ZERO
	position = Vector3(-1.35, 0.04, 0.8) if player_controlled else home_position
	facing = Vector3(1, 0, -0.56).normalized() if player_controlled else Vector3(-1, 0, 0.56).normalized()
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
	if player_controlled:
		hitbox.scale = Vector3.ONE
		skill_hitbox.scale = Vector3.ONE

func request_ghost() -> void:
	if not player_controlled or dead or not arena.ready_to_play:
		return
	ghost_requested = not ghost_requested
	if not attacking and stagger <= 0.0:
		_apply_ghost()

func _apply_ghost() -> void:
	if ghost_active == ghost_requested:
		return
	ghost_active = ghost_requested
	_combo_next = 0
	combo_index = 0
	combo_left = 0.0
	strike_index = -1
	current_move = GHOST_COMBO[0] if ghost_active else NORMAL_COMBO[0]
	if is_instance_valid(ghost_aura):
		ghost_aura.queue_free()
	ghost_aura = null
	if ghost_active:
		ghost_aura = arena.feedback.create_ghost_aura(self)
	flash_material.set_shader_parameter("ghost_strength", 0.6 if ghost_active else 0.0)
	sword_glow.set_shader_parameter("ghost_strength", 0.8 if ghost_active else 0.0)
	hitbox.scale = Vector3(1.3, 1.0, 1.3) if ghost_active else Vector3.ONE
	skill_hitbox.scale = Vector3(1.3, 1.0, 1.3) if ghost_active else Vector3.ONE
	ghost_changed.emit(ghost_active)

func _clear_ghost() -> void:
	ghost_active = false
	ghost_requested = false
	if is_instance_valid(ghost_aura):
		ghost_aura.queue_free()
	ghost_aura = null
	if is_instance_valid(flash_material):
		flash_material.set_shader_parameter("ghost_strength", 0.0)
	if is_instance_valid(sword_glow):
		sword_glow.set_shader_parameter("ghost_strength", 0.0)

func get_attack_phase() -> String:
	if not attacking:
		return "就绪"
	var time := animation.current_animation_position
	var first: float = SKILL_SWING if using_skill else current_move.strikes[0] - 0.03
	var last: float = SKILL_ACTIVE_END if using_skill else current_move.strikes.back() + 0.07
	return "蓄势" if time < first else ("挥斩" if time < last else "收势")

func request_attack() -> void:
	_request_move(false)

func request_skill() -> void:
	_request_move(true)

func _request_move(heavy: bool) -> void:
	if not player_controlled or dead or stagger > 0.0 or not arena.ready_to_play:
		return
	if heavy and skill_cooldown > 0.0:
		return
	if attacking:
		# One-slot late buffer. Early spam is discarded, never an unbounded combo queue.
		if animation.current_animation_position >= move_duration - BUFFER_TIME * attack_speed:
			buffered = BUFFER_TIME + 0.04
			buffered_skill = heavy
		return
	_begin_attack(heavy)

func _begin_attack(heavy := false) -> void:
	attacking = true
	using_skill = heavy
	if heavy:
		skill_cooldown = SKILL_COOLDOWN
		_combo_next = 0
		combo_left = 0.0
	else:
		if combo_left <= 0.0:
			_combo_next = 0
		combo_index = _combo_next
		current_move = (GHOST_COMBO if ghost_active else NORMAL_COMBO)[combo_index]
		_combo_next = (combo_index + 1) % combo_total
	recovering = false
	active = false
	did_hit = false
	strike_index = -1
	_hit_ids.clear()
	buffered = 0.0
	attack_count += 1
	# Generous but local facing assist. No long-distance magnet or teleport.
	var nearest := 3.3
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate.dead or not candidate.is_visible_in_tree():
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < nearest:
			nearest = distance
			opponent = candidate
	if is_instance_valid(opponent) and not opponent.dead and opponent.is_visible_in_tree():
		var to_target := opponent.global_position - global_position
		to_target.y = 0
		if to_target.length() < 3.3:
			facing = to_target.normalized()
	attack_direction = facing
	visual.rotation.y = atan2(facing.x, facing.z)
	hitbox.rotation.y = visual.rotation.y
	animation.speed_scale = attack_speed
	animation.play(SKILL if heavy else current_move.animation, 0.045, 1.0)
	swing_started.emit(heavy)

func _start_swing(strike := 0) -> void:
	if not attacking or dead:
		return
	strike_index = strike
	swing_active.emit(using_skill)

func _open_hit_window() -> void:
	if not attacking:
		return
	active = true
	did_hit = false
	_hit_ids.clear()
	if using_skill:
		skill_released.emit()
	_try_hit()

func _close_hit_window() -> void:
	active = false

func _allow_movement() -> void:
	recovering = true

func _try_hit() -> void:
	if not active or dead:
		return
	var round_attack: bool = using_skill or current_move.round
	var area := skill_hitbox if round_attack else hitbox
	for body in area.get_overlapping_bodies():
		if body is DuelFighter and body != self and not body.dead and body.is_visible_in_tree() and body.get_instance_id() not in _hit_ids:
			var toward: Vector3 = body.global_position - global_position
			toward.y = 0
			if not round_attack and toward.normalized().dot(attack_direction) < 0.2:
				continue
			_hit_ids.append(body.get_instance_id())
			did_hit = true
			var direction := toward.normalized() if round_attack else attack_direction
			var damage := roundi((SKILL_DAMAGE if using_skill else int(current_move.damage)) * damage_multiplier)
			var linking := not using_skill and strike_index < strike_total - 1
			var heavy_hit := using_skill or combo_finisher
			var lethal: bool = body.receive_hit(damage, direction, heavy_hit, linking)
			if ghost_active:
				body.flash_material.set_shader_parameter("tint", Color("ff608f"))
				body.flash_material.set_shader_parameter("flash", 0.36 if lethal else 0.28)
			elif combo_finisher:
				body.flash_material.set_shader_parameter("tint", Color("ffc05c"))
			var stop := (0.105 if lethal else 0.085) if heavy_hit else (0.080 if lethal else 0.058)
			if ghost_active and not heavy_hit:
				stop = 0.035 if lethal else 0.024
			freeze_left = maxf(freeze_left, stop)
			animation.speed_scale = 0.0
			var point: Vector3 = body.global_position - direction * 0.48 + Vector3.UP * 1.13
			hit_confirmed.emit(body, point, lethal, damage, using_skill)

func receive_hit(damage: int, direction: Vector3, heavy := false, spectral := false) -> bool:
	if dead:
		return false
	health = maxi(health - damage, 0)
	dead = health == 0
	if player_controlled:
		attacking = false
		active = false
		using_skill = false
		buffered = 0.0
		combo_left = 0.0
		_combo_next = 0
	var hit_freeze := (0.105 if dead else 0.085) if heavy else (0.080 if dead else 0.058)
	freeze_left = maxf(freeze_left, 0.016 if spectral and not dead else hit_freeze)
	stagger = maxf(stagger, 0.10 if spectral else (0.60 if heavy else 0.36))
	return_delay = 1.0 if heavy else 0.75
	velocity = direction * (1.2 if spectral and not dead else ((8.5 if dead else 7.2) if heavy else (6.3 if dead else 4.0)))
	animation.play("Death_B" if dead else ("Hit_A" if health % 50 == 0 else "Hit_B"), 0.035)
	animation.advance(0.035)
	animation.speed_scale = 0.0
	flash_material.set_shader_parameter("tint", Color("8bebff") if heavy or spectral else Color("ffc05c"))
	flash_material.set_shader_parameter("flash", 0.32 if spectral and not dead else 0.62)
	if dead:
		_clear_ghost()
		collision_layer = 0
		collision_mask = 1
		respawn_left = 3.1
		defeated.emit()
	return dead

func _physics_process(delta: float) -> void:
	skill_cooldown = maxf(0.0, skill_cooldown - delta)
	if player_controlled:
		var time := animation.current_animation_position
		var glow := clampf(time / SKILL_SWING, 0.0, 1.0) * (1.0 - smoothstep(0.66, 0.86, time)) if using_skill else 0.0
		sword_glow.set_shader_parameter("tint", Color("ff426f") if ghost_active else Color("62ddff"))
		sword_glow.set_shader_parameter("flash", glow * 0.78)
	if freeze_left > 0.0:
		freeze_left = maxf(0.0, freeze_left - delta)
		if freeze_left == 0.0:
			animation.speed_scale = attack_speed if attacking else 1.0
		return
	var flash: float = flash_material.get_shader_parameter("flash")
	flash_material.set_shader_parameter("flash", move_toward(flash, 0.0, delta * 12.0))
	buffered = maxf(0.0, buffered - delta)
	stagger = maxf(0.0, stagger - delta)
	return_delay = maxf(0.0, return_delay - delta)
	if not attacking:
		combo_left = maxf(0.0, combo_left - delta)
	if dead:
		respawn_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, delta * 13.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 13.0)
		if respawn_left < 0.7:
			for mesh in meshes:
				mesh.transparency = 1.0 - clampf(respawn_left / 0.7, 0.0, 1.0)
		if respawn_left <= 0:
			reset_fighter()
			arena.target_respawned(self)
	elif stagger > 0:
		velocity.x = move_toward(velocity.x, 0.0, delta * 9.5)
		velocity.z = move_toward(velocity.z, 0.0, delta * 9.5)
	elif player_controlled:
		if not attacking and ghost_requested != ghost_active:
			_apply_ghost()
		if not attacking and Input.is_action_pressed("attack") and arena.ready_to_play:
			request_attack()
		_player_motion(delta)
	else:
		_target_motion(delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if active:
		_try_hit()
	# Physical ring colliders are the primary boundary. This catches reset/teleport edge cases.
	var flat := Vector2(position.x, position.z)
	if flat.length() > 5.65:
		flat = flat.normalized() * 5.65
		position.x = flat.x
		position.z = flat.y
	if player_controlled:
		step_distance += (position - _last_position).length()
		if step_distance > 1.0 and not attacking:
			step_distance = 0.0
			arena.footstep(global_position)
	_last_position = position

func _player_motion(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x
	var forward := camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var direction := right * input.x + forward * input.y
	if attacking and not recovering:
		var time := animation.current_animation_position
		var window := false
		for contact in ([SKILL_RELEASE] if using_skill else current_move.strikes):
			window = window or (time >= float(contact) - 0.08 and time < float(contact) + 0.07)
		var impulse: float = (1.6 if using_skill else float(current_move.lunge)) * (1.15 if ghost_active else 1.0) if window and not did_hit else 0.0
		velocity.x = attack_direction.x * impulse
		velocity.z = attack_direction.z * impulse
		return
	var speed := MOVE_SPEED * (0.45 if attacking else 1.0)
	velocity.x = move_toward(velocity.x, direction.x * speed, 32.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 32.0 * delta)
	if direction.length() > 0.1:
		facing = direction.normalized()
		if not attacking:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, 20.0 * delta))
	if not attacking:
		_play_locomotion(direction.length() > 0.1, "Running_A", 1.25)

func _target_motion(delta: float) -> void:
	var toward := opponent.position - position
	toward.y = 0
	var direction := toward.normalized()
	var approach := toward.length() > 2.05 and return_delay <= 0.0
	var desired := direction * 1.4 if approach else Vector3.ZERO
	velocity.x = move_toward(velocity.x, desired.x, 6.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 6.0 * delta)
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 6.0))
	_play_locomotion(approach, "Walking_A", 1.0)

func _play_locomotion(moving: bool, walk: String, speed: float) -> void:
	var clip := walk if moving else "Idle"
	if animation.current_animation != clip:
		animation.speed_scale = 1.0
		animation.play(clip, 0.14, speed if moving else 1.0)

func _on_animation_finished(clip: StringName) -> void:
	if attacking and (clip == SKILL or clip == current_move.animation):
		attacking = false
		active = false
		recovering = false
		combo_left = 0.0 if using_skill else COMBO_GRACE
		using_skill = false
		animation.speed_scale = 1.0
		_apply_ghost()
		if buffered > 0:
			_begin_attack(buffered_skill)
		elif Input.is_action_pressed("attack") and arena.ready_to_play:
			_begin_attack(false)
		else:
			animation.play("Idle", 0.1)
