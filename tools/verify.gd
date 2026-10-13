extends Node
## Uses the actual scene and native physics. -- --verify --fps=60 --perf-enemies=80

const ENEMY_SCENE = preload("res://scenes/enemy.tscn")

var scene: Node3D
var checks: Array[String] = []
var failures: Array[String] = []
var captures: Array[String] = []
var requested_fps := 120
var performance_enemies := 0
var headless := false
var started_ms := 0
var recording := false
var last_frame_us := 0
var wall_frame_ms: Array[float] = []
var simulation_frame_ms: Array[float] = []
var max_draw_calls := 0
var max_nodes := 0
var max_active_swords := 0
var max_active_meteors := 0
var performance: Dictionary = {"requested": false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	scene = get_parent()
	headless = DisplayServer.get_name() == "headless"
	started_ms = Time.get_ticks_msec()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--fps60":
			requested_fps = 60
		elif argument.begins_with("--fps="):
			requested_fps = 60 if argument.get_slice("=", 1).to_int() == 60 else 120
		elif argument.begins_with("--perf-enemies="):
			performance_enemies = clampi(argument.get_slice("=", 1).to_int(), 1, 160)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	call_deferred("run")

func _process(delta: float) -> void:
	if not recording:
		return
	var now := Time.get_ticks_usec()
	if last_frame_us > 0:
		wall_frame_ms.append(float(now - last_frame_us) / 1000.0)
	last_frame_us = now
	simulation_frame_ms.append(delta * 1000.0)
	max_draw_calls = maxi(max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	max_nodes = maxi(max_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	max_active_swords = maxi(max_active_swords, scene.storm.active_swords)
	max_active_meteors = maxi(max_active_meteors, scene.storm.meteors.size())

func check(condition: bool, message: String) -> void:
	(checks if condition else failures).append(message)
	print(("PASS " if condition else "FAIL "), message)

func physics_wait(seconds: float) -> void:
	for frame in maxi(1, ceili(seconds * Engine.physics_ticks_per_second)):
		await get_tree().physics_frame

func until(predicate: Callable, seconds: float) -> bool:
	for frame in maxi(1, ceili(seconds * Engine.physics_ticks_per_second)):
		if bool(predicate.call()):
			return true
		await get_tree().physics_frame
	return bool(predicate.call())

func capture(label: String) -> void:
	if headless:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "res://artifacts/roguelite-%s-%dfps.png" % [label, requested_fps]
	var error := get_viewport().get_texture().get_image().save_png(file)
	check(error == OK, "Screenshot saved: " + label)
	if error == OK:
		captures.append(file)

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)

func release_movement() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

func prepare(automatic := false) -> void:
	release_movement()
	scene.restart()
	scene.director.enabled = false
	scene.director._spawn_timer.stop()
	scene.player.auto_attack = automatic
	scene.player.stats.crit_chance = 0.0
	scene.storm.active = true
	scene.storm.meteor_chance = 0.28
	await physics_wait(0.04)

func enemy_at(point: Vector3, health := 500.0, kind := "chaser", moving := false) -> ArenaEnemy:
	var enemy := ENEMY_SCENE.instantiate() as ArenaEnemy
	enemy.configure(kind, 0, 0)
	enemy.target = scene.player
	enemy.camera = scene.camera
	enemy.arena_radius = scene.player.arena_radius
	enemy.position = point
	scene.director.enemy_container.add_child(enemy)
	scene.director._alive.append(enemy)
	enemy.defeated.connect(scene.director._on_defeated)
	enemy.tree_exited.connect(scene.director._on_enemy_exited.bind(enemy))
	enemy.stats.max_health = health
	enemy.health = health
	enemy.stats.physical_defense = 0.0
	enemy.stats.magic_defense = 0.0
	enemy.stats.crit_chance = 0.0
	enemy.stats.dodge_chance = 0.0
	enemy.set_physics_process(moving)
	enemy.defeated.connect(scene._on_enemy_defeated)
	return enemy

func run() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while scene.state != "playing" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(scene.state == "playing" and scene.ready_to_play, "The real main scene reaches playing after startup")
	if scene.state != "playing":
		finish_report()
		return
	scene.set_frame_limit(requested_fps)
	check(scene.player.progression == scene.progression and scene.storm.player == scene.player and scene.storm.progression == scene.progression and scene.storm.feedback == scene.feedback and scene.storm.camera == scene.camera, "Combat dependencies are explicitly supplied by the scene")
	check(scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "The game uses an orthographic 2.5D view")
	var pitch := rad_to_deg(asin(clampf(scene.camera.global_basis.z.y, -1.0, 1.0)))
	check(pitch >= 55.0 and pitch <= 65.0, "Camera elevation is between 55 and 65 degrees")
	check(scene.hud.frame_select.item_count == 2, "The native frame selector has two choices")
	scene.set_frame_limit(60)
	check(Engine.max_fps == 60 and scene.hud.frame_select.selected == 0, "60 FPS selection updates the limiter and HUD")
	scene.set_frame_limit(120)
	check(Engine.max_fps == 120 and scene.hud.frame_select.selected == 1, "120 FPS selection updates the limiter and HUD")
	scene.set_frame_limit(requested_fps)
	await physics_wait(2.0)
	await capture("playing")
	check_damage_rules()
	check_progression()
	await check_automatic_combat()
	await check_active_skills()
	await check_incoming_damage()
	await check_pickups_and_choices()
	await check_pause()
	await check_auxiliary_skills()
	await check_crowd_hits()
	await check_restart()
	await check_waves_and_endings()
	if performance_enemies > 0:
		await check_short_load()
	finish_report()

func check_damage_rules() -> void:
	var attacker := BattleStats.new()
	var defender := BattleStats.new()
	attacker.physical_attack = 100.0
	attacker.magic_attack = 200.0
	attacker.independent_attack = 300.0
	attacker.crit_chance = 0.5
	attacker.crit_multiplier = 2.0
	defender.physical_defense = 100.0
	defender.magic_defense = 300.0
	check(DamageRules.calculate(attacker, defender, 0, 1.0, 0, 1.0, 1.0).damage == 50, "Physical damage reads physical attack and physical defense only")
	check(DamageRules.calculate(attacker, defender, 1, 1.0, 0, 1.0, 1.0).damage == 50, "Magical damage reads magic attack and magic defense only")
	check(DamageRules.calculate(attacker, defender, 2, 1.0, 0, 1.0, 1.0).damage == 300, "Fixed damage reads independent attack")
	defender.physical_defense = 10000.0
	defender.magic_defense = 10000.0
	check(DamageRules.calculate(attacker, defender, 2, 1.0, 0, 1.0, 1.0).damage == 300, "Increasing either defense does not reduce fixed damage")
	attacker.element = DamageRules.Element.FIRE
	attacker.element_bonus[0] = 0.2
	defender.resistances[0] = 0.35
	check(DamageRules.calculate(attacker, defender, 2, 1.0, -1, 1.0, 1.0).damage == 255, "Fixed damage still uses the inherited element and resistance")
	check(DamageRules.calculate(attacker, defender, 2, 1.0, -1, 0.0, 1.0).damage == 510, "Element-adjusted fixed damage can critically strike")
	check(DamageRules.calculate(attacker, defender, 2, 1.0, 0, 1.0, 1.0).damage == 300, "Explicit no-element damage does not use elemental modifiers")
	defender.dodge_chance = 0.5
	var evade := DamageRules.calculate(attacker, defender, 2, 1.0, -1, 0.0, 0.0)
	check(evade.damage == 0 and evade.dodged and not evade.critical, "Fixed damage respects evasion without a phantom critical hit")
	defender.resistances[0] = -10.0
	check(DamageRules.calculate(attacker, defender, 2, 1.0, 1, 1.0, 1.0).damage == 900, "Elemental amplification is capped at three times")
	defender.resistances[0] = 10.0
	check(DamageRules.calculate(attacker, defender, 2, 1.0, 1, 1.0, 1.0).damage == 45, "Elemental resistance cannot reduce a hit below the 15 percent multiplier")

func check_progression() -> void:
	var first := RunProgression.new()
	var second := RunProgression.new()
	first.reset()
	second.reset()
	first.stats.physical_attack = 99.0
	first.stats.element_bonus[0] = 0.8
	check(second.stats.physical_attack == 25.0 and first.base_stats.physical_attack == 25.0 and second.stats.element_bonus[0] == 0.0 and first.base_stats.element_bonus[0] == 0.0, "Each run deep-copies stats and elemental arrays without changing its starting Resource")
	first.reset()
	var ids: Array[String] = []
	for option: Dictionary in first._available_choices():
		ids.append(option.id)
	check(ids.has("physical_attack") and not ids.has("magic_attack") and not ids.has("independent_attack"), "The starting swordmaster offers physical attack and excludes attacks with no unlocked beneficiary")
	first.skills.meteor = 1
	first.skills.swords = 1
	ids.clear()
	for option: Dictionary in first._available_choices():
		ids.append(option.id)
	check(ids.has("magic_attack") and ids.has("independent_attack"), "Unlocking meteor and swords enables their matching attack upgrades")
	first.skills.slash = 5
	ids.clear()
	for option: Dictionary in first._available_choices():
		ids.append(option.id)
	check(not ids.has("skill_slash"), "A max-level skill cannot appear in the choice pool")
	var alias_skill := SkillDefinition.new()
	alias_skill.id = "arcane_wave"
	alias_skill.kind = DamageRules.Kind.MAGICAL
	alias_skill.coefficient = 1.0
	var harmless_stance := SkillDefinition.new()
	harmless_stance.id = "harmless_stance"
	harmless_stance.kind = DamageRules.Kind.PHYSICAL
	harmless_stance.coefficient = 0.0
	harmless_stance.max_level = 1
	second.skill_definitions = [alias_skill, harmless_stance]
	second.initial_skills = {"arcane_wave": 1, "harmless_stance": 1}
	second.reset()
	ids.clear()
	for option: Dictionary in second._available_choices():
		ids.append(option.id)
	check(ids.has("magic_attack") and not ids.has("physical_attack") and not ids.has("independent_attack"), "Attack cards follow a custom alias skill's damage kind, not swordmaster IDs or a zero-damage stance")
	first.reset()
	first.add_experience(1000)
	var earned := first.pending_levels
	var remainder := first.xp
	check(earned > 1 and remainder < first.xp_required(), "One XP grant preserves overflow and can earn multiple pending choices")
	check(not first.choose(-1) and not first.choose(3) and first.pending_levels == earned, "Invalid choices do not consume a level")
	var reentrant: Array[bool] = []
	var retry: Callable = func(): reentrant.append(first.choose(0))
	first.changed.connect(retry)
	first.choose(0)
	first.changed.disconnect(retry)
	check(first.pending_levels == earned - 1 and reentrant == [false], "One choice cannot synchronously consume a second choice through a signal callback")
	var unique := true
	while first.pending_levels > 0:
		ids.clear()
		unique = unique and first.choices.size() == 3
		for option: Dictionary in first.choices:
			unique = unique and not ids.has(option.id)
			ids.append(option.id)
		first.choose(0)
	check(unique and first.xp == remainder and first.choices.is_empty(), "Successive choices remain unique and preserve the unspent XP remainder")
	first.free()
	second.free()

func check_automatic_combat() -> void:
	await prepare(true)
	var target := enemy_at(Vector3(0, 0.04, -1.5))
	await physics_wait(0.03)
	var before: Vector3 = scene.player.global_position
	var camera_before: Vector3 = scene.camera.global_position
	var camera_direction: Vector3 = -scene.camera.global_basis.z
	Input.action_press("move_right")
	await physics_wait(0.30)
	Input.action_release("move_right")
	scene.player.auto_attack = false
	await physics_wait(0.45)
	check(scene.player.attack_count >= 1 and target.health < 500.0 and scene.hit_count > 0, "A reachable enemy receives real auto-attack damage without pressing attack")
	check(scene.player.global_position.distance_to(before) > 0.8, "Auto-attacking does not lock player movement")
	check(scene.camera.global_position.distance_to(camera_before) > 0.2 and camera_direction.dot(-scene.camera.global_basis.z) > 0.999, "The elevated camera follows movement without rotating with the player")
	check(not scene.player.attacking and is_zero_approx(scene.player.freeze_left), "The auto-attack animation and hit-stop recover cleanly")
	await prepare(true)
	target = enemy_at(Vector3(6, 0.04, 0))
	before = scene.player.global_position
	await physics_wait(0.65)
	check(scene.player.attack_count == 0 and target.health == 500.0, "Auto-attacks do not start on an unreachable enemy")
	check(Vector2(scene.player.position.x - before.x, scene.player.position.z - before.z).length() < 0.01, "Auto-targeting never walks the player toward enemies")
	await prepare(true)
	var first := enemy_at(Vector3(0, 0.04, -1.5))
	var second := enemy_at(Vector3(0, 0.04, 1.8))
	await until(func() -> bool: return scene.player.attacking, 0.3)
	var direction: Vector3 = scene.player.attack_direction
	first.receive_damage({"damage": 10000, "critical": false, "dodged": false}, Vector3.ZERO)
	await physics_wait(0.15)
	check(scene.player.attack_direction.is_equal_approx(direction), "Losing a target cannot rotate a committed attack mid-swing")
	await physics_wait(0.65)
	check(scene.player.attack_count >= 2 and scene.player.attack_direction.dot(direction) < -0.8 and is_instance_valid(second), "The next combo boundary reacquires a different reachable target")
	await prepare(false)
	scene.player.position = Vector3(scene.player.arena_radius - 0.7, 0.04, 0)
	Input.action_press("move_right")
	await physics_wait(0.8)
	Input.action_release("move_right")
	check(Vector2(scene.player.position.x, scene.player.position.z).length() <= scene.player.arena_radius - 0.45, "The arena boundary contains continued player movement")
	await prepare(false)
	# S uses the flattened camera-forward direction: the arena's screen-bottom edge.
	Input.action_press("move_down")
	await physics_wait(3.35)
	Input.action_release("move_down")
	await physics_wait(0.65)
	var foot: Vector2 = scene.camera.unproject_position(scene.player.get_node("Footing").global_position)
	var view_height: float = get_viewport().get_visible_rect().size.y
	var edge_reached: bool = Vector2(scene.player.position.x, scene.player.position.z).length() >= scene.player.arena_radius - 1.0
	check(edge_reached and foot.y > 0.0 and foot.y < view_height * 0.83, "After WASD movement settles at the bottom boundary, the player's feet stay above the bottom HUD safety line")

func check_active_skills() -> void:
	await prepare(false)
	var target := enemy_at(Vector3(0, 0.04, -1.5))
	await physics_wait(0.04)
	press("skill")
	await physics_wait(0.08)
	check(scene.player.using_skill and scene.player.skill_cooldown > 0.0, "The configured skill input starts the authored ring attack and cooldown")
	await physics_wait(0.18)
	check(target.health == 500.0, "The active skill windup does not apply premature damage")
	await physics_wait(0.55)
	check(target.health == 445.0 and scene.hit_count == 1, "One real ring release applies one 55-damage physical hit")
	var count: int = scene.player.attack_count
	for attempt in 8:
		press("skill")
	await physics_wait(0.15)
	check(scene.player.attack_count == count, "Active-skill input spam is rejected during cooldown")
	await prepare(false)
	scene.player.request_ghost()
	check(not scene.player.ghost_active and scene.player.ghost_cooldown == 0.0, "The locked ghost skill cannot be activated")
	scene.progression.skills.ghost = 1
	press("ghost_state")
	await physics_wait(0.03)
	check(scene.player.ghost_active and scene.player.ghost_left > 7.8 and scene.player.ghost_cooldown > 23.8, "Unlocked ghost uses the configured eight-second duration and 24-second cooldown")
	check(scene.player.stats.physical_attack == 25.0 and scene.player.damage_multiplier == 1.5, "Ghost is a temporary combat multiplier rather than a permanent stat mutation")
	var original_cooldown: float = scene.player.ghost_cooldown
	scene.player.ghost_cooldown = 0.0
	scene.player.ghost_left = 3.0
	press("ghost_state")
	await physics_wait(0.03)
	check(scene.player.ghost_active and scene.player.ghost_cooldown == 0.0 and scene.player.ghost_left <= 3.0 and scene.player.ghost_left > 2.8, "Repeated G during an active ghost buff neither spends a ready cooldown nor refreshes its duration")
	scene.player.ghost_cooldown = original_cooldown
	scene.player.ghost_left = 0.03
	await physics_wait(0.12)
	check(not scene.player.ghost_active and not scene.player.ghost_requested and scene.player.damage_multiplier == 1.0 and scene.player.ghost_cooldown > 0.0, "Ghost expires and leaves its cooldown in force")

func check_incoming_damage() -> void:
	await prepare(false)
	var enemy := enemy_at(Vector3(0, 0.04, -1.5), 500.0, "chaser", true)
	enemy.stats.physical_attack = 12.0
	enemy._attack_left = 0.1
	scene.player.stats.physical_defense = 0.0
	var health: float = scene.player.health
	await physics_wait(0.2)
	check(scene.player.health == health, "An approaching enemy's body and attack windup do not cause contact damage")
	var connected := await until(func() -> bool: return scene.player.health < health, 1.8)
	check(connected and scene.player.health == health - 12.0, "A live enemy telegraph releases real damage against the player")
	enemy.set_physics_process(false)
	var protected_health: float = scene.player.health
	var result: Dictionary = scene.player.receive_damage(DamageRules.calculate(enemy.stats, scene.player.stats, 2, 1.0, 0, 1.0, 1.0), Vector3.ZERO)
	check(result.get("immune", false) and result.actual == 0 and scene.player.health == protected_health, "The post-hit protection also blocks an immediate fixed-damage hit")
	await physics_wait(0.7)
	result = scene.player.receive_damage(DamageRules.calculate(enemy.stats, scene.player.stats, 2, 1.0, 0, 1.0, 1.0), Vector3.ZERO)
	check(result.actual > 0 and scene.player.health < protected_health, "Damage becomes possible again after post-hit protection expires")
	await prepare(false)
	enemy = enemy_at(Vector3(0, 0.04, -5.0), 500.0, "ranged")
	health = scene.player.health
	enemy._launch_projectile((scene.player.global_position - enemy.global_position).normalized(), 6.0, 1.0)
	check(await until(func() -> bool: return scene.player.health < health, 1.5), "A native ranged projectile reaches the player and applies damage")

func check_pickups_and_choices() -> void:
	await prepare(false)
	var enemy := enemy_at(Vector3(6, 0.04, 0), 48.0)
	var result: Dictionary = scene.player.deal_damage(enemy, DamageRules.Kind.FIXED, 100.0, 0)
	await physics_wait(0.04)
	check(result.lethal and result.actual == 48.0 and scene.defeat_count == 1 and scene.drops.get_child_count() == 1, "A lethal hit reports actual HP loss and creates exactly one XP pickup")
	enemy.receive_damage({"damage": 10000, "dodged": false}, Vector3.ZERO)
	await physics_wait(0.04)
	check(scene.defeat_count == 1 and scene.drops.get_child_count() == 1, "Repeated hits on a dead enemy cannot duplicate its kill reward")
	await physics_wait(0.25)
	check(scene.progression.xp == 0 and scene.drops.get_child_count() == 1, "A distant XP pickup stays on the ground")
	var gem := scene.drops.get_child(0) as ExperienceGem
	var expected_xp := gem.value
	gem.global_position = scene.player.global_position + Vector3(1.4, 0.2, 0)
	check(await until(func() -> bool: return scene.progression.xp == expected_xp, 1.0), "A pickup inside the stat-driven radius homes in and grants its XP")
	await physics_wait(0.03)
	check(not is_instance_valid(gem), "A collected pickup removes itself exactly once")
	enemy = enemy_at(Vector3(6, 0.04, 0), 48.0)
	enemy.experience_value = 100
	scene.player.deal_damage(enemy, DamageRules.Kind.FIXED, 100.0, 0)
	await physics_wait(0.03)
	gem = scene.drops.get_child(0) as ExperienceGem
	scene.player.skill_cooldown = 2.0
	scene.director.enabled = true
	gem.global_position = scene.player.global_position + Vector3(1.4, 0.2, 0)
	check(await until(func() -> bool: return scene.state == "choosing", 1.0), "Collecting enough real XP opens the upgrade state")
	check(get_tree().paused and scene.hud.choice_panel.visible and scene.progression.choices.size() == 3 and scene.progression.pending_levels >= 2, "A multi-level pickup pauses the battle and displays three choices")
	var time: float = scene.director.elapsed
	var cooldown: float = scene.player.skill_cooldown
	await physics_wait(0.3)
	check(scene.director.elapsed == time and scene.player.skill_cooldown == cooldown, "Upgrade pause freezes the wave clock and active cooldown")
	scene.toggle_pause()
	check(scene.state == "choosing" and get_tree().paused and scene.hud.choice_panel.visible, "The pause action cannot bypass a required upgrade")
	var previous_level: int = scene.progression.level
	var previous_pending: int = scene.progression.pending_levels
	# Model another gem collected in the same physics batch, earning just one more level.
	var extra_experience: int = scene.progression.xp_required() - scene.progression.xp + 3
	scene._collect_experience(extra_experience)
	await physics_wait(0.15)
	var heading: String = scene.hud._choice_subtitle.text
	check(scene.state == "choosing" and get_tree().paused and scene.progression.xp == 3 and scene.progression.level == previous_level + 1 and scene.progression.pending_levels == previous_pending + 1 and heading.contains("Lv.%d" % scene.progression.level) and heading.contains("尚有 %d 次选择" % scene.progression.pending_levels), "A second gem received while choosing preserves XP and refreshes the displayed level and pending-choice count")
	await capture("choosing")
	await capture_choice_layouts()
	var pending: int = scene.progression.pending_levels
	var remainder: int = scene.progression.xp
	var unique := true
	var sequential := true
	while scene.progression.pending_levels > 0:
		var ids: Array[String] = []
		for option: Dictionary in scene.progression.choices:
			unique = unique and not ids.has(option.id)
			ids.append(option.id)
		var before: int = scene.progression.pending_levels
		scene.choose_upgrade(0)
		sequential = sequential and scene.progression.pending_levels == before - 1
		if scene.progression.pending_levels > 0:
			sequential = sequential and scene.state == "choosing" and get_tree().paused
	check(pending >= 2 and sequential and unique, "Each UI-level choice resolves only one level and rolls fresh unique options")
	check(scene.state == "playing" and not get_tree().paused and not scene.hud.choice_panel.visible and scene.progression.xp == remainder, "The last selection resumes play without discarding overflow XP")

func capture_choice_layouts() -> void:
	if headless:
		return
	var original := DisplayServer.window_get_size()
	for size: Vector2i in [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1440, 900)]:
		DisplayServer.window_set_size(size)
		await physics_wait(0.1)
		await capture("layout-%dx%d" % [size.x, size.y])
		var viewport := get_viewport().get_visible_rect()
		var box: Rect2 = scene.hud._choice_box.get_global_rect()
		check(viewport.grow(1.0).encloses(box), "Upgrade content stays inside the %dx%d viewport" % [size.x, size.y])
	DisplayServer.window_set_size(original)
	await physics_wait(0.1)

func check_pause() -> void:
	await prepare(false)
	var target := enemy_at(Vector3(0, 0.04, -5.0), 500.0, "ranged")
	scene.progression.skills.meteor = 1
	scene.player.request_skill()
	await physics_wait(0.12)
	scene.storm._call_meteor(target)
	target._launch_projectile(Vector3.RIGHT, 6.0, 1.0)
	var projectile: Node3D
	for child in target.get_children():
		if child is EnemyProjectile:
			projectile = child
	scene.director.enabled = true
	scene.director._spawn_timer.start(0.2)
	scene.toggle_pause()
	var time: float = scene.director.elapsed
	var cooldown: float = scene.player.skill_cooldown
	var animation_time: float = scene.player.animation.current_animation_position
	var spawn_time: float = scene.director._spawn_timer.time_left
	var meteor_time: float = scene.storm.meteors[0].left
	var meteor_position: Vector3 = scene.storm.meteors[0].node.global_position
	var projectile_position: Vector3 = projectile.global_position
	var position: Vector3 = scene.player.global_position
	Input.action_press("move_right")
	await physics_wait(0.35)
	Input.action_release("move_right")
	check(scene.state == "paused" and get_tree().paused and scene.hud.pause_panel.visible, "The pause action opens its native modal and pauses the tree")
	check(scene.director.elapsed == time and scene.director._spawn_timer.time_left == spawn_time and scene.player.skill_cooldown == cooldown and scene.player.animation.current_animation_position == animation_time, "Pause freezes wave timers, active cooldown and authored animation together")
	check(scene.storm.meteors[0].left == meteor_time and scene.storm.meteors[0].node.global_position.is_equal_approx(meteor_position) and projectile.global_position.is_equal_approx(projectile_position), "Pause freezes in-flight meteor state, its tween and enemy projectiles")
	check(scene.player.global_position.is_equal_approx(position), "Movement input cannot advance the paused player")
	await capture("pause")
	scene.toggle_pause()
	await physics_wait(0.15)
	check(scene.state == "playing" and not get_tree().paused and scene.director.elapsed > time and scene.player.skill_cooldown < cooldown, "Resume restarts simulation and cooldown from their frozen state")

func blade_ids() -> Array[int]:
	var ids: Array[int] = []
	for blade: Node3D in scene.storm.blades:
		ids.append(blade.get_instance_id())
	return ids

func check_auxiliary_skills() -> void:
	await prepare(false)
	var target := enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	scene.storm.on_swing(false)
	await physics_wait(0.04)
	check(scene.storm.volley_count == 0 and scene.storm.meteor_count == 0 and scene.storm.blades.is_empty(), "Neither locked passive can launch or instantiate an active sword formation")
	scene.progression.skills.meteor = 1
	scene.storm.meteor_chance = 1.0
	scene.storm.on_swing(false)
	check(scene.storm.meteor_count == 1 and scene.storm.volley_count == 0 and scene.storm.blades.is_empty(), "Meteor unlocks independently without unlocking swords")
	await physics_wait(1.1)
	check(scene.storm.meteor_hits > 0 and target.health < 10000.0 and scene.storm.meteor_rolls == 1 and scene.storm.meteor_count == 1, "A real meteor lands without recursively rolling auxiliary skills")
	await prepare(false)
	target = enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	target.stats.physical_defense = 10000.0
	target.stats.magic_defense = 10000.0
	scene.progression.skills.swords = 1
	scene.storm.refresh_skills()
	var original_ids := blade_ids()
	check(original_ids.size() == 8 and scene.storm.slots.size() == 8, "Unlocking swords instantiates exactly eight source-asset blades")
	var peak := 0
	for attempt in 4:
		scene.storm.on_swing(false)
		for frame in 36:
			await get_tree().physics_frame
			peak = maxi(peak, scene.storm.active_swords)
	await physics_wait(2.0)
	var returned: bool = scene.storm.active_swords == 0 and blade_ids() == original_ids
	for index in scene.storm.blades.size():
		returned = returned and scene.storm.blades[index].get_parent() == scene.storm.slots[index]
	check(peak > 0 and peak <= 8 and scene.storm.blades.size() == 8, "Repeated volleys never create more than the eight physical blades")
	check(scene.storm.sword_hits > 0 and target.health < 10000.0 and scene.storm.meteor_count == 0, "Fixed-damage swords hit through high double defense without unlocking meteor")
	check(returned, "The same eight blade instances return to their formation after attacks")

func check_crowd_hits() -> void:
	await prepare(false)
	var crowd: Array[ArenaEnemy] = []
	for index in 40:
		var angle := TAU * float(index) / 40.0
		crowd.append(enemy_at(Vector3(cos(angle) * 1.9, 0.04, sin(angle) * 1.9), 500.0))
	await physics_wait(0.04)
	scene.player.request_skill()
	await physics_wait(0.8)
	var damaged := 0
	for target: ArenaEnemy in crowd:
		if target.health == 445.0:
			damaged += 1
	check(damaged == 40 and scene.hit_count == 40, "A native ring attack hits all 40 overlapping enemies once, not just 32")
	check(scene.hud.popups.size() <= scene.hud.MAX_POPUPS and scene.shake_power <= 0.06, "Crowd hit feedback stays bounded instead of multiplying shake and popups indefinitely")
	await prepare(false)
	crowd.clear()
	for index in 40:
		var angle := TAU * float(index) / 40.0
		crowd.append(enemy_at(Vector3(cos(angle), 0.04, -5.0 + sin(angle)), 500.0))
	scene.progression.skills.meteor = 1
	await physics_wait(0.04)
	scene.storm._call_meteor(crowd[0])
	await physics_wait(1.1)
	check(scene.storm.meteor_hits == 40, "The meteor query resolves all 40 targets beyond the old 32-body query limit")

func check_restart() -> void:
	await prepare(false)
	var target := enemy_at(Vector3(0, 0.04, -4.0), 10000.0, "ranged")
	scene.progression.skills.swords = 1
	scene.progression.skills.meteor = 1
	scene.progression.skills.ghost = 1
	scene.storm.refresh_skills()
	scene.storm.on_swing(true)
	scene.storm._call_meteor(target)
	scene.player.request_ghost()
	target._launch_projectile(Vector3.RIGHT, 6.0, 1.0)
	var enemy_id := target.get_instance_id()
	var old_feedback_id: int = scene.feedback.get_instance_id()
	var old_blades := blade_ids()
	var dropped := enemy_at(Vector3(7, 0.04, 0), 1.0)
	scene.player.deal_damage(dropped, 2, 100.0, 0)
	await physics_wait(0.04)
	scene.progression.add_experience(100)
	check(scene.state == "choosing" and scene.progression.pending_levels > 0 and not scene.storm.meteors.is_empty() and scene.drops.get_child_count() > 0, "Reset fixture contains pending upgrades, a dropped pickup and in-flight effects")
	scene.restart()
	scene.director.enabled = false
	scene.director._spawn_timer.stop()
	check(scene.state == "playing" and not get_tree().paused and scene.ready_to_play, "Restart synchronously returns the existing scene to play")
	check(scene.enemies.get_child_count() == 0 and scene.drops.get_child_count() == 0 and scene.director.get_alive_count() == 0 and scene.director._pending.is_empty(), "Restart clears all enemy, projectile, drop and scheduled-spawn owners")
	check(scene.storm.active_swords == 0 and scene.storm.meteors.is_empty() and scene.storm.blades.is_empty(), "Restart removes in-flight swords, meteor state and the now-locked formation")
	check(scene.progression.level == 1 and scene.progression.xp == 0 and scene.progression.pending_levels == 0 and scene.progression.choices.is_empty(), "Restart clears level, XP and every pending choice")
	check(scene.player.health == scene.player.stats.max_health and not scene.player.dead and not scene.player.ghost_active and scene.player.skill_cooldown == 0.0 and scene.player.ghost_cooldown == 0.0 and scene.defeat_count == 0 and scene.hit_count == 0, "Restart resets health, death, buffs, cooldowns and run counters")
	await physics_wait(0.05)
	var freed := not is_instance_id_valid(enemy_id) and not is_instance_id_valid(old_feedback_id)
	for blade_id: int in old_blades:
		freed = freed and not is_instance_id_valid(blade_id)
	check(freed, "Old enemies, effect-owned tweens and formation instances are actually freed")
	await physics_wait(1.1)
	check(scene.enemies.get_child_count() == 0 and scene.drops.get_child_count() == 0 and scene.hit_count == 0 and scene.player.health == scene.player.stats.max_health, "Cancelled old impacts and pickups cannot reappear after restart")

func check_waves_and_endings() -> void:
	scene.restart()
	scene.player.auto_attack = false
	await physics_wait(0.35)
	check(scene.director._pending.size() == 3 and scene.director.get_alive_count() == 0, "The opening wave has a visible timed warning before its three enemies enter")
	await physics_wait(0.85)
	var safe := true
	for enemy: Node3D in scene.director._alive:
		safe = safe and enemy.global_position.distance_to(scene.player.global_position) >= 6.0
	check(scene.director.get_alive_count() == 3 and safe, "The first real wave enters from the perimeter at a safe distance")
	scene.director.elapsed = 119.99
	await physics_wait(0.04)
	check(scene.director._elite_done[0], "The authored two-minute boundary schedules its elite only once")
	await physics_wait(0.9)
	var elites := 0
	for enemy: Node3D in scene.director._alive:
		if enemy.elite:
			elites += 1
	check(elites == 1, "The scheduled elite enters through the real warning timer")
	scene.director.elapsed = scene.director.duration - 0.01
	await physics_wait(1.0)
	check(is_instance_valid(scene.boss) and scene.boss.boss and scene.director._boss_scheduled, "The ten-minute boundary spawns the final boss")
	if not is_instance_valid(scene.boss):
		return
	var boss_id: int = scene.boss.get_instance_id()
	await physics_wait(1.1)
	var bosses := 0
	for enemy: Node3D in scene.director._alive:
		if enemy.boss:
			bosses += 1
	check(bosses == 1 and scene.boss.get_instance_id() == boss_id and scene.director._spawn_timer.is_stopped(), "The final boss is not duplicated and ordinary spawning stops")
	var kills: int = scene.defeat_count
	var boss_health: float = scene.boss.health
	var result: Dictionary = scene.player.deal_damage(scene.boss, DamageRules.Kind.FIXED, 100000.0, 0)
	check(result.lethal and result.actual == boss_health and scene.defeat_count == kills + 1 and scene.state == "won", "An actual boss kill enters victory exactly once with clamped actual damage")
	check(get_tree().paused and scene.hud.result_panel.visible and not scene.player.enabled, "Victory freezes combat and displays the result panel")
	scene.boss.receive_damage({"damage": 10000, "dodged": false}, Vector3.ZERO)
	scene._finish(false)
	check(scene.state == "won" and scene.defeat_count == kills + 1, "A repeated boss hit or late loss cannot replace the completed victory")
	await capture("end-won")
	await prepare(false)
	var attacker := BattleStats.new()
	attacker.independent_attack = 100000.0
	scene.player.receive_damage(DamageRules.calculate(attacker, scene.player.stats, 2, 1.0, 0, 1.0, 1.0), Vector3.ZERO)
	check(scene.state == "lost" and scene.player.dead and scene.player.health == 0.0 and get_tree().paused and scene.hud.result_panel.visible, "Real lethal damage ends the run without a target-dummy respawn")
	await capture("end-lost")
	scene.restart()
	check(scene.state == "playing" and not scene.player.dead and scene.player.health == 120.0 and not scene.hud.result_panel.visible, "The same scene can restart cleanly after defeat")

func check_short_load() -> void:
	await prepare(true)
	scene.player.stats.max_health = 100000.0
	scene.player.health = 100000.0
	scene.progression.skills.swords = 1
	scene.progression.skills.meteor = 1
	scene.progression.skills.ghost = 1
	scene.storm.refresh_skills()
	scene.player.request_ghost()
	for index in performance_enemies:
		var angle := TAU * float(index) / float(performance_enemies)
		var radius := 2.5 + float(index % 6) * 0.8
		var kind := "ranged" if index % 6 == 0 else ("charger" if index % 4 == 0 else "chaser")
		enemy_at(Vector3(cos(angle) * radius, 0.04, sin(angle) * radius), 50000.0, kind, true)
	await physics_wait(0.25)
	wall_frame_ms.clear()
	simulation_frame_ms.clear()
	last_frame_us = 0
	recording = true
	var load_started := Time.get_ticks_msec()
	for action: String in ["move_right", "move_up", "move_left", "move_down"]:
		Input.action_press(action)
		scene.player.skill_cooldown = 0.0
		scene.player.request_skill()
		await physics_wait(1.25)
		Input.action_release(action)
	recording = false
	performance = {
		"requested": true,
		"scope": "headless_logic_load_only_not_rendered_fps" if headless else "rendered_short_fixture_not_target_hardware_guarantee",
		"fixture": "Real AI enemies, all three optional skills unlocked, movement and one forced active cast per 1.25 seconds; elevated health prevents upgrade/death pauses.",
		"requested_enemies": performance_enemies,
		"remaining_enemies": get_tree().get_nodes_in_group("enemies").size(),
		"simulation_seconds": 5.0,
		"wall_seconds": float(Time.get_ticks_msec() - load_started) / 1000.0,
		"wall_frame_ms": summarize(wall_frame_ms),
		"simulation_delta_ms": summarize(simulation_frame_ms),
		"max_draw_calls": max_draw_calls,
		"max_nodes": max_nodes,
		"max_active_swords": max_active_swords,
		"max_active_meteors": max_active_meteors,
	}
	check(scene.state == "playing" and not get_tree().paused, "The short crowd-load fixture completes without a state lock or unexpected upgrade pause")
	check(max_active_swords <= 8 and max_active_meteors <= 2, "Crowd-load auxiliary concurrency stays within its authored limits")
	await capture("crowd-%d" % performance_enemies)

func summarize(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"samples": 0}
	var sorted := values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "median": sorted[int((sorted.size() - 1) * 0.5)], "p95": sorted[int((sorted.size() - 1) * 0.95)], "max": sorted.back()}

func finish_report() -> void:
	release_movement()
	var report := {
		"schema": "roguelite-verification-1",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"headless": headless,
		"frame_limit": requested_fps,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"duration_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"passed": checks,
		"failed": failures,
		"captures": captures,
		"viewport": str(get_viewport().get_visible_rect().size),
		"performance": performance,
		"limitations": "Headless runs verify logic, not rendered FPS. A short synthetic crowd fixture does not establish long-session stability, target-hardware performance, controller feel or visual approval.",
	}
	var mode := "headless" if headless else "rendered"
	for path: String in ["res://artifacts/roguelite-verification.json", "res://artifacts/roguelite-verification-%dfps-%s.json" % [requested_fps, mode]]:
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify(report, "\t"))
			output.close()
		else:
			push_error("Could not write verification report: " + path)
	print("ROGUELITE_VERIFICATION ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
