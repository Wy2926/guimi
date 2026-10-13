extends Node3D
## Scene composition and one run's lifetime. Combat and UI do not reach back here.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const STORM_SCRIPT = preload("res://scripts/sword_storm.gd")
const FEEDBACK_SCRIPT = preload("res://scripts/feedback.gd")
const ARENA_RADIUS := 15.8
const CAMERA_OFFSET := Vector3(10, 24, 10)

@onready var feedback: Node3D = $Feedback
@onready var camera: Camera3D = $Camera3D
@onready var hud: Control = $HUD/Interface
@onready var enemies: Node3D = $Enemies
@onready var drops: Node3D = $Drops

var player: DuelFighter
var progression: RunProgression
var director: WaveDirector
var storm: Node3D
var boss: Node3D
var state := "loading"
var ready_to_play := false
var frame_limit := 120
var shake_enabled := true
var hit_count := 0
var defeat_count := 0
var shake_time := 0.0
var shake_power := 0.0
var focus := Vector3.ZERO
var clock := 0.0
var _impact_left := 0.0

func _ready() -> void:
	Input.use_accumulated_input = false
	progression = RunProgression.new()
	progression.name = "Progression"
	add_child(progression)
	player = PLAYER_SCENE.instantiate() as DuelFighter
	player.progression = progression
	player.feedback = feedback
	player.arena_radius = ARENA_RADIUS
	add_child(player)
	storm = STORM_SCRIPT.new()
	storm.name = "SwordStorm"
	storm.player = player
	storm.progression = progression
	storm.feedback = feedback
	storm.camera = camera
	add_child(storm)
	director = WaveDirector.new()
	director.name = "Waves"
	director.player = player
	director.enemy_container = enemies
	director.camera = camera
	director.arena_radius = ARENA_RADIUS
	add_child(director)
	director.enemy_spawned.connect(_on_enemy_spawned)
	director.boss_spawned.connect(func(enemy: Node3D) -> void: boss = enemy)
	progression.choice_requested.connect(_on_choices)
	player.swing_started.connect(_on_windup)
	player.swing_active.connect(_on_swing)
	player.skill_released.connect(func() -> void: feedback.skill_release(player))
	player.hit_confirmed.connect(_on_hit)
	player.ghost_changed.connect(_on_ghost_changed)
	player.defeated.connect(func() -> void: _finish(false))
	player.hurt.connect(_on_hurt)
	player.stepped.connect(func(point: Vector3) -> void: feedback.sound("step%d" % (randi() % 3), point, -19, 1.1))
	hud.setup(self)
	hud.pause_requested.connect(toggle_pause)
	hud.restart_requested.connect(restart)
	hud.upgrade_selected.connect(choose_upgrade)
	hud.frame_limit_requested.connect(func(fps: int) -> void: set_frame_limit(fps, true))
	hud.shake_changed.connect(func(value: bool) -> void: shake_enabled = value)
	var settings := ConfigFile.new()
	settings.load("user://settings.cfg")
	set_frame_limit(int(settings.get_value("display", "frame_limit", 120)))
	camera.position = CAMERA_OFFSET
	camera.look_at(focus)
	_warm_start()
	if "--verify" in OS.get_cmdline_user_args():
		var driver := load("res://tools/verify.gd").new() as Node
		add_child(driver)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
	if state != "playing" or event.is_echo():
		return
	if event.is_action_pressed("skill"):
		player.request_skill()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ghost_state"):
		player.request_ghost()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	clock += delta
	_impact_left = maxf(0.0, _impact_left - delta)
	shake_time = maxf(0.0, shake_time - delta)
	# Keep the player above the bottom skill strip even at the near arena edge.
	var follow := Vector2(player.position.x, player.position.z).limit_length(10.5)
	var target := Vector3(follow.x, 0, follow.y)
	focus = focus.lerp(target, 1.0 - exp(-delta * 6.0))
	var offset := Vector3.ZERO
	if shake_enabled and shake_time > 0:
		offset = Vector3(sin(clock * 173), cos(clock * 137), 0) * shake_power * pow(shake_time / 0.16, 2.0)
	camera.position = CAMERA_OFFSET + focus + offset
	camera.look_at(focus)

func set_frame_limit(fps: int, save := false) -> void:
	frame_limit = 60 if fps == 60 else 120
	Engine.max_fps = frame_limit
	if is_instance_valid(hud):
		hud.sync_frame_limit(frame_limit)
	if save:
		var settings := ConfigFile.new()
		settings.load("user://settings.cfg")
		settings.set_value("display", "frame_limit", frame_limit)
		settings.save("user://settings.cfg")

func toggle_pause() -> void:
	if state not in ["playing", "paused"]:
		return
	state = "playing" if state == "paused" else "paused"
	get_tree().paused = state == "paused"
	hud.show_pause(state == "paused")

func _on_choices(options: Array[Dictionary]) -> void:
	if state not in ["playing", "choosing"]:
		return
	state = "choosing"
	get_tree().paused = true
	hud.show_choices(options)

