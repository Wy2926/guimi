extends Node3D
## One growing sword formation: the same asset instances follow native attack/return paths.

const RANGE := 8.5
const SWORD_SCENE := preload("res://assets/weapons/astral_edge/astral_edge.tscn")
const SWORD_VISUAL := preload("res://assets/weapons/astral_edge/astral_edge.gd")
# Six authored rank-five blades plus Nezha's one additional controlled blade.
const MAX_ACTIVE_SWORDS := 7
# Keep the authored model; its in-game length is now ~2.31 units instead of 3.55.
const BLADE_SCALE := 0.65
const BLADE_CONTACT := Vector3(0, 2.6, 0)
const APPROACH_SPEED := 9.0
const STRIKE_SPEED := 48.0
const STRIKE_HOLD := 0.085
const PIERCE_MIN_TIME := 0.16
const ORBIT_RADIUS := 1.65
const ORBIT_HEIGHT := 1.25
const ORBIT_SPEED := 0.55
const VOLLEY_INTERVAL := 0.24
const METEOR_RADIUS := 3.2
const METEOR_DELAY := 0.9
const SEAL_VISUAL := preload("res://assets/effects/zhaotian_seal/zhaotian_seal.gd")
const RIBBON_VISUAL := preload("res://assets/effects/huntian_ling/huntian_ling.gd")
const RIBBON_JUMP_RANGE := 4.6

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
var meteor_cooldown := 0.0
var sword_hits := 0
var meteor_hits := 0
var evolved_strikes := 0
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
var ribbon: Dictionary = {}
var ribbon_cooldown := 0.0
var ribbon_casts := 0
var ribbon_hits := 0

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
	var count := clampi(progression.artifact_count("swords"), 0, MAX_ACTIVE_SWORDS)
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
			blade.feedback = feedback
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
	if not ribbon.is_empty() and ribbon.get("tween") != null:
		ribbon.tween.kill()
	ribbon.clear()
	ribbon_cooldown = 0.0
	ribbon_casts = 0
	ribbon_hits = 0
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
	meteor_cooldown = 0.0
	sword_hits = 0
	meteor_hits = 0
	evolved_strikes = 0
	target_cursor = 0
	blade_cursor = 0
	refresh_skills()

func request_fate_cast(target: Node3D, secondary := true) -> bool:
	# Reuse the same warning, flight and impact; bonus casts do not reset auto-CD.
	return _call_meteor(target, secondary)

func _targets(target_range := -1.0) -> Array[Node3D]:
	var targets: Array[Node3D] = []
	var reach := target_range if target_range >= 0.0 else RANGE * player.stats.range_multiplier
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate.dead and candidate.is_visible_in_tree() and candidate.global_position.distance_to(player.global_position) <= reach:
			targets.append(candidate)
	return targets

func _physics_process(delta: float) -> void:
	clock += delta
	if player.dead or not player.enabled:
		if get_child_count() > (1 if is_instance_valid(halo) else 0):
			reset()
		if is_instance_valid(halo):
			halo.hide()
		return
	refresh_skills()
	if is_instance_valid(halo):
		_update_formation()
	if not active:
		if get_child_count() > (1 if is_instance_valid(halo) else 0):
			reset()
		return
	volley_left = maxf(0.0, volley_left - delta)
	meteor_cooldown = maxf(0.0, meteor_cooldown - delta)
	if progression.skill_level("swords") > 0 and volley_left <= 0.0:
		# Bound idle target scans too; no attack animation or swing grace is required.
		volley_left = VOLLEY_INTERVAL
		_fire_volley(_targets())
	if progression.skill_level("meteor") > 0 and meteor_cooldown <= 0.0 and meteors.size() < 2:
		var targets := _targets()
		if not targets.is_empty() and _call_meteor(targets[0]):
			meteor_cooldown = progression.skill("meteor").cooldown * player.stats.cooldown_multiplier
	_advance_swords()
	_advance_meteors(delta)
	_advance_ribbon(delta)

