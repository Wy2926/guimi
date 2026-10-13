extends Node
## Run the actual scene with -- --verify. Artifacts are generated, never shipped.

var scene: Node3D
var failures: Array[String] = []
var checks: Array[String] = []
var frame_times: Array[float] = []
var record_frames := false
var headless := false
var wall_times: Array[float] = []
var last_frame_us := 0
var first_contact_ms := -1
var attack_started_ms := 0
var skill_started_ms := 0
var first_skill_contact_ms := -1
var max_draw_calls := 0
var requested_fps := 120

func _ready() -> void:
	scene = get_parent()
	headless = DisplayServer.get_name() == "headless"
	requested_fps = 60 if "--fps60" in OS.get_cmdline_user_args() else 120
	scene.set_frame_limit(requested_fps)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	call_deferred("showcase" if "--showcase" in OS.get_cmdline_user_args() else "run")

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if record_frames:
		frame_times.append(delta * 1000.0)
		if last_frame_us > 0:
			wall_times.append(float(now - last_frame_us) / 1000.0)
		max_draw_calls = maxi(max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	last_frame_us = now

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(label: String) -> void:
	if headless:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s.png" % label)

func check(condition: bool, message: String) -> void:
	(checks if condition else failures).append(message)
	print(("PASS " if condition else "FAIL "), message)

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)

func pair() -> void:
	scene.restart()
	scene.player.position = Vector3(-0.95, 0.02, 0.5)
	scene.enemy.position = Vector3(0.95, 0.02, -0.5)
	scene.enemy.return_delay = 99.0