func choose_upgrade(index: int) -> void:
	if state != "choosing":
		return
	var previous_health := player.stats.max_health
	if not progression.choose(index):
		return
	# Extra maximum life also grants that much current life; no full heal on level-up.
	player.health = minf(player.stats.max_health, player.health + maxf(0.0, player.stats.max_health - previous_health))
	player._refresh_range()
	storm.refresh_skills()
	if progression.pending_levels == 0:
		hud.choice_panel.hide()
		state = "playing"
		get_tree().paused = false

func _on_enemy_spawned(enemy: Node3D) -> void:
	enemy.defeated.connect(_on_enemy_defeated)

func _on_enemy_defeated(enemy: Node3D) -> void:
	if state not in ["playing", "choosing"]:
		return
	defeat_count += 1
	if enemy.boss:
		_finish(true)
		return
	var gem := ExperienceGem.new()
	gem.configure(enemy.experience_value, player)
	gem.position = enemy.global_position + Vector3.UP * 0.2
	gem.collected.connect(_collect_experience)
	# Death can occur in an Area3D callback during physics query flushing.
	drops.add_child.call_deferred(gem)

func _collect_experience(amount: int) -> void:
	if state in ["playing", "choosing"]:
		progression.add_experience(amount)

func _on_windup(heavy: bool) -> void:
	feedback.sound("cloth", player.global_position, -19.0, 1.0)
	if heavy:
		feedback.skill_charge(player)

func _on_swing(heavy: bool) -> void:
	if state != "playing":
		return
	if heavy:
		feedback.skill_spin(player)
	else:
		feedback.slash(player, player.current_move.style, player.ghost_active, player.strike_index, player.combo_finisher)
	if player.strike_index == 0:
		storm.on_swing(heavy)

func _on_ghost_changed(active: bool) -> void:
	feedback.ghost_transition(player, active)
	hud.notice = "厉鬼临身 · 五式八击" if active else "鬼气收敛 · 三式连斩"
	hud.notice_left = 2.0

func _on_hit(target: Node3D, point: Vector3, result: Dictionary, heavy: bool, source: String) -> void:
	hit_count += 1
	var lethal := bool(result.get("lethal", false))
	var critical := bool(result.get("critical", false))
	hud.hit(point, lethal, roundi(result.get("actual", 0)), heavy or critical, "暴击" if critical else source)
	# One presentation accent per short interval, independent of the number of victims.
	if _impact_left > 0.0:
		return
	_impact_left = 0.07
	var direction := (target.global_position - player.global_position).normalized()
	if source == "飞剑":
		feedback.storm_hit(point, direction, lethal)
	elif source != "流星":
		feedback.impact(point, direction, lethal, heavy, player.ghost_active, player.combo_finisher)
	shake_time = 0.16
	shake_power = 0.055 if heavy else 0.025
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		Input.start_joy_vibration(pads[0], 0.2 if heavy else 0.08, 0.4 if heavy else 0.18, 0.08)

func _on_hurt(result: Dictionary) -> void:
	if result.get("dodged", false):
		hud.notice = "闪避"
		hud.notice_left = 0.65
	elif result.get("actual", 0) > 0:
		feedback.sound("impact", player.global_position, -12.0, 0.85)
		shake_time = 0.16
		shake_power = 0.06

func _finish(won: bool) -> void:
	if state not in ["playing", "choosing"]:
		return
	state = "won" if won else "lost"
	player.enabled = false
	director.enabled = false
	storm.set_physics_process(false)
	# A lethal meteor can be inside its own iteration; release attacks afterwards.
	storm.reset.call_deferred()
	get_tree().paused = true
	hud.show_result(won)

func restart() -> void:
	if state == "loading":
		return
	state = "loading"
	get_tree().paused = false
	player.enabled = false
	progression.reset()
	player.reset_fighter()
	storm.reset()
	director.reset()
	for container in [enemies, drops]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	# All effect-owned tweens/audio die with their scene, including unlanded VFX.
	remove_child(feedback)
	feedback.queue_free()
	feedback = FEEDBACK_SCRIPT.new()
	feedback.name = "Feedback"
	add_child(feedback)
	player.feedback = feedback
	storm.feedback = feedback
	boss = null
	hit_count = 0
	defeat_count = 0
	shake_time = 0.0
	_impact_left = 0.0
	focus = Vector3.ZERO
	camera.position = CAMERA_OFFSET
	camera.look_at(focus)
	hud.reset_hud()
	storm.set_physics_process(true)
	player.enabled = true
	ready_to_play = true
	state = "playing"
	hud.notice = "剑豪 · 靠近敌人自动出剑，拾取经验破境"
	hud.notice_left = 5.0

func _warm_start() -> void:
	var veil := ColorRect.new()
	veil.color = Color("0e191f")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(veil)
	if DisplayServer.get_name() != "headless":
		await feedback.prewarm(player)
		var reveal := create_tween()
		reveal.tween_property(veil, "modulate:a", 0.0, 0.35)
		await reveal.finished
	veil.queue_free()
	player.enabled = true
	director.reset()
	ready_to_play = true
	state = "playing"
	hud.notice = "剑豪 · 靠近敌人自动出剑，拾取经验破境"
	hud.notice_left = 5.0