# Mixed with the existing native-path auxiliary scheduler deliberately: no
# parallel damage engine, target registry, effect factory or chain framework.
func _ribbon_target(origin: Vector3, distance: float, visited: Array) -> Node3D:
	var nearest: Node3D
	var best := distance * distance
	var camera := get_viewport().get_camera_3d()
	var reach: float = ribbon.get("range", progression.skill("huntian_ling").radius_at(progression.skill_level("huntian_ling")) * player.stats.range_multiplier)
	for candidate in _targets(reach):
		if candidate.get_instance_id() in visited or not _ribbon_visible(candidate, camera):
			continue
		var offset := candidate.global_position - origin
		offset.y = 0.0
		if offset.length_squared() <= best:
			best = offset.length_squared()
			nearest = candidate
	return nearest

func _ribbon_visible(target: Node3D, camera: Camera3D) -> bool:
	return is_instance_valid(target) and not target.dead and target.is_visible_in_tree() and is_instance_valid(camera) and camera.is_position_in_frustum(target.global_position + Vector3.UP * 0.2) and camera.is_position_in_frustum(target.global_position + Vector3.UP)

func _launch_ribbon(target: Node3D) -> void:
	var definition := progression.skill("huntian_ling")
	var level := progression.skill_level("huntian_ling")
	var path := Path3D.new()
	path.name = "HuntianChain"
	add_child(path)
	var follow := PathFollow3D.new()
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_XYZ
	path.add_child(follow)
	var visual := RIBBON_VISUAL.new()
	visual.name = "HuntianLing"
	visual.feedback = feedback
	follow.add_child(visual)
	var origin := player.global_position + Vector3.UP * 1.0
	visual.begin(origin)
	# Rank/range and divinity's extra contact are cast snapshots, matching the
	# existing projectile semantics. One cloth visits one more distinct target.
	ribbon = {"path": path, "follow": follow, "visual": visual, "tween": null,
		"visited": [], "remaining": progression.artifact_count("huntian_ling"), "coefficient": definition.coefficient_at(level),
		"range": definition.radius_at(level) * player.stats.range_multiplier,
		"jump_range": RIBBON_JUMP_RANGE * player.stats.range_multiplier,
		"burn_snapshot": {}, "direction": player.facing,
		"origin": origin, "leg_range": definition.radius_at(level) * player.stats.range_multiplier,
		"phase": "flight", "left": 0.0, "contact": false}
	ribbon_casts += 1
	ribbon_cooldown = definition.cooldown * player.stats.cooldown_multiplier
	_route_ribbon(target, origin)
	feedback.sound("cloth", origin, -13.0, 1.18)

func _route_ribbon(target: Node3D, start: Vector3) -> void:
	if ribbon.tween != null:
		ribbon.tween.kill()
	ribbon.visual.trace_path()
	var center := target.global_position + Vector3.UP * 0.95
	var direction := center-start
	direction.y = 0.0
	direction = direction.normalized()
	if direction.length_squared() < 0.001:
		direction = player.facing
	var departure: Vector3 = direction if ribbon.visited.is_empty() else -ribbon.follow.global_basis.z.normalized()
	var side := direction.cross(Vector3.UP) * (-1.0 if ribbon.visited.size() % 2 == 0 else 1.0)
	var destination := center-direction*RIBBON_VISUAL.COIL_RADIUS
	var curve := Curve3D.new()
	curve.bake_interval = 0.05
	curve.add_point(start, Vector3.ZERO, departure * 0.85 + Vector3.UP * 0.12)
	curve.add_point(start.lerp(destination, 0.55) + side * 0.70 + Vector3.UP * 0.38, -direction * 0.70, direction * 0.70)
	# Enter tangentially into the real wrap, so the head does not stop or
	# rotate the cloth as a rigid unit when it reaches a victim.
	curve.add_point(destination, -side * 0.45, Vector3.ZERO)
	ribbon.path.curve = curve
	ribbon.follow.progress = 0.0
	ribbon.entry_offset = -direction*RIBBON_VISUAL.COIL_RADIUS
	ribbon.coil_side = side
	ribbon.target = weakref(target)
	ribbon.origin = start
	ribbon.visited.append(target.get_instance_id())
	ribbon.remaining -= 1
	ribbon.phase = "flight"
	ribbon.contact = false
	ribbon.direction = direction
	ribbon.visual.flow()
	var duration := clampf(curve.get_baked_length() / 16.0, 0.16, 0.60)
	ribbon.tween = ribbon.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	ribbon.tween.tween_property(ribbon.follow, "progress_ratio", 1.0, duration).set_trans(Tween.TRANS_LINEAR)

