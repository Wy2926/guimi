extends Area3D
## One following formation. Native overlaps and the existing fighter own all damage.

const MODEL = preload("res://assets/effects/taiji_aura/taiji_aura.glb")
const RING_SHADER = preload("res://shaders/astral_ring.gdshader")
const ENERGY_SHADER = preload("res://assets/weapons/astral_edge/energy.gdshader")
const SKILL_ID := "taiji_aura"
const PULSE_TIME := 0.42
const JADE := Color("59ddcc")
const GOLD := Color("f6d395")

var player: DuelFighter
var progression: RunProgression
var feedback: Node3D
var radius := 0.0
var cooldown_left := 0.0
var age := 0.0
var pulse_count := 0
var hit_count := 0

var _level := 0
var _collision: CollisionShape3D
var _shape: CylinderShape3D
var _visual: Node3D
var _model: Node3D
var _animation: AnimationPlayer
var _energy_meshes: Array[MeshInstance3D] = []
var _boundary: MeshInstance3D
var _pulse_ring: MeshInstance3D
var _emitters: Array[GPUParticles3D] = []
var _pulse_particles: GPUParticles3D
var _pulse_left := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitorable = false
	monitoring = false
	_collision = CollisionShape3D.new()
	_shape = CylinderShape3D.new()
	_shape.height = 2.4
	_collision.shape = _shape
	_collision.disabled = true
	add_child(_collision)
	refresh_skills()

func refresh_skills() -> void:
	_level = progression.skill_level(SKILL_ID) if is_instance_valid(progression) else 0
	if _level <= 0 or not is_instance_valid(player) or player.dead:
		_clear_visual()
		return
	var definition := progression.skill(SKILL_ID)
	radius = definition.radius_at(_level) * player.stats.range_multiplier
	_shape.set_deferred("radius", radius)
	_collision.set_deferred("disabled", false)
	set_deferred("monitoring", true)
	_follow_player()
	if not is_instance_valid(_visual):
		_make_visuals()
		cooldown_left = definition.cooldown * player.stats.cooldown_multiplier
	# Upgrades resize the same instance; they do not grant an extra free pulse.
	_visual.scale = Vector3(radius, 1.0, radius)

func reset() -> void:
	_clear_visual()
	_level = 0
	age = 0.0
	pulse_count = 0
	hit_count = 0
	# No rebuild here: victory/death retain run ranks but must dispose of the aura.

func _clear_visual() -> void:
	if is_instance_valid(_visual):
		_visual.hide()
		_visual.queue_free()
	_visual = null
	_model = null
	_animation = null
	_boundary = null
	_pulse_ring = null
	_pulse_particles = null
	_energy_meshes.clear()
	_emitters.clear()
	radius = 0.0
	cooldown_left = 0.0
	_pulse_left = 0.0
	set_deferred("monitoring", false)
	if is_instance_valid(_collision):
		_collision.set_deferred("disabled", true)

func _follow_player() -> void:
	# World-aligned; turning the character never spins the field or its collision.
	global_position = Vector3(player.global_position.x, 0.85, player.global_position.z)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.dead or not player.enabled:
		if is_instance_valid(_visual):
			_clear_visual()
		return
	if _level <= 0 or not is_instance_valid(_visual):
		return
	_follow_player()
	age += delta
	cooldown_left = maxf(0.0, cooldown_left - delta)
	_pulse_left = maxf(0.0, _pulse_left - delta)
	if cooldown_left <= 0.0:
		_pulse()
	if is_instance_valid(_visual):
		_update_visuals()

func _pulse() -> void:
	var definition := progression.skill(SKILL_ID)
	if definition == null:
		return
	cooldown_left = definition.cooldown * player.stats.cooldown_multiplier
	_pulse_left = PULSE_TIME
	pulse_count += 1
	_pulse_particles.restart()
	# Area3D returns every overlap (not a capped 16-result manual shape query).
	for target in get_overlapping_bodies():
		if not target.is_in_group("enemies") or target.dead:
			continue
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		# A body merely touching the cylinder must not be hit beyond the visible edge.
		if offset.length_squared() > radius * radius:
			continue
		var result := player.deal_fabao_damage(target, SKILL_ID, definition.coefficient_at(_level), false, false, offset, false)
		if float(result.get("actual", 0.0)) > 0.0:
			hit_count += 1
		# A lethal boss hit can finish and pause the run inside deal_damage.
		if not player.enabled or player.dead or get_tree().paused:
			break

