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
var max_active_orbs := 0
var sword_checks_completed := false
var orb_checks_completed := false
var aura_checks_completed := false
var seal_checks_completed := false
var ribbon_checks_completed := false
var max_ribbon_particle_slots := 0
var max_ribbon_spine_bones := 0
var max_ribbon_history_points := 0
var ribbon_skin_poses: Array[Dictionary] = []
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
	max_active_orbs = maxi(max_active_orbs, scene.orbs.orbs.size())
	if not scene.storm.ribbon.is_empty():
		max_ribbon_spine_bones = maxi(max_ribbon_spine_bones, scene.storm.ribbon.visual.spine_bones.size())
		max_ribbon_history_points = maxi(max_ribbon_history_points, scene.storm.ribbon.visual.history.size())
		if "--huntian-demo" in OS.get_cmdline_user_args() and scene.storm.ribbon_hits in [1, 3, 5] and ribbon_skin_poses.size() < (scene.storm.ribbon_hits+1)/2:
			var visual: Node3D = scene.storm.ribbon.visual
			var bones: Dictionary = {}
			for bone in visual.spine_bones:
				var pose: Transform3D = visual.skeleton.global_transform*visual.skeleton.get_bone_global_pose(bone)
				bones[visual.skeleton.get_bone_name(bone)] = [pose.basis.x.x, pose.basis.y.x, pose.basis.z.x, pose.origin.x, pose.basis.x.y, pose.basis.y.y, pose.basis.z.y, pose.origin.y, pose.basis.x.z, pose.basis.y.z, pose.basis.z.z, pose.origin.z, 0, 0, 0, 1]
			var targets: Array = []
			for enemy: Node3D in scene.enemies.get_children():
				targets.append([enemy.position.x, enemy.position.y, enemy.position.z])
			ribbon_skin_poses.append({"hits": scene.storm.ribbon_hits, "bones": bones, "targets": targets})
		var slots := 0
		for emitter: GPUParticles3D in scene.storm.ribbon.path.find_children("*", "GPUParticles3D", true, false):
			slots += emitter.amount
		max_ribbon_particle_slots = maxi(max_ribbon_particle_slots, slots)

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
	enemy.configure(kind, 0, 0, false, kind == "boss")
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
	if "--huntian-demo" in OS.get_cmdline_user_args():
		await huntian_demo()
		return
	if "--huntian-only" in OS.get_cmdline_user_args():
		await check_huntian_body()
		await check_huntian_ling()
		check(ribbon_checks_completed, "Huntian Ling checks finish without a skipped runtime error")
		finish_report()
		return
	check(scene.player.progression == scene.progression and scene.storm.player == scene.player and scene.storm.progression == scene.progression and scene.storm.feedback == scene.feedback, "Combat dependencies are explicitly supplied by the scene")
	check(scene.orbs.player == scene.player and scene.orbs.progression == scene.progression and scene.orbs.feedback == scene.feedback and scene.orbs.camera == scene.camera, "Periodic orb dependencies are explicitly supplied by the scene")
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
	await check_skill_upgrade_ui()
	await check_automatic_combat()
	await check_active_skills()
	await check_incoming_damage()
	await check_pickups_and_choices()
	await check_pause()
	await check_zhaotian_seal()
	check(seal_checks_completed, "Zhaotian Seal checks finish without a skipped runtime error")
	await check_auxiliary_skills()
	check(sword_checks_completed, "The automatic sword integration checks reach completion without a skipped runtime error")
	await check_thunder_orbs()
	check(orb_checks_completed, "The periodic-orb integration checks reach completion without a skipped runtime error")
	await check_taiji_aura()
	check(aura_checks_completed, "The Taiji aura checks reach completion without a skipped runtime error")
	await check_huntian_body()
	await check_huntian_ling()
	check(ribbon_checks_completed, "Huntian Ling checks finish without a skipped runtime error")
	await check_crowd_hits()
	await check_restart()
	await check_waves_and_endings()
	if performance_enemies > 0:
		await check_short_load()
	finish_report()

func huntian_demo() -> void:
	# The normal arena, enemies, skill scheduler and hit animations, not a
	# second visual-only implementation. Only deterministic fixture setup lives here.
	await prepare(false)
	scene.shake_enabled = false
	scene.progression.skills.huntian_ling = 5
	for point: Vector2 in [Vector2(-3,-1.6), Vector2(-4.6,-3.7), Vector2(-2.2,-5.2), Vector2(0.5,-4.6), Vector2(3.1,-5), Vector2(4.5,-2.6), Vector2(2.1,-1.4)]:
		enemy_at(Vector3(point.x,0.04,point.y), 1000000.0)
	scene.hud.notice = "混天绫演示 · 头部绕敌 / 绫身沿轨迹跟随 · Esc 暂停"
	scene.hud.notice_left = 3600.0
	if headless:
		recording = true
		check(await until(func() -> bool: return scene.storm.ribbon_hits == 7, 6.0), "The real arena demo chains seven separated targets")
		scene.storm.ribbon_cooldown = 100.0
		check(max_ribbon_spine_bones == 65 and max_ribbon_history_points > 80, "The demo bends one continuous 65-bone skin along the actual travelled multi-target route")
		check(await until(func() -> bool: return scene.storm.ribbon.is_empty(), 2.0), "The demo chain cleans up completely after returning")
		recording = false
		finish_report()

func check_huntian_body() -> void:
	await prepare(false)
	var visual := scene.storm.RIBBON_VISUAL.new() as Node3D
	visual.feedback = scene.feedback
	scene.storm.add_child(visual)
	visual.set_physics_process(false)
	visual.begin(Vector3(0, 1, 8))
	for i in range(1, 121):
		visual._append_point(Vector3(0, 1, 8-float(i)*0.1))
	visual._pose_body()
	var saved: Array[Transform3D] = []
	for bone in visual.spine_bones:
		saved.append(visual.skeleton.get_bone_global_pose(bone))
	visual.rotation.y = PI/2.0
	visual.position = Vector3(7, 2, -4)
	visual._pose_body()
	var isolated: bool = visual.model.global_transform.is_equal_approx(Transform3D.IDENTITY)
	for i in visual.spine_bones.size():
		isolated = isolated and saved[i].is_equal_approx(visual.skeleton.get_bone_global_pose(visual.spine_bones[i]))
	check(isolated, "Moving or turning the head root does not rigidly rotate or translate the cloth skin")
	for i in range(1, 31):
		visual._append_point(Vector3(float(i)*0.1, 1, -4))
	visual._pose_body()
	var tail: Vector3 = visual.skeleton.get_bone_global_pose(visual.spine_bones[0]).origin
	var middle: Vector3 = visual.skeleton.get_bone_global_pose(visual.spine_bones[32]).origin
	var tip: Vector3 = visual.skeleton.get_bone_global_pose(visual.spine_bones[64]).origin
	check(tail.distance_to(Vector3(0, 1, 5)) < 0.04 and middle.distance_to(Vector3(0, 1, -1)) < 0.04 and tip.distance_to(Vector3(3, 1, -4)) < 0.04, "After a right-angle head turn the tail and middle still follow their own positions on the old leg")
	var retained: Array = visual.history.duplicate()
	visual.age += 5.0
	visual._pose_body()
	check(visual.history == retained and visual.skeleton.get_bone_global_pose(visual.spine_bones[0]).origin.is_equal_approx(tail), "Five seconds without head travel cannot expire or straighten the tail")
	for i in range(31, 151):
		visual._append_point(Vector3(float(i)*0.1, 1, -4))
	visual._pose_body()
	tail = visual.skeleton.get_bone_global_pose(visual.spine_bones[0]).origin
	check(tail.distance_to(Vector3(3, 1, -4)) < 0.04, "The tail takes the same corner only after one full cloth length of head travel")
	var binding_ok: bool = visual.spine_bones.size() == 65 and visual.meshes.size() == 1 and visual.meshes[0].skin != null
	for surface in visual.meshes[0].mesh.get_surface_count():
		var arrays: Array = visual.meshes[0].mesh.surface_get_arrays(surface)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		binding_ok = binding_ok and not weights.is_empty()
		for i in range(0, weights.size(), 4):
			binding_ok = binding_ok and absf(weights[i]+weights[i+1]+weights[i+2]+weights[i+3]-1.0) < 0.001
	check(binding_ok, "Cloth, gold edges and cloud embroidery all have normalized native skin weights on the same mesh")
	check(visual.history.size() <= 384 and visual.meshes[0].custom_aabb.has_point(tail), "History is bounded and the deformed tail stays inside the updated mesh culling bounds")
	visual.queue_free()
	await physics_wait(0.02)

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
	var sword_definition := first.skill("swords")
	var orb_definition := first.skill("thunder_orb")
	var authored_growth := true
	for rank in range(1, 6):
		authored_growth = authored_growth and sword_definition.count_at(rank) == rank + 1 and orb_definition.count_at(rank) == [1, 1, 2, 2, 3][rank - 1]
	check(authored_growth and orb_definition.element == DamageRules.Element.DARK and orb_definition.kind == DamageRules.Kind.MAGICAL and orb_definition.radius_at(5) > orb_definition.radius_at(1) and orb_definition.visual_scale_at(5) > orb_definition.visual_scale_at(1), "Five ranks grow swords from two to six and dark-magic black holes from one to three with larger coverage")
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
	await prepare(false)
	var capsule := scene.player.get_node("CollisionShape3D").shape as CapsuleShape3D
	check(scene.player.visual.scale.is_equal_approx(Vector3.ONE) and is_equal_approx(capsule.radius, 0.28) and is_equal_approx(capsule.height, 1.27), "The player model is reduced from 1.3x to 1.0x with a matching smaller body collider")
	Input.action_press("move_right")
	await physics_wait(0.4)
	var movement_speed := Vector2(scene.player.velocity.x, scene.player.velocity.z).length()
	Input.action_release("move_right")
	check(is_equal_approx(scene.player.stats.move_speed, 6.8) and absf(movement_speed - 6.8) < 0.05, "Real movement reaches the increased 6.8-unit base speed through the existing stat")
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

