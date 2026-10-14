extends Area3D
## A compact projectile becomes a stationary, expanding dark-magic gravity well.

signal expired(orb: Node3D)

const MODEL = preload("res://assets/effects/thunder_orb/thunder_orb.glb")
const CORE_SHADER = preload("res://assets/effects/thunder_orb/singularity.gdshader")
const ENERGY_SHADER = preload("res://assets/weapons/astral_edge/energy.gdshader")
const RING_SHADER = preload("res://shaders/astral_ring.gdshader")
const HIT_INTERVAL := 0.35
const FLIGHT_RADIUS := 0.72
const EXPAND_TIME := 0.42
const COLLAPSE_TIME := 0.32
const SLOW_RATIO := 0.55
const PULL_SPEED := 3.8

enum Phase { FLIGHT, WELL, COLLAPSE }

var manager: Node3D
var feedback: Node3D
var direction := Vector3.FORWARD
var speed := 2.8
var radius := 2.6
var visual_scale := 1.0
var life_left := 4.0
var age := 0.0
var arena_radius := 15.8
var coefficient := 0.6
var kind := DamageRules.Kind.MAGICAL
var element := DamageRules.Element.DARK
var phase := Phase.FLIGHT
var current_radius := FLIGHT_RADIUS

var _well_duration := 4.0
var _expired := false
var _next_hits: Dictionary = {}
var _affected: Array[Node3D] = []
var _shape: CylinderShape3D
var _visual: Node3D
var _animation: AnimationPlayer
var _energy_meshes: Array[MeshInstance3D] = []
var _lightning: Array[Node3D] = []
var _field: Node3D
var _boundary: MeshInstance3D
var _trail: GPUParticles3D
var _infall: GPUParticles3D
var _mist: GPUParticles3D
var _transition: Tween
var _flash_left := 0.0

func configure(source: Node3D, heading: Vector3, definition: SkillDefinition, level: int, reach: float, boundary: float) -> void:
	manager = source
	direction = Vector3(heading.x, 0.0, heading.z).normalized()
	radius = definition.radius_at(level) * reach
	visual_scale = definition.visual_scale_at(level) * reach
	current_radius = FLIGHT_RADIUS * visual_scale
	_well_duration = definition.duration_at(level)
	life_left = 4.0
	coefficient = definition.coefficient_at(level)
	kind = definition.kind
	element = definition.element
	arena_radius = boundary

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitorable = false
	var collision := CollisionShape3D.new()
	_shape = CylinderShape3D.new()
	_shape.radius = current_radius
	_shape.height = 2.4
	collision.shape = _shape
	add_child(collision)
	body_exited.connect(_on_body_exited)
	_make_visuals()

func _physics_process(delta: float) -> void:
	if _expired:
		return
	if not is_instance_valid(manager) or not is_instance_valid(manager.player) or manager.player.dead or not manager.player.enabled:
		cancel()
		return
	age += delta
	life_left = maxf(0.0, life_left - delta)
	if phase == Phase.FLIGHT:
		global_position += direction * speed * delta
	if phase != Phase.COLLAPSE:
		if life_left <= 0.0 or Vector2(global_position.x, global_position.z).length() > arena_radius:
			_collapse()
		else:
			for body in get_overlapping_bodies():
				if not body.is_in_group("enemies") or body.dead:
					continue
				if phase == Phase.FLIGHT:
					_anchor()
				if not _affected.has(body):
					_affected.append(body)
					body.add_gravity_well(self)
				var target_id := body.get_instance_id()
				if age + 0.00001 < float(_next_hits.get(target_id, 0.0)):
					continue
				_next_hits[target_id] = age + HIT_INTERVAL
				manager.contact(body, self)
				if _expired or manager.player.dead or not manager.player.enabled:
					return
	_update_visuals(delta)

