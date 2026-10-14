class_name WaveDirector
extends Node
## A ten-minute authored rhythm. Native timers and scene ownership handle pause/reset.

signal enemy_spawned(enemy: Node3D)
signal boss_spawned(enemy: Node3D)

const ENEMY_SCENE = preload("res://scenes/enemy.tscn")
const ELITE_TIMES := [120.0, 300.0, 480.0]

var player: Node3D
var camera: Camera3D
var enemy_container: Node3D
var arena_radius := 15.8
var duration := 600.0
var elapsed := 0.0
var phase_name := "第1波 · 暖场"
var spawned_total := 0
var enabled := false
var combat_demo := false
var normal_cap := 60
var peak_cap := 80
var rng := RandomNumberGenerator.new()

var _spawn_timer: Timer
var _pending: Array[Dictionary] = []
var _alive: Array[Node3D] = []
var _elite_done: Array[bool] = [false, false, false]
var _boss_scheduled := false
var _spawn_cursor := 0

func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_spawn_timer.timeout.connect(_spawn_tick)
	add_child(_spawn_timer)

func reset() -> void:
	_clear_pending()
	for enemy in _alive:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_alive.clear()
	elapsed = 0.0
	spawned_total = 0
	phase_name = "第1波 · 暖场"
	_elite_done = [false, false, false]
	_boss_scheduled = false
	_spawn_cursor = 0
	enabled = true
	_spawn_timer.start(0.2)

func get_alive_count() -> int:
	return _alive.size()

func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(player) or player.dead:
		return
	if combat_demo:
		elapsed += delta
		phase_name = "全法宝试炼 · 厚血怪持续补充"
		return
	elapsed = minf(elapsed + delta, duration)
	if elapsed >= duration:
		phase_name = "第%d波 · 终局 · 骸骨领主" % (int(duration / 60.0) + 1)
		if not _boss_scheduled:
			_boss_scheduled = true
			_spawn_timer.stop()
			_clear_pending()
			_queue_enemy("boss", true, true)
		return
	var local_time := fmod(elapsed, 60.0)
	var phase := ("暖场" if elapsed < 60.0 else "集结") if local_time < 20.0 else ("增压" if local_time < 46.0 else "喘息")
	phase_name = "第%d波 · %s" % [int(elapsed / 60.0) + 1, phase]
	for i in ELITE_TIMES.size():
		if not _elite_done[i] and elapsed >= ELITE_TIMES[i]:
			_elite_done[i] = true
			_queue_enemy("charger" if i != 1 else "ranged", true)

func _spawn_tick() -> void:
	if not enabled or not is_instance_valid(player) or player.dead or (not combat_demo and elapsed >= duration):
		return
	var stage := 0 if combat_demo else int(elapsed / 60.0)
	var local_time := fmod(elapsed, 60.0)
	var pressure := local_time >= 20.0 and local_time < 46.0
	var rest := local_time >= 46.0
	var cap := peak_cap if pressure and stage >= 3 else normal_cap
	var batch := mini(2 + stage / 3, 5) if pressure else 1
	if spawned_total == 0 and _pending.is_empty():
		batch = 3
	if combat_demo:
		cap = peak_cap
		batch = 40 if spawned_total == 0 and _pending.is_empty() else 4
	for i in batch:
		if _alive.size() + _pending.size() >= cap:
			break
		var choice := rng.randf()
		var type := "chaser"
		if (combat_demo or elapsed >= 60.0) and choice > 0.78:
			type = "ranged"
		elif (combat_demo or elapsed >= 20.0) and choice > 0.57:
			type = "charger"
		_queue_enemy(type)
	var interval := (1.4 if pressure else (3.0 if rest else 1.75)) - minf(stage * 0.06, 0.4)
	_spawn_timer.start(2.0 if combat_demo else interval)

func _queue_enemy(type: String, is_elite := false, is_boss := false) -> void:
	if not is_instance_valid(enemy_container):
		return
	var point := _spawn_position()
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8 if is_boss else 0.45
	ring.outer_radius = 0.86 if is_boss else 0.49
	ring.rings = 32
	ring.ring_segments = 4
	marker.mesh = ring
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffc16e") if is_elite or is_boss else Color("ce745d")
	marker.material_override = material
	enemy_container.add_child(marker)
	marker.global_position = point + Vector3.UP * 0.05
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(timer)
	var element := 0 if combat_demo or elapsed < 60.0 else rng.randi_range(0, 4)
	var pending := {"kind": type, "stage": 0 if combat_demo else int(elapsed / 60.0), "element": element, "elite": is_elite, "boss": is_boss, "point": point, "marker": marker, "timer": timer}
	_pending.append(pending)
	timer.timeout.connect(_spawn_pending.bind(pending))
	timer.start(0.8)

func _spawn_position() -> Vector3:
	var radius := maxf(arena_radius - 0.8, 1.0)
	for attempt in 16:
		var angle := _spawn_cursor * PI / 2.0 + rng.randf_range(-0.45, 0.45)
		_spawn_cursor += 1
		var point := Vector3(cos(angle) * radius, 0.04, sin(angle) * radius)
		if not is_instance_valid(player) or point.distance_to(player.global_position) >= 6.0:
			return point
	var away := -player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	return away.normalized() * radius + Vector3.UP * 0.04

func _spawn_pending(pending: Dictionary) -> void:
	_pending.erase(pending)
	if is_instance_valid(pending.marker):
		pending.marker.queue_free()
	if is_instance_valid(pending.timer):
		pending.timer.queue_free()
	if not enabled or not is_instance_valid(player) or player.dead or not is_instance_valid(enemy_container):
		return
	if not combat_demo and elapsed >= duration and not pending.boss:
		return
	if _alive.size() >= peak_cap:
		# Keep one deferred special spawn instead of exceeding the crowd budget.
		if pending.elite or pending.boss:
			_queue_enemy(pending.kind, pending.elite, pending.boss)
		return
	# The player can move during the warning; defer instead of spawning on top of them.
	if player.global_position.distance_to(pending.point) < 6.0:
		_queue_enemy(pending.kind, pending.elite, pending.boss)
		return
	var enemy := ENEMY_SCENE.instantiate() as ArenaEnemy
	enemy.configure(pending.kind, pending.stage, pending.element, pending.elite, pending.boss)
	if combat_demo:
		enemy.stats.max_health = 20000.0
		enemy.health = enemy.stats.max_health
		enemy.experience_value = 0
	enemy.target = player
	enemy.camera = camera
	enemy.arena_radius = arena_radius
	enemy.position = pending.point
	enemy_container.add_child(enemy)
	_alive.append(enemy)
	enemy.defeated.connect(_on_defeated)
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))
	spawned_total += 1
	enemy_spawned.emit(enemy)
	if pending.boss:
		boss_spawned.emit(enemy)

func _on_defeated(enemy: Node3D) -> void:
	_alive.erase(enemy)

func _on_enemy_exited(enemy: Node3D) -> void:
	_alive.erase(enemy)

func _clear_pending() -> void:
	for pending in _pending:
		if is_instance_valid(pending.timer):
			pending.timer.stop()
			pending.timer.queue_free()
		if is_instance_valid(pending.marker):
			pending.marker.queue_free()
	_pending.clear()

func _exit_tree() -> void:
	_clear_pending()