func _strike_ribbon(target: Node3D) -> void:
	ribbon.visual.trace_path()
	var center := target.global_position+Vector3.UP*0.95
	var curve := Curve3D.new()
	curve.bake_interval = 0.035
	var offsets: Array[Vector3] = []
	var radial: Vector3 = ribbon.entry_offset
	var side: Vector3 = ribbon.coil_side*RIBBON_VISUAL.COIL_RADIUS
	# Four cubic 60-degree arcs: 240 degrees of genuine moving contact.
	# The same skin then traverses this loop in head-to-tail order.
	var handle := 4.0/3.0*tan(PI/12.0)
	for i in 5:
		var angle := float(i)*PI/3.0
		var offset := radial*cos(angle)+side*sin(angle)+Vector3.UP*(0.08*sin(angle))
		var tangent := -radial*sin(angle)+side*cos(angle)+Vector3.UP*(0.08*cos(angle))
		offsets.append(offset)
		curve.add_point(center+offset, -tangent*handle, tangent*handle)
	ribbon.path.curve = curve
	ribbon.follow.progress = 0.0
	ribbon.coil_offsets = offsets
	ribbon.phase = "strike"
	ribbon.left = RIBBON_VISUAL.STRIKE_TIME
	ribbon.visual.strike()
	ribbon.tween = ribbon.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	ribbon.tween.tween_property(ribbon.follow, "progress_ratio", 1.0, RIBBON_VISUAL.STRIKE_TIME)