func _anchor() -> void:
	phase = Phase.WELL
	speed = 0.0
	life_left = _well_duration
	_field.show()
	if is_instance_valid(_trail):
		_trail.emitting = false
		_infall.emitting = true
		_mist.emitting = true
	_transition = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel(true)
	_transition.tween_method(_set_radius, current_radius, radius, EXPAND_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(_visual, "scale", Vector3.ONE * visual_scale * 1.08, EXPAND_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_instance_valid(feedback):
		var burst: GPUParticles3D = feedback._burst(global_position, Vector3.UP, 26, Color("c681ff"), 0.42, 3.3, 0.036)
		burst.name = "ContactSparks"
		burst.reparent(self)
		feedback.sound("charge", global_position, -17.0, 0.65)
	flash_hit()

func _set_radius(value: float) -> void:
	current_radius = value
	_shape.set_deferred("radius", value)

func influence_at(point: Vector3) -> float:
	if _expired or phase != Phase.WELL:
		return 0.0
	var distance := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	if distance > current_radius:
		return 0.0
	return lerpf(1.0, 0.65, distance / maxf(current_radius, 0.001))

func flash_hit() -> void:
	_flash_left = 0.11

func _on_body_exited(body: Node3D) -> void:
	_affected.erase(body)
	if is_instance_valid(body) and body.has_method("remove_gravity_well"):
		body.remove_gravity_well(self)

func _release_targets() -> void:
	for target in _affected:
		if is_instance_valid(target):
			target.remove_gravity_well(self)
	_affected.clear()

func _collapse() -> void:
	phase = Phase.COLLAPSE
	set_deferred("monitoring", false)
	_release_targets()
	if is_instance_valid(_transition):
		_transition.kill()
	for particles in [_trail, _infall, _mist]:
		if is_instance_valid(particles):
			particles.emitting = false
	_transition = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel(true)
	_transition.tween_property(_visual, "scale", Vector3.ONE * 0.015, COLLAPSE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition.tween_method(_set_radius, current_radius, 0.01, COLLAPSE_TIME)
	_transition.chain().tween_callback(cancel)

func cancel() -> void:
	if _expired:
		return
	_expired = true
	if is_instance_valid(_transition):
		_transition.kill()
	_release_targets()
	set_physics_process(false)
	set_deferred("monitoring", false)
	hide()
	expired.emit(self)
	queue_free()

func _exit_tree() -> void:
	_release_targets()

func _make_visuals() -> void:
	_visual = MODEL.instantiate() as Node3D
	_visual.name = "BlackHoleModel"
	_visual.scale = Vector3.ONE * visual_scale * 0.70
	add_child(_visual)
	var materials: Dictionary = {}
	for item: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var animated_material := false
		for surface in item.mesh.get_surface_count():
			var original := item.mesh.surface_get_material(surface)
			var label := original.resource_name if original else ""
			if "Debris" in label:
				continue
			if not materials.has(label):
				var material := ShaderMaterial.new()
				material.shader = CORE_SHADER if "Core" in label else ENERGY_SHADER
				if "Core" not in label:
					material.set_shader_parameter("tint", Color("ca8dff") if "Lightning" in label else Color("8835e5"))
					material.set_shader_parameter("layer", 0.0 if "Accretion" in label else 1.0)
				materials[label] = material
			item.set_surface_override_material(surface, materials[label])
			animated_material = true
		if animated_material:
			_energy_meshes.append(item)
	for i in 3:
		var branch := _visual.find_child("Lightning%d" % i, true, false) as Node3D
		if branch:
			_lightning.append(branch)
	_animation = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation and _animation.has_animation("VortexOrbit"):
		# Private copy: do not mutate animation Resources shared by other orb instances.
		var loop := _animation.get_animation("VortexOrbit").duplicate(true) as Animation
		loop.loop_mode = Animation.LOOP_LINEAR
		for library_name in _animation.get_animation_library_list():
			_animation.remove_animation_library(library_name)
		var library := AnimationLibrary.new()
		library.add_animation("VortexOrbit", loop)
		_animation.add_animation_library("", library)
		_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		_animation.play("VortexOrbit")
	_field = Node3D.new()
	_field.name = "GravityField"
	add_child(_field)
	_field.hide()
	_boundary = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (2.0 / 0.972)
	_boundary.mesh = quad
	_boundary.rotation.x = -PI / 2.0
	_boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.set_shader_parameter("warning", true)
	material.set_shader_parameter("tint", Color(0.28, 0.025, 0.52, 0.5))
	material.set_shader_parameter("edge", Color("ba79ef"))
	_boundary.material_override = material
	_field.add_child(_boundary)
	if is_instance_valid(feedback):
		_trail = feedback.attach_trail(self, Color("8d36e8"), 20, 0.30)
		_trail.name = "VioletWake"
		_infall = _make_infall("InwardSparks", 48, Color("bb76ff"), false)
		_mist = _make_infall("VortexMist", 20, Color(0.24, 0.035, 0.42, 0.2), true)

func _make_infall(label: String, amount: int, color: Color, soft: bool) -> GPUParticles3D:
	# Reuse the existing emitter, ramp and particle material, then author this motion.
	var particles: GPUParticles3D = feedback.attach_trail(_field, color, amount, 0.8)
	particles.name = label
	particles.emitting = false
	particles.local_coords = true
	particles.position.y = 0.65
	particles.visibility_aabb = AABB(Vector3(-1.4, -1.0, -1.4), Vector3(2.8, 3.0, 2.8))
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.0
	process.emission_ring_inner_radius = 0.85
	process.emission_ring_height = 0.38 if soft else 0.22
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.radial_velocity_min = -1.05
	process.radial_velocity_max = -0.85
	process.orbit_velocity_min = 1.0
	process.orbit_velocity_max = 1.0
	# 3D orbital velocity uses a CurveXYZTexture; Y is the floor's normal.
	var orbit := CurveXYZTexture.new()
	var still := Curve.new()
	still.add_point(Vector2.ZERO)
	still.add_point(Vector2(1.0, 0.0))
	orbit.curve_x = still
	orbit.curve_z = still
	var spin := Curve.new()
	spin.add_point(Vector2(0.0, 0.32 if soft else 0.52))
	spin.add_point(Vector2(1.0, 0.75))
	orbit.curve_y = spin
	process.orbit_velocity_curve = orbit
	var size := Curve.new()
	size.add_point(Vector2(0.0, 0.0))
	size.add_point(Vector2(0.15, 1.0))
	size.add_point(Vector2(1.0, 0.0))
	var size_curve := CurveTexture.new()
	size_curve.curve = size
	process.scale_curve = size_curve
	if soft:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.24, 0.14)
		var material := particles.draw_pass_1.material as StandardMaterial3D
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.emission_energy_multiplier = 0.5
		var spot := GradientTexture2D.new()
		spot.width = 32
		spot.height = 32
		spot.fill = GradientTexture2D.FILL_RADIAL
		spot.fill_from = Vector2(0.5, 0.5)
		spot.fill_to = Vector2(1.0, 0.5)
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1, 1, 1, 0))
		spot.gradient = gradient
		material.albedo_texture = spot
		quad.material = material
		particles.draw_pass_1 = quad
	return particles

func _update_visuals(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	var flash := _flash_left / 0.11
	for item in _energy_meshes:
		item.set_instance_shader_parameter("visual_time", age)
		item.set_instance_shader_parameter("power", flash * 0.7)
	for i in _lightning.size():
		_lightning[i].visible = flash > 0.0 or (int(age * 16.0) + i * 3) % 7 < 5
	_field.position.y = -global_position.y + 0.07
	_field.scale = Vector3(current_radius, 1.0, current_radius)
	_boundary.rotation.z = age * -0.22
	_boundary.material_override.set_shader_parameter("progress", 0.20 + 0.55 * (1.0 - life_left / _well_duration))