func run() -> void:
	await wait(2.0)
	check(scene.hud.frame_select.item_count == 2 and scene.hud.frame_select.get_item_id(0) == 60 and scene.hud.frame_select.get_item_id(1) == 120, "Frame selector offers exactly 60 and 120 FPS")
	scene.set_frame_limit(60)
	check(Engine.max_fps == 60 and scene.hud.frame_select.selected == 0, "60 FPS selection updates the native limiter and UI")
	scene.set_frame_limit(120)
	check(Engine.max_fps == 120 and scene.hud.frame_select.selected == 1, "120 FPS selection updates the native limiter and UI")
	scene.set_frame_limit(requested_fps)
	if "--layout-check" in OS.get_cmdline_user_args() and not headless:
		DisplayServer.window_set_size(Vector2i(960, 600))
		await wait(0.3)
		await capture("07-small-960x600")
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await wait(0.3)
		await capture("08-wide-1280x720")
		DisplayServer.window_set_size(Vector2i(1440, 900))
		await wait(0.3)
	var left_event := InputEventKey.new()
	left_event.physical_keycode = KEY_LEFT
	var right_event := InputEventKey.new()
	right_event.physical_keycode = KEY_RIGHT
	check(left_event.is_action("move_left") and right_event.is_action("move_right"), "Physical arrow keys map to the correct directions")
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_J
	key_event.pressed = true
	Input.parse_input_event(key_event)
	await get_tree().physics_frame
	check(scene.player.attacking, "Physical J key starts the attack through InputMap")
	key_event.pressed = false
	Input.parse_input_event(key_event)
	await wait(0.8)
	pair()
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	Input.parse_input_event(mouse_event)
	await get_tree().physics_frame
	check(scene.player.attacking, "Left mouse button starts the attack through InputMap")
	mouse_event.pressed = false
	Input.parse_input_event(mouse_event)
	await wait(0.8)
	pair()
	await wait(0.1)
	await capture("01-arena")
	# Measure first-contact wall time without blocking screenshot readback in the swing.
	pair()
	await wait(0.15)
	scene.player.hit_confirmed.connect(func(_target: DuelFighter, _point: Vector3, _lethal: bool, _damage: int, heavy: bool) -> void:
		if first_contact_ms < 0 and not heavy:
			first_contact_ms = Time.get_ticks_msec() - attack_started_ms
		if first_skill_contact_ms < 0 and heavy and skill_started_ms > 0:
			first_skill_contact_ms = Time.get_ticks_msec() - skill_started_ms)
	attack_started_ms = Time.get_ticks_msec()
	press("attack")
	await wait(0.9)
	check(first_contact_ms > 0 and first_contact_ms < 280, "First real contact arrives within 280 ms")
	pair()
	await wait(0.15)
	var started := Time.get_ticks_msec()
	press("attack")
	await get_tree().physics_frame
	check(scene.player.attacking, "J/action starts the one attack immediately")
	await wait(0.12)
	check(scene.enemy.health == 100, "Windup cannot deal damage")
	await capture("02-windup")
	await wait(0.095)
	await capture("03-impact")
	print("CONTACT_SNAPSHOT_MS ", Time.get_ticks_msec() - started)
	await wait(0.16)
	await capture("04-follow-through")
	await wait(0.6)
	check(scene.enemy.health == 75 and scene.hit_count == 1, "One swing = exactly one 25-damage hit")
	check(not scene.player.attacking and scene.player.freeze_left == 0, "Attack and hit-stop recover without a stuck state")
	check(scene.enemy.position.distance_to(Vector3(0.95, 0.02, -0.5)) > 0.2, "Hit physically displaces the target")
	pair()
	scene.player.position = Vector3(-4, 0.02, 0)
	scene.enemy.position = Vector3(4, 0.02, 0)
	await wait(0.1)
	press("attack")
	await wait(0.8)
	check(scene.enemy.health == 100 and scene.hit_count == 0, "Out-of-range swing has no damage or hit confirmation")
	pair()
	await wait(0.1)
	press("attack")
	await wait(0.06)
	scene.enemy.position = scene.player.position - scene.player.attack_direction * 1.8
	await wait(0.8)
	check(scene.enemy.health == 100, "Enemy behind the attacker is not hit")
	pair()
	await wait(0.1)
	var count: int = scene.player.attack_count
	for i in 12:
		press("attack")
	await wait(1.25)
	check(scene.player.attack_count == count + 1, "Early input spam cannot queue repeated attacks")
	pair()
	await wait(0.1)
	count = scene.player.attack_count
	press("attack")
	await wait(0.57)
	press("attack")
	await wait(0.8)
	check(scene.player.attack_count == count + 2, "Late single-slot attack buffer accepts one follow-up")
	pair()
	await wait(0.1)
	for i in 4:
		scene.enemy.position = scene.player.position + Vector3(1.65, 0, -0.45)
		scene.enemy.return_delay = 99
		await wait(0.08)
		press("attack")
		await wait(0.85)
	check(scene.enemy.dead and scene.enemy.health == 0, "Four confirmed hits produce one death")
	check(scene.enemy.collision_layer == 0, "Defeated guard does not leave an invisible upright collider")
	await capture("05-defeated")
	scene.player.position = Vector3(1.15, 0.02, -0.6)
	await wait(3.4)
	check(not scene.enemy.dead and scene.enemy.health == 100, "Target respawns cleanly with full health")
	check(scene.enemy.position.distance_to(scene.player.position) > 1.0 and scene.enemy.collision_layer == 4, "Occupied respawn point is resolved without overlapping the hero")
	pair()
	press("attack")
	await wait(0.20)
	press("restart")
	await wait(0.3)
	check(scene.enemy.health == 100 and not scene.player.attacking and scene.player.animation.speed_scale == 1, "Reset during contact restores animation, health and transient state")
	# The skill uses the same scene, authored rig and native physics at both frame caps.
	pair()
	await wait(0.1)
	key_event.physical_keycode = KEY_K
	key_event.pressed = true
	skill_started_ms = Time.get_ticks_msec()
	Input.parse_input_event(key_event)
	await get_tree().physics_frame
	check(scene.player.using_skill and scene.player.animation.current_animation == DuelFighter.SKILL, "Physical K starts the authored spin skill immediately")
	key_event.pressed = false
	Input.parse_input_event(key_event)
	await wait(0.25)
	check(scene.enemy.health == 100 and scene.hit_count == 0, "Skill charge cannot deal damage or fake hit confirmation")
	await wait(1.1)
	check(first_skill_contact_ms >= 425 and first_skill_contact_ms < 495, "Skill impact stays aligned to the 440 ms animation event")
	check(scene.enemy.health == 45 and scene.hit_count == 1, "One skill release deals exactly one 55-damage hit")
	check(scene.enemy.position.distance_to(Vector3(0.95, 0.02, -0.5)) > 1.0, "Skill impact produces stronger physical knockback")
	check(not scene.player.attacking and scene.player.freeze_left == 0.0 and scene.player.animation.speed_scale == 1.0, "Skill hit-stop and recovery release control cleanly")
	count = scene.player.attack_count
	for i in 12:
		press("skill")
	await wait(0.15)
	check(scene.player.attack_count == count, "Cooldown blocks repeated skill requests without queuing them")
	press("attack")
	await get_tree().physics_frame
	check(scene.player.attacking and not scene.player.using_skill, "Normal attack remains available during skill cooldown")
	await wait(1.8)
	check(scene.player.skill_cooldown == 0.0, "Skill cooldown returns to ready after three seconds")
	pair()
	await wait(0.1)
	mouse_event.button_index = MOUSE_BUTTON_RIGHT
	mouse_event.pressed = true
	Input.parse_input_event(mouse_event)
	await get_tree().physics_frame
	check(scene.player.using_skill, "Right mouse button starts the skill through InputMap")
	mouse_event.pressed = false
	Input.parse_input_event(mouse_event)
	await wait(0.19)
	await capture("10-skill-charge")
	await wait(0.17)
	await capture("11-skill-spin")
	await wait(0.14)
	await capture("12-skill-impact")
	check(scene.hud.popups.size() == 1 and int(scene.hud.popups[0].damage) == 55, "Skill damage popup uses the actual damage value")
	await wait(0.28)
	await capture("13-skill-follow-through")
	await wait(0.5)
	pair()
	scene.player.position = Vector3(-4, 0.02, 0)
	scene.enemy.position = Vector3(4, 0.02, 0)
	await wait(0.1)
	press("skill")
	await wait(1.3)
	check(scene.enemy.health == 100 and scene.hit_count == 0 and scene.shake_time == 0.0, "Out-of-range skill plays but cannot damage or trigger impact shake")
	pair()
	await wait(0.1)
	press("skill")
	await wait(0.06)
	scene.enemy.position = scene.player.position - scene.player.attack_direction * 2.0
	await wait(1.2)
	check(scene.enemy.health == 45, "The circular blade also hits an overlapping target behind the player")
	pair()
	await wait(0.1)
	press("attack")
	await wait(0.57)
	press("skill")
	await wait(1.4)
	check(scene.player.attack_count == 2 and scene.enemy.health == 20, "Late normal-attack buffer links into one skill without duplicate damage")
	pair()
	press("skill")
	await wait(0.18)
	scene.hud.toggle_pause()
	var frozen_time: float = scene.player.animation.current_animation_position
	var frozen_cooldown: float = scene.player.skill_cooldown
	await wait(0.2)
	check(is_equal_approx(scene.player.animation.current_animation_position, frozen_time) and is_equal_approx(scene.player.skill_cooldown, frozen_cooldown), "Pause freezes the skill animation and cooldown together")
	scene.hud.toggle_pause()
	press("restart")
	await wait(0.6)
	check(scene.enemy.health == 100 and not scene.player.using_skill and scene.player.skill_cooldown == 0.0 and scene.feedback.get_child_count() == 0, "Reset cancels charge VFX, pending hit events and cooldown")
	pair()
	press("skill")
	await wait(0.2)
	scene.set_frame_limit(60 if requested_fps == 120 else 120)
	await wait(1.1)
	check(scene.enemy.health == 45 and scene.hit_count == 1 and not scene.player.attacking, "Switching frame cap mid-skill preserves one hit and a clean recovery")
	scene.set_frame_limit(requested_fps)
	pair()
	scene.enemy.health = 40
	await wait(0.1)
	press("skill")
	await wait(1.3)
	check(scene.enemy.dead and scene.defeat_count == 1 and scene.enemy.collision_layer == 0, "Skill lethal impact triggers the existing death path exactly once")
	pair()
	scene.hud.toggle_pause()
	await get_tree().process_frame
	await capture("06-pause")
	var before: Vector3 = scene.player.position
	Input.action_press("move_right")
	await get_tree().create_timer(0.2, true).timeout
	Input.action_release("move_right")
	check(scene.player.position.is_equal_approx(before), "Pause stops gameplay simulation")
	scene.hud.toggle_pause()
	Input.action_press("move_right")
	await wait(2.2)
	Input.action_release("move_right")
	check(scene.player.position.length() <= 5.7, "Stage boundary contains player movement")
	pair()
	record_frames = true
	for i in 8:
		scene.enemy.position = scene.player.position + Vector3(1.8, 0, -0.45)
		scene.enemy.health = 100
		scene.enemy.return_delay = 99
		if i % 2 == 0:
			scene.player.skill_cooldown = 0.0
		press("skill" if i % 2 == 0 else "attack")
		await wait(1.3 if i % 2 == 0 else 0.82)
	record_frames = false
	await wait(2.0)
	check(scene.feedback.get_child_count() == 0, "Transient particles, rings, audio and lights are released")
	frame_times.sort()
	wall_times.sort()
	var stats := {"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "headless": headless, "passed": checks, "failed": failures}
	stats["first_contact_ms"] = first_contact_ms
	stats["first_skill_contact_ms"] = first_skill_contact_ms
	stats["frame_limit"] = requested_fps
	stats["max_draw_calls"] = max_draw_calls
	stats["viewport"] = str(get_viewport().get_visible_rect().size)
	stats["window_pixels"] = str(DisplayServer.window_get_size())
	if not frame_times.is_empty():
		stats["frame_median_ms"] = frame_times[frame_times.size() / 2]
		stats["frame_p95_ms"] = frame_times[int(frame_times.size() * 0.95)]
		stats["frame_samples"] = frame_times.size()
	if not wall_times.is_empty():
		stats["wall_frame_median_ms"] = wall_times[wall_times.size() / 2]
		stats["wall_frame_p95_ms"] = wall_times[int(wall_times.size() * 0.95)]
	var output := FileAccess.open("res://artifacts/verification-%dfps.json" % requested_fps, FileAccess.WRITE)
	output.store_string(JSON.stringify(stats, "\t"))
	output.close()
	print("VERIFICATION ", JSON.stringify(stats))
	get_tree().quit(0 if failures.is_empty() else 1)

func showcase() -> void:
	await wait(2.5)
	Input.action_press("move_left")
	await wait(0.25)
	Input.action_release("move_left")
	Input.action_press("move_right")
	await wait(0.25)
	Input.action_release("move_right")
	await wait(0.6)
	press("attack")
	await wait(1.2)
	press("skill")
	await wait(1.15)
	Input.action_press("move_right")
	await wait(0.38)
	Input.action_release("move_right")
	await wait(0.08)
	press("attack")
	await wait(3.8)
	press("skill")
	await wait(2.2)
	print("SHOWCASE hits=", scene.hit_count, " defeats=", scene.defeat_count)
	get_tree().quit()