func _return_ribbon() -> void:
	if ribbon.tween != null:
		ribbon.tween.kill()
	ribbon.visual.trace_path()
	var start: Vector3 = ribbon.follow.global_position
	var destination := player.global_position + Vector3.UP
	var curve := Curve3D.new()
	curve.add_point(start, Vector3.ZERO, -ribbon.follow.global_basis.z.normalized() * 0.85 + Vector3.UP * 0.5)
	curve.add_point(destination, (start - destination).normalized() * 0.8 + Vector3.UP * 0.4, Vector3.ZERO)
	ribbon.path.curve = curve
	ribbon.follow.progress = 0.0
	ribbon.phase = "return"
	ribbon.visual.set_carried_fire(false)
	ribbon.visual.flow()
	ribbon.tween = ribbon.path.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	ribbon.tween.tween_property(ribbon.follow, "progress_ratio", 1.0, 0.48).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _advance_ribbon(delta: float) -> void:
	if player.dead or not player.enabled:
		return
	ribbon_cooldown = maxf(0.0, ribbon_cooldown - delta)
	if progression.skill_level("huntian_ling") <= 0:
		if not ribbon.is_empty():
			ribbon.tween.kill()
			ribbon.path.queue_free()
			ribbon.clear()
		return
	if ribbon.is_empty():
		if ribbon_cooldown <= 0.0:
			var target := _ribbon_target(player.global_position, progression.skill("huntian_ling").radius_at(progression.skill_level("huntian_ling")) * player.stats.range_multiplier, [])
			if target != null:
				_launch_ribbon(target)
		return
	if not ribbon.burn_snapshot.is_empty():
		# Carry the first primary burn along this actual path, never refresh its
		# remaining lifetime while the cloth travels or pick up a propagated burn.
		ribbon.burn_snapshot.remaining = maxf(0.0, float(ribbon.burn_snapshot.remaining) - delta)
	_refresh_ribbon_fire()
	if ribbon.phase == "fade":
		ribbon.left -= delta
		if ribbon.left <= 0.0:
			ribbon.path.queue_free()
			ribbon.clear()
		return
	if ribbon.phase == "return":
		ribbon.path.curve.set_point_position(1, player.global_position + Vector3.UP)
		if not ribbon.tween.is_running():
			ribbon.visual.dissolve()
			ribbon.phase = "fade"
			ribbon.left = 0.65
		return
	var target := (ribbon.target as WeakRef).get_ref() as Node3D
	var valid := _ribbon_visible(target, get_viewport().get_camera_3d())
	if valid:
		var from_player := target.global_position - player.global_position
		var from_origin: Vector3 = target.global_position - ribbon.origin
		from_player.y = 0.0
		from_origin.y = 0.0
		valid = from_player.length_squared() <= float(ribbon.range) ** 2 and from_origin.length_squared() <= float(ribbon.leg_range) ** 2
	if ribbon.phase == "flight" and valid:
		ribbon.path.curve.set_point_position(2, target.global_position + Vector3.UP * 0.95 + ribbon.entry_offset)
		if ribbon.tween.is_running():
			return
		ribbon.follow.progress_ratio = 1.0
		_strike_ribbon(target)
		return
	if ribbon.phase == "strike":
		ribbon.left -= delta
		if valid:
			for i in ribbon.coil_offsets.size():
				ribbon.path.curve.set_point_position(i, target.global_position + Vector3.UP * 0.95 + ribbon.coil_offsets[i])
			if not ribbon.contact and RIBBON_VISUAL.STRIKE_TIME - float(ribbon.left) >= RIBBON_VISUAL.CONTACT_TIME:
				ribbon.contact = true
				_ribbon_contact(target)
		# The head keeps moving through the wrap even after its contact beat.
		if ribbon.tween.is_running() and (valid or ribbon.contact):
			return
	var origin: Vector3 = ribbon.follow.global_position
	# Preserve the authored enemy-to-enemy jump distance; the decorative
	# half-metre wrap must not silently extend acquisition range.
	var jump_origin: Vector3 = target.global_position if is_instance_valid(target) else origin
	var next := _ribbon_target(jump_origin, ribbon.jump_range, ribbon.visited) if ribbon.remaining > 0 else null
	if next != null:
		ribbon.leg_range = ribbon.jump_range
		_route_ribbon(next, origin)
		ribbon.origin = jump_origin
	else:
		_return_ribbon()

func _ribbon_contact(target: Node3D) -> void:
	# Reuse the scheduler's native contact query. This tight coil only hits its
	# selected victim, never everyone near the decorative sweep or trail.
	var point: Vector3 = ribbon.follow.global_position
	var shape := sword_query.shape as CapsuleShape3D
	shape.height = shape.radius * 2.0
	sword_query.transform = Transform3D(Basis.IDENTITY, point)
	for contact in get_world_3d().direct_space_state.intersect_shape(sword_query, 128):
		if contact.collider != target:
			continue
		var burn: Dictionary = target.get_status("burn") if ribbon.burn_snapshot.is_empty() else {}
		var hit := player.deal_fabao_damage(target, "huntian_ling", ribbon.coefficient, false, false, ribbon.direction)
		if float(hit.get("actual", 0.0)) > 0.0:
			ribbon_hits += 1
			if not ribbon.burn_snapshot.is_empty() and float(ribbon.burn_snapshot.remaining) > 0.0:
				var source := (ribbon.burn_snapshot.source as WeakRef).get_ref() as DuelFighter
				if is_instance_valid(source) and target.apply_status("burn", source, ribbon.burn_snapshot.skill_id, ribbon.burn_snapshot.remaining, ribbon.burn_snapshot.potency, true):
					feedback.ribbon_fire_contact(point, ribbon.direction, ribbon.path)
			elif ribbon.burn_snapshot.is_empty() and not burn.is_empty() and not bool(burn.get("secondary", false)):
				ribbon.burn_snapshot = burn.duplicate()
			_refresh_ribbon_fire()
			ribbon.visual.hit()
			feedback.ribbon_impact(point, ribbon.direction, ribbon.path)
		break

