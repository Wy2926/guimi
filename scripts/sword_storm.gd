extends Node3D
## One authored stance: eight asset instances, native paths, physics queries and GPU particles.

const RANGE := 8.5
const SWORD_SCENE := preload("res://assets/weapons/niko_katana/sword.tscn")
const MAX_ACTIVE_SWORDS := 8
const VOLLEY_INTERVAL := 0.24
const METEOR_RADIUS := 3.2
const METEOR_DELAY := 0.9

var player: DuelFighter
var progression: RunProgression
var feedback: Node3D
var camera: Camera3D
var active := true
var active_swords: int:
	get: return flights.size()
var volley_count := 0
var meteor_count := 0
var meteor_rolls := 0
var sword_hits := 0
var meteor_hits := 0
var meteor_chance := 0.28
var rng := RandomNumberGenerator.new()
var flights: Array[Dictionary] = []
var meteors: Array[Dictionary] = []
var blades: Array[Node3D] = []
var slots: Array[Node3D] = []
var halo: Node3D
var fire_left := 0.0
var volley_left := 0.0
var clock := 0.0
var target_cursor := 0
var blade_cursor := 0
var sword_query := PhysicsShapeQueryParameters3D.new()
var meteor_query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	var tip := SphereShape3D.new()
	tip.radius = 0.48
	sword_query.shape = tip
	sword_query.collision_mask = 4
	var blast := SphereShape3D.new()
	blast.radius = METEOR_RADIUS
	meteor_query.shape = blast
	meteor_query.collision_mask = 4
	refresh_skills()

func refresh_skills() -> void:
	if player.enabled and progression.skill_level("swords") > 0 and not is_instance_valid(halo):
		_make_halo()
		feedback.storm_activate(player.global_position)

func _make_halo() -> void:
	halo = Node3D.new()
	halo.name = "EightBlades"
	add_child(halo)
	for i in MAX_ACTIVE_SWORDS:
		var slot := Node3D.new()
		slot.name = "Slot%d" % (i + 1)
		halo.add_child(slot)
		slots.append(slot)
		var blade := SWORD_SCENE.instantiate() as Node3D
		slot.add_child(blade)
		blades.append(blade)
	# A single gentle emitter for the formation, not eight particle systems.
	var motes: GPUParticles3D = feedback.attach_trail(halo, Color("78c9dc"), 24, 0.75)
	motes.position = Vector3(0, 2.8, 0)
	var process := motes.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2.0, 0.65, 0.05)
	halo.visible = active
	motes.emitting = active

func reset() -> void:
	# Killing these bound tweens also cancels every pending impact on reset/toggle.
	for flight in flights:
		flight.tween.kill()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	flights.clear()
	meteors.clear()
	blades.clear()
	slots.clear()
	halo = null
	fire_left = 0.0
	volley_left = 0.0
	volley_count = 0
	meteor_count = 0
	meteor_rolls = 0
	sword_hits = 0
	meteor_hits = 0
	target_cursor = 0
	blade_cursor = 0
	refresh_skills()

func on_swing(heavy: bool) -> void:
	if not active or not player.enabled or player.dead:
		return
	refresh_skills()
	var targets := _targets()
	if targets.is_empty():
		return
	if progression.skill_level("swords") > 0:
		fire_left = 0.66 if heavy else 0.42
		if volley_left <= 0.0:
			_fire_volley(targets)
	# Only the authored player's swing rolls this once. Auxiliary hits never call it.
	if progression.skill_level("meteor") > 0:
		meteor_rolls += 1
		if rng.randf() < meteor_chance and meteors.size() < 2:
			_call_meteor(targets[rng.randi_range(0, targets.size() - 1)])

func _targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate.dead and candidate.is_visible_in_tree() and candidate.global_position.distance_to(player.global_position) <= RANGE * player.stats.range_multiplier:
			targets.append(candidate)
	return targets

func _physics_process(delta: float) -> void:
	clock += delta
	if player.dead or not player.enabled:
		if fire_left > 0.0 or not flights.is_empty() or not meteors.is_empty():
			reset()
		if is_instance_valid(halo):
			halo.hide()
		return
	refresh_skills()
	# Keep the fan behind the fighter, but open its plane toward the fixed camera
	# so eight separate blades remain readable instead of collapsing edge-on.
	if is_instance_valid(halo):
		halo.visible = active
		halo.global_position = player.global_position - player.facing * 0.85
		var to_camera: Vector3 = camera.global_position - halo.global_position
		halo.rotation.y = atan2(to_camera.x, to_camera.z)
		for i in slots.size():
			var angle := lerpf(-1.12, 1.12, float(i) / 7.0)
			slots[i].position = Vector3(sin(angle) * 2.45, 2.6 + cos(angle) * 0.8 + sin(clock * 1.8 + i) * 0.07, 0)
			slots[i].rotation.z = -angle * 0.48
	if not active:
		return
	volley_left = maxf(0.0, volley_left - delta)
	fire_left = maxf(0.0, fire_left - delta)
	if progression.skill_level("swords") > 0 and fire_left > 0.0 and volley_left <= 0.0:
		_fire_volley(_targets())
	_advance_swords(delta)
	_advance_meteors(delta)

