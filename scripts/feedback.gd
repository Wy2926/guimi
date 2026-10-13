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
var _last_storm_sound := -1000

func sound(key: String, pos: Vector3, volume := -5.0, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
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
	slash(fighter, "rise", true, 0)
	slash(fighter, "thrust", true, 0)
	var aura := create_ghost_aura(fighter)
	ghost_transition(fighter, true)
	impact(Vector3(0, 1, 0), Vector3.FORWARD, true, true)
	skill_charge(fighter)
	skill_spin(fighter)
	skill_release(fighter)
	storm_activate(Vector3(0, 0.08, 0))
	storm_muzzle(Vector3(0, 2.3, 0))
	storm_hit(Vector3(0, 1.0, 0), Vector3.FORWARD)
	meteor_warning(Vector3.ZERO, 0.5)
	meteor_impact(Vector3.ZERO)
	await get_tree().create_timer(1.1, false).timeout
	if is_instance_valid(aura):
		aura.free()
	AudioServer.set_bus_mute(1, was_muted)

func slash(fighter: DuelFighter, style: String = "horizontal", ghost: bool = false, strike: int = 0, finisher: bool = false) -> void:
	# Every call comes from an authored animation's strike event, not an idle timer.
	# Reuse the existing crescent material on differently oriented native quads.
	sound("spin" if style == "spin" else "swish", fighter.global_position, -3.0 if ghost else -1.5, (1.06 if ghost else 0.82) + strike * 0.07)
	var pivot := Node3D.new()
	pivot.name = "GhostSlash" if ghost else "ComboSlash"
	add_child(pivot)
	pivot.global_position = fighter.global_position + Vector3.UP * (1.05 if style == "rise" else 1.2)
	pivot.rotation.y = atan2(fighter.attack_direction.x, fighter.attack_direction.z)
	var plane := Vector3(-PI / 2.0, 0.0, -0.13)
	var sweep := -1.65
	var diameter := 6.4 if ghost else 5.2
	var duration := 0.30
	match style:
		"rise":
			plane = Vector3(-0.90, 0.0, -0.48)
			sweep = 1.45
		"reverse":
			plane = Vector3(-1.08, 0.0, 0.3)
			sweep = 1.9
		"down":
			plane = Vector3(-0.32, PI / 2.0 - 0.52, -0.18)
			sweep = -0.45
			diameter += 0.35
			duration = 0.34
		"spin":
			plane = Vector3(-1.12 if strike % 2 == 0 else -1.82, 0.0, -0.12 if strike % 2 == 0 else 0.18)
			# The authored multi-turn clip crosses a different world-space arc per hit.
			pivot.rotation.y += strike * TAU / 3.0
			sweep = -2.35
			diameter += 0.3
		"thrust":
			plane = Vector3(-PI / 2.0, 0.0, 0.0)
			sweep = 0.0
	if finisher:
		diameter += 0.6
	diameter *= fighter.stats.range_multiplier
	var layers := 3 if ghost and finisher else 2
	for layer in layers:
		var arc := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.2 + layer * 0.3, diameter) if style == "thrust" else Vector2.ONE * (diameter + layer * 0.28)
		arc.mesh = quad
		arc.rotation = plane
		arc.rotation.z += layer * (0.1 if ghost else 0.045)
		arc.position.y = layer * 0.045
		if style == "thrust":
			arc.position.z = 0.85
		elif style == "down":
			arc.position.z = 0.8
			arc.position.x = 0.18
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/slash.gdshader")
		material.set_shader_parameter("tint", Color("d81a4c") if ghost else Color("f9a128"))
		material.set_shader_parameter("edge", Color("edc4ff") if ghost else Color("fff0c4"))
		material.set_shader_parameter("width", (0.26 if ghost else 0.22) if layer == 0 else 0.045)
		material.set_shader_parameter("thrust", style == "thrust")
		material.set_shader_parameter("ghost", ghost)
		var opacity := (0.83 if ghost else 0.9) if layer == 0 else 0.5
		material.set_shader_parameter("opacity", opacity)
		arc.material_override = material
		pivot.add_child(arc)
		var fade := arc.create_tween()
		fade.tween_method(func(value: float) -> void: material.set_shader_parameter("opacity", value), opacity, 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var tween := pivot.create_tween().set_parallel(true)
	tween.tween_property(pivot, "rotation:y", pivot.rotation.y + sweep * 0.65, duration * 0.82).from(pivot.rotation.y - sweep * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if style == "down":
		tween.tween_property(pivot, "position:y", pivot.position.y - 0.45, duration)
	elif style == "rise":
		tween.tween_property(pivot, "position:y", pivot.position.y + 0.5, duration)
	elif style == "thrust":
		tween.tween_property(pivot, "position", pivot.position + fighter.attack_direction * 0.75, duration)
	tween.tween_interval(duration)
	tween.chain().tween_callback(pivot.queue_free)
	var sparks := _burst(fighter.global_position + fighter.attack_direction * 1.15 + Vector3.UP * 1.05, fighter.attack_direction + Vector3.UP * 0.25, 18 if ghost else 12, Color("ff3977") if ghost else Color("ffc55e"), 0.32, 3.8 if ghost else 3.0, 0.035)
	var process := sparks.process_material as ParticleProcessMaterial
	process.spread = 28.0
	process.gravity = Vector3(0, -2.0, 0)
	if finisher:
		ground_ring(fighter.global_position + fighter.attack_direction * 1.2 + Vector3.UP * 0.07, Color("ac47e7") if ghost else Color("d99544"), 0.3, 3.4)

func create_ghost_aura(fighter: DuelFighter) -> Node3D:
	# The fighter owns this one native emitter. Death/reset/exit can free it at once.
	var aura := Node3D.new()
	aura.name = "GhostAura"
	fighter.add_child(aura)
	var motes := attach_trail(aura, Color("ed2463"), 24, 0.7)
	motes.name = "GhostEmbers"
	motes.position.y = 0.06
	var process := motes.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.68
	process.emission_ring_inner_radius = 0.36
	process.emission_ring_height = 0.08
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.3
	process.gravity = Vector3(0, 0.35, 0)
	process.tangential_accel_min = 0.7
	process.tangential_accel_max = 1.6
	process.particle_flag_align_y = true
	var spark := motes.draw_pass_1 as SphereMesh
	spark.radius = 0.017
	spark.height = 0.17
	var gradient := Gradient.new()
	gradient.set_color(0, Color("f94d86"))
	gradient.set_color(1, Color(0.19, 0.04, 0.32, 0.0))
	gradient.add_point(0.38, Color("983bdd"))
	(process.color_ramp as GradientTexture1D).gradient = gradient
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.6
	mesh.outer_radius = 0.615
	mesh.rings = 40
	mesh.ring_segments = 4
	ring.mesh = mesh
	ring.position.y = 0.045
	ring.scale.y = 0.18
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = _emissive(Color("782555"), 0.7)
	aura.add_child(ring)
	return aura

func ghost_transition(fighter: DuelFighter, enabled: bool) -> void:
	var pos := fighter.global_position + Vector3.UP * 0.075
	sound("charge" if enabled else "cloth", pos, -12.0 if enabled else -17.0, 0.72 if enabled else 0.9)
	ground_ring(pos, Color("c444bd") if enabled else Color("6b466b"), 0.4, 4.2 if enabled else 2.3)
	if not enabled:
		return
	var embers := _burst(pos, Vector3.UP, 28, Color("f3417d"), 0.65, 2.5, 0.042)
	var process := embers.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.72
	process.emission_ring_inner_radius = 0.3
	process.emission_ring_height = 0.1
	process.spread = 12.0
	process.gravity = Vector3(0, 1.0, 0)
	_light_flash(pos + Vector3.UP * 1.2, Color("ab3b94"), 1.8, 3.0, 0.2)

func skill_charge(fighter: DuelFighter) -> void:
	sound("charge", fighter.global_position, -16.0, 1.5)
	var pos := fighter.global_position
	pos.y = 0.07
	_energy_wave(pos, 4.8 * fighter.stats.range_multiplier, DuelFighter.SKILL_SWING, true)
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
	pivot.scale = Vector3.ONE * fighter.stats.range_multiplier * (1.3 if fighter.ghost_active else 1.0)
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
	_energy_wave(pos, 7.2 * fighter.stats.range_multiplier * (1.3 if fighter.ghost_active else 1.0), 0.48)
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

func storm_activate(pos: Vector3) -> void:
	sound("charge", pos, -14.0, 1.15)
	sound("shatter", pos, -20.0, 1.65)
	_astral_ring(Vector3(pos.x, 0.085, pos.z), 5.2, 1.0, false, Color("21bfff"), Color("ffe0a0"))
	var motes := _burst(pos + Vector3.UP * 0.12, Vector3.UP, 34, Color("6bebff"), 0.85, 2.4, 0.045)
	var process := motes.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.55
	process.emission_ring_inner_radius = 1.2
	process.emission_ring_height = 0.1
	process.spread = 8.0
	process.gravity = Vector3(0, 0.8, 0)
	process.tangential_accel_min = 3.0
	process.tangential_accel_max = 5.0
	_burst(pos + Vector3.UP * 1.65, Vector3.UP, 12, Color("ffe4a9"), 0.65, 1.4, 0.038)
	_light_flash(pos + Vector3.UP * 1.6, Color("56d7ff"), 2.0, 4.5, 0.38)

func storm_muzzle(pos: Vector3) -> void:
	var motes := _burst(pos, Vector3.UP, 5, Color("8cf6ff"), 0.24, 1.6, 0.027)
	var process := motes.process_material as ParticleProcessMaterial
	process.gravity = Vector3.ZERO
	process.spread = 100.0

func storm_hit(pos: Vector3, direction: Vector3, lethal := false) -> void:
	# A volley can hit several enemies together: keep the per-sword accent light.
	var now := Time.get_ticks_msec()
	if now - _last_storm_sound >= 85:
		sound("metal", pos, -17.5, 1.55)
		_last_storm_sound = now
	var sparks := _burst(pos, direction + Vector3.UP * 0.2, 14 if lethal else 10, Color("94f1ff"), 0.3, 4.0, 0.033)
	var process := sparks.process_material as ParticleProcessMaterial
	process.gravity = Vector3(0, -2.0, 0)
	for i in 2:
		var ray := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.024, 0.024, 0.46 + i * 0.18)
		ray.mesh = mesh
		ray.material_override = _emissive(Color("d2faff") if i == 0 else Color("ffe2a2"), 2.0)
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ray)
		ray.global_position = pos
		ray.rotation = Vector3(0.6 + i, atan2(direction.x, direction.z) + i * 1.2, 0.4)
		var tween := ray.create_tween()
		tween.tween_property(ray, "scale", Vector3(0.02, 0.02, 1.45), 0.12)
		tween.tween_callback(ray.queue_free)