func _refresh_ribbon_fire() -> void:
	var carries := false
	if not ribbon.burn_snapshot.is_empty() and float(ribbon.burn_snapshot.remaining) > 0.0 and ribbon.phase in ["flight", "strike"]:
		var source := (ribbon.burn_snapshot.source as WeakRef).get_ref() as DuelFighter
		carries = is_instance_valid(source) and source.enabled and not source.dead
	ribbon.visual.set_carried_fire(carries)

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
	var eligible: Array[Node3D] = []
	if progression.has_evolution("swords_pierce"):
		for target in targets:
			if is_instance_valid(target) and not target.dead and target.is_visible_in_tree() and target.has_status("bind"):
				eligible.append(target)
	if eligible.is_empty():
		eligible = targets
	var fallback: Node3D
	for i in eligible.size():
		var candidate := eligible[target_cursor % eligible.size()]
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
	var flight := {"path": path, "follow": follow, "target": weakref(target), "hit_ids": [], "duration": 0.0, "blade": blade, "tween": null, "through": Vector3.UP, "slot": slot, "phase": FlightPhase.APPROACH, "leg": 0, "previous_contact": start, "coefficient": progression.coefficient("swords"), "evolved": false}
	_route_sword(flight, target, start)
	flights.append(flight)

func _route_sword(flight: Dictionary, target: Node3D, start: Vector3) -> void:
	if flight.tween != null:
		flight.tween.kill()
	# Each acquired target is a new attack leg. Keep a committed leg's
	# snapshot, but do not strand a continuously flying sword at its old rank.
	flight.coefficient = progression.coefficient("swords")
	var first := int(flight.leg) == 0
	var contact := target.global_position + Vector3.UP * 1.05
	var direction := Vector3(contact.x - start.x, 0, contact.z - start.z).normalized()
	if direction.length_squared() < 0.01:
		direction = player.facing
	flight.evolved = progression.has_evolution("swords_pierce") and target.has_status("bind")
	if flight.evolved:
		# The same sword/path skips the orbiting approach, then crosses through
		# the bound victim with the existing swept-contact strike implementation.
		flight.blade.position = Vector3.ZERO
		flight.target = weakref(target)
		flight.hit_ids.clear()
		flight.leg += 1
		if not first:
			chain_count += 1
		evolved_strikes += 1
		feedback.storm_muzzle(start)
		_strike_sword(flight, target, start)
		return
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

func _strike_sword(flight: Dictionary, target: Node3D, start: Vector3) -> void:
	if flight.tween != null:
		flight.tween.kill()
	var follow := flight.follow as PathFollow3D
	var blade := flight.blade as Node3D
	var contact := target.global_position + Vector3.UP * 1.05
	var direction := (contact - start).normalized()
	# Normal strikes stop embedded; the evolved blade clears the body entirely.
	var destination := contact + direction * 1.4 if flight.evolved else contact - direction * (BLADE_CONTACT.y * BLADE_SCALE - 0.22)
	var curve := Curve3D.new()
	curve.add_point(start)
	curve.add_point(destination)
	flight.path.curve = curve
	follow.progress = 0.0
	blade.rotation = Vector3(-PI / 2.0, 0, 0)
	blade.set_motion(SWORD_VISUAL.Motion.FLIGHT)
	blade.set_piercing(flight.evolved)
	if flight.evolved:
		feedback.sword_pierce(start, direction, flight.path)
	flight.previous_contact = start if flight.evolved else blade.to_global(BLADE_CONTACT)
	flight.through = direction
	flight.phase = FlightPhase.STRIKE
	# One remaining bound target must not turn close return stabs into a
	# millisecond damage/particle loop. Retain a readable native action beat.
	var travel_time := maxf(PIERCE_MIN_TIME if flight.evolved else 0.001, curve.get_baked_length() / STRIKE_SPEED)
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
			_strike_sword(flight, target, follow.global_position)
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
		var point := body.global_position + Vector3.UP * 1.05
		var hit := player.deal_fabao_damage(body, "swords", flight.coefficient, false, true, flight.through)
		if hit.get("actual", 0) > 0:
			sword_hits += 1
			# Per-contact flashes do not share the arena's camera/accent throttle.
			feedback.storm_hit(point, flight.through, bool(hit.get("lethal", false)))

