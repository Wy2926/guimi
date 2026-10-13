class_name DuelFighter
extends CharacterBody3D
## Two authored moves in one scene; AnimationPlayer owns their poses and events.

signal swing_started(heavy: bool)
signal swing_active(heavy: bool)
signal skill_released
signal hit_confirmed(target: DuelFighter, point: Vector3, lethal: bool, damage: int, heavy: bool)
signal defeated

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

@export var player_controlled := false
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
	flash_material = ShaderMaterial.new()
	flash_material.shader = preload("res://shaders/hit_flash.gdshader")
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		meshes.append(mesh)
		mesh.material_overlay = flash_material
		if player_controlled and ("Shield" in mesh.name or mesh.name == "2H_Sword" or mesh.name == "1H_Sword_Offhand"):
			mesh.hide()
		if mesh.name == "1H_Sword":
			sword = mesh
			mesh.scale *= 0.83
			if player_controlled:
				sword_glow = flash_material.duplicate() as ShaderMaterial
				sword_glow.set_shader_parameter("tint", Color("62ddff"))
				mesh.material_overlay = sword_glow
	_setup_animations()
	_last_position = position
	reset_fighter()

func _setup_animations() -> void:
	var library := AnimationLibrary.new()
	var used := ["Idle", "Running_A", "Walking_A", "Hit_A", "Hit_B", "Death_B", ATTACK]
	if player_controlled:
		used.append(SKILL)
	for clip in used:
		var source := animation.get_animation(clip).duplicate(true) as Animation
		source.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Running_A", "Walking_A"] else Animation.LOOP_NONE
		if clip == ATTACK or clip == SKILL:
			# Retime an existing authored clip. No custom skeletal animation system.
			for track in source.get_track_count():
				for key in source.track_get_key_count(track):
					var time := source.track_get_key_time(track, key)
					var mapped: float
					if clip == SKILL:
						# Original clip: 0–0.8 anticipation, 0.8–1.6 turn, then settle.
						if time <= 0.8:
							mapped = remap(time, 0, 0.8, 0, SKILL_SWING)
						elif time <= 1.6:
							mapped = remap(time, 0.8, 1.6, SKILL_SWING, 0.66)
						else:
							mapped = remap(time, 1.6, source.length, 0.66, SKILL_DURATION)
					elif time <= 0.2:
						mapped = remap(time, 0, 0.2, 0, SWING_START)
					elif time <= 1.0 / 3.0:
						mapped = remap(time, 0.2, 1.0 / 3.0, SWING_START, ACTIVE_END)
					else:
						mapped = remap(time, 1.0 / 3.0, source.length, ACTIVE_END, ATTACK_DURATION)
					source.track_set_key_time(track, key, mapped)
			var heavy: bool = clip == SKILL
			source.length = SKILL_DURATION if heavy else ATTACK_DURATION
			var event_track := source.add_track(Animation.TYPE_METHOD)
			source.track_set_path(event_track, NodePath("../.."))
			source.track_insert_key(event_track, SKILL_SWING if heavy else SWING_START, {"method": &"_start_swing", "args": []})
			source.track_insert_key(event_track, SKILL_RELEASE if heavy else ACTIVE_START, {"method": &"_open_hit_window", "args": []})
			source.track_insert_key(event_track, SKILL_ACTIVE_END if heavy else ACTIVE_END, {"method": &"_close_hit_window", "args": []})
			source.track_insert_key(event_track, 0.78 if heavy else 0.46, {"method": &"_allow_movement", "args": []})
		library.add_animation(clip, source)
	for key in animation.get_animation_library_list():
		animation.remove_animation_library(key)
	animation.add_animation_library("", library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animation.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	animation.animation_finished.connect(_on_animation_finished)
	animation.play("Idle")

func reset_fighter() -> void:
	collision_layer = 2 if player_controlled else 4
	collision_mask = 5 if player_controlled else 3
	health = MAX_HEALTH
	dead = false
	attacking = false
	active = false
	did_hit = false
	recovering = false
	using_skill = false
	skill_cooldown = 0.0
	buffered = 0.0
	buffered_skill = false
	attack_count = 0
	stagger = 0.0
	freeze_left = 0.0
	respawn_left = 0.0
	return_delay = 0.6
	velocity = Vector3.ZERO
	position = Vector3(-1.35, 0.04, 0.8) if player_controlled else Vector3(1.15, 0.04, -0.6)
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

func request_attack() -> void:
	_request_move(false)

func request_skill() -> void:
	_request_move(true)

func _request_move(heavy: bool) -> void:
	if not player_controlled or dead:
		return
	if heavy and skill_cooldown > 0.0:
		return
	if attacking:
		# One-slot late buffer. Early spam is discarded, never an unbounded combo queue.
		var duration := SKILL_DURATION if using_skill else ATTACK_DURATION
		if animation.current_animation_position >= duration - BUFFER_TIME:
			buffered = BUFFER_TIME
			buffered_skill = heavy
		return
	_begin_attack(heavy)

func _begin_attack(heavy := false) -> void:
	attacking = true
	using_skill = heavy
	if heavy:
		skill_cooldown = SKILL_COOLDOWN
	recovering = false
	active = false
	did_hit = false
	buffered = 0.0
	attack_count += 1
	# Generous but local facing assist. No long-distance magnet or teleport.
	if is_instance_valid(opponent) and not opponent.dead:
		var to_target := opponent.global_position - global_position
		to_target.y = 0
		if to_target.length() < 3.3:
			facing = to_target.normalized()
	attack_direction = facing
	visual.rotation.y = atan2(facing.x, facing.z)
	hitbox.rotation.y = visual.rotation.y
	animation.play(SKILL if heavy else ATTACK, 0.045, 1.0)
	swing_started.emit(heavy)

func _start_swing() -> void:
	swing_active.emit(using_skill)

func _open_hit_window() -> void:
	if not attacking:
		return
	active = true
	if using_skill:
		skill_released.emit()
	_try_hit()

func _close_hit_window() -> void:
	active = false

func _allow_movement() -> void:
	recovering = true

func _try_hit() -> void:
	if did_hit or not active:
		return
	var area := skill_hitbox if using_skill else hitbox
	for body in area.get_overlapping_bodies():
		if body is DuelFighter and body != self and not body.dead:
			var toward: Vector3 = body.global_position - global_position
			toward.y = 0
			if not using_skill and toward.normalized().dot(attack_direction) < 0.2:
				continue
			did_hit = true
			var direction := toward.normalized() if using_skill else attack_direction
			var damage := SKILL_DAMAGE if using_skill else DAMAGE
			var lethal: bool = body.receive_hit(damage, direction, using_skill)
			freeze_left = (0.105 if lethal else 0.085) if using_skill else (0.080 if lethal else 0.058)
			animation.speed_scale = 0.0
			var point: Vector3 = body.global_position - direction * 0.48 + Vector3.UP * 1.13
			hit_confirmed.emit(body, point, lethal, damage, using_skill)
			break

func receive_hit(damage: int, direction: Vector3, heavy := false) -> bool:
	if dead:
		return false
	health = maxi(health - damage, 0)
	dead = health == 0
	freeze_left = (0.105 if dead else 0.085) if heavy else (0.080 if dead else 0.058)
	stagger = 0.60 if heavy else 0.36
	return_delay = 1.0 if heavy else 0.75
	velocity = direction * ((8.5 if dead else 7.2) if heavy else (6.3 if dead else 4.0))
	animation.play("Death_B" if dead else ("Hit_A" if health % 50 == 0 else "Hit_B"), 0.035)
	animation.advance(0.035)
	animation.speed_scale = 0.0
	flash_material.set_shader_parameter("tint", Color("8bebff") if heavy else Color("ffc05c"))
	flash_material.set_shader_parameter("flash", 0.62)
	if dead:
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
		sword_glow.set_shader_parameter("flash", glow * 0.78)
	if freeze_left > 0.0:
		freeze_left = maxf(0.0, freeze_left - delta)
		if freeze_left == 0.0:
			animation.speed_scale = 1.0
		return
	var flash: float = flash_material.get_shader_parameter("flash")
	flash_material.set_shader_parameter("flash", move_toward(flash, 0.0, delta * 12.0))
	buffered = maxf(0.0, buffered - delta)
	stagger = maxf(0.0, stagger - delta)
	return_delay = maxf(0.0, return_delay - delta)
	if dead:
		respawn_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, delta * 13.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 13.0)
		if respawn_left < 0.7:
			for mesh in meshes:
				mesh.transparency = 1.0 - clampf(respawn_left / 0.7, 0.0, 1.0)
		if respawn_left <= 0:
			reset_fighter()
			arena.target_respawned()
	elif stagger > 0:
		velocity.x = move_toward(velocity.x, 0.0, delta * 9.5)
		velocity.z = move_toward(velocity.z, 0.0, delta * 9.5)
	elif player_controlled:
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
		var start := SKILL_SWING if using_skill else SWING_START
		var end := SKILL_ACTIVE_END if using_skill else ACTIVE_END
		var impulse := (1.6 if using_skill else 3.8) if time >= start and time < end and not did_hit else 0.0
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
		animation.play(clip, 0.14, speed if moving else 1.0)

func _on_animation_finished(clip: StringName) -> void:
	if clip == ATTACK or clip == SKILL:
		attacking = false
		active = false
		recovering = false
		using_skill = false
		if buffered > 0:
			_begin_attack(buffered_skill)
		else:
			animation.play("Idle", 0.1)
