extends Node3D
## One growing sword formation: the same asset instances follow native attack/return paths.

const RANGE := 8.5
const SWORD_SCENE := preload("res://assets/weapons/astral_edge/astral_edge.tscn")
const SWORD_VISUAL := preload("res://assets/weapons/astral_edge/astral_edge.gd")
const MAX_ACTIVE_SWORDS := 6
# Keep the authored model; its in-game length is now ~2.31 units instead of 3.55.
const BLADE_SCALE := 0.65
const BLADE_CONTACT := Vector3(0, 2.6, 0)
const APPROACH_SPEED := 9.0
const STRIKE_SPEED := 48.0
const STRIKE_HOLD := 0.085
const ORBIT_RADIUS := 1.65
const ORBIT_HEIGHT := 1.25
const ORBIT_SPEED := 0.55
const VOLLEY_INTERVAL := 0.24
const METEOR_RADIUS := 3.2
const METEOR_DELAY := 0.9

enum FlightPhase { APPROACH, STRIKE, RETURN }

var player: DuelFighter
var progression: RunProgression
var feedback: Node3D
var active := true
var active_swords: int:
	get: return flights.size()
var volley_count := 0
var chain_count := 0
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
var volley_left := 0.0
var clock := 0.0
var target_cursor := 0
var blade_cursor := 0
var sword_query := PhysicsShapeQueryParameters3D.new()
var meteor_query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	# A native swept capsule covers the blade's contact point between physics ticks.
	var tip := CapsuleShape3D.new()
	tip.radius = 0.32
	tip.height = tip.radius * 2.0
	sword_query.shape = tip
	sword_query.collision_mask = 4
	var blast := SphereShape3D.new()
	blast.radius = METEOR_RADIUS
	meteor_query.shape = blast
	meteor_query.collision_mask = 4
	refresh_skills()

func refresh_skills() -> void:
	var level := progression.skill_level("swords")
	if not player.enabled or player.dead or level <= 0:
		return
	var count := clampi(progression.skill("swords").count_at(level), 0, MAX_ACTIVE_SWORDS)
	if not is_instance_valid(halo):
		_make_halo()
		feedback.storm_activate(player.global_position)
	# A rank-up adds physical swords in place; existing paths and sword IDs survive.
	if blades.size() < count:
		while blades.size() < count:
			var slot := Node3D.new()
			slot.name = "Slot%d" % (blades.size() + 1)
			halo.add_child(slot)
			slots.append(slot)
			var blade := SWORD_SCENE.instantiate() as Node3D
			blade.scale = Vector3.ONE * BLADE_SCALE
			blade.phase = blades.size() * 1.8
			slot.add_child(blade)
			blades.append(blade)
		_update_formation()

func _make_halo() -> void:
	halo = Node3D.new()
	halo.name = "SwordFormation"
	add_child(halo)
	# The authored sword scene already owns its idle motes and flight trail.
	halo.visible = active