func meteor_warning(pos: Vector3, duration: float, radius := 3.2) -> MeshInstance3D:
	# The outside circle declares the damage radius; the inner one closes.
	return _astral_ring(Vector3(pos.x, 0.095, pos.z), radius * 2.0, maxf(0.05, duration), true, Color("f66a24"), Color("ffdd94"))

func meteor_impact(pos: Vector3, range_scale := 1.0) -> void:
	var center := Vector3(pos.x, 0.18, pos.z)
	sound("impact", center, -1.0, 0.52)
	sound("crack", center, -8.0, 0.55)
	sound("shatter", center, -17.0, 0.72)
	var fragments := _burst(center, Vector3.UP, 48, Color("ffb05b"), 0.7, 8.5, 0.09)
	var process := fragments.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.65
	process.emission_ring_inner_radius = 0.1
	process.emission_ring_height = 0.12
	process.spread = 72.0
	process.gravity = Vector3(0, -13.0, 0)
	var embers := _burst(center, Vector3.UP, 26, Color("ff763c"), 1.0, 3.0, 0.044)
	var ember_process := embers.process_material as ParticleProcessMaterial
	ember_process.gravity = Vector3(0, 0.65, 0)
	ember_process.spread = 80.0
	ember_process.radial_accel_min = 1.0
	ember_process.radial_accel_max = 2.4
	_burst(center, Vector3.UP, 14, Color("be9270"), 0.7, 3.4, 0.075)
	ground_ring(Vector3(pos.x, 0.07, pos.z), Color("ffbe70"), 0.43, 7.0 * range_scale)
	ground_ring(Vector3(pos.x, 0.075, pos.z), Color("f46b36"), 0.65, 8.0 * range_scale)
	_light_flash(center + Vector3.UP * 0.75, Color("ffb15e"), 4.5, 6.0, 0.26)

