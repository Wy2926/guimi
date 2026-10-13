extends Node3D

@onready var player: DuelFighter = $Player
@onready var enemy: DuelFighter = $Enemy
@onready var feedback: Node3D = $Feedback
@onready var camera: Camera3D = $Camera3D
@onready var hud: Control = $HUD/Interface

var shake_enabled := true
var hit_count := 0
var defeat_count := 0
var shake_time := 0.0
var shake_power := 0.0
var base_camera := Vector3(8.9, 12.2, 15.9)
var focus := Vector3(0, -0.55, 0)
var clock := 0.0
var ready_to_play := false
var frame_limit := 120
var guards: Array[DuelFighter] = []
var storm: Node3D

func _ready() -> void:
	Input.use_accumulated_input = false
	player.opponent = enemy
	enemy.opponent = player
	guards.append(enemy)
	# Reuse the same authored guard three times to exercise real multi-target combat.
	for home in [Vector3(3.2, 0.04, 1.5), Vector3(-2.9, 0.04, -2.2), Vector3(1.0, 0.04, -3.7)]:
		var guard := enemy.duplicate() as DuelFighter
		guard.home_position = home
		guard.opponent = player
		add_child(guard)
		guards.append(guard)
	storm = Node3D.new()
	storm.set_script(preload("res://scripts/sword_storm.gd"))
	storm.name = "SwordStorm"
	add_child(storm)
	camera.look_at(focus)
	player.swing_started.connect(_on_windup)
	player.swing_active.connect(_on_swing)
	player.skill_released.connect(func() -> void: feedback.skill_release(player))
	player.hit_confirmed.connect(_on_hit)
	player.ghost_changed.connect(_on_ghost_changed)
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		set_frame_limit(int(settings.get_value("display", "frame_limit", 120)))
	else:
		set_frame_limit(120)
	_warm_start()
	# The test driver uses the exact same loaded scene/input/physics as normal play.
	if ResourceLoader.exists("res://tools/verify.gd") and ("--verify" in OS.get_cmdline_user_args() or "--showcase" in OS.get_cmdline_user_args()):
		var driver := load("res://tools/verify.gd").new() as Node
		add_child(driver)

func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_play:
		return
	if event.is_action_pressed("attack") and not event.is_echo():
		player.request_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("skill") and not event.is_echo():
		player.request_skill()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sword_storm") and not event.is_echo():
		storm.set_active(not storm.active)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ghost_state") and not event.is_echo():
		player.request_ghost()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and not event.is_echo():
		restart()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(delta: float) -> void:
	clock += delta
	shake_time = maxf(0, shake_time - delta)
	var middle := (player.position + enemy.position) * 0.5
	var target_focus := Vector3(middle.x * 0.28, -0.55, middle.z * 0.28)
	focus = focus.lerp(target_focus, 1.0 - exp(-delta * 3.2))
	var offset := Vector3.ZERO
	if shake_enabled and shake_time > 0:
		var strength := shake_power * pow(shake_time / 0.22, 2.0)
		offset = Vector3(sin(clock * 173), cos(clock * 137), 0) * strength
	camera.position = base_camera + Vector3(focus.x, 0, focus.z) + offset
	camera.look_at(focus)
	camera.fov = move_toward(camera.fov, 34.0, delta * 7.0)
	for guard in guards:
		guard.get_node("Footing").visible = not guard.dead

func set_frame_limit(fps: int, save := false) -> void:
	frame_limit = 60 if fps == 60 else 120
	Engine.max_fps = frame_limit
	if is_instance_valid(hud):
		hud.sync_frame_limit(frame_limit)
	if save:
		var settings := ConfigFile.new()
		settings.set_value("display", "frame_limit", frame_limit)
		settings.save("user://settings.cfg")

func _on_windup(heavy: bool) -> void:
	feedback.sound("cloth", player.global_position, -14.0, 1.0)
	if heavy:
		feedback.skill_charge(player)

func _on_swing(heavy: bool) -> void:
	if heavy:
		feedback.skill_spin(player)
	else:
		feedback.slash(player, player.current_move.style, player.ghost_active, player.strike_index, player.combo_finisher)
	# A multi-hit action still requests auxiliary swords/meteors just once.
	if player.strike_index == 0:
		storm.on_swing(heavy)

func _on_ghost_changed(enabled: bool) -> void:
	feedback.ghost_transition(player, enabled)
	hud.notice = "厉鬼临身 · 五式八击" if enabled else "收敛鬼气 · 三式连斩"
	hud.notice_left = 2.0

func _on_hit(target: DuelFighter, point: Vector3, lethal: bool, damage: int, heavy: bool) -> void:
	hit_count += 1
	if lethal:
		defeat_count += 1
	var direction := (target.position - player.position).normalized() if heavy else player.attack_direction
	var finisher := player.combo_finisher
	feedback.impact(point, direction, lethal, heavy or finisher, player.ghost_active, finisher)
	shake_time = 0.22
	shake_power = 0.12 if heavy or finisher else (0.10 if lethal else (0.038 if player.ghost_active else 0.057))
	if shake_enabled:
		camera.fov = 33.0 if heavy else (33.45 if lethal else 33.7)
	hud.hit(point, lethal, damage, heavy, "厉鬼" if player.ghost_active else "")
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		Input.start_joy_vibration(pads[0], 0.3 if heavy else 0.16, 0.7 if heavy else (0.5 if lethal else 0.28), 0.18 if heavy else 0.12)

func target_respawned(target: DuelFighter = null) -> void:
	if target == null:
		target = enemy
	# The hero may be standing on the home point when the guard reforms.
	if target.position.distance_to(player.position) < 1.25:
		for offset in [Vector3(-2.3, 0, 0), Vector3(2.3, 0, 0), Vector3(0, 0, -2.3)]:
			var candidate: Vector3 = target.home_position + offset
			if Vector2(candidate.x, candidate.z).length() <= 5.2 and candidate.distance_to(player.position) > 1.3:
				target.position = candidate
				break
		target.reset_physics_interpolation()
	feedback.ground_ring(target.position + Vector3.UP * 0.04, Color("5bced2"), 0.55)
	hud.notice = "守卫归位"
	hud.notice_left = 1.5

func footstep(pos: Vector3) -> void:
	feedback.sound("step%d" % (randi() % 3), pos, -16, 1.1)

func restart() -> void:
	get_tree().paused = false
	player.reset_fighter()
	for guard in guards:
		guard.reset_fighter()
	storm.reset()
	hit_count = 0
	defeat_count = 0
	shake_time = 0.0
	camera.fov = 34.0
	# Remove outstanding effects/tweens by replacing just the ephemeral feedback node.
	var replacement := Node3D.new()
	replacement.set_script(preload("res://scripts/feedback.gd"))
	remove_child(feedback)
	feedback.queue_free()
	replacement.name = "Feedback"
	add_child(replacement)
	feedback = replacement
	hud.reset_hud()

func _warm_start() -> void:
	player.set_physics_process(false)
	for guard in guards:
		guard.set_physics_process(false)
	var veil := ColorRect.new()
	veil.color = Color("0e191f")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(veil)
	await feedback.prewarm(player)
	var reveal := create_tween()
	reveal.tween_property(veil, "modulate:a", 0.0, 0.5)
	await reveal.finished
	veil.queue_free()
	player.set_physics_process(true)
	for guard in guards:
		guard.set_physics_process(true)
	ready_to_play = true