func check_skill_upgrade_ui() -> void:
	await prepare(false)
	scene.progression.skills.swords = 4
	scene.progression.skills.thunder_orb = 4
	scene.progression.skills.meteor = 1
	var options: Array[Dictionary] = []
	var pool: Array[Dictionary] = scene.progression._available_choices()
	for desired: String in ["skill_swords", "skill_thunder_orb", "element_fire"]:
		for option: Dictionary in pool:
			if option.id == desired:
				options.append(option)
	check(options.size() == 3 and options[0].description.contains("5 → 6") and options[1].description.contains("2 → 3") and options[1].description.contains("暗") and options[2].description.contains("雷缚珠"), "Upgrade cards expose sword and orb counts, larger coverage and the protected dark element")
	scene.progression.choices = options
	scene.progression.pending_levels = 1
	scene._on_choices(options)
	if not headless:
		var original := DisplayServer.window_get_size()
		DisplayServer.window_set_size(Vector2i(960, 600))
		await physics_wait(0.1)
		await capture("skill-upgrades-960x600")
		var content_fits := true
		for i in scene.hud._choice_buttons.size():
			var box: Rect2 = scene.hud._choice_buttons[i].get_global_rect()
			var description: Label = scene.hud._choice_labels[i].description
			content_fits = content_fits and box.encloses(description.get_global_rect())
		check(content_fits, "The longer new skill descriptions stay within their native cards at the minimum window size")
		DisplayServer.window_set_size(original)
		await physics_wait(0.1)
	# Use the connected native button signal, not a direct write to the skill rank.
	scene.hud._choice_buttons[1].pressed.emit()
	check(scene.state == "playing" and scene.progression.skill_level("thunder_orb") == 5, "Selecting the new skill card immediately upgrades its real run state and resumes play")
	# HUD labels intentionally refresh every 80 ms; wait for that existing presentation tick.
	var hud_updated := await until(func() -> bool: return scene.hud._skill_widgets.size() == 7 and scene.hud._skill_widgets.thunder_orb.title.text.contains("Lv.5"), 0.25)
	check(hud_updated, "The fifth HUD slot reflects the selected skill rank on its normal presentation refresh")

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