func attach_trail(parent: Node3D, color: Color, amount: int = 18, lifetime: float = 0.26) -> GPUParticles3D:
	# Native world-space particles leave a curved wake as their parent follows Curve3D.
	# The projectile owns this emitter; freeing that node also frees its GPU resources.
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.amount = clampi(amount, 4, 64)
	particles.lifetime = clampf(lifetime, 0.1, 0.8)
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-20, -12, -20), Vector3(40, 30, 40))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.055
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.03
	process.initial_velocity_max = 0.25
	process.gravity = Vector3.ZERO
	process.scale_min = 0.4
	process.scale_max = 1.25
	var gradient := Gradient.new()
	gradient.set_color(0, Color("e0fcff").lerp(color, 0.45))
	gradient.set_color(1, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0))
	gradient.add_point(0.25, color)
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var spark := SphereMesh.new()
	spark.radius = 0.028
	spark.height = 0.056
	spark.radial_segments = 5
	spark.rings = 2
	var material := _emissive(color, 1.2)
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.material = material
	particles.draw_pass_1 = spark
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	particles.emitting = true
	return particles

func _astral_ring(pos: Vector3, diameter: float, duration: float, warning: bool, color: Color, edge: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	ring.mesh = quad
	ring.rotation.x = -PI / 2.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/astral_ring.gdshader")
	material.set_shader_parameter("warning", warning)
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("edge", edge)
	ring.material_override = material
	add_child(ring)
	ring.global_position = pos
	var tween := ring.create_tween()
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.0, duration)
	tween.tween_callback(ring.queue_free)
	return ring

