extends Node3D
## Godot particles, mesh/material tweens and positional audio; no third-party runtime.

const SOUNDS := {
	"swish": preload("res://assets/audio/knifeSlice.ogg"),
	"spin": preload("res://assets/audio/knifeSlice2.ogg"),
	"charge": preload("res://assets/audio/impactBell_heavy_002.ogg"),
	"crack": preload("res://assets/audio/impactPlate_heavy_000.ogg"),
	"cloth": preload("res://assets/audio/cloth1.ogg"),
	"impact": preload("res://assets/audio/impactPunch_heavy_000.ogg"),
	"metal": preload("res://assets/audio/impactMetal_medium_000.ogg"),
	"shatter": preload("res://assets/audio/impactGlass_light_000.ogg"),
	"step0": preload("res://assets/audio/footstep_concrete_000.ogg"),
	"step1": preload("res://assets/audio/footstep_concrete_001.ogg"),
	"step2": preload("res://assets/audio/footstep_concrete_002.ogg"),
}

var random := RandomNumberGenerator.new()

func sound(key: String, pos: Vector3, volume := -5.0, pitch := 1.0) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.stream = SOUNDS[key]
	audio.bus = &"SFX"
	audio.volume_db = volume
	audio.pitch_scale = pitch * random.randf_range(0.96, 1.04)
	# The listener is on an elevated fixed camera, not at the player's ears.
	# Keep spatial panning, but do not attenuate every impact by camera height.
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	audio.max_distance = 0.0
	audio.attenuation_filter_cutoff_hz = 17000
	add_child(audio)
	audio.global_position = pos
	audio.finished.connect(audio.queue_free)
	# Skip source lead-in silence so the audible transient follows the animation event.
	audio.play(0.075 if key == "swish" else (0.014 if key == "spin" else 0.0))

func prewarm(fighter: DuelFighter) -> void:
	# Render each native material/particle variant behind the opening veil once.
	# This avoids first-contact shader compilation in the playable encounter.
	var was_muted := AudioServer.is_bus_mute(1)
	AudioServer.set_bus_mute(1, true)
	fighter.attack_direction = fighter.facing
	slash(fighter)
	impact(Vector3(0, 1, 0), Vector3.FORWARD, true, true)
	skill_charge(fighter)
	skill_spin(fighter)
	skill_release(fighter)
	await get_tree().create_timer(1.1).timeout
	AudioServer.set_bus_mute(1, was_muted)

func slash(fighter: DuelFighter) -> void:
	sound("swish", fighter.global_position, -1.5, 0.78)
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = fighter.global_position + Vector3.UP * 1.13
	pivot.rotation.y = atan2(fighter.attack_direction.x, fighter.attack_direction.z)
	var arc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.7, 4.7)
	arc.mesh = quad
	arc.rotation.x = -PI / 2.0
	arc.rotation.z = -0.1
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/slash.gdshader")
	material.set_shader_parameter("opacity", 1.0)
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(arc)
	# A short arc rides the actual swing; it is never a persistent ability effect.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(pivot, "rotation:y", pivot.rotation.y - 1.2, 0.17).from(pivot.rotation.y + 0.65)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("opacity", value), 1.0, 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(pivot.queue_free)
	_burst(fighter.global_position + Vector3.UP * 0.07, -fighter.attack_direction, 8, Color("a7977e"), 0.5, 0.8, 0.08)

func skill_charge(fighter: DuelFighter) -> void:
	sound("charge", fighter.global_position, -16.0, 1.5)
	var pos := fighter.global_position
	pos.y = 0.07
	_energy_wave(pos, 4.8, DuelFighter.SKILL_SWING, true)
	var motes := _burst(pos + Vector3.UP * 0.65, Vector3.UP, 24, Color("70e8ff"), 0.34, 0.1, 0.045)
	var process := motes.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 2.1
	process.emission_ring_inner_radius = 1.8
	process.emission_ring_height = 0.6
	process.gravity = Vector3.ZERO
	process.radial_accel_min = -48.0
	process.radial_accel_max = -40.0