func _fire_volley(targets: Array[Node3D]) -> void:
	if targets.is_empty() or blades.is_empty():
		return
	volley_left = VOLLEY_INTERVAL
	var launched := 0
	for i in MAX_ACTIVE_SWORDS:
		var slot := blade_cursor % MAX_ACTIVE_SWORDS
		blade_cursor += 1
		# The formation sword itself departs. An empty slot cannot emit a copy.
		if blades[slot].get_parent() != slots[slot]:
			continue
		var target := targets[target_cursor % targets.size()]
		target_cursor += 1
		_launch_sword(target, slot)
		launched += 1
		if launched == 3:
			break
	if launched > 0:
		volley_count += 1

func _launch_sword(target: Node3D, slot: int) -> void:
	var start := blades[slot].global_position
	var contact := target.global_position + Vector3.UP * 1.05
	var direction := (contact - start).normalized()
	var side := direction.cross(Vector3.UP).normalized() * (-1.0 if slot % 2 == 0 else 1.0)
	var middle := start.lerp(contact, 0.48) + side * (1.35 + (slot % 3) * 0.4) + Vector3.UP * 0.6
	var through := Vector3(direction.x, 0, direction.z).normalized() * 2.0
	var curve := Curve3D.new()
	curve.bake_interval = 0.10
	curve.add_point(start, Vector3.ZERO, (middle - start) * 0.55 + Vector3.UP * 0.6)
	curve.add_point(middle, -direction * 0.8, direction * 0.8)
	curve.add_point(contact, -through * 0.5, through * 0.5)
	curve.add_point(contact + through, -through * 0.4, Vector3.ZERO)
	var path := Path3D.new()
	path.curve = curve
	add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_XYZ
	path.add_child(follow)
	var blade := blades[slot]
	blade.reparent(follow)
	blade.position = Vector3.ZERO
	feedback.storm_muzzle(start)
	var trail: GPUParticles3D = feedback.attach_trail(follow, Color("f3cd8d") if slot % 3 == 0 else Color("77dcff"), 28, 0.28)
	# Native velocity-aligned particles overlap into a readable curved light wake.
	var wake := trail.draw_pass_1 as SphereMesh
	wake.radius = 0.018
	wake.height = 0.30
	var wake_process := trail.process_material as ParticleProcessMaterial
	wake_process.particle_flag_align_y = true
	wake_process.direction = Vector3.BACK
	wake_process.spread = 3.0
	wake_process.initial_velocity_min = 0.15
	wake_process.initial_velocity_max = 0.25
	var duration := clampf(curve.get_baked_length() / 13.5, 0.64, 1.15)
	var tween := path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tween.tween_property(follow, "progress_ratio", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(blade, "rotation", Vector3(-PI / 2.0, 0, 0), 0.16).set_trans(Tween.TRANS_SINE)
	flights.append({"path": path, "follow": follow, "target": target, "hit_ids": [], "age": 0.0, "duration": duration, "blade": blade, "trail": trail, "tween": tween, "through": through, "slot": slot, "returning": false})

func _return_sword(flight: Dictionary) -> void:
	flight.tween.kill()
	var follow := flight.follow as PathFollow3D
	var blade := flight.blade as Node3D
	var start := follow.global_position
	var destination := slots[flight.slot].global_position
	var side := Vector3.RIGHT.rotated(Vector3.UP, halo.rotation.y) * (-1.0 if flight.slot % 2 == 0 else 1.0)
	var middle := start.lerp(destination, 0.55) + side * 0.85 + Vector3.UP * 1.3
	var curve := Curve3D.new()
	curve.bake_interval = 0.10
	curve.add_point(start, Vector3.ZERO, flight.through * 0.45 + Vector3.UP * 0.8)
	curve.add_point(middle, (start - destination).normalized() * 0.65, (destination - start).normalized() * 0.65)
	curve.add_point(destination, -slots[flight.slot].global_basis.y * 0.7, Vector3.ZERO)
	flight.path.curve = curve
	follow.progress = 0.0
	flight.age = 0.0
	flight.duration = clampf(curve.get_baked_length() / 19.0, 0.32, 0.48)
	flight.returning = true
	# Native path playback remains the only motion driver on the return leg too.
	var tween: Tween = flight.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tween.tween_property(follow, "progress_ratio", 1.0, flight.duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(blade, "global_rotation", slots[flight.slot].global_rotation, 0.14).set_delay(flight.duration - 0.14)
	flight.tween = tween

func _advance_swords(delta: float) -> void:
	for i in range(flights.size() - 1, -1, -1):
		var flight := flights[i]
		flight.age += delta
		var follow := flight.follow as PathFollow3D
		if flight.age >= flight.duration:
			if not flight.returning:
				_return_sword(flight)
			else:
				flight.tween.kill()
				flight.blade.reparent(slots[flight.slot])
				flight.blade.transform = Transform3D.IDENTITY
				flight.trail.emitting = false
				# Let world-space particles die away after the actual sword is home.
				var fade: Tween = flight.path.create_tween()
				fade.tween_interval(0.30)
				fade.tween_callback(flight.path.queue_free)
				flights.remove_at(i)
			continue
		if flight.returning:
			flight.path.curve.set_point_position(2, slots[flight.slot].global_position)
			continue
		# Gently update only the destination while the blade is approaching; its curved
		# launch stays intact. Once it passes the target it continues through, not orbiting.
		if is_instance_valid(flight.target) and not flight.target.dead and follow.progress_ratio < 0.67:
			var target: Node3D = flight.target
			var contact := target.global_position + Vector3.UP * 1.05
			flight.path.curve.set_point_position(2, contact)
			flight.path.curve.set_point_position(3, contact + flight.through)
		sword_query.transform = Transform3D(Basis.IDENTITY, follow.global_position)
		for result in get_world_3d().direct_space_state.intersect_shape(sword_query, 128):
			var body := result.collider as Node3D
			if not is_instance_valid(body) or body.dead or not body.is_visible_in_tree() or body.get_instance_id() in flight.hit_ids:
				continue
			flight.hit_ids.append(body.get_instance_id())
			var definition := progression.skill("swords")
			var hit := player.deal_damage(body, definition.kind, progression.coefficient("swords"), definition.element, false, true, "飞剑")
			if hit.get("actual", 0) > 0:
				sword_hits += 1

func _call_meteor(target: Node3D) -> void:
	if not player.enabled or progression.skill_level("meteor") == 0:
		return
	meteor_count += 1
	var point := target.global_position
	point.y = 0.08
	var radius := METEOR_RADIUS * player.stats.range_multiplier
	var warning: MeshInstance3D = feedback.meteor_warning(point, METEOR_DELAY, radius)
	# Keep the warning with its gameplay owner so toggling/death also cancels it.
	warning.reparent(self)
	var meteor := Node3D.new()
	add_child(meteor)
	var core := MeshInstance3D.new()
	var rock := SphereMesh.new()
	rock.radius = 0.36
	rock.height = 0.78
	rock.radial_segments = 8
	rock.rings = 4
	core.mesh = rock
	core.material_override = feedback._emissive(Color("ffb95d"), 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meteor.add_child(core)
	var trail: GPUParticles3D = feedback.attach_trail(meteor, Color("ffad52"), 80, 0.48)
	var process := trail.process_material as ParticleProcessMaterial
	process.scale_min *= 2.8
	process.scale_max *= 3.2
	var start := point + Vector3(-3.8, 9.0, -2.7)
	meteor.global_position = start
	var descent := meteor.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	descent.tween_property(meteor, "global_position", point, METEOR_DELAY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	meteors.append({"node": meteor, "core": core, "trail": trail, "position": point, "start": start, "left": METEOR_DELAY, "radius": radius})

func _advance_meteors(delta: float) -> void:
	for i in range(meteors.size() - 1, -1, -1):
		var meteor := meteors[i]
		meteor.left -= delta
		if meteor.left > 0.0:
			continue
		var point: Vector3 = meteor.position
		feedback.meteor_impact(point, float(meteor.radius) / METEOR_RADIUS)
		meteor_query.shape.radius = meteor.radius
		meteor_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.6)
		var hit_ids: Array[int] = []
		for result in get_world_3d().direct_space_state.intersect_shape(meteor_query, 128):
			var body := result.collider as Node3D
			if not is_instance_valid(body) or body.dead or not body.is_visible_in_tree() or body.get_instance_id() in hit_ids:
				continue
			hit_ids.append(body.get_instance_id())
			var definition := progression.skill("meteor")
			var hit := player.deal_damage(body, definition.kind, progression.coefficient("meteor"), definition.element, true, false, "流星")
			if hit.get("actual", 0) > 0:
				meteor_hits += 1
		meteor.core.hide()
		meteor.trail.emitting = false
		var fade: Tween = meteor.node.create_tween()
		fade.tween_interval(0.5)
		fade.tween_callback(meteor.node.queue_free)
		meteors.remove_at(i)