func model_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null:
			bounds = bounds.merge((root.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb())
	return bounds

func horizontal_formation() -> bool:
	if not is_instance_valid(scene.storm.halo) or scene.storm.blades.is_empty():
		return false
	var centered: bool = scene.storm.halo.global_position.distance_to(scene.player.global_position) < 0.01
	var center := Vector3.ZERO
	for index in scene.storm.blades.size():
		var blade: Node3D = scene.storm.blades[index]
		var slot: Node3D = scene.storm.slots[index]
		var offset: Vector3 = slot.global_position - scene.player.global_position
		center += offset
		centered = centered and blade.get_parent() == slot and blade.motion == 0 and absf(offset.y - 1.25) < 0.01
		centered = centered and absf(Vector2(offset.x, offset.z).length() - 1.65) < 0.01
		centered = centered and absf(blade.global_basis.y.normalized().dot(Vector3.UP)) < 0.01 and blade.global_basis.z.normalized().dot(Vector3.UP) > 0.99
	return centered and Vector2(center.x, center.z).length() < 0.01

func check_zhaotian_seal() -> void:
	await prepare(false)
	var definition: SkillDefinition = scene.progression.skill("meteor")
	check(definition.title == "罗宣·照天印" and definition.resource_path.ends_with("zhaotian_seal.tres") and not FileAccess.file_exists("res://data/skills/meteor.tres"), "The legacy meteor resource is replaced, not duplicated; the stable run-state ID is preserved")
	check(definition.kind == DamageRules.Kind.MAGICAL and definition.element == DamageRules.Element.FIRE and is_equal_approx(definition.coefficient_at(5), 2.304), "All five seal ranks retain the existing fixed-fire magical damage progression")
	scene.progression.skills.meteor = 1
	scene.player.stats.magic_attack = 80.0
	scene.player.stats.element = DamageRules.Element.DARK
	scene.player.stats.element_bonus[0] = 0.2
	scene.player.stats.element_bonus[3] = 0.8
	var target := enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	target.stats.resistances = [0.3, 0.0, 0.0, -0.5]
	var nearby := enemy_at(Vector3(2.2, 0.04, -4.0), 10000.0)
	var outside := enemy_at(Vector3(3.35, 0.04, -4.0), 10000.0)
	scene.storm._call_meteor(target)
	var flight: Dictionary = scene.storm.meteors[0]
	var seal: Node3D = flight.node
	var seal_id := seal.get_instance_id()
	var shard := seal.model.find_child("Shard_00", true, false) as Node3D
	check(seal.model.scene_file_path.ends_with("zhaotian_seal.glb") and seal.model.find_children("*", "MeshInstance3D", true, false).size() == 15 and is_instance_valid(shard), "The falling seal loads the actual Blender asset with twelve stone and three knob chunks")
	check(is_instance_valid(seal.animation) and seal.animation.has_animation("SealShatter") and not seal.animation.is_playing(), "The native imported fracture clip stays intact until actual ground contact")
	if not is_instance_valid(shard) or not is_instance_valid(seal.animation):
		return
	var slots := 0
	for emitter: GPUParticles3D in seal.emitters:
		slots += emitter.amount
	check(seal.emitters.size() == 3 and slots == 68 and not seal.energy_meshes.is_empty(), "Three directional flight particle layers use 68 slots and the existing energy shader")
	check(is_equal_approx(flight.warning.mesh.size.x * 0.5 * 0.972, flight.radius), "The fixed warning edge matches the actual seal damage radius")
	await physics_wait(0.70)
	check(target.health == 10000.0 and not seal.landed and not seal.animation.is_playing(), "Suspended charge and accelerating descent cannot deal damage or fracture early")
	var landed := await until(func() -> bool: return seal.landed, 0.35)
	check(landed and seal.global_position.distance_to(flight.position) < 0.001 and scene.storm.meteors.is_empty(), "One physics-owned contact snaps the seal to the ground and retires its flight")
	check(target.health == 9908.0 and nearby.health < 10000.0 and outside.health == 10000.0 and scene.storm.meteor_hits == 2, "Ground impact deals 92 fire-magic damage through shared resistance math and never hits beyond its boundary")
	check(nearby._push.x > 0.0 and nearby._stagger_left > 0.0, "The stamp reuses enemy heavy-hit stagger and pushes outward from its contact point")
	var contact_health := target.health
	var hits: int = scene.storm.meteor_hits
	await physics_wait(0.12)
	var no_wake := true
	for emitter: GPUParticles3D in seal.emitters:
		no_wake = no_wake and not emitter.emitting
	check(no_wake and seal.find_children("Seal*", "GPUParticles3D", true, false).size() == 3 and seal.animation.is_playing(), "Impact stops all wakes, starts three owned burst layers and plays the real fracture clip")
	scene.toggle_pause()
	var paused_age: float = seal.age
	var paused_time: float = seal.animation.current_animation_position
	var paused_pose := shard.transform
	await physics_wait(0.24)
	check(seal.age == paused_age and seal.animation.current_animation_position == paused_time and shard.transform.is_equal_approx(paused_pose), "Pause freezes the fracture pose, model animation and local shader clock together")
	scene.toggle_pause()
	await physics_wait(0.26)
	check(not shard.transform.is_equal_approx(paused_pose) and scene.storm.meteor_hits == hits and target.health == contact_health, "The same visible chunks scatter and tumble without a second damage event")
	await physics_wait(1.15)
	check(not is_instance_id_valid(seal_id) and target.health == contact_health, "All seal chunks, six particle layers and bound effects expire after their animation")
	check(scene.hud._skill_widgets.meteor.title.text.contains("照天印") and scene.hud._skill_widgets.meteor.binding.text.contains("罗宣"), "HUD uses the short seal name and its owner without widening the skill row")
	# Native owners must cancel both the in-flight and the post-contact phases.
	scene.storm._call_meteor(target)
	var cancelled: Node3D = scene.storm.meteors[0].node
	var cancelled_id := cancelled.get_instance_id()
	var warning_id: int = scene.storm.meteors[0].warning.get_instance_id()
	scene.storm.reset()
	await physics_wait(1.0)
	check(not is_instance_id_valid(cancelled_id) and not is_instance_id_valid(warning_id) and target.health == contact_health, "Reset cancels the falling seal, its warning and its pending damage")
	scene.storm._call_meteor(target)
	var stopped: Node3D = scene.storm.meteors[0].node
	var stopped_id := stopped.get_instance_id()
	await until(func() -> bool: return stopped.landed, 1.0)
	scene.storm.active = false
	await physics_wait(0.06)
	check(not is_instance_id_valid(stopped_id), "Disabling auxiliary effects also frees already-landed chunks after the flight list is empty")
	seal_checks_completed = true

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
	target = enemy_at(Vector3(0, 0.04, -10.0), 10000.0)
	target.stats.physical_defense = 10000.0
	target.stats.magic_defense = 10000.0
	scene.progression.skills.swords = 1
	scene.storm.refresh_skills()
	var original_ids := blade_ids()
	check(original_ids.size() == 2 and scene.storm.slots.size() == 2, "Unlocking swords instantiates exactly two source-asset blades")
	var reused := true
	for blade: Node3D in scene.storm.blades:
		reused = reused and blade.scene_file_path == "res://assets/weapons/astral_edge/astral_edge.tscn" and blade.fins.size() == 2 and is_instance_valid(blade.wake) and is_instance_valid(blade.ambient)
	check(reused, "The formation reuses the authored Astral Edge scene, fins, idle particles and trail")
	var new_size: Vector3 = model_bounds(scene.storm.blades[0]).size * scene.storm.BLADE_SCALE
	check(absf(new_size.y - 2.31) < 0.03 and is_equal_approx(scene.storm.blades[0].scale.x, 0.65), "The existing sword is reduced to 65 percent scale, about 2.31 units long")
	await physics_wait(0.3)
	check(horizontal_formation(), "Idle swords lie horizontally in an evenly spaced ring around the player")
	check(scene.storm.volley_count == 0 and target.health == 10000.0, "A target beyond the 8.5-unit range neither launches swords nor receives damage")
	var first_position: Vector3 = scene.storm.slots[0].position
	Input.action_press("move_right")
	await physics_wait(0.25)
	Input.action_release("move_right")
	await physics_wait(0.25)
	check(horizontal_formation() and scene.storm.slots[0].position.distance_to(first_position) > 0.2, "The horizontal ring orbits while following player movement and turning")
	await capture("swords-two-orbiting")
	target.position = Vector3(0, 0.04, -4.0)
	target.hide()
	await physics_wait(0.3)
	check(scene.storm.volley_count == 0, "Hidden enemies inside range do not trigger the automatic swords")
	target.show()
	var launched := await until(func() -> bool: return scene.storm.active_swords == 2, 0.4)
	check(launched and scene.player.attack_count == 0, "Swords launch at an in-range enemy with auto-attack disabled and no swing event")
	if not launched:
		return
	await physics_wait(0.2)
	scene.toggle_pause()
	var paused_blade: Node3D = scene.storm.blades[0]
	var paused_position := paused_blade.global_position
	var paused_clock: float = paused_blade.clock
	var paused_hits: int = scene.storm.sword_hits
	await physics_wait(0.2)
	check(paused_blade.global_position.is_equal_approx(paused_position) and paused_blade.clock == paused_clock and scene.storm.sword_hits == paused_hits, "Pause freezes both automatic sword flight and its reused visual animation")
	scene.toggle_pause()
	var peak := 0
	var continuous := true
	var trail_seen := false
	var trails_aligned := true
	var impact_seen := false
	var surface_flashes := true
	var strike_samples: Dictionary = {}
	var sharp_turns := 0
	var abrupt_accelerations := 0
	var peak_strike_speed := 0.0
	var embedded_frames := 0
	var aligned_stabs := true
	var clean_approaches := true
	var impact_events: Array[int] = [0]
	var directional_flashes: Array[bool] = [true]
	var record_impact: Callable = func(effect: Node) -> void:
		if effect.scene_file_path == "res://assets/weapons/astral_edge/impact.tscn":
			impact_events[0] += 1
			directional_flashes[0] = directional_flashes[0] and effect.direction.y < -0.25
	scene.feedback.child_entered_tree.connect(record_impact)
	var initial_hits: int = scene.storm.sword_hits
	# Shared camera/normal-hit throttling must not swallow these contact flashes.
	scene._impact_left = 10.0
	var upgraded_ids: Array[int] = []
	for attempt in 12:
		if attempt == 4:
			scene.progression.skills.swords = 5
			scene.storm.refresh_skills()
			upgraded_ids = blade_ids()
			check(upgraded_ids.size() == 6 and upgraded_ids[0] == original_ids[0] and upgraded_ids[1] == original_ids[1], "Upgrading during flight adds blades up to six without replacing either original sword")
		for frame in 36:
			await get_tree().physics_frame
			peak = maxi(peak, scene.storm.active_swords)
			for flight: Dictionary in scene.storm.flights:
				continuous = continuous and flight.phase != scene.storm.FlightPhase.RETURN
				trail_seen = trail_seen or flight.blade.history.size() >= 3
				trails_aligned = trails_aligned and flight.blade.wake.global_transform.is_equal_approx(Transform3D.IDENTITY)
				var blade_id: int = flight.blade.get_instance_id()
				var point: Vector3 = flight.follow.global_position
				var previous: Dictionary = strike_samples.get(blade_id, {})
				var speed := 0.0 if previous.is_empty() else point.distance_to(previous.point) * Engine.physics_ticks_per_second
				var tangent: Vector3 = -flight.path.curve.get_point_in(2).normalized() if flight.phase == scene.storm.FlightPhase.APPROACH else flight.through
				if flight.phase == scene.storm.FlightPhase.STRIKE:
					aligned_stabs = aligned_stabs and flight.through.y < -0.25 and flight.blade.global_basis.y.normalized().dot(flight.through) > 0.99
					peak_strike_speed = maxf(peak_strike_speed, speed)
					if not previous.is_empty() and previous.phase == scene.storm.FlightPhase.APPROACH:
						if previous.tangent.dot(flight.through) < 0.65:
							sharp_turns += 1
						if speed > 30.0 and speed > previous.speed * 4.0:
							abrupt_accelerations += 1
					if flight.follow.progress_ratio > 0.999 and speed < 0.01 and flight.blade.to_global(scene.storm.BLADE_CONTACT).distance_to(target.global_position + Vector3.UP * 1.05) < 0.5:
						embedded_frames += 1
				else:
					clean_approaches = clean_approaches and flight.hit_ids.is_empty() and flight.blade.motion == 1
				strike_samples[blade_id] = {"phase": flight.phase, "point": point, "speed": speed, "tangent": tangent}
			for effect in scene.feedback.get_children():
				if effect.scene_file_path == "res://assets/weapons/astral_edge/impact.tscn" and effect.age > 0.0:
					impact_seen = true
					var offset: Vector3 = effect.flash.global_position - effect.global_position
					var toward_camera: Vector3 = (scene.camera.global_position - effect.global_position).normalized()
					surface_flashes = surface_flashes and absf(offset.length() - 0.5) < 0.001 and offset.normalized().dot(toward_camera) > 0.99
	check(continuous and scene.storm.chain_count > 0 and scene.player.attack_count == 0, "Automatic swords continuously chain real passes without any basic attacks or swing refresh")
	check(trail_seen and trails_aligned and impact_seen, "Flight reuses correctly aligned world-space trails and hits instantiate the existing impact scene")
	check(impact_seen and surface_flashes, "Impact flash geometry sits half a unit toward the camera, outside the victim body")
	check(clean_approaches and sharp_turns > 0 and aligned_stabs, "Damage-free curved approaches abruptly turn into blade-aligned diagonal stabs at the body")
	check(abrupt_accelerations > 0 and peak_strike_speed >= 44.0 and peak_strike_speed < 55.0, "Stab movement abruptly accelerates to the authored 48-unit speed without teleporting (peak %.2f)" % peak_strike_speed)
	check(embedded_frames > 0, "The sword holds its embedded contact pose before routing the next attack")
	check(impact_events[0] == scene.storm.sword_hits - initial_hits and impact_events[0] > 0 and directional_flashes[0], "Every actual stab hit emits one matching directional flash even while shared hit accents are throttled")
	scene.feedback.child_entered_tree.disconnect(record_impact)
	await capture("swords-battlefield")
	check(peak > 0 and peak <= 6 and scene.storm.blades.size() == 6, "Automatic volleys never create more than the six physical blades")
	check(scene.storm.sword_hits > 0 and target.health < 10000.0 and scene.storm.meteor_count == 0, "Fixed-damage swords hit through high double defense without unlocking meteor")
	target.position = Vector3(0, 0.04, -12.0)
	var distant_health := target.health
	Input.action_press("move_right")
	await physics_wait(0.25)
	Input.action_release("move_right")
	await until(func() -> bool: return scene.storm.active_swords == 0, 4.0)
	await physics_wait(0.25)
	check(scene.storm.active_swords == 0 and blade_ids() == upgraded_ids and horizontal_formation() and target.health == distant_health, "Leaving range returns the same six swords to the moving horizontal ring and stops damage")
	await capture("swords-six-orbiting")
	target.global_position = scene.player.global_position + Vector3.FORWARD * 10.0
	scene.player.stats.range_multiplier = 1.5
	scene.progression.skills.meteor = 1
	scene.storm.meteor_chance = 1.0
	check(await until(func() -> bool: return scene.storm.active_swords > 0, 0.4), "Increasing the existing range stat automatically reacquires a previously out-of-range enemy")
	await physics_wait(1.4)
	check(target.health < distant_health and scene.player.attack_count == 0 and scene.storm.meteor_rolls == 0, "Autonomous sword damage never rolls even an unlocked guaranteed meteor")
	target.queue_free()
	check(await until(func() -> bool: return scene.storm.active_swords == 0, 1.2), "Freed targets safely release all returning swords")
	check(horizontal_formation() and blade_ids() == upgraded_ids, "Target loss retains all six original sword instances and restores their idle visual state")
	await physics_wait(0.5)
	var cleared_impacts := true
	for effect in scene.feedback.get_children():
		cleared_impacts = cleared_impacts and effect.scene_file_path != "res://assets/weapons/astral_edge/impact.tscn"
	check(cleared_impacts, "Directional impact flashes free themselves after the burst instead of accumulating")
	scene.player.enabled = false
	await physics_wait(0.05)
	check(not scene.storm.halo.visible and scene.storm.active_swords == 0, "Disabling the player hides the formation and prevents automatic attacks")
	# At 30 physics ticks the burst advances ~1.6 units per tick; point samples can tunnel.
	await prepare(false)
	var physics_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 30
	target = enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	scene.progression.skills.swords = 1
	await physics_wait(1.1)
	check(scene.storm.sword_hits > 0 and target.health < 10000.0, "Native swept contact still hits during the sudden stab at only 30 physics ticks per second")
	Engine.physics_ticks_per_second = physics_rate
	await prepare(false)
	target = enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	target.stats.dodge_chance = 1.0
	scene.progression.skills.swords = 1
	impact_events[0] = 0
	scene.feedback.child_entered_tree.connect(record_impact)
	await physics_wait(1.2)
	check(scene.storm.chain_count > 0 and scene.storm.sword_hits == 0 and impact_events[0] == 0, "Dodged stabs neither apply damage nor emit a false impact flash")
	scene.feedback.child_entered_tree.disconnect(record_impact)
	sword_checks_completed = true

func check_huntian_ling() -> void:
	await prepare(false)
	var first := enemy_at(Vector3(0, 0.04, -3.0), 10000.0)
	var second := enemy_at(Vector3(2.2, 0.04, -3.8), 10000.0)
	var third := enemy_at(Vector3(-1.8, 0.04, -4.0), 10000.0)
	var isolated := enemy_at(Vector3(5.8, 0.04, 2.0), 10000.0)
	await physics_wait(0.15)
	check(scene.storm.ribbon.is_empty() and scene.storm.ribbon_casts == 0, "Locked Huntian Ling neither creates a model nor consumes cooldown")
	var definition: SkillDefinition = scene.progression.skill("huntian_ling")
	var growth := definition.title == "哪吒·混天绫" and definition.kind == DamageRules.Kind.MAGICAL and definition.element == DamageRules.Element.NONE
	for level in range(1, 6):
		growth = growth and definition.count_at(level) == level + 2 and is_equal_approx(definition.coefficient_at(level), 0.88 * (1.0 + 0.2 * (level - 1)))
	check(growth, "Five authored ranks grow one sash from three to seven distinct targets, with neutral magic damage")
	var options: Array[Dictionary] = []
	for option: Dictionary in scene.progression._available_choices():
		if option.id == "skill_huntian_ling":
			options.append(option)
	check(options.size() == 1 and options[0].description.contains("连锁目标 3"), "The existing choice pool offers Huntian Ling with explicit chain count")
	scene.progression.choices = options
	scene.progression.pending_levels = 1
	scene._on_choices(options)
	scene.hud._choice_buttons[0].pressed.emit()
	check(scene.progression.skill_level("huntian_ling") == 1 and scene.state == "playing", "The connected upgrade button unlocks Huntian Ling without another loadout system")
	scene.player.stats.magic_attack = 100.0
	scene.player.stats.element = DamageRules.Element.FIRE
	scene.player.stats.element_bonus[0] = 0.8
	scene.player.stats.life_steal = 0.1
	scene.player.health = 40.0
	for target in [first, second, third]:
		target.stats.magic_defense = 25.0
	scene.progression.skills.ghost = 1
	scene.player.request_ghost()
	scene.progression.skills.meteor = 1
	scene.storm.meteor_chance = 1.0
	var received: Array[Dictionary] = []
	var record: Callable = func(target: Node3D, _point: Vector3, result: Dictionary, _heavy: bool, source: String) -> void:
		if source == "混天绫":
			received.append({"id": target.get_instance_id(), "damage": result.damage, "element": result.element})
	scene.player.hit_confirmed.connect(record)
	var launched := await until(func() -> bool: return not scene.storm.ribbon.is_empty(), 0.3)
	check(launched and scene.storm.ribbon_casts == 1 and scene.player.attack_count == 0, "The sash autonomously launches once without a player swing")
	if not launched:
		scene.player.hit_confirmed.disconnect(record)
		return
	scene.storm.ribbon_cooldown = 100.0
	var flight: Dictionary = scene.storm.ribbon
	var visual: Node3D = flight.visual
	var visual_id := visual.get_instance_id()
	var path_id: int = flight.path.get_instance_id()
	var mesh := visual.model.find_child("HuntianSilk", true, false) as MeshInstance3D
	check(visual.model.scene_file_path.ends_with("huntian_ling.glb") and mesh != null and mesh.mesh.get_surface_count() == 3 and mesh.skin != null and mesh.mesh.get_blend_shape_count() == 0, "The runtime uses the continuous silk GLB with three skinned material surfaces, not whole-model morph swaps")
	check(visual.spine_bones.size() == 65 and visual.skeleton.get_bone_count() == 66 and visual.BODY_LENGTH == 12.0, "A stationary root and 65 independent native spine bones carry the twelve-metre cloth")
	var particle_ids: Array[int] = []
	var slots := 0
	for particles: GPUParticles3D in visual.emitters:
		particle_ids.append(particles.get_instance_id())
		slots += particles.amount
	check(visual.emitters.size() == 4 and slots == 132, "Four stronger native trail layers use a fixed 132-slot budget")
	await physics_wait(0.07)
	var point: Vector3 = flight.follow.global_position
	var age: float = visual.age
	var cooldown: float = scene.storm.ribbon_cooldown
	var bone_pose: Transform3D = visual.skeleton.get_bone_global_pose(visual.spine_bones[50])
	var history_count: int = visual.history.size()
	scene.toggle_pause()
	await physics_wait(0.20)
	check(flight.follow.global_position.is_equal_approx(point) and visual.age == age and visual.skeleton.get_bone_global_pose(visual.spine_bones[50]).is_equal_approx(bone_pose) and visual.history.size() == history_count and scene.storm.ribbon_cooldown == cooldown and received.is_empty(), "Pause freezes the head, actual skin pose, retained path, local shader clock and pending contact")
	scene.toggle_pause()
	scene.progression.skills.huntian_ling = 5
	scene.player.stats.range_multiplier = 1.4
	scene.storm.refresh_skills()
	check(flight.visual.get_instance_id() == visual_id and flight.remaining == 2 and is_equal_approx(flight.coefficient, 0.88) and is_equal_approx(flight.jump_range, 4.6), "Mid-flight upgrades keep the same sash and the original three-target damage/range snapshot")
	await until(func() -> bool: return scene.storm.ribbon.phase == "strike", 0.8)
	var entry: Vector3 = flight.follow.global_position
	await physics_wait(0.06)
	check(visual.coiling and flight.follow.global_position.distance_to(entry) > 0.2 and received.is_empty(), "The real head keeps moving around its victim before the contact beat, instead of pausing for a whole-body morph")
	check(await until(func() -> bool: return scene.storm.ribbon_hits == 3, 3.0), "A single physical sash completes three sequential real contacts")
	var body_targets := 0
	for target in [first, second, third]:
		for bone in visual.spine_bones:
			var position: Vector3 = visual.skeleton.get_bone_global_pose(bone).origin
			if position.distance_to(target.global_position+Vector3.UP*0.95) < 0.9:
				body_targets += 1
				break
	check(body_targets == 3 and visual.history.size() > 80 and visual.meshes.size() == 1, "The same physical cloth simultaneously spans all three victims without cloned coil meshes")
	bone_pose = visual.skeleton.get_bone_global_pose(visual.spine_bones[20])
	history_count = visual.history.size()
	scene.toggle_pause()
	await physics_wait(0.15)
	check(visual.skeleton.get_bone_global_pose(visual.spine_bones[20]).is_equal_approx(bone_pose) and visual.history.size() == history_count and received.size() == 3, "Pause also freezes the real cloth spanning multiple victims without extra hits")
	scene.toggle_pause()
	var ids: Array[int] = []
	var accurate := received.size() == 3
	for result: Dictionary in received:
		accurate = accurate and result.damage == 70 and result.element == DamageRules.Element.NONE and not ids.has(result.id)
		ids.append(result.id)
	check(accurate and first.health == 9930.0 and second.health == 9930.0 and third.health == 9930.0 and isolated.health == 10000.0, "Each chained victim loses 70 HP once through shared magic defense math; fire enchantment, ghost and the remote cluster add no phantom hits")
	check(scene.player.health > 40.0 and scene.storm.meteor_rolls == 0 and scene.storm.sword_hits == 0, "Chain hits reuse life steal and never recursively roll swords or the guaranteed meteor")
	check(is_instance_valid(visual) and visual.get_instance_id() == visual_id and first._stagger_left > 0.0, "The same deformed model attacks every target and reuses the enemy hit/stagger animation")
	var same_emitters := true
	for i in visual.emitters.size():
		same_emitters = same_emitters and visual.emitters[i].get_instance_id() == particle_ids[i]
	check(same_emitters, "Jumping preserves the primary model and all four trail emitters")
	var live_contact_layers: int = flight.path.find_children("*", "GPUParticles3D", true, false).size()
	check(live_contact_layers >= 7, "A confirmed hit adds gold sparks, red silk fragments and a sparse dust burst")
	Input.action_press("move_right")
	await physics_wait(0.32)
	Input.action_release("move_right")
	if not scene.storm.ribbon.is_empty() and scene.storm.ribbon.phase == "return":
		check(scene.storm.ribbon.path.curve.get_point_position(1).distance_to(scene.player.global_position + Vector3.UP) < 0.10, "Return path tracks the moving player's current position")
	check(await until(func() -> bool: return scene.storm.ribbon.is_empty(), 1.6), "The completed chain returns and cleanly dissolves without re-hitting its first enemy")
	await physics_wait(0.04)
	check(not is_instance_id_valid(visual_id) and not is_instance_id_valid(path_id), "All cloth, trail, burst and path nodes are released after the visual tail")
	check(received.size() == 3, "The following body and retraction do not cause duplicate damage")
	scene.player.hit_confirmed.disconnect(record)
	await until(func() -> bool: return scene.hud._skill_widgets.huntian_ling.title.text.contains("Lv.5"), 0.2)
	check(scene.hud._skill_widgets.huntian_ling.title.text.contains("混天绫") and scene.hud._skill_widgets.huntian_ling.binding.text.contains("哪吒"), "HUD names Nezha and the sash without forcing the full title into the compact slot")
	var offers_maxed := false
	for option: Dictionary in scene.progression._available_choices():
		offers_maxed = offers_maxed or option.id == "skill_huntian_ling"
	check(not offers_maxed, "A maximum-rank sash leaves the upgrade pool")

	await prepare(false)
	scene.progression.skills.huntian_ling = 5
	await physics_wait(0.15)
	check(scene.storm.ribbon_casts == 0 and scene.storm.ribbon_cooldown == 0.0, "No enemy means no empty cast or wasted sash cooldown")
	first = enemy_at(Vector3(0, 0.04, -12.0), 10000.0)
	await physics_wait(0.1)
	check(scene.storm.ribbon_casts == 0, "Initial acquisition respects the configured 8.5-unit range")
	first.position = Vector3(0, 0.04, -4.0)
	first.hide()
	await physics_wait(0.1)
	check(scene.storm.ribbon_casts == 0, "Hidden enemies cannot start a chain")
	first.show()
	var camera_size: float = scene.camera.size
	scene.camera.size = 2.0
	await physics_wait(0.1)
	check(scene.storm.ribbon_casts == 0, "Off-camera enemies inside range cannot start a chain")
	scene.camera.size = camera_size
	first.stats.dodge_chance = 1.0
	await until(func() -> bool: return scene.storm.ribbon_casts == 1, 0.2)
	scene.storm.ribbon_cooldown = 100.0
	await until(func() -> bool: return not scene.storm.ribbon.is_empty() and scene.storm.ribbon.phase == "return", 1.5)
	check(scene.storm.ribbon_hits == 0 and first.health == 10000.0 and scene.storm.ribbon.visited.size() == 1 and scene.storm.ribbon.path.find_children("*", "GPUParticles3D", true, false).size() == 4, "A dodged contact consumes its unique visit without false impact particles or repeated boss farming")
	await until(func() -> bool: return scene.storm.ribbon.is_empty(), 1.3)
	first.stats.dodge_chance = 0.0
	scene.player.stats.cooldown_multiplier = 0.4
	scene.storm.ribbon_cooldown = 0.0
	await until(func() -> bool: return scene.storm.ribbon_casts == 2, 0.2)
	check(absf(scene.storm.ribbon_cooldown - definition.cooldown * 0.4) < 0.03, "The existing cooldown multiplier shortens the next sash cycle")
	first.queue_free()
	scene.storm.ribbon_cooldown = 100.0
	check(await until(func() -> bool: return scene.storm.ribbon.is_empty(), 1.4), "A freed in-flight target releases the native path safely")
	check(scene.storm.ribbon_hits == 0, "Target loss cannot damage a stale instance")

	await prepare(false)
	first = enemy_at(Vector3(0, 0.04, -3.0), 10000.0)
	second = enemy_at(Vector3(0, 0.04, -7.9), 10000.0)
	scene.progression.skills.huntian_ling = 5
	await until(func() -> bool: return scene.storm.ribbon_casts == 1, 0.2)
	scene.storm.ribbon_cooldown = 100.0
	await until(func() -> bool: return scene.storm.ribbon.is_empty(), 2.4)
	check(scene.storm.ribbon_hits == 1 and second.health == 10000.0, "A next enemy 4.9 units away is not reached by a 4.6-unit chain jump")
	scene.storm.ribbon_cooldown = 0.0
	await until(func() -> bool: return scene.storm.ribbon_casts == 2, 0.2)
	first.position = Vector3(12, 0.04, 0)
	second.hide()
	scene.storm.ribbon_cooldown = 100.0
	await until(func() -> bool: return scene.storm.ribbon.is_empty(), 1.4)
	check(scene.storm.ribbon_hits == 1, "A fleeing target outside range cancels its pending hit")

	await prepare(false)
	var rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 30
	for i in 7:
		enemy_at(Vector3((i % 3 - 1) * 1.4, 0.04, -2.8 - floorf(float(i) / 3.0) * 1.4), 10000.0)
	scene.progression.skills.huntian_ling = 5
	await until(func() -> bool: return scene.storm.ribbon_casts == 1, 0.3)
	scene.storm.ribbon_cooldown = 100.0
	check(await until(func() -> bool: return scene.storm.ribbon_hits == 7, 6.0), "At 30 physics ticks, rank five still resolves exactly seven sequential native contacts")
	Engine.physics_ticks_per_second = rate
	var cancelled_id: int = scene.storm.ribbon.visual.get_instance_id()
	scene.restart()
	scene.director.enabled = false
	scene.director._spawn_timer.stop()
	await physics_wait(0.05)
	check(not is_instance_id_valid(cancelled_id) and scene.storm.ribbon.is_empty() and scene.storm.ribbon_casts == 0 and scene.storm.ribbon_hits == 0 and scene.storm.ribbon_cooldown == 0.0 and scene.progression.skill_level("huntian_ling") == 0, "Restart clears all chain nodes, counters, cooldown and unlocked rank")
	await prepare(false)
	first = enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	scene.progression.skills.huntian_ling = 1
	await until(func() -> bool: return not scene.storm.ribbon.is_empty(), 0.2)
	cancelled_id = scene.storm.ribbon.visual.get_instance_id()
	scene.player.receive_damage({"damage": 10000.0, "critical": false, "dodged": false}, Vector3.ZERO)
	await physics_wait(0.08)
	check(scene.state == "lost" and scene.storm.ribbon.is_empty() and not is_instance_id_valid(cancelled_id) and first.health == 10000.0, "Player death cancels the travelling sash before a delayed hit can land")
	await prepare(false)
	first = enemy_at(Vector3(0, 0.04, -3.0), 1.0, "boss")
	scene.progression.skills.huntian_ling = 1
	check(await until(func() -> bool: return scene.state == "won", 1.5), "A real chain contact can defeat the boss through the existing victory signal")
	await physics_wait(0.06)
	check(scene.storm.ribbon.is_empty(), "Boss victory releases the lethal chain after the damage callback")
	ribbon_checks_completed = true

func check_thunder_orbs() -> void:
	await prepare(false)
	var target := enemy_at(Vector3(0, 0.04, -4.0), 10000.0)
	await physics_wait(0.15)
	check(scene.orbs.orbs.is_empty() and scene.orbs.cast_count == 0, "The locked black-hole passive cannot fire")
	scene.player.stats.magic_attack = 80.0
	scene.player.stats.element = DamageRules.Element.FIRE
	scene.player.stats.element_bonus[0] = 0.8
	scene.player.stats.element_bonus[2] = 0.9
	scene.player.stats.element_bonus[3] = 0.2
	scene.player.stats.life_steal = 0.1
	scene.player.health = 50.0
	target.stats.resistances = [-0.2, 0.0, -0.5, 0.4]
	scene.progression.skills.ghost = 1
	scene.player.request_ghost()
	scene.progression.skills.thunder_orb = 1
	scene.orbs.refresh_skills()
	var received: Array[Dictionary] = []
	var record_hit: Callable = func(_target: Node3D, _point: Vector3, result: Dictionary, _heavy: bool, source: String) -> void:
		if source == "雷缚珠":
			received.append(result.duplicate())
	scene.player.hit_confirmed.connect(record_hit)
	var launched := await until(func() -> bool: return scene.orbs.cast_count == 1, 0.3)
	check(launched and scene.orbs.orbs.size() == 1 and scene.player.attack_count == 0, "A black-hole orb casts without a basic attack")
	if not launched or scene.orbs.orbs.is_empty():
		scene.player.hit_confirmed.disconnect(record_hit)
		return
	var orb: Node3D = scene.orbs.orbs[0]
	var start: Vector3 = orb.global_position
	var orbit_visual := orb._visual.find_child("OuterOrbit", true, false) as Node3D
	var initial_basis := orbit_visual.basis
	await physics_wait(0.25)
	check(orb.phase == orb.Phase.FLIGHT and orb.global_position.distance_to(start) > 0.5 and is_equal_approx(orb.current_radius, 0.72), "The compact orb travels before contact without applying its full field")
	check(orb._visual.scene_file_path.ends_with("thunder_orb.glb") and orb._visual.find_children("*", "MeshInstance3D", true, false).size() == 9 and orb._animation.is_playing(), "The real projectile uses the Blender GLB, nine mesh batches and native orbit animation")
	check(not orbit_visual.basis.is_equal_approx(initial_basis), "The imported orbit animation actually rotates the modeled accretion layers")
	check(orb._trail.emitting and not orb._infall.emitting and not orb._mist.emitting, "Three native particle layers exist and inward particles wait for contact")
	var landed := await until(func() -> bool: return not received.is_empty(), 2.0)
	check(landed and received[0].element == DamageRules.Element.DARK and received[0].damage == 38 and scene.player.ghost_active, "Dark magic reads dark resistance and magic attack, ignoring fire enchantment, light bonuses and ghost")
	check(landed and scene.player.health > 50.0 and target._stagger_left == 0.0 and target._push == Vector3.ZERO, "Dark ticks reuse life steal without knockback or hard stagger")
	check(scene.storm.volley_count == 0 and scene.storm.meteor_rolls == 0, "Black holes never recursively trigger other passives")
	var anchor: Vector3 = orb.global_position
	var impact_radius: float = orb.current_radius
	check(orb.phase == orb.Phase.WELL and orb.speed == 0.0 and impact_radius < orb.radius, "First native contact stops the projectile and starts expansion")
	var hits_before: int = scene.orbs.hit_count
	await physics_wait(0.15)
	check(scene.orbs.hit_count == hits_before and orb.current_radius > impact_radius and orb.current_radius < orb.radius, "Expansion is gradual and damage is not applied every physics tick")
	await physics_wait(0.25)
	check(scene.orbs.hit_count == hits_before + 1, "A persistent overlap is damaged again after the 0.35-second interval")
	await physics_wait(0.12)
	check(orb.global_position == anchor and is_equal_approx(orb.current_radius, 2.6) and is_equal_approx(orb._shape.radius, 2.6), "The center stays anchored while native collision reaches the full 2.6-unit radius")
	check(not orb._trail.emitting and orb._infall.emitting and orb._mist.emitting and orb._lightning.size() == 3, "Impact switches the wake to inward sparks and mist with three purple lightning layers")
	scene.toggle_pause()
	var frozen_life: float = orb.life_left
	var frozen_age: float = orb.age
	var frozen_animation: float = orb._animation.current_animation_position
	var frozen_cooldown: float = scene.orbs.cooldown_left
	var frozen_hits: int = scene.orbs.hit_count
	await physics_wait(0.25)
	check(orb.global_position == anchor and orb.life_left == frozen_life and orb.age == frozen_age and orb._animation.current_animation_position == frozen_animation and scene.orbs.cooldown_left == frozen_cooldown and scene.orbs.hit_count == frozen_hits, "Pause freezes field, shader clock, model animation, life, cooldown and damage")
	scene.toggle_pause()
	var old_radius: float = orb.radius
	var old_coefficient: float = orb.coefficient
	scene.progression.skills.thunder_orb = 5
	scene.orbs.refresh_skills()
	check(orb.radius == old_radius and orb.coefficient == old_coefficient and scene.orbs.cooldown_left == frozen_cooldown, "Upgrade preserves active well snapshots and cooldown")
	scene.orbs.cooldown_left = 0.0
	await physics_wait(0.04)
	check(scene.orbs.cast_count == 2 and scene.orbs.orbs.size() == 4, "Rank five adds three projectiles without replacing the old well")
	if scene.orbs.orbs.size() >= 4:
		var second: Node3D = scene.orbs.orbs[1]
		var third: Node3D = scene.orbs.orbs[2]
		check(is_equal_approx(second.radius, 4.0) and is_equal_approx(second.visual_scale, 1.6), "Rank five has a four-unit field and 160-percent visual scale")
		check(second.global_position.distance_to(third.global_position) > 1.1 and second.direction.dot(third.direction) > 0.999, "Multi-orb lanes use compact bodies, not expanded-field spacing")
		var health_before := target.health
		scene.orbs.contact(target, second)
		scene.orbs.contact(target, third)
		check(is_equal_approx(health_before - target.health, 138.0) and target._push == Vector3.ZERO, "Two orbs deal independent dark damage without outward push")
	scene.player.hit_confirmed.disconnect(record_hit)
	scene.orbs.cooldown_left = 100.0
	await until(func() -> bool: return orb.phase == orb.Phase.COLLAPSE, 4.1)
	check(orb.influence_at(target.global_position) == 0.0 and not target._gravity_wells.has(orb), "Collapse releases control before its visual tail completes")
	check(scene.orbs.orbs.size() == 4 and scene.orbs.orbs[1].phase == orb.Phase.WELL and scene.orbs.orbs[2].phase == orb.Phase.WELL and scene.orbs.orbs[3].phase == orb.Phase.WELL, "All three rank-five lanes actually contact a single target and deploy their fields")
	await until(func() -> bool: return scene.orbs.orbs.is_empty(), 4.5)
	check(scene.orbs.orbs.is_empty(), "All black-hole fields and visual tails expire")
	check((await check_gravity_movement()) == true, "Gravity movement checks reach completion without a skipped runtime error")

	await prepare(false)
	scene.progression.skills.thunder_orb = 1
	scene.orbs.refresh_skills()
	await physics_wait(0.25)
	check(scene.orbs.cast_count == 0 and scene.orbs.cooldown_left == 0.0, "A periodic skill with no visible target does not waste cooldown")
	target = enemy_at(Vector3(0, 0.04, -13), 500.0)
	await physics_wait(0.15)
	check(scene.orbs.cast_count == 0, "Black holes do not launch beyond the targeting range")
	target.position = Vector3(0, 0.04, -4)
	await until(func() -> bool: return not scene.orbs.orbs.is_empty(), 0.3)
	target.position = Vector3(10, 0.04, -4)
	scene.orbs.cooldown_left = 100.0
	await physics_wait(4.4)
	check(scene.orbs.orbs.is_empty(), "A missed projectile expires without creating a field")
	target.position = Vector3(0, 0.04, -4)
	scene.orbs.cooldown_left = 0.0
	await until(func() -> bool: return not scene.orbs.orbs.is_empty(), 0.3)
	orb = scene.orbs.orbs[0]
	await until(func() -> bool: return orb.phase == orb.Phase.WELL, 2.0)
	var death_orbs: Array[int] = []
	for current: Node3D in scene.orbs.orbs:
		death_orbs.append(current.get_instance_id())
	scene.player.receive_damage({"damage": 10000, "dodged": false}, Vector3.ZERO)
	await physics_wait(0.05)
	var expired_on_death: bool = scene.orbs.orbs.is_empty()
	for instance_id in death_orbs:
		expired_on_death = expired_on_death and not is_instance_id_valid(instance_id)
	check(not death_orbs.is_empty() and scene.state == "lost" and expired_on_death and target._gravity_wells.is_empty(), "Player death frees fields and particles and releases control even while the result pauses the tree")
	orb_checks_completed = true

func check_taiji_aura() -> void:
	await prepare(false)
	var aura: Area3D = scene.aura
	check(aura.player == scene.player and aura.feedback == scene.feedback and aura.progression == scene.progression, "The Taiji aura uses the existing explicitly supplied combat dependencies")
	check(not is_instance_valid(aura._visual) and not aura.monitoring and scene.progression.skill_level("taiji_aura") == 0, "A locked aura has no visuals, emitters or active collision")
	var definition: SkillDefinition = scene.progression.skill("taiji_aura")
	var growth_ok := true
	for rank in range(1, 6):
		growth_ok = growth_ok and is_equal_approx(definition.coefficient_at(rank), [0.55, 0.66, 0.77, 0.88, 0.99][rank - 1]) and is_equal_approx(definition.radius_at(rank), [2.6, 2.85, 3.1, 3.35, 3.6][rank - 1])
	check(growth_ok and definition.kind == DamageRules.Kind.MAGICAL and definition.element == DamageRules.Element.LIGHT, "Five authored ranks grow the fixed-light magical aura without changing shared Resource data")
	var target := enemy_at(Vector3(0, 0.04, -1.8), 10000.0)
	var outside := enemy_at(Vector3(2.72, 0.04, 0), 10000.0)
	scene.player.stats.magic_attack = 80.0
	scene.player.stats.element = DamageRules.Element.DARK
	scene.player.stats.element_bonus[2] = 0.2
	scene.player.stats.element_bonus[3] = 0.8
	scene.player.stats.life_steal = 0.1
	scene.player.health = 50.0
	target.stats.resistances = [0.0, 0.0, 0.3, -0.5]
	var options: Array[Dictionary] = []
	for option: Dictionary in scene.progression._available_choices():
		if option.id == "skill_taiji_aura":
			options.append(option)
	check(options.size() == 1 and options[0].title.contains("太上老君") and options[0].description.contains("光"), "The existing choice pool offers the mythology-named aura with its protected light element")
	scene.progression.choices = options
	scene.progression.pending_levels = 1
	scene._on_choices(options)
	scene.hud._choice_buttons[0].pressed.emit()
	check(scene.state == "playing" and scene.progression.skill_level("taiji_aura") == 1 and is_instance_valid(aura._visual), "Choosing the real upgrade button unlocks the formation and resumes play")
	if not is_instance_valid(aura._visual):
		return
	var visual_id: int = aura._visual.get_instance_id()
	var glyphs := aura._model.find_child("Bagua", true, false) as Node3D
	var initial_basis := glyphs.basis
	var received: Array[Dictionary] = []
	var record_hit: Callable = func(_target: Node3D, _point: Vector3, result: Dictionary, _heavy: bool, source: String) -> void:
		if source == "太极图":
			received.append(result.duplicate())
	scene.player.hit_confirmed.connect(record_hit)
	var landed := await until(func() -> bool: return not received.is_empty(), 1.6)
	check(landed and received[0].element == DamageRules.Element.LIGHT and received[0].damage == 40, "Aura pulses use magic attack and light resistance through DamageRules, ignoring dark enchantment")
	check(scene.player.attack_count == 0 and scene.storm.meteor_rolls == 0 and scene.storm.volley_count == 0 and scene.orbs.cast_count == 0, "The aura works without attacks and cannot recursively trigger other passives")
	check(scene.player.health > 50.0 and target._stagger_left == 0.0 and target._push == Vector3.ZERO, "Aura hits retain shared life steal without knockback or hard stagger")
	check(outside.health == 10000.0 and aura.hit_count == 1, "Touching the native cylinder outside the visible 2.6m boundary does not deal damage")
	check(aura._model.scene_file_path.ends_with("taiji_aura.glb") and aura._model.find_children("*", "MeshInstance3D", true, false).size() == 12 and aura._animation.is_playing() and not glyphs.basis.is_equal_approx(initial_basis), "The real formation loads the Blender GLB, 12 material batches and native counter-rotation")
	var particle_slots := 0
	for emitter: GPUParticles3D in aura._emitters:
		particle_slots += emitter.amount
	check(aura._emitters.size() == 4 and particle_slots == 160 and aura._pulse_particles.one_shot, "Four native particle layers share reusable emitters with a bounded 160-slot budget")
	check(scene.hud._skill_widgets.size() == 7 and scene.hud._skill_widgets.taiji_aura.title.text.contains("太极图") and scene.hud._skill_widgets.taiji_aura.binding.text.contains("太上老君"), "The sixth HUD slot exposes the aura ability and its mythological owner without a new HUD system")
	check(aura._boundary.material_override.shader.resource_path == "res://shaders/astral_ring.gdshader" and not aura._energy_meshes.is_empty() and aura._energy_meshes[0].get_surface_override_material(0).shader.resource_path == "res://assets/weapons/astral_edge/energy.gdshader", "Aura materials reuse the existing range and energy shaders")
	var hits_before: int = aura.hit_count
	await physics_wait(0.2)
	check(aura.hit_count == hits_before, "Continuous overlap does not damage on every physics frame")
	scene.toggle_pause()
	var frozen_age: float = aura.age
	var frozen_cd: float = aura.cooldown_left
	var frozen_anim: float = aura._animation.current_animation_position
	await physics_wait(0.25)
	check(aura.age == frozen_age and aura.cooldown_left == frozen_cd and aura._animation.current_animation_position == frozen_anim and aura.hit_count == hits_before, "Pause freezes aura damage, cooldown, shader clock and native model animation")
	scene.toggle_pause()
	scene.progression.skills.taiji_aura = 5
	scene.player.stats.range_multiplier = 1.5
	aura.refresh_skills()
	check(aura._visual.get_instance_id() == visual_id and aura.cooldown_left == frozen_cd and is_equal_approx(aura.radius, 5.4), "Rank/range upgrades resize the same instance without an extra free pulse")
	await physics_wait(0.04)
	check(is_equal_approx(aura._shape.radius, 5.4) and aura._visual.scale == Vector3(5.4, 1.0, 5.4), "Native collision and displayed boundary receive the same upgraded radius")
	aura.cooldown_left = 100.0
	scene.player.position = Vector3(8, 0.04, 0)
	scene.player.facing = Vector3.RIGHT
	await physics_wait(0.06)
	check(is_equal_approx(aura.global_position.x, scene.player.global_position.x) and is_equal_approx(aura.global_position.z, scene.player.global_position.z) and aura.basis.is_equal_approx(Basis.IDENTITY), "The formation follows translation without inheriting facing rotation")
	var health_before: float = target.health
	aura.cooldown_left = 0.0
	await physics_wait(0.04)
	check(target.health == health_before, "Moving the field away cannot leave stale damage at the old center")
	scene.player.hit_confirmed.disconnect(record_hit)
	scene.restart()
	scene.director.enabled = false
	scene.director._spawn_timer.stop()
	await physics_wait(0.05)
	check(not is_instance_id_valid(visual_id) and not is_instance_valid(aura._visual) and aura.pulse_count == 0 and aura.hit_count == 0 and scene.progression.skill_level("taiji_aura") == 0, "Restart releases the model, particle children and all aura run state")

	await prepare(false)
	scene.progression.skills.taiji_aura = 5
	scene.player.stats.cooldown_multiplier = 0.4
	aura.refresh_skills()
	var crowd: Array[ArenaEnemy] = []
	for i in 32:
		var angle := float(i) * TAU / 32.0
		crowd.append(enemy_at(Vector3(cos(angle) * 1.6, 0.04, sin(angle) * 1.6), 10000.0))
	var crowd_hit := await until(func() -> bool: return aura.pulse_count == 1, 0.65)
	var affected := 0
	for enemy in crowd:
		if enemy.health < 10000.0:
			affected += 1
	check(crowd_hit and affected == 32 and aura.hit_count == 32, "One native pulse reaches all 32 enemies once, beyond the old 16-result query limit")
	check(aura.cooldown_left <= 0.48 and aura.cooldown_left > 0.40, "The aura period respects the existing 40-percent cooldown floor")
	await physics_wait(0.12)
	check(aura.hit_count == 32, "The faster high-rank aura still cannot hit the same enemy twice within one pulse")
	var emitter_ids: Array[int] = []
	for emitter: GPUParticles3D in aura._emitters:
		emitter_ids.append(emitter.get_instance_id())
	visual_id = aura._visual.get_instance_id()
	await until(func() -> bool: return aura.pulse_count >= 3, 1.1)
	var same_emitters: bool = aura._visual.get_instance_id() == visual_id
	for i in emitter_ids.size():
		same_emitters = same_emitters and aura._emitters[i].get_instance_id() == emitter_ids[i]
	check(same_emitters and aura.hit_count == 96, "Repeated pulses hit once per cycle and reuse all four original emitters instead of accumulating nodes")
	scene.player.receive_damage({"damage": 10000, "dodged": false}, Vector3.ZERO)
	await physics_wait(0.05)
	var freed := not is_instance_id_valid(visual_id)
	for instance_id in emitter_ids:
		freed = freed and not is_instance_id_valid(instance_id)
	check(scene.state == "lost" and freed and not is_instance_valid(aura._visual), "Death releases all aura particles and visuals even when the result pauses the tree")
	await prepare(false)
	scene.progression.skills.taiji_aura = 1
	aura.refresh_skills()
	var boss := enemy_at(Vector3(0, 0.04, -1.5), 1.0)
	boss.boss = true
	scene.boss = boss
	var survivor := enemy_at(Vector3(1.5, 0.04, 0), 10000.0)
	visual_id = aura._visual.get_instance_id()
	var aura_won := await until(func() -> bool: return scene.state == "won", 1.5)
	await physics_wait(0.05)
	var survivor_health := survivor.health
	await physics_wait(0.1)
	check(aura_won and not is_instance_id_valid(visual_id) and not is_instance_valid(aura._visual) and survivor.health == survivor_health, "An aura boss kill safely ends its own overlap iteration, clears the effect and cannot damage after victory")
	aura_checks_completed = true

func check_gravity_movement() -> bool:
	await prepare(false)
	var target := enemy_at(Vector3(0, 0.04, -4), 10000.0)
	scene.progression.skills.thunder_orb = 1
	scene.orbs.refresh_skills()
	await until(func() -> bool: return not scene.orbs.orbs.is_empty(), 0.3)
	var orb: Node3D = scene.orbs.orbs[0]
	await until(func() -> bool: return orb.phase == orb.Phase.WELL, 2.0)
	scene.orbs.cooldown_left = 100.0
	await physics_wait(0.48)
	var center: Vector3 = orb.global_position
	center.y = 0.04
	var ordinary := enemy_at(center + Vector3(1.8, 0, 0), 10000.0, "charger")
	var elite := enemy_at(center + Vector3(1.8, 0, 0), 10000.0, "charger")
	elite.elite = true
	var boss_target := enemy_at(center + Vector3(1.8, 0, 0), 10000.0, "charger")
	boss_target.boss = true
	var outside := enemy_at(center + Vector3(3.5, 0, 0), 10000.0)
	await physics_wait(0.06)
	check(ordinary._gravity_wells.has(orb) and outside._gravity_wells.is_empty() and outside.health == 10000.0, "The expanded native area includes nearby enemies and excludes enemies outside it")
	for body in [ordinary, elite, boss_target]:
		body._state = ArenaEnemy.State.CHARGE
		body._state_left = 10.0
		body._direction = Vector3.FORWARD
		body._physics_process(1.0 / 120.0)
	check(is_equal_approx(ordinary.velocity.z, -4.5) and ordinary.velocity.x < -2.0 and ordinary.stats.move_speed > 2.0, "Ordinary enemies receive 55-percent slow and inward velocity without changing stats")
	check(is_equal_approx(elite.velocity.z, -8.075) and elite.velocity.x < -0.5 and absf(elite.velocity.x) < absf(ordinary.velocity.x), "Elite slow and pull use 35-percent control strength")
	check(is_equal_approx(boss_target.velocity.z, -10.0) and is_zero_approx(boss_target.velocity.x), "Bosses are immune to slowing and displacement")
	scene.orbs.contact(boss_target, orb)
	check(boss_target.health < 10000.0, "Control immunity does not prevent dark damage")
	ordinary._state = ArenaEnemy.State.APPROACH
	ordinary._attack_left = 100.0
	ordinary.set_physics_process(true)
	var distance_before := ordinary.global_position.distance_to(center)
	await physics_wait(0.22)
	check(ordinary.global_position.distance_to(center) < distance_before - 0.25, "Live AI and native movement pull an enemy closer over multiple ticks")
	ordinary.set_physics_process(false)
	var gravity_targets: Array[Node3D] = [target]
	for i in 2:
		scene.orbs._cast(gravity_targets)
		var extra: Node3D = scene.orbs.orbs.back()
		extra.global_position = orb.global_position
		extra._anchor()
	scene.orbs.cooldown_left = 100.0
	ordinary.global_position = center + Vector3(1.8, 0, 0)
	await physics_wait(0.50)
	ordinary._state = ArenaEnemy.State.CHARGE
	ordinary._state_left = 10.0
	ordinary._direction = Vector3.FORWARD
	ordinary._physics_process(1.0 / 120.0)
	check(ordinary._gravity_wells.size() == 3 and is_equal_approx(ordinary.velocity.z, -4.5) and absf(ordinary.velocity.x) <= orb.PULL_SPEED + 0.001, "Three overlapping wells do not stack slow or exceed the pull-speed cap")
	ordinary.global_position = center + Vector3(4, 0, 0)
	await physics_wait(0.06)
	ordinary._physics_process(1.0 / 120.0)
	check(ordinary._gravity_wells.is_empty() and is_equal_approx(ordinary.velocity.z, -10.0) and is_zero_approx(ordinary.velocity.x), "Leaving the areas restores normal movement")
	scene.orbs._clear_orbs()
	check(elite._gravity_wells.is_empty() and boss_target._gravity_wells.is_empty(), "Cancellation immediately removes every field source from surviving enemies")
	return true

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
	scene.progression.skills.thunder_orb = 5
	scene.storm.refresh_skills()
	scene.orbs.refresh_skills()
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
	var old_orbs: Array[int] = []
	for orb: Node3D in scene.orbs.orbs:
		old_orbs.append(orb.get_instance_id())
	scene.progression.add_experience(100)
	check(scene.state == "choosing" and scene.progression.pending_levels > 0 and not scene.storm.meteors.is_empty() and scene.drops.get_child_count() > 0, "Reset fixture contains pending upgrades, a dropped pickup and in-flight effects")
	scene.restart()
	scene.director.enabled = false
	scene.director._spawn_timer.stop()
	check(scene.state == "playing" and not get_tree().paused and scene.ready_to_play, "Restart synchronously returns the existing scene to play")
	check(scene.enemies.get_child_count() == 0 and scene.drops.get_child_count() == 0 and scene.director.get_alive_count() == 0 and scene.director._pending.is_empty(), "Restart clears all enemy, projectile, drop and scheduled-spawn owners")
	check(scene.storm.active_swords == 0 and scene.storm.meteors.is_empty() and scene.storm.blades.is_empty(), "Restart removes in-flight swords, meteor state and the now-locked formation")
	check(not old_orbs.is_empty() and scene.orbs.orbs.is_empty() and scene.orbs.cast_count == 0 and scene.orbs.cooldown_left == 0.0 and scene.progression.skill_level("thunder_orb") == 0, "Restart clears the new periodic skill, its cast counters, cooldown and locked rank")
	check(scene.progression.level == 1 and scene.progression.xp == 0 and scene.progression.pending_levels == 0 and scene.progression.choices.is_empty(), "Restart clears level, XP and every pending choice")
	check(scene.player.health == scene.player.stats.max_health and not scene.player.dead and not scene.player.ghost_active and scene.player.skill_cooldown == 0.0 and scene.player.ghost_cooldown == 0.0 and scene.defeat_count == 0 and scene.hit_count == 0, "Restart resets health, death, buffs, cooldowns and run counters")
	await physics_wait(0.05)
	var freed := not is_instance_id_valid(enemy_id) and not is_instance_id_valid(old_feedback_id)
	for blade_id: int in old_blades:
		freed = freed and not is_instance_id_valid(blade_id)
	for orb_id: int in old_orbs:
		freed = freed and not is_instance_id_valid(orb_id)
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
	scene.progression.skills.swords = 5
	scene.progression.skills.meteor = 1
	scene.progression.skills.ghost = 1
	scene.progression.skills.thunder_orb = 5
	scene.progression.skills.taiji_aura = 5
	scene.progression.skills.huntian_ling = 5
	scene.player.stats.cooldown_multiplier = 0.4
	scene.storm.refresh_skills()
	scene.orbs.refresh_skills()
	scene.aura.refresh_skills()
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
		"fixture": "Real AI enemies, six swords, rank-five dark wells, light Taiji aura and a seven-target Huntian sash at minimum cooldown, meteor and ghost unlocked; movement and forced actives; elevated health prevents pauses.",
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
		"max_active_orbs": max_active_orbs,
		"aura_particle_emitters": scene.aura._emitters.size(),
		"aura_pulses": scene.aura.pulse_count,
		"aura_hits": scene.aura.hit_count,
		"ribbon_casts": scene.storm.ribbon_casts,
		"ribbon_hits": scene.storm.ribbon_hits,
		"max_ribbon_particle_slots": max_ribbon_particle_slots,
		"max_ribbon_spine_bones": max_ribbon_spine_bones,
		"max_ribbon_history_points": max_ribbon_history_points,
	}
	check(scene.state == "playing" and not get_tree().paused, "The short crowd-load fixture completes without a state lock or unexpected upgrade pause")
	check(max_active_swords <= 6 and max_active_meteors <= 2 and max_active_orbs <= 9, "Crowd-load auxiliary concurrency stays within its authored limits")
	check(scene.aura._emitters.size() == 4 and scene.aura.pulse_count >= 8 and scene.aura.hit_count > 0, "The full-load formation keeps four emitters and continues real damage beside all existing skills")
	check(scene.storm.ribbon_casts > 0 and scene.storm.ribbon_hits > 0 and max_ribbon_particle_slots <= 340 and max_ribbon_spine_bones == 65 and max_ribbon_history_points <= 384, "The full-load sash stays within 340 particle slots, one 65-bone skin and 384 history samples")
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
	var paths: Array[String] = ["res://artifacts/roguelite-verification.json", "res://artifacts/roguelite-verification-%dfps-%s.json" % [requested_fps, mode]]
	if "--huntian-demo" in OS.get_cmdline_user_args():
		report["huntian_demo"] = {"spine_bones": max_ribbon_spine_bones, "history_points": max_ribbon_history_points, "max_particle_slots": max_ribbon_particle_slots}
		var poses := FileAccess.open("res://artifacts/huntian-skin-poses.json", FileAccess.WRITE)
		poses.store_string(JSON.stringify(ribbon_skin_poses))
		paths = ["res://artifacts/huntian-demo-%s.json" % mode]
	elif "--huntian-only" in OS.get_cmdline_user_args():
		paths = ["res://artifacts/huntian-verification-%s.json" % mode]
	for path: String in paths:
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify(report, "\t"))
			output.close()
		else:
			push_error("Could not write verification report: " + path)
	print("ROGUELITE_VERIFICATION ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