func _call_meteor(target: Node3D, secondary := false) -> bool:
	if not active or not player.enabled or player.dead or progression.skill_level("meteor") <= 0 or meteors.size() >= 2:
		return false
	if not is_instance_valid(target) or target.dead or not target.is_visible_in_tree() or target.global_position.distance_to(player.global_position) > RANGE * player.stats.range_multiplier:
		return false
	meteor_count += 1
	var point := target.global_position
	point.y = 0.08
	var radius := METEOR_RADIUS * player.stats.range_multiplier
	var warning: MeshInstance3D = feedback.seal_warning(point, METEOR_DELAY, radius)
	# Keep the warning with its gameplay owner so toggling/death also cancels it.
	warning.reparent(self)
	var start := point + Vector3(-1.6, 7.8, -1.2)
	var meteor := SEAL_VISUAL.new()
	meteor.name = "ZhaotianSeal"
	meteor.feedback = feedback
	meteor.flight_vector = (start - point).normalized()
	meteor.position = to_local(start)
	meteor.rotation = Vector3(0.12, rng.randf_range(-PI, PI), -0.09)
	meteor.scale = Vector3.ONE * (0.9 + 0.06 * progression.skill_level("meteor"))
	add_child(meteor)
	var descent := meteor.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# Brief suspended charge followed by a committed, accelerating stamp.
	descent.tween_interval(0.22)
	descent.tween_property(meteor, "global_position", point, METEOR_DELAY - 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	descent.parallel().tween_property(meteor, "rotation", Vector3(0, meteor.rotation.y, 0), METEOR_DELAY - 0.22)
	meteors.append({"node": meteor, "tween": descent, "warning": warning, "position": point, "start": start, "left": METEOR_DELAY, "radius": radius, "coefficient": progression.coefficient("meteor"), "secondary": secondary})
	if secondary:
		feedback.fate_seal(point + Vector3.UP * 0.2, meteor)
	return true

func _advance_meteors(delta: float) -> void:
	for i in range(meteors.size() - 1, -1, -1):
		var meteor := meteors[i]
		meteor.left -= delta
		if meteor.left > 0.0:
			continue
		var point: Vector3 = meteor.position
		# Physics owns the exact contact tick; a tween never damages at a distance.
		meteor.tween.kill()
		meteor.node.global_position = point
		meteor.node.rotation.x = 0.0
		meteor.node.rotation.z = 0.0
		if is_instance_valid(meteor.warning):
			meteor.warning.queue_free()
		meteor.node.shatter()
		feedback.seal_impact(point, float(meteor.radius) / METEOR_RADIUS, meteor.node)
		meteor_query.shape.radius = meteor.radius
		meteor_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.6)
		var hit_ids: Array[int] = []
		for result in get_world_3d().direct_space_state.intersect_shape(meteor_query, 128):
			var body := result.collider as Node3D
			if not is_instance_valid(body) or body.dead or not body.is_visible_in_tree() or body.get_instance_id() in hit_ids:
				continue
			var offset := Vector2(body.global_position.x - point.x, body.global_position.z - point.z)
			if offset.length_squared() > float(meteor.radius) * float(meteor.radius):
				continue
			hit_ids.append(body.get_instance_id())
			var direction := (body.global_position - point).normalized()
			var hit := player.deal_fabao_damage(body, "meteor", meteor.coefficient, true, false, direction, true, meteor.secondary)
			if hit.get("actual", 0) > 0:
				meteor_hits += 1
		meteors.remove_at(i)