func _light_flash(pos: Vector3, color: Color, energy: float, radius: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)

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

func impact(pos: Vector3, direction: Vector3, lethal: bool, heavy := false, ghost := false, last := false) -> void:
	sound("impact", pos, (-3.0 if ghost and not last else 0.0) if heavy else (1.0 if lethal else -1.0), (0.62 if last else 1.12) if ghost else (0.65 if heavy else (0.7 if lethal else 0.9)))
	sound("crack" if heavy or last else "metal", pos, -12.0 if ghost else (-9.0 if heavy else -10.0), 0.78 if ghost else (0.65 if heavy else 1.2))
	if lethal:
		sound("shatter", pos, -6.0, 0.78)
	var color := Color("f64788") if ghost else (Color("90efff") if heavy else Color("ffca78"))
	var amount := (38 if last or lethal else 18) if ghost else (46 if heavy else (36 if lethal else 26))
	_burst(pos, direction + Vector3.UP * 0.2, amount, color, 0.35 if ghost and not last else (0.48 if heavy else 0.42), 8.5 if heavy or last else 6.5, 0.047 if ghost else (0.065 if heavy else 0.055))
	_burst(pos, Vector3.UP, 4 if ghost else 9, Color("a950c2") if ghost else Color("e0d6bc"), 0.45 if ghost else 0.62, 2.4, 0.048 if ghost else 0.065)
	# White-hot contact star: tiny and brief, readable without washing out the scene.
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = (3.0 if last else 2.2) if ghost else (6.0 if heavy else 5.0)
	flash.omni_range = 4.0 if heavy else 3.0
	flash.shadow_enabled = false
	add_child(flash)
	flash.global_position = pos
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.15)
	tween.tween_callback(flash.queue_free)
	for i in ((4 if last else 2) if ghost else (5 if heavy else 3)):
		var ray := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.035, 0.035, 0.65 + i * 0.24)
		ray.mesh = mesh
		ray.material_override = _emissive(Color("ecd0ff") if ghost else (Color("e2fcff") if heavy else Color("fff0c5")), 2.3 if ghost else 4.0)
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ray)
		ray.global_position = pos
		ray.rotation = Vector3(0.6 + i * 0.7, i * 1.1, 0.3)
		var fade := create_tween()
		fade.tween_property(ray, "scale", Vector3(0.01, 0.01, 1.7), 0.13)
		fade.tween_callback(ray.queue_free)
	ground_ring(Vector3(pos.x, 0.06, pos.z), color, 0.5 if heavy or lethal else 0.3)

func ground_ring(pos: Vector3, color: Color, duration: float, scale_factor := 3.3) -> void:
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
	tween.tween_property(ring, "scale", Vector3(scale_factor, 0.1, scale_factor), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
	gradient.set_color(1, Color(color.r * 0.5, color.g * 0.4, color.b * 0.3, 0.0))
	gradient.add_point(0.4, color)
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
	var cleanup := particles.create_tween()
	cleanup.tween_interval(lifetime + 0.35)
	cleanup.tween_callback(particles.queue_free)
	return particles

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