func _make_visuals() -> void:
	_visual = Node3D.new()
	_visual.name = "TaijiFormation"
	_visual.position.y = -0.79
	add_child(_visual)
	_model = MODEL.instantiate() as Node3D
	_visual.add_child(_model)
	var materials: Dictionary = {}
	for item: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in item.mesh.get_surface_count():
			var original := item.mesh.surface_get_material(surface)
			var label := original.resource_name if original else ""
			if label not in ["TA_Cyan", "TA_Warm"]:
				continue
			if not materials.has(label):
				var material := ShaderMaterial.new()
				material.shader = ENERGY_SHADER
				material.set_shader_parameter("tint", JADE if label == "TA_Cyan" else GOLD)
				material.set_shader_parameter("layer", 1.0)
				materials[label] = material
			item.set_surface_override_material(surface, materials[label])
			if not _energy_meshes.has(item):
				_energy_meshes.append(item)
	_animation = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation and _animation.has_animation("TaijiOrbit"):
		var animation := _animation.get_animation("TaijiOrbit").duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR
		for library_name in _animation.get_animation_library_list():
			_animation.remove_animation_library(library_name)
		var library := AnimationLibrary.new()
		library.add_animation("TaijiOrbit", animation)
		_animation.add_animation_library("", library)
		_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		_animation.play("TaijiOrbit")
	_boundary = _make_ring("DamageBoundary", true)
	_boundary.material_override.set_shader_parameter("progress", 0.27)
	_pulse_ring = _make_ring("QingQiPulse", false)
	_pulse_ring.position.y = 0.015
	_pulse_ring.hide()
	# Reuse Feedback's emitter/material/ramp. Only this formation's motions differ.
	_make_particles("CyanCirculation", 64, JADE, 0.94, 0.12, 0.75, 0.0)
	_make_particles("GoldenMotes", 32, GOLD, 0.70, 0.04, 0.0, 0.42)
	var seals := _make_particles("RisingSeals", 16, JADE.lerp(GOLD, 0.4), 0.83, 0.14, -0.35, 0.16)
	var seal_mesh := PrismMesh.new()
	seal_mesh.size = Vector3(0.012, 0.045, 0.012)
	seal_mesh.material = seals.draw_pass_1.material
	seals.draw_pass_1 = seal_mesh
	_pulse_particles = _make_particles("PulseSparks", 48, GOLD, 0.46, 0.04, 0.0, 0.0)
	_pulse_particles.one_shot = true
	_pulse_particles.explosiveness = 1.0
	_pulse_particles.lifetime = PULSE_TIME
	_pulse_particles.emitting = false
	var pulse_process := _pulse_particles.process_material as ParticleProcessMaterial
	pulse_process.radial_velocity_min = 0.9
	pulse_process.radial_velocity_max = 1.15

func _make_ring(label: String, warning: bool) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = label
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (2.0 / 0.972)
	ring.mesh = quad
	ring.rotation.x = -PI / 2.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.set_shader_parameter("warning", warning)
	material.set_shader_parameter("tint", JADE * 0.4 if warning else JADE)
	material.set_shader_parameter("edge", GOLD * 0.5 if warning else GOLD)
	ring.material_override = material
	_visual.add_child(ring)
	return ring

func _make_particles(label: String, amount: int, color: Color, emission_radius: float, height: float, orbit_speed: float, rise_speed: float) -> GPUParticles3D:
	var particles: GPUParticles3D = feedback.attach_trail(_visual, color, amount, 0.8)
	particles.name = label
	particles.local_coords = true
	particles.position.y = height
	particles.visibility_aabb = AABB(Vector3(-1.3, -0.2, -1.3), Vector3(2.6, 1.7, 2.6))
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = emission_radius
	process.emission_ring_inner_radius = emission_radius - 0.045
	process.emission_ring_height = 0.06
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = rise_speed
	process.initial_velocity_max = rise_speed
	process.scale_min = 0.15
	process.scale_max = 0.45
	if label == "RisingSeals":
		process.scale_min = 0.65
		process.scale_max = 1.0
	if not is_zero_approx(orbit_speed):
		process.orbit_velocity_min = 1.0
		process.orbit_velocity_max = 1.0
		var orbit := CurveXYZTexture.new()
		var still := Curve.new()
		still.add_point(Vector2.ZERO)
		still.add_point(Vector2(1.0, 0.0))
		var spin := Curve.new()
		spin.min_value = -1.0
		spin.add_point(Vector2(0.0, orbit_speed))
		spin.add_point(Vector2(1.0, orbit_speed))
		orbit.curve_x = still
		orbit.curve_z = still
		orbit.curve_y = spin
		process.orbit_velocity_curve = orbit
	_emitters.append(particles)
	return particles

func _update_visuals() -> void:
	var flash := _pulse_left / PULSE_TIME
	for item in _energy_meshes:
		item.set_instance_shader_parameter("visual_time", age)
		item.set_instance_shader_parameter("power", flash * 0.45)
	_pulse_ring.visible = _pulse_left > 0.0
	_pulse_ring.scale = Vector3.ONE * lerpf(0.2, 1.0, smoothstep(0.0, 0.7, 1.0 - flash))
	_pulse_ring.material_override.set_shader_parameter("progress", 1.0 - flash)
