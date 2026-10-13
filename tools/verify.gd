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
var max_active_swords := 0
var max_active_meteors := 0
var normal_combo_damage := 0
var ghost_combo_damage := 0
var normal_combo_wall_ms := 0
var ghost_combo_wall_ms := 0

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
		max_active_swords = maxi(max_active_swords, scene.storm.active_swords)
		max_active_meteors = maxi(max_active_meteors, scene.storm.meteors.size())
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
	scene.storm.set_active(false)
	scene.enemy.process_mode = Node.PROCESS_MODE_INHERIT
	scene.enemy.set_physics_process(true)
	scene.enemy.show()
	# Keep the original single-target regression independent of auxiliary damage.
	for guard in scene.guards:
		if guard == scene.enemy:
			continue
		guard.process_mode = Node.PROCESS_MODE_DISABLED
		guard.hide()
		guard.collision_layer = 0
	scene.player.position = Vector3(-0.95, 0.02, 0.5)
	scene.enemy.position = Vector3(0.95, 0.02, -0.5)
	scene.enemy.return_delay = 99.0

func run() -> void:
	await wait(2.0)
	pair()
	check_outfit()
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
	check(scene.player.attacking, "J/action starts the first normal-combo attack immediately")
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
	check(scene.player.sword.material_overlay == scene.player.sword_glow and float(scene.player.sword_glow.get_shader_parameter("flash")) > 0.3, "Skill charge illuminates the equipped greatsword, not the hidden old blade")
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
	await check_combos()
	await check_storm()
	storm_arena(1.0)
	var performance_blades := formation_ids()
	record_frames = true
	for i in 8:
		if i == 4:
			press("ghost_state")
		for guard in scene.guards:
			guard.reset_fighter()
			guard.health = 1000
			guard.return_delay = 99
		if i % 2 == 0:
			scene.player.skill_cooldown = 0.0
		press("skill" if i % 2 == 0 else "attack")
		await wait(1.3 if i % 2 == 0 else 0.82)
	record_frames = false
	if scene.player.ghost_requested:
		press("ghost_state")
	await wait(2.2)
	check(scene.feedback.get_child_count() == 0, "Transient particles, rings, audio and lights are released")
	check(scene.storm.MAX_ACTIVE_SWORDS == 8 and max_active_swords > 0 and max_active_swords <= 8 and max_active_meteors > 0, "Multi-target effects use no more than the eight physical formation blades")
	check(formation_is_consistent(performance_blades, true) and scene.storm.meteors.is_empty(), "The same eight swords return to their formation after the last attack")
	frame_times.sort()
	wall_times.sort()
	var stats := {"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "headless": headless, "passed": checks, "failed": failures}
	stats["first_contact_ms"] = first_contact_ms
	stats["first_skill_contact_ms"] = first_skill_contact_ms
	stats["frame_limit"] = requested_fps
	stats["max_draw_calls"] = max_draw_calls
	stats["max_active_swords"] = max_active_swords
	stats["max_active_meteors"] = max_active_meteors
	stats["performance_targets"] = scene.guards.size()
	stats["performance_modes"] = ["normal", "ghost"]
	stats["normal_combo_damage"] = normal_combo_damage
	stats["ghost_combo_damage"] = ghost_combo_damage
	stats["normal_combo_wall_ms"] = normal_combo_wall_ms
	stats["ghost_combo_wall_ms"] = ghost_combo_wall_ms
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

func wait_attack_end() -> void:
	# Native physics frames, with a finite timeout so a stuck move fails instead of hanging.
	for i in 360:
		await get_tree().physics_frame
		if not scene.player.attacking:
			return
	check(false, "An authored combo move finishes within three seconds")

func wait_move_time(time: float) -> void:
	for i in 240:
		await get_tree().physics_frame
		if not scene.player.attacking or scene.player.animation.current_animation_position >= time:
			return
	check(false, "The combo animation reaches its late input-buffer window")

func stationary_pair() -> void:
	pair()
	# A stationary high-health native collider isolates damage-window deduplication
	# from knockback. Real moving-target combat remains covered by the other checks.
	scene.player.position = Vector3(0, 0.04, 0)
	scene.enemy.position = Vector3(0, 0.04, 1.8)
	scene.enemy.health = 10000
	scene.enemy.set_physics_process(false)
	scene.player.reset_physics_interpolation()
	scene.enemy.reset_physics_interpolation()

func check_combo_assets() -> void:
	var original := preload("res://assets/characters/Knight.glb").instantiate()
	var authored := original.get_node("AnimationPlayer") as AnimationPlayer
	var normal_sources: Array[StringName] = []
	var ghost_sources: Array[StringName] = []
	var poses_preserved := true
	var event_counts_match := true
	var event_total := [0, 0]
	for mode in 2:
		var profiles: Array = DuelFighter.NORMAL_COMBO if mode == 0 else DuelFighter.GHOST_COMBO
		for profile in profiles:
			var sources := normal_sources if mode == 0 else ghost_sources
			if not sources.has(profile.source):
				sources.append(profile.source)
			var exists: bool = authored.has_animation(profile.source) and scene.player.animation.has_animation(profile.animation)
			poses_preserved = poses_preserved and exists
			if not exists:
				continue
			var source := authored.get_animation(profile.source)
			var runtime: Animation = scene.player.animation.get_animation(profile.animation)
			# Retiming is allowed; the authored transform keys themselves must remain intact.
			for track in source.get_track_count():
				var type := source.track_get_type(track)
				if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
					continue
				var mapped := runtime.find_track(source.track_get_path(track), type)
				if mapped < 0 or runtime.track_get_key_count(mapped) != source.track_get_key_count(track):
					poses_preserved = false
					continue
				for key in source.track_get_key_count(track):
					poses_preserved = poses_preserved and runtime.track_get_key_value(mapped, key) == source.track_get_key_value(track, key)
			var windows := 0
			for track in runtime.get_track_count():
				if runtime.track_get_type(track) != Animation.TYPE_METHOD:
					continue
				for key in runtime.track_get_key_count(track):
					var event: Dictionary = runtime.track_get_key_value(track, key)
					if event.method == &"_open_hit_window":
						windows += 1
			event_counts_match = event_counts_match and windows == profile.strikes.size()
			event_total[mode] += windows
	check(normal_sources.size() == 3 and ghost_sources.size() == 5 and poses_preserved, "Three normal and five ghost moves preserve distinct authored GLB transform keys instead of generating new skeletal poses")
	check(event_counts_match and event_total == [3, 8], "Native AnimationPlayer method tracks define exactly three normal hits and eight ghost hits per complete chain")
	original.free()

func check_combos() -> void:
	pair()
	check_combo_assets()
	var hits: Array[Dictionary] = []
	var record_hit := func(target: DuelFighter, _point: Vector3, _lethal: bool, damage: int, heavy: bool) -> void:
		hits.append({"target": target.get_instance_id(), "strike": scene.player.strike_index, "clip": scene.player.animation.current_animation, "damage": damage, "heavy": heavy})
	scene.player.hit_confirmed.connect(record_hit)
	var played: Array[StringName] = []
	for mode in 2:
		stationary_pair()
		if mode == 1:
			press("ghost_state")
		var profiles: Array = DuelFighter.NORMAL_COMBO if mode == 0 else DuelFighter.GHOST_COMBO
		var cycle_damage := 0
		var cycle_hits := 0
		var began := Time.get_ticks_msec()
		for index in profiles.size():
			var profile: Dictionary = profiles[index]
			scene.player.position = Vector3(0, 0.04, 0)
			scene.player.velocity = Vector3.ZERO
			scene.enemy.position = Vector3(0, 0.04, 1.8)
			scene.enemy.health = 10000
			await wait(0.06)
			hits.clear()
			press("attack")
			await get_tree().physics_frame
			played.append(scene.player.animation.current_animation)
			check(scene.player.combo_index == index and scene.player.animation.current_animation == profile.animation and scene.player.combo_total == profiles.size(), "%s move %d selects its own authored animation through normal attack input" % ["Ghost" if mode == 1 else "Normal", index + 1])
			await wait_attack_end()
			var expected_damage := roundi(float(profile.damage) * (1.5 if mode == 1 else 1.0))
			var unique: Dictionary = {}
			var exact: bool = hits.size() == profile.strikes.size()
			for hit in hits:
				var key := "%d/%d" % [hit.target, hit.strike]
				exact = exact and not unique.has(key) and hit.strike >= 0 and hit.strike < profile.strikes.size() and hit.damage == expected_damage and not hit.heavy
				unique[key] = true
				cycle_damage += int(hit.damage)
				cycle_hits += 1
			exact = exact and scene.enemy.health == 10000 - expected_damage * profile.strikes.size()
			check(exact, "%s move %d deals exactly %d event-aligned hits, once per target per window" % ["Ghost" if mode == 1 else "Normal", index + 1, profile.strikes.size()])
		if mode == 0:
			normal_combo_damage = cycle_damage
			normal_combo_wall_ms = Time.get_ticks_msec() - began
			check(cycle_hits == 3 and cycle_damage == 91, "The complete normal chain is three distinct attacks and 91 actual damage")
		else:
			ghost_combo_damage = cycle_damage
			ghost_combo_wall_ms = Time.get_ticks_msec() - began
			check(cycle_hits == 8 and cycle_damage == 270, "The complete ghost chain becomes five moves, eight real hits and 270 actual damage")
	check(ghost_combo_damage * normal_combo_wall_ms > normal_combo_damage * ghost_combo_wall_ms and is_equal_approx(scene.player.attack_speed, 1.25), "Ghost state measurably raises full-chain damage throughput and uses 1.25x native animation speed")
	await wait(0.72)
	press("attack")
	await get_tree().physics_frame
	check(scene.player.combo_index == 0 and scene.player.animation.current_animation == DuelFighter.GHOST_COMBO[0].animation, "A gap longer than the combo grace period restarts at the first ghost move")
	await wait_attack_end()

	# Multiple separate native colliders, not overlapping fixture bodies.
	for mode in 2:
		storm_arena(0.0)
		scene.storm.set_active(false)
		var placements := [Vector3(0, 0.04, 1.8), Vector3(-0.8, 0.04, 1.8), Vector3(0.8, 0.04, 1.8), Vector3(0, 0.04, -1.8)]
		for i in scene.guards.size():
			scene.guards[i].position = placements[i]
			scene.guards[i].health = 10000
			scene.guards[i].set_physics_process(false)
		if mode == 1:
			press("ghost_state")
		await wait(0.1)
		hits.clear()
		press("attack")
		if mode == 1:
			await wait(0.19)
			await capture("20-ghost-multi-hit")
		await wait_attack_end()
		var expected_hits := 3 if mode == 0 else 8
		var expected_damage := 25 if mode == 0 else 60
		var group_exact := hits.size() == expected_hits
		for i in scene.guards.size():
			var should_hit: bool = mode == 1 or i < 3
			group_exact = group_exact and scene.guards[i].health == 10000 - (expected_damage if should_hit else 0)
		check(group_exact, "Ghost spinning windows hit all four surrounding enemies exactly twice" if mode == 1 else "A normal slash hits all three front targets once while excluding the target behind")

	stationary_pair()
	# Include normal lunging travel, not just the stationary hitbox extent.
	scene.enemy.position = Vector3(0, 0.04, 3.6)
	scene.player.facing = Vector3.BACK
	await wait(0.1)
	press("attack")
	await wait_attack_end()
	var missed_normal: bool = scene.enemy.health == 10000
	scene.player.position = Vector3(0, 0.04, 0)
	scene.player.velocity = Vector3.ZERO
	press("ghost_state")
	await wait(0.1)
	press("attack")
	await wait_attack_end()
	check(missed_normal and scene.enemy.health < 10000 and scene.player.hitbox.scale.is_equal_approx(Vector3(1.3, 1.0, 1.3)), "Ghost state expands the native melee area and reaches a target outside the normal slash")
	stationary_pair()
	press("ghost_state")
	scene.player.position = Vector3(-4, 0.04, 0)
	scene.enemy.position = Vector3(4, 0.04, 0)
	await wait(0.1)
	hits.clear()
	press("attack")
	await wait_attack_end()
	check(hits.is_empty() and scene.enemy.health == 10000 and scene.shake_time == 0.0, "A ghost multi-hit whiff still cannot deal remote damage or fake hit-confirm shake")

	stationary_pair()
	await wait(0.1)
	press("attack")
	await wait(0.06)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	check(not scene.player.ghost_active and scene.player.ghost_requested and scene.player.animation.current_animation == DuelFighter.ATTACK, "Physical G requests ghost state without cancelling or replacing the current normal attack")
	await wait_attack_end()
	check(scene.player.ghost_active and scene.player.ghost_requested and scene.enemy.health == 9975, "Ghost state takes effect only after the original move completes with its original damage")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	check(pad.is_action("ghost_state") and not pad.is_action("skill") and not pad.is_action("sword_storm"), "Gamepad B maps only to ghost state, alongside the existing X/Y actions")
	await capture("19-ghost-state")
	for i in 4:
		press("ghost_state")
	check(scene.player.ghost_active and is_equal_approx(scene.player.attack_speed, 1.25) and scene.player.hitbox.scale.is_equal_approx(Vector3(1.3, 1.0, 1.3)), "Repeated state toggles do not stack attack speed or hitbox scale")
	scene.enemy.health = 10000
	scene.player.position = Vector3(0, 0.04, 0)
	scene.player.velocity = Vector3.ZERO
	await wait(0.1)
	press("attack")
	await wait(0.04)
	press("ghost_state")
	check(scene.player.ghost_active and not scene.player.ghost_requested, "Leaving ghost state is deferred while its multi-hit animation is active")
	await wait_attack_end()
	check(not scene.player.ghost_active and scene.enemy.health == 9940 and is_equal_approx(scene.player.attack_speed, 1.0), "Deferred ghost exit preserves both current hits, then restores normal speed")

	stationary_pair()
	press("ghost_state")
	await wait(0.1)
	press("attack")
	await wait(0.06)
	scene.hud.toggle_pause()
	var frozen_time: float = scene.player.animation.current_animation_position
	var frozen_hp: int = scene.enemy.health
	press("ghost_state")
	await wait(0.2)
	check(is_equal_approx(scene.player.animation.current_animation_position, frozen_time) and scene.enemy.health == frozen_hp and scene.player.ghost_active and scene.player.ghost_requested, "Pause freezes ghost animation and pending hit events and ignores combat state input")
	scene.hud.toggle_pause()
	await wait_attack_end()
	check(scene.enemy.health == 9940, "Resuming a paused ghost attack completes exactly its original two hit windows")

	stationary_pair()
	press("ghost_state")
	await wait(0.1)
	hits.clear()
	press("skill")
	await wait_attack_end()
	check(hits.size() == 1 and hits[0].heavy and hits[0].damage == 83 and scene.enemy.health == 9917, "Ghost state also boosts the existing skill to one real 83-damage hit without multiplying its windows")
	stationary_pair()
	press("ghost_state")
	press("attack")
	await wait(0.05)
	scene.player.receive_hit(999, Vector3.ZERO)
	scene.player.respawn_left = 99.0
	await wait(0.8)
	check(scene.player.dead and not scene.player.attacking and not scene.player.active and not scene.player.ghost_active and not scene.player.ghost_requested and scene.enemy.health == 10000, "Player death clears ghost state, its active window and all later animation damage")
	stationary_pair()
	press("attack")
	await wait(0.04)
	press("ghost_state")
	press("restart")
	await wait(0.5)
	check(not scene.player.attacking and not scene.player.active and not scene.player.ghost_active and not scene.player.ghost_requested and scene.player.hitbox.scale.is_equal_approx(Vector3.ONE) and scene.enemy.health == 100, "Reset cancels pending transformation, combo events and all temporary damage/range boosts")

	stationary_pair()
	press("ghost_state")
	await wait(0.1)
	for i in 12:
		press("attack")
	await wait(1.0)
	check(scene.player.attack_count == 1 and not scene.player.attacking, "Early ghost-input spam cannot enqueue an unbounded chain")
	stationary_pair()
	press("ghost_state")
	await wait(0.1)
	press("attack")
	await wait_move_time(scene.player.move_duration - DuelFighter.BUFFER_TIME + 0.035)
	for i in 12:
		press("attack")
	await wait(1.25)
	check(scene.player.attack_count == 2 and not scene.player.attacking, "The ghost late buffer stores one follow-up move even under repeated input")
	stationary_pair()
	press("ghost_state")
	await wait(0.1)
	played.clear()
	var record_move := func(heavy: bool) -> void:
		if not heavy:
			played.append(scene.player.animation.current_animation)
	scene.player.swing_started.connect(record_move)
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	await wait(3.9)
	key.pressed = false
	Input.parse_input_event(key)
	await wait_attack_end()
	var cycling := played.size() >= 6
	for i in played.size():
		cycling = cycling and played[i] == DuelFighter.GHOST_COMBO[i % 5].animation
	check(cycling, "Holding the physical attack key cycles through all five ghost moves and starts the chain again")
	var stopped: int = scene.player.attack_count
	await wait(0.75)
	check(scene.player.attack_count == stopped and not scene.player.attacking and not scene.player.active, "Releasing held attack finishes the current move without latent attacks or an active collider")
	scene.player.swing_started.disconnect(record_move)
	scene.player.hit_confirmed.disconnect(record_hit)
	pair()

func storm_arena(chance: float) -> void:
	scene.restart()
	scene.player.position = Vector3(0, 0.04, 0)
	var positions := [Vector3(3.8, 0.04, -0.8), Vector3(-3.7, 0.04, -1.0), Vector3(0.9, 0.04, 3.8), Vector3(-1.2, 0.04, -3.8)]
	for i in scene.guards.size():
		var guard: DuelFighter = scene.guards[i]
		guard.process_mode = Node.PROCESS_MODE_INHERIT
		guard.set_physics_process(true)
		guard.show()
		guard.position = positions[i]
		guard.return_delay = 99.0
		guard.reset_physics_interpolation()
	scene.storm.set_active(true)
	scene.storm.meteor_chance = chance

func formation_ids() -> Array[int]:
	var ids: Array[int] = []
	for blade in scene.storm.blades:
		ids.append(blade.get_instance_id())
	return ids

func formation_is_consistent(ids: Array[int], require_home := false) -> bool:
	if ids.size() != 8 or scene.storm.blades.size() != 8 or scene.storm.slots.size() != 8:
		return false
	var flying_slots: Array[int] = []
	for flight in scene.storm.flights:
		var slot: int = flight.slot
		if slot < 0 or slot >= 8 or flying_slots.has(slot):
			return false
		if not is_instance_valid(flight.blade) or flight.blade.get_instance_id() != ids[slot] or flight.blade != scene.storm.blades[slot] or flight.blade.get_parent() != flight.follow:
			return false
		flying_slots.append(slot)
	for i in 8:
		var blade: Node3D = scene.storm.blades[i]
		var slot: Node3D = scene.storm.slots[i]
		if not is_instance_valid(blade) or blade.get_instance_id() != ids[i]:
			return false
		if flying_slots.has(i):
			if require_home or slot.get_child_count() != 0:
				return false
		elif blade.get_parent() != slot or slot.get_child_count() != 1 or not blade.transform.is_equal_approx(Transform3D.IDENTITY):
			return false
	return true

func check_storm() -> void:
	storm_arena(0.0)
	await wait(0.1)
	check(scene.guards.size() == 4 and scene.storm.active, "One arena reuses four visible guard instances with sword storm enabled")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_L
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await get_tree().physics_frame
	check(not scene.storm.active and scene.storm.active_swords == 0, "Physical L disables the formation and clears live projectiles")
	toggle.pressed = false
	Input.parse_input_event(toggle)
	press("sword_storm")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	check(scene.storm.active and pad.is_action("sword_storm") and not pad.is_action("restart"), "Formation toggle restores the state and gamepad Y does not also reset the arena")
	await capture("15-sword-formation")
	var original_blades := formation_ids()
	check(scene.storm.MAX_ACTIVE_SWORDS == 8 and formation_is_consistent(original_blades, true), "Eight original sword instances occupy eight separate formation slots")
	press("attack")
	await wait(0.31)
	check(scene.storm.active_swords == 3 and formation_is_consistent(original_blades), "The first volley physically removes three original blades from their now-empty slots without cloning")
	var assigned: Array[int] = []
	var curved := 0
	var samples: Array[Dictionary] = []
	for flight in scene.storm.flights:
		var target: DuelFighter = flight.target
		if is_instance_valid(target) and not assigned.has(target.get_instance_id()):
			assigned.append(target.get_instance_id())
		var path: Path3D = flight.path
		var curve := path.curve
		var start := curve.sample_baked(0.0)
		var end := curve.sample_baked(curve.get_baked_length())
		var middle := curve.sample_baked(curve.get_baked_length() * 0.5)
		if (middle - start - (middle - start).project(end - start)).length() > 0.25:
			curved += 1
		var follow: PathFollow3D = flight.follow
		samples.append({"follow": follow, "progress": follow.progress})
	check(assigned.size() >= 3 and curved >= 3, "A real attack assigns native curved sword paths across distant targets")
	scene.hud.toggle_pause()
	await wait(0.18)
	var frozen := not samples.is_empty()
	for sample in samples:
		frozen = frozen and is_instance_valid(sample.follow) and is_equal_approx(sample.follow.progress, sample.progress)
	check(frozen, "Pause freezes in-flight PathFollow3D progress")
	scene.hud.toggle_pause()
	await wait(0.08)
	var moved := 0
	for sample in samples:
		if is_instance_valid(sample.follow) and sample.follow.progress > sample.progress + 0.02:
			moved += 1
	check(moved >= 3, "Native sword followers actually advance along their curves after unpausing")
	await capture("16-sword-crossfire")
	var saw_return := false
	var same_instances := true
	for i in 22:
		await wait(0.1)
		same_instances = same_instances and formation_is_consistent(original_blades)
		for flight in scene.storm.flights:
			saw_return = saw_return or flight.returning
	check(saw_return and same_instances, "The original outgoing blades travel a visible return phase with no duplicate instances")
	var damaged := 0
	for guard in scene.guards:
		if guard.health < DuelFighter.MAX_HEALTH:
			damaged += 1
	check(damaged >= 3 and scene.storm.sword_hits >= 3, "Flying swords deal real damage to multiple enemies beyond melee reach")
	check(scene.storm.meteor_rolls == 1 and scene.storm.meteor_count == 0, "Zero meteor probability takes the no-drop branch once per player swing without recursion")
	check(scene.storm.volley_count >= 2 and formation_is_consistent(original_blades, true), "After one swing the same eight blades are restored to their original slots and local transforms")
	storm_arena(1.0)
	for guard in scene.guards:
		guard.health = 1000
	press("attack")
	await wait(0.31)
	check(scene.storm.meteor_rolls == 1 and scene.storm.meteor_count == 1 and scene.storm.meteors.size() == 1, "Full meteor probability creates one delayed drop from the same real attack path")
	if not scene.storm.meteors.is_empty():
		var center: Vector3 = scene.storm.meteors[0].position
		var offsets := [Vector3(-0.65, 0, -0.65), Vector3(0.65, 0, -0.65), Vector3(-0.65, 0, 0.65), Vector3(0.65, 0, 0.65)]
		for i in scene.guards.size():
			scene.guards[i].position = center + offsets[i]
			scene.guards[i].position.y = 0.04
			scene.guards[i].velocity = Vector3.ZERO
	await capture("17-meteor-warning")
	await wait(0.85)
	await capture("18-meteor-impact")
	await wait(0.5)
	check(scene.storm.meteor_hits >= 2, "The native meteor area query damages multiple enemies at the landing point")
	check(scene.storm.meteor_rolls == 1 and scene.storm.meteor_count == 1, "Sword penetration and meteor area hits never roll more meteors recursively")
	storm_arena(1.0)
	for guard in scene.guards:
		guard.health = 1000
	press("ghost_state")
	press("attack")
	await wait(1.3)
	check(scene.storm.meteor_rolls == 1 and scene.storm.meteor_count == 1 and scene.storm.volley_count >= 2, "A two-hit ghost move starts one sword stream and rolls one meteor, not one roll per damage window")
	storm_arena(0.0)
	scene.player.position = Vector3(-5.55, 0.04, 0)
	# Native CharacterBody colliders must not be stacked inside one another.
	var distant := [Vector3(4.1, 0.04, -2.0), Vector3(4.1, 0.04, 2.0), Vector3(3.85, 0.04, -0.5), Vector3(5.2, 0.04, 0.5)]
	for i in scene.guards.size():
		scene.guards[i].position = distant[i]
	press("attack")
	await wait(1.5)
	var untouched := true
	for guard in scene.guards:
		untouched = untouched and guard.health == DuelFighter.MAX_HEALTH
	check(untouched and scene.storm.volley_count == 0, "Enemies outside the wide acquisition radius receive no sword damage")
	storm_arena(0.0)
	original_blades = formation_ids()
	press("attack")
	await wait(0.28)
	var target_lost := false
	if not scene.storm.flights.is_empty():
		var doomed: DuelFighter = scene.storm.flights[0].target
		doomed.receive_hit(999, Vector3.ZERO)
		doomed.respawn_left = 99.0
		target_lost = true
	await wait(2.2)
	check(target_lost and scene.storm.active_swords == 0 and formation_is_consistent(original_blades, true), "A target dying in flight cannot strand a blade away from its formation")
	storm_arena(1.0)
	press("attack")
	await wait(0.28)
	press("restart")
	await wait(1.4)
	untouched = true
	for guard in scene.guards:
		untouched = untouched and guard.health == DuelFighter.MAX_HEALTH
	check(untouched and scene.storm.active_swords == 0 and scene.storm.meteors.is_empty() and scene.storm.meteor_count == 0, "Reset clears flying swords, pending meteors and their delayed damage")
	storm_arena(1.0)
	press("attack")
	await wait(0.28)
	scene.player.receive_hit(999, Vector3.ZERO)
	scene.player.respawn_left = 99.0
	await wait(0.12)
	check(scene.storm.active_swords == 0 and scene.storm.meteors.is_empty(), "Player death cancels the active sword stream and pending meteor")
	storm_arena(0.0)
	for guard in scene.guards:
		guard.health = 1000
	original_blades = formation_ids()
	var hold := InputEventKey.new()
	hold.physical_keycode = KEY_J
	hold.pressed = true
	Input.parse_input_event(hold)
	var peak := 0
	var trips: Dictionary = {}
	same_instances = true
	for i in 35:
		await wait(0.1)
		peak = maxi(peak, scene.storm.active_swords)
		same_instances = same_instances and formation_is_consistent(original_blades)
		for flight in scene.storm.flights:
			var blade_id: int = flight.blade.get_instance_id()
			var path_id: int = flight.path.get_instance_id()
			var paths: Array = trips.get(blade_id, [])
			if not paths.has(path_id):
				paths.append(path_id)
			trips[blade_id] = paths
	hold.pressed = false
	Input.parse_input_event(hold)
	var reused := false
	for paths in trips.values():
		reused = reused or paths.size() >= 2
	check(scene.player.attack_count >= 4 and scene.storm.volley_count >= 4 and peak > 0 and peak <= 8 and same_instances and reused, "Held attack repeatedly relaunches the same eight blades after their return without cloning")
	await wait(2.2)
	check(formation_is_consistent(original_blades, true), "Releasing held attack returns all eight original blades rather than deleting the projectiles")

func check_outfit() -> void:
	var original := preload("res://assets/characters/Knight.glb").instantiate()
	var outfit := preload("res://assets/characters/Rogue.glb").instantiate()
	var current := scene.player.get_node("Visual/Model/Rig/Skeleton3D") as Skeleton3D
	var original_rig := original.get_node("Rig/Skeleton3D") as Skeleton3D
	var outfit_rig := outfit.get_node("Rig/Skeleton3D") as Skeleton3D
	var compatible := current.get_bone_count() == 41 and outfit_rig.get_bone_count() == 41
	for bone in current.get_bone_count():
		compatible = compatible and current.get_bone_name(bone) == outfit_rig.get_bone_name(bone) and original_rig.get_bone_rest(bone).is_equal_approx(outfit_rig.get_bone_rest(bone))
	check(compatible, "Outfit uses the same 41-bone rig and authored rest poses without retargeting")
	var garments_replaced := true
	for part in ["Body", "ArmLeft", "ArmRight", "LegLeft", "LegRight"]:
		var equipped := current.get_node("Knight_" + part) as MeshInstance3D
		var donor := outfit_rig.get_node("Rogue_" + part) as MeshInstance3D
		garments_replaced = garments_replaced and equipped.mesh == donor.mesh and equipped.skin == donor.skin
	check(garments_replaced and current.get_node("chest/Knight_Cape").mesh == outfit_rig.get_node("chest/Rogue_Cape").mesh, "All five garments and the cape use the new authored models")
	check(current.get_node("Knight_Head").mesh == original_rig.get_node("Knight_Head").mesh and current.get_node("head/Knight_Helmet").mesh == original_rig.get_node("head/Knight_Helmet").mesh, "The same knight keeps the original head and helmet")
	check(scene.player.sword.name == &"2H_Sword" and scene.player.sword.visible and not current.get_node("handslot_r/1H_Sword").visible and scene.player.sword.get_parent() is BoneAttachment3D, "One new greatsword is visible on the original animated hand attachment")
	original.free()
	outfit.free()

func showcase_hold(seconds: float) -> void:
	# Sustain only the recorded input, even if the desktop focus changes during capture.
	# Actual physical-key holding is exercised independently by the verification suite.
	var timer := get_tree().create_timer(seconds)
	while timer.time_left > 0.0:
		Input.action_press("attack")
		await get_tree().physics_frame
	Input.action_release("attack")

func showcase() -> void:
	await wait(2.5)
	# Reproducible native gameplay; keep default probability, damage and target health.
	scene.storm.rng.seed = 41
	# Show the new melee chain clearly before layering the existing sword formation.
	press("sword_storm")
	await wait(0.4)
	await showcase_hold(3.5)
	await wait(0.7)
	press("ghost_state")
	await wait(0.8)
	await showcase_hold(5.0)
	await wait(0.7)
	press("sword_storm")
	await wait(0.2)
	await showcase_hold(3.5)
	await wait(0.7)
	press("skill")
	await wait(1.3)
	press("ghost_state")
	await wait(1.2)
	print("SHOWCASE hits=", scene.hit_count, " defeats=", scene.defeat_count, " attacks=", scene.player.attack_count, " volleys=", scene.storm.volley_count, " meteors=", scene.storm.meteor_count)
	get_tree().quit()