func skill_spin(fighter: DuelFighter) -> void:
	sound("spin", fighter.global_position, -3.0, 0.65)
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = fighter.global_position + Vector3.UP * 1.12
	pivot.rotation.y = atan2(fighter.attack_direction.x, fighter.attack_direction.z) + 0.6
	for i in 2:
		var arc := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * (6.2 if i == 0 else 5.6)
		arc.mesh = quad
		arc.rotation = Vector3(-PI / 2.0, 0, i * PI)
		arc.position.y = i * 0.16
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/slash.gdshader")
		material.set_shader_parameter("tint", Color("209dd8"))
		material.set_shader_parameter("edge", Color("bafff6"))
		material.set_shader_parameter("opacity", 0.95 if i == 0 else 0.45)
		arc.material_override = material
		pivot.add_child(arc)
		var fade := create_tween()
		fade.tween_method(func(value: float) -> void: material.set_shader_parameter("opacity", value), 0.95 if i == 0 else 0.45, 0.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var turn := create_tween()
	turn.tween_property(pivot, "rotation:y", pivot.rotation.y - TAU * 1.08, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	turn.tween_callback(pivot.queue_free)

func skill_release(fighter: DuelFighter) -> void:
	var pos := fighter.global_position
	pos.y = 0.09
	_energy_wave(pos, 7.2, 0.48)
	var fragments := _burst(pos + Vector3.UP * 0.35, Vector3.UP, 42, Color("67d4ee"), 0.65, 2.0, 0.06)
	var process := fragments.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.4
	process.emission_ring_inner_radius = 0.8
	process.emission_ring_height = 0.1
	process.radial_accel_min = 14.0
	process.radial_accel_max = 22.0
	process.gravity = Vector3(0, -3, 0)
	ground_ring(pos, Color("91f4ff"), 0.35)

func _energy_wave(pos: Vector3, diameter: float, duration: float, inward := false) -> void:
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	ring.mesh = quad
	ring.rotation.x = -PI / 2.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/skill_ring.gdshader")
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("inward", inward)
	ring.material_override = material
	add_child(ring)
	ring.global_position = pos
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.0, duration)
	tween.tween_callback(ring.queue_free)

func impact(pos: Vector3, direction: Vector3, lethal: bool, heavy := false) -> void:
	sound("impact", pos, 0.0 if heavy else (1.0 if lethal else -1.0), 0.65 if heavy else (0.7 if lethal else 0.9))
	sound("crack" if heavy else "metal", pos, -9.0 if heavy else -10.0, 0.65 if heavy else 1.2)
	if lethal:
		sound("shatter", pos, -6.0, 0.78)
	var color := Color("90efff") if heavy else Color("ffca78")
	_burst(pos, direction + Vector3.UP * 0.2, 46 if heavy else (36 if lethal else 26), color, 0.48 if heavy else 0.42, 8.5 if heavy else 6.5, 0.065 if heavy else 0.055)
	_burst(pos, Vector3.UP, 9, Color("e0d6bc"), 0.62, 2.4, 0.065)
	# White-hot contact star: tiny and brief, readable without washing out the scene.
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 6.0 if heavy else 5.0
	flash.omni_range = 4.0 if heavy else 3.0
	add_child(flash)
	flash.global_position = pos
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.15)
	tween.tween_callback(flash.queue_free)
	for i in (5 if heavy else 3):
		var ray := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.035, 0.035, 0.65 + i * 0.24)
		ray.mesh = mesh
		ray.material_override = _emissive(Color("e2fcff") if heavy else Color("fff0c5"), 4.0)
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ray)
		ray.global_position = pos
		ray.rotation = Vector3(0.6 + i * 0.7, i * 1.1, 0.3)
		var fade := create_tween()
		fade.tween_property(ray, "scale", Vector3(0.01, 0.01, 1.7), 0.13)
		fade.tween_callback(ray.queue_free)
	ground_ring(Vector3(pos.x, 0.06, pos.z), color, 0.5 if heavy or lethal else 0.3)

func ground_ring(pos: Vector3, color: Color, duration: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.44
	mesh.outer_radius = 0.46
	mesh.rings = 48
	mesh.ring_segments = 4
	ring.mesh = mesh
	ring.material_override = _emissive(color, 1.1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = pos
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.3, 0.1, 3.3), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, duration)
	tween.chain().tween_callback(ring.queue_free)

func _burst(pos: Vector3, direction: Vector3, amount: int, color: Color, lifetime: float, speed: float, size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.visibility_aabb = AABB(Vector3(-5, -3, -5), Vector3(10, 10, 10))
	var process := ParticleProcessMaterial.new()
	process.direction = direction.normalized()
	process.spread = 65.0
	process.initial_velocity_min = speed * 0.35
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, -6, 0)
	process.damping_min = 1.0
	process.damping_max = 3.0
	process.scale_min = 0.5
	process.scale_max = 1.6
	process.particle_flag_align_y = true
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.add_point(0.4, color)
	gradient.set_color(1, Color(color.r * 0.5, color.g * 0.4, color.b * 0.3, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var spark := SphereMesh.new()
	spark.radius = size * 0.5
	spark.height = size * 3.8
	spark.radial_segments = 5
	spark.rings = 2
	var material := _emissive(color, 1.4)
	material.albedo_color = Color.WHITE
	material.emission_energy_multiplier = 2.4
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.material = material
	particles.draw_pass_1 = spark
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.35).timeout.connect(particles.queue_free)
	return particles

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