func _update_formation() -> void:
	halo.visible = active
	halo.global_position = player.global_position
	for i in slots.size():
		var angle := TAU * float(i) / float(slots.size()) + clock * ORBIT_SPEED
		slots[i].position = Vector3(cos(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(angle) * ORBIT_RADIUS)
		# +Y is the blade axis, +Z the decorated front: lie flat, point along the orbit,
		# and keep the front facing up toward the arena camera.
		slots[i].rotation = Vector3(-PI / 2.0, PI - angle, 0)

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
	volley_left = 0.0
	volley_count = 0
	chain_count = 0
	meteor_count = 0
	meteor_rolls = 0
	sword_hits = 0
	meteor_hits = 0
	target_cursor = 0
	blade_cursor = 0
	refresh_skills()

func on_swing(_heavy: bool) -> void:
	# Only meteor is swing-triggered. Swords acquire targets in their own physics tick.
	if not active or not player.enabled or player.dead or progression.skill_level("meteor") <= 0:
		return
	var targets := _targets()
	if targets.is_empty():
		return
	# Only the authored player's swing rolls this once. Auxiliary hits never call it.
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
		if not flights.is_empty() or not meteors.is_empty():
			reset()
		if is_instance_valid(halo):
			halo.hide()
		return
	refresh_skills()
	if is_instance_valid(halo):
		_update_formation()
	if not active:
		if not flights.is_empty() or not meteors.is_empty():
			reset()
		return
	volley_left = maxf(0.0, volley_left - delta)
	if progression.skill_level("swords") > 0 and volley_left <= 0.0:
		# Bound idle target scans too; no attack animation or swing grace is required.
		volley_left = VOLLEY_INTERVAL
		_fire_volley(_targets())
	_advance_swords()
	_advance_meteors(delta)

func _fire_volley(targets: Array[Node3D]) -> void:
	if targets.is_empty() or blades.is_empty():
		return
	var launched := 0
	for i in blades.size():
		var slot := blade_cursor % blades.size()
		blade_cursor += 1
		# The formation sword itself departs. An empty slot cannot emit a copy.
		if blades[slot].get_parent() != slots[slot]:
			continue
		var target := _next_target(targets)
		if not is_instance_valid(target):
			continue
		_launch_sword(target, slot)
		launched += 1
		if launched == 3:
			break
	if launched > 0:
		volley_count += 1

func _next_target(targets: Array[Node3D], previous: Node3D = null) -> Node3D:
	if targets.is_empty():
		return null
	var fallback: Node3D
	for i in targets.size():
		var candidate := targets[target_cursor % targets.size()]
		target_cursor += 1
		if not is_instance_valid(candidate) or candidate.dead or not candidate.is_visible_in_tree():
			continue
		fallback = candidate
		if candidate != previous:
			return candidate
	return fallback

func _launch_sword(target: Node3D, slot: int) -> void:
	var path := Path3D.new()
	add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_XYZ
	path.add_child(follow)
	var blade := blades[slot]
	var start := blade.global_position
	blade.reparent(follow)
	var flight := {"path": path, "follow": follow, "target": weakref(target), "hit_ids": [], "duration": 0.0, "blade": blade, "tween": null, "through": Vector3.UP, "slot": slot, "phase": FlightPhase.APPROACH, "leg": 0, "previous_contact": start}
	_route_sword(flight, target, start)
	flights.append(flight)

func _route_sword(flight: Dictionary, target: Node3D, start: Vector3) -> void:
	if flight.tween != null:
		flight.tween.kill()
	var first := int(flight.leg) == 0
	var contact := target.global_position + Vector3.UP * 1.05
	var direction := Vector3(contact.x - start.x, 0, contact.z - start.z).normalized()
	if direction.length_squared() < 0.01:
		direction = player.facing
	var side := direction.cross(Vector3.UP) * (-1.0 if (int(flight.slot) + int(flight.leg)) % 2 == 0 else 1.0)
	# The curved approach ends moving sideways ABOVE the victim, not through them.
	# A separate straight stab must visibly break this tangent to reach the body.
	var approach := contact - direction * 2.4 + side * 1.7 + Vector3.UP * 1.6
	var sweep := start.lerp(approach, 0.5) + side * 0.8 + Vector3.UP * 0.45
	var departure: Vector3 = slots[flight.slot].global_basis.y if first else (flight.through as Vector3).normalized()
	var curve := Curve3D.new()
	curve.bake_interval = 0.08
	curve.add_point(start, Vector3.ZERO, departure * 1.1 + side * 0.3)
	curve.add_point(sweep, -direction * 0.65, direction * 0.65)
	curve.add_point(approach, -side * 0.85, Vector3.ZERO)
	flight.path.curve = curve
	flight.follow.progress = 0.0
	flight.blade.position = Vector3.ZERO
	flight.duration = clampf(curve.get_baked_length() / APPROACH_SPEED, 0.36, 0.75)
	flight.target = weakref(target)
	flight.approach_offset = approach - target.global_position
	flight.through = side
	flight.hit_ids.clear()
	flight.phase = FlightPhase.APPROACH
	flight.blade.set_motion(SWORD_VISUAL.Motion.CHARGE)
	flight.leg += 1
	if not first:
		chain_count += 1
	feedback.storm_muzzle(start)
	var tween: Tween = flight.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tween.tween_property(flight.follow, "progress_ratio", 1.0, flight.duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# +Y is the asset's blade axis; PathFollow3D advances along its local -Z.
	tween.tween_property(flight.blade, "rotation", Vector3(-PI / 2.0, 0, 0), 0.14).set_trans(Tween.TRANS_SINE)
	flight.tween = tween

func _strike_sword(flight: Dictionary, target: Node3D) -> void:
	flight.tween.kill()
	var follow := flight.follow as PathFollow3D
	var blade := flight.blade as Node3D
	var start := follow.global_position
	var contact := target.global_position + Vector3.UP * 1.05
	var direction := (contact - start).normalized()
	# The blade, rather than its pommel, enters the body. Hold it briefly embedded.
	var destination := contact - direction * (BLADE_CONTACT.y * BLADE_SCALE - 0.22)
	var curve := Curve3D.new()
	curve.add_point(start)
	curve.add_point(destination)
	flight.path.curve = curve
	follow.progress = 0.0
	blade.rotation = Vector3(-PI / 2.0, 0, 0)
	blade.set_motion(SWORD_VISUAL.Motion.FLIGHT)
	flight.previous_contact = blade.to_global(BLADE_CONTACT)
	flight.through = direction
	flight.phase = FlightPhase.STRIKE
	var travel_time := curve.get_baked_length() / STRIKE_SPEED
	flight.duration = travel_time + STRIKE_HOLD
	# No ease-in and no homing bend during a committed stab: speed changes immediately.
	var tween: Tween = flight.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(follow, "progress_ratio", 1.0, travel_time).set_trans(Tween.TRANS_LINEAR)
	tween.tween_interval(STRIKE_HOLD)
	flight.tween = tween

func _return_sword(flight: Dictionary) -> void:
	flight.tween.kill()
	var follow := flight.follow as PathFollow3D
	var blade := flight.blade as Node3D
	var start := follow.global_position
	var destination := slots[flight.slot].global_position
	var side := slots[flight.slot].global_basis.x * (-1.0 if flight.slot % 2 == 0 else 1.0)
	var middle := start.lerp(destination, 0.55) + side * 0.85 + Vector3.UP * 1.3
	var curve := Curve3D.new()
	curve.bake_interval = 0.10
	curve.add_point(start, Vector3.ZERO, flight.through * 0.45 + Vector3.UP * 0.8)
	curve.add_point(middle, (start - destination).normalized() * 0.65, (destination - start).normalized() * 0.65)
	curve.add_point(destination, -slots[flight.slot].global_basis.y * 0.7, Vector3.ZERO)
	flight.path.curve = curve
	follow.progress = 0.0
	flight.duration = clampf(curve.get_baked_length() / 20.0, 0.34, 0.58)
	flight.phase = FlightPhase.RETURN
	blade.set_motion(SWORD_VISUAL.Motion.RETURN)
	# Native path playback remains the only motion driver on the return leg too.
	var tween: Tween = flight.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tween.tween_property(follow, "progress_ratio", 1.0, flight.duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(blade, "global_rotation", slots[flight.slot].global_rotation, 0.14).set_delay(flight.duration - 0.14)
	flight.tween = tween

func _advance_swords() -> void:
	var targets: Array[Node3D] = []
	var found_targets := false
	for i in range(flights.size() - 1, -1, -1):
		var flight := flights[i]
		var follow := flight.follow as PathFollow3D
		if flight.phase == FlightPhase.RETURN:
			flight.path.curve.set_point_position(2, slots[flight.slot].global_position)
			flight.path.curve.set_point_in(2, -slots[flight.slot].global_basis.y * 0.7)
			if not flight.tween.is_running():
				flight.tween.kill()
				flight.blade.reparent(slots[flight.slot])
				flight.blade.position = Vector3.ZERO
				flight.blade.rotation = Vector3.ZERO
				flight.blade.scale = Vector3.ONE * BLADE_SCALE
				flight.blade.set_motion(SWORD_VISUAL.Motion.IDLE)
				flight.path.queue_free()
				flights.remove_at(i)
			continue
		var target := (flight.target as WeakRef).get_ref() as Node3D
		var target_valid: bool = is_instance_valid(target) and not target.dead and target.is_visible_in_tree() and target.global_position.distance_to(player.global_position) <= RANGE * player.stats.range_multiplier
		if flight.phase == FlightPhase.STRIKE:
			_strike_contacts(flight)
			# Finish the short committed stab/hold even if its hit killed the target.
			if flight.tween.is_running():
				continue
		elif target_valid:
			flight.path.curve.set_point_position(2, target.global_position + flight.approach_offset)
			if flight.tween.is_running():
				continue
			_strike_sword(flight, target)
			continue
		# At most one target scan for all re-routing swords in this physics tick.
		if not found_targets:
			targets = _targets()
			found_targets = true
		var next := _next_target(targets, target if is_instance_valid(target) else null)
		if is_instance_valid(next):
			_route_sword(flight, next, follow.global_position)
		else:
			_return_sword(flight)

func _strike_contacts(flight: Dictionary) -> void:
	var contact: Vector3 = flight.blade.to_global(BLADE_CONTACT)
	var previous: Vector3 = flight.previous_contact
	var motion := contact - previous
	flight.previous_contact = contact
	var shape := sword_query.shape as CapsuleShape3D
	shape.height = motion.length() + shape.radius * 2.0
	var basis := Basis(Quaternion(Vector3.UP, motion.normalized())) if motion.length_squared() > 0.00001 else Basis.IDENTITY
	sword_query.transform = Transform3D(basis, (previous + contact) * 0.5)
	for result in get_world_3d().direct_space_state.intersect_shape(sword_query, 128):
		var body := result.collider as Node3D
		if not is_instance_valid(body) or body.dead or not body.is_visible_in_tree() or body.get_instance_id() in flight.hit_ids:
			continue
		if body.global_position.distance_to(player.global_position) > RANGE * player.stats.range_multiplier:
			continue
		flight.hit_ids.append(body.get_instance_id())
		var definition := progression.skill("swords")
		var point := body.global_position + Vector3.UP * 1.05
		var hit := player.deal_damage(body, definition.kind, progression.coefficient("swords"), definition.element, false, true, "飞剑", flight.through)
		if hit.get("actual", 0) > 0:
			sword_hits += 1
			# Per-contact flashes do not share the arena's camera/accent throttle.
			feedback.storm_hit(point, flight.through, bool(hit.get("lethal", false)))

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
