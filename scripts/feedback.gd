extends Node3D
## Godot particles, mesh/material tweens and positional audio; no third-party runtime.

const SWORD_IMPACT := preload("res://assets/weapons/astral_edge/impact.tscn")
const MAX_REACTION_EFFECTS := 32

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
var _reaction_roots: Array[Node3D] = []

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
	slash(fighter, "rise")
	slash(fighter, "down", false, 0, true)
	impact(Vector3(0, 1, 0), Vector3.FORWARD, true, true)
	storm_activate(Vector3(0, 0.08, 0))
	storm_muzzle(Vector3(0, 2.3, 0))
	storm_hit(Vector3(0, 1.0, 0), Vector3.FORWARD)
	seal_warning(Vector3.ZERO, 0.5)
	var seal := preload("res://assets/effects/zhaotian_seal/zhaotian_seal.gd").new()
	seal.feedback = self
	add_child(seal)
	seal.shatter()
	seal_impact(Vector3.ZERO, 1.0, seal)
	shock_chain(Vector3(-1, 0.8, 0), Vector3(1, 0.8, 0))
	curse_spread(Vector3(1, 0.8, 0), Vector3(-1, 0.8, 0))
	ice_shatter(Vector3.ZERO)
	ice_contact(Vector3(0, 0.8, 0))
	ribbon_fire_contact(Vector3(0, 0.8, 0), Vector3.FORWARD, fighter)
	sword_pierce(Vector3(0, 1.2, 0), Vector3.FORWARD, fighter)
	fate_seal(Vector3(0, 0.2, 0), fighter)
	await get_tree().create_timer(1.1, false).timeout
	AudioServer.set_bus_mute(1, was_muted)

func slash(fighter: DuelFighter, style: String = "horizontal", ghost: bool = false, strike: int = 0, finisher: bool = false) -> void:
	# Every call comes from an authored animation's strike event, not an idle timer.
	# Reuse the existing crescent material on differently oriented native quads.
	sound("spin" if style == "spin" else "swish", fighter.global_position, -3.0 if ghost else -1.5, (1.06 if ghost else 0.82) + strike * 0.07)
	var pivot := Node3D.new()
	pivot.name = "DivinitySlash" if ghost else "ComboSlash"
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
	var reach := fighter.stats.range_multiplier
	diameter *= reach
	var layers := 3 if ghost and finisher else 2
	for layer in layers:
		var arc := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2((1.2 + layer * 0.3) * reach, diameter) if style == "thrust" else Vector2.ONE * (diameter + layer * 0.28)
		arc.mesh = quad
		arc.rotation = plane
		arc.rotation.z += layer * (0.1 if ghost else 0.045)
		arc.position.y = layer * 0.045
		if style == "thrust":
			arc.position.z = 0.85 * reach
		elif style == "down":
			arc.position.z = 0.8 * reach
			arc.position.x = 0.18 * reach
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
		tween.tween_property(pivot, "position", pivot.position + fighter.attack_direction * (0.75 * reach), duration)
	tween.tween_interval(duration)
	tween.chain().tween_callback(pivot.queue_free)
	var sparks := _burst(fighter.global_position + fighter.attack_direction * (1.15 * reach) + Vector3.UP * 1.05, fighter.attack_direction + Vector3.UP * 0.25, 18 if ghost else 12, Color("ff3977") if ghost else Color("ffc55e"), 0.32, 3.8 if ghost else 3.0, 0.035)
	var process := sparks.process_material as ParticleProcessMaterial
	process.spread = 28.0
	process.gravity = Vector3(0, -2.0, 0)
	if finisher:
		ground_ring(fighter.global_position + fighter.attack_direction * (1.2 * reach) + Vector3.UP * 0.07, Color("ac47e7") if ghost else Color("d99544"), 0.3, 3.4 * reach)

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
	# Every actual contact gets a local flash; expensive light/audio accents stay capped.
	var now := Time.get_ticks_msec()
	if now - _last_storm_sound >= 85:
		sound("metal", pos, -13.5, 1.35)
		_light_flash(pos, Color("bdefff"), 2.8, 2.6, 0.10)
		_last_storm_sound = now
	var impact := SWORD_IMPACT.instantiate() as Node3D
	impact.direction = direction
	impact.scale = Vector3.ONE * (1.0 if lethal else 0.85)
	add_child(impact)
	impact.global_position = pos

func seal_warning(pos: Vector3, duration: float, radius := 3.2) -> MeshInstance3D:
	# The outside circle declares the damage radius; the inner one closes.
	# astral_ring's outer stroke is at UV radius 0.972, not the quad's edge.
	return _astral_ring(Vector3(pos.x, 0.095, pos.z), radius * 2.0 / 0.972, maxf(0.05, duration), true, Color("f66a24"), Color("ffdd94"))

func seal_impact(pos: Vector3, range_scale := 1.0, owner_node: Node3D = null) -> void:
	var center := Vector3(pos.x, 0.18, pos.z)
	sound("impact", center, -1.0, 0.52)
	sound("crack", center, -8.0, 0.55)
	sound("shatter", center, -17.0, 0.72)
	var fragments := _burst(center, Vector3.UP, 48, Color("ffb05b"), 0.7, 8.5, 0.09)
	fragments.name = "SealContactSparks"
	var process := fragments.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.65
	process.emission_ring_inner_radius = 0.1
	process.emission_ring_height = 0.12
	process.spread = 72.0
	process.gravity = Vector3(0, -13.0, 0)
	var embers := _burst(center, Vector3.UP, 26, Color("ff763c"), 1.0, 3.0, 0.044)
	embers.name = "SealRisingEmbers"
	var ember_process := embers.process_material as ParticleProcessMaterial
	ember_process.gravity = Vector3(0, 0.65, 0)
	ember_process.spread = 80.0
	ember_process.radial_accel_min = 1.0
	ember_process.radial_accel_max = 2.4
	var dust := _burst(center, Vector3.UP, 14, Color("a17b61"), 0.72, 3.4, 0.075)
	dust.name = "SealGroundDust"
	var dust_process := dust.process_material as ParticleProcessMaterial
	dust_process.spread = 88.0
	dust_process.gravity = Vector3(0, -1.0, 0)
	# Unlit, non-emissive, softly transparent dust instead of another bright spark.
	var dust_mesh := QuadMesh.new()
	dust_mesh.size = Vector2.ONE * 0.36
	var dust_material := StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_material.vertex_color_use_as_albedo = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.22))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	dust_material.albedo_texture = texture
	dust_mesh.material = dust_material
	dust.draw_pass_1 = dust_mesh
	for particles in [fragments, embers, dust]:
		if is_instance_valid(owner_node):
			particles.reparent(owner_node)
			var placement: Transform3D = particles.global_transform
			particles.top_level = true
			particles.global_transform = placement
	var shock := ground_ring(Vector3(pos.x, 0.07, pos.z), Color("ffbe70"), 0.28, 3.2 * range_scale / 0.46)
	var echo := ground_ring(Vector3(pos.x, 0.075, pos.z), Color("f46b36"), 0.48, 2.75 * range_scale / 0.46)
	var flash := _light_flash(center + Vector3.UP * 0.75, Color("ffb15e"), 4.5, 6.0, 0.14)
	for effect in [shock, echo, flash]:
		if is_instance_valid(owner_node):
			effect.reparent(owner_node)
			var placement: Transform3D = effect.global_transform
			effect.top_level = true
			effect.global_transform = placement

func ribbon_impact(pos: Vector3, direction: Vector3, owner_node: Node3D) -> void:
	# Distinct, short contact layers composed from the same native burst/ring.
	var sparks := _burst(pos, direction, 24, Color("ffd499"), 0.34, 5.6, 0.050)
	var silk := _burst(pos, direction + Vector3.UP * 0.25, 20, Color("e64b57"), 0.65, 3.2, 0.075)
	var dust := _burst(pos, Vector3.UP, 8, Color("c58f7b"), 0.50, 1.1, 0.09)
	(dust.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.5, 0)
	(dust.draw_pass_1.material as StandardMaterial3D).emission_enabled = false
	var ring := ground_ring(pos, Color("efa664"), 0.32, 2.3)
	ring.rotation = Vector3(0.45, atan2(direction.x, direction.z), 0.25)
	var echo := ground_ring(pos + Vector3.UP*0.16, Color("d63b54"), 0.62, 2.65)
	echo.rotation = Vector3(-0.32, ring.rotation.y, -0.3)
	var light := _light_flash(pos, Color("ffc289"), 1.4, 2.4, 0.15)
	for effect in [sparks, silk, dust, ring, echo, light]:
		effect.reparent(owner_node)
		var placement: Transform3D = effect.global_transform
		effect.top_level = true
		effect.global_transform = placement
	sound("cloth", pos, -11.0, 1.45)
	sound("swish", pos, -13.0, 1.25)
	sound("impact", pos, -15.0, 1.2)

func shock_chain(origin: Vector3, destination: Vector3) -> void:
	var root := _reaction_root("ShockChain", origin, 0.55)
	if root == null:
		return
	var toward := destination - origin
	var side := toward.normalized().cross(Vector3.UP).normalized()
	var points := PackedVector3Array()
	for i in 9:
		var fraction := float(i) / 8.0
		# Both endpoints stay on the actual receivers; only the middle branches.
		var offset := sin(fraction * PI) * (0.12 if i % 2 == 0 else -0.12)
		points.append(origin.lerp(destination, fraction) + side * offset)
	_reaction_line(root, "ShockMistPath", points, 0.14, Color("59ddcc"), 0.22, true)
	_reaction_line(root, "ShockCore", points, 0.018, Color("fff0bb"), 0.19)
	var sparks := _burst(destination, toward, 12, Color("f6d395"), 0.24, 3.5, 0.031)
	sparks.name = "ShockContactSparks"
	(sparks.process_material as ParticleProcessMaterial).spread = 42.0
	var motes := _burst(destination, Vector3.UP, 8, Color("59ddcc"), 0.38, 0.9, 0.028)
	motes.name = "ShockRisingMotes"
	(motes.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.6, 0)
	for effect in [sparks, motes]:
		effect.reparent(root)

func curse_spread(origin: Vector3, destination: Vector3) -> void:
	var root := _reaction_root("CurseSpread", origin, 0.72)
	if root == null:
		return
	var points := PackedVector3Array()
	var curve := Curve3D.new()
	for i in 9:
		var fraction := float(i) / 8.0
		var point := origin.lerp(destination, fraction) + Vector3.UP * sin(fraction * PI) * 0.35
		points.append(point)
		curve.add_point(point - origin)
	_reaction_line(root, "CurseThread", points, 0.065, Color("8835e5"), 0.46, true)
	var seed := MeshInstance3D.new()
	seed.name = "CurseSeed"
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 8
	mesh.rings = 4
	seed.mesh = mesh
	seed.material_override = _emissive(Color("ca8dff"), 1.35)
	seed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(seed)
	var sparks := attach_trail(seed, Color("ca8dff"), 12, 0.24)
	sparks.name = "CurseSparks"
	var mist := attach_trail(seed, Color("8835e5"), 8, 0.36)
	mist.name = "CurseMist"
	_soften_particles(mist, Vector2(0.17, 0.12), 0.19)
	var travel := root.create_tween()
	travel.tween_method(func(distance: float) -> void: seed.position = curve.sample_baked(distance), 0.0, curve.get_baked_length(), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	travel.tween_callback(func() -> void:
		sparks.emitting = false
		mist.emitting = false)
	travel.tween_property(seed, "transparency", 1.0, 0.12)

func ice_shatter(origin: Vector3, radius: float = 3.0) -> void:
	var root := _reaction_root("IceShatter", origin, 0.80)
	if root == null:
		return
	# Match the actual fixed reaction radius, not the player's range multiplier.
	var boundary := _astral_ring(Vector3(origin.x, 0.11, origin.z), radius * 2.0 / 0.972, 0.58, false, Color("6abbd7"), Color("e1faff"))
	boundary.name = "IceBoundary"
	boundary.reparent(root)
	var shards := _burst(origin + Vector3.UP * 0.7, Vector3.UP, 28, Color("a4e7f5"), 0.62, 5.0, 0.045)
	shards.name = "IceFacets"
	var process := shards.process_material as ParticleProcessMaterial
	process.spread = 82.0
	process.gravity = Vector3(0, -4.0, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.38
	process.emission_ring_inner_radius = 0.12
	process.emission_ring_height = 0.15
	var facet := PrismMesh.new()
	facet.size = Vector3(0.065, 0.20, 0.027)
	facet.material = shards.draw_pass_1.material
	(facet.material as StandardMaterial3D).emission_energy_multiplier = 0.7
	shards.draw_pass_1 = facet
	var frost := _burst(origin + Vector3.UP * 0.35, Vector3.UP, 12, Color("95d6e8"), 0.50, 2.5, 0.048)
	frost.name = "IceFrostCloud"
	(frost.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.2, 0)
	_soften_particles(frost, Vector2(0.25, 0.18), 0.25)
	for effect in [shards, frost]:
		effect.reparent(root)

func ice_contact(pos: Vector3) -> void:
	var root := _reaction_root("IceContact", pos, 0.48)
	if root == null:
		return
	var sparks := _burst(pos, Vector3.UP, 10, Color("d6faff"), 0.27, 2.4, 0.030)
	sparks.name = "IceContactFlakes"
	var frost := _burst(pos, Vector3.UP, 6, Color("66bddf"), 0.36, 0.7, 0.035)
	frost.name = "IceContactMist"
	(frost.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.35, 0)
	_soften_particles(frost, Vector2(0.14, 0.11), 0.2)
	var ring := ground_ring(pos, Color("a4e7f5"), 0.26, 1.15)
	for effect in [sparks, frost, ring]:
		effect.reparent(root)

func ribbon_fire_contact(pos: Vector3, direction: Vector3, owner_node: Node3D) -> void:
	var root := _reaction_root("RibbonFireContact", pos, 0.70, owner_node)
	if root == null:
		return
	var forward := direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	var points := PackedVector3Array([pos - forward * 0.35, pos, pos + forward * 0.7 + Vector3.UP * 0.18])
	_reaction_line(root, "FireSilkWake", points, 0.22, Color("e96b35"), 0.36, true)
	_reaction_line(root, "FireSilkCore", points, 0.018, Color("ffd499"), 0.20)
	var sparks := _burst(pos, forward, 14, Color("ffd499"), 0.35, 3.6, 0.037)
	sparks.name = "FireContactSparks"
	(sparks.process_material as ParticleProcessMaterial).spread = 24.0
	var embers := _burst(pos, forward * 0.4 + Vector3.UP, 10, Color("ee6b39"), 0.50, 1.2, 0.043)
	embers.name = "FireSilkEmbers"
	(embers.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.55, 0)
	_soften_particles(embers, Vector2(0.12, 0.23), 0.32)
	for effect in [sparks, embers]:
		effect.reparent(root)

func sword_pierce(pos: Vector3, direction: Vector3, owner_node: Node3D) -> void:
	var root := _reaction_root("SwordPierce", pos, 0.48, owner_node)
	if root == null:
		return
	var forward := direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	var side := forward.cross(Vector3.UP).normalized()
	var path := PackedVector3Array([pos - forward * 0.35, pos, pos + forward * 1.45])
	_reaction_line(root, "PierceGoldWake", path, 0.16, Color("e4b76d"), 0.27, true)
	var point := pos + forward * 0.55
	_reaction_line(root, "PiercePoint", PackedVector3Array([pos - side * 0.24, point, pos + side * 0.24]), 0.020, Color("fff0c4"), 0.21)
	var sparks := _burst(pos, forward, 12, Color("f6d395"), 0.25, 4.8, 0.032)
	sparks.name = "PierceForwardSparks"
	(sparks.process_material as ParticleProcessMaterial).spread = 9.0
	(sparks.process_material as ParticleProcessMaterial).gravity = Vector3.ZERO
	var wake := _burst(pos, -forward, 8, Color("78dce7"), 0.34, 1.2, 0.022)
	wake.name = "PierceCounterMotes"
	(wake.process_material as ParticleProcessMaterial).spread = 16.0
	(wake.process_material as ParticleProcessMaterial).gravity = Vector3.ZERO
	for effect in [sparks, wake]:
		effect.reparent(root)

func fate_seal(pos: Vector3, owner_node: Node3D) -> void:
	var root := _reaction_root("FateSeal", pos, 0.62, owner_node)
	if root == null:
		return
	# A small suspended seal, distinct from the full-size ground damage warning.
	var center := pos + Vector3.UP * 0.38
	var corners := PackedVector3Array()
	for i in 5:
		var angle := float(i) * PI / 2.0 + PI / 4.0
		corners.append(center + Vector3(cos(angle), 0, sin(angle)) * 0.44)
	_reaction_line(root, "FateSealOutline", corners, 0.025, Color("f6d395"), 0.43)
	_reaction_line(root, "FateSealInner", PackedVector3Array([center - Vector3.RIGHT * 0.21, center, center + Vector3.FORWARD * 0.21]), 0.08, Color("ef702e"), 0.40, true)
	var sparks := _burst(center, Vector3.UP, 12, Color("ffe1a1"), 0.32, 1.5, 0.033)
	sparks.name = "FateGoldSparks"
	(sparks.process_material as ParticleProcessMaterial).spread = 18.0
	(sparks.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.3, 0)
	var embers := _burst(center, Vector3.UP, 8, Color("e97636"), 0.48, 0.7, 0.031)
	embers.name = "FateFireMotes"
	(embers.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.6, 0)
	for effect in [sparks, embers]:
		effect.reparent(root)

func clear_reactions() -> void:
	# Result screens pause the world immediately, so do not await fading tweens.
	for root: Node3D in _reaction_roots:
		if is_instance_valid(root):
			root.hide()
			root.queue_free()
	_reaction_roots.clear()

func _reaction_root(label: String, pos: Vector3, lifetime: float, owner_node: Node3D = null) -> Node3D:
	# A bounded addition to this existing feedback owner, not a second effect manager.
	# Skipping decoration at saturation never changes damage, statuses or proc counts.
	if not is_inside_tree() or get_tree().paused:
		return null
	for i in range(_reaction_roots.size() - 1, -1, -1):
		if not is_instance_valid(_reaction_roots[i]):
			_reaction_roots.remove_at(i)
	if _reaction_roots.size() >= MAX_REACTION_EFFECTS:
		return null
	var root := Node3D.new()
	root.name = label
	root.set_meta("reaction_fx", true)
	# The arena itself processes pause UI; feedback must follow the paused world.
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(root, true)
	root.global_position = pos
	_reaction_roots.append(root)
	if is_instance_valid(owner_node) and owner_node != self:
		owner_node.tree_exiting.connect(root.queue_free, CONNECT_ONE_SHOT)
	var cleanup := root.create_tween()
	cleanup.tween_interval(lifetime)
	cleanup.tween_callback(root.queue_free)
	return root

func _reaction_line(root: Node3D, label: String, points: PackedVector3Array, width: float, color: Color, lifetime: float, soft := false) -> MeshInstance3D:
	# Native strips preserve exact world endpoints without new trail resources.
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var direction := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var across := direction.cross(Vector3.UP).normalized()
		if across.is_zero_approx():
			across = Vector3.RIGHT
		for edge in 2:
			mesh.surface_set_uv(Vector2(float(i) / float(points.size() - 1), float(edge)))
			mesh.surface_add_vertex(root.to_local(points[i] + across * width * (-1.0 if edge == 0 else 1.0)))
	mesh.surface_end()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	if soft:
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/weapons/astral_edge/trail.gdshader")
		material.set_shader_parameter("tint", color)
		material.set_shader_parameter("edge_color", color.lerp(Color("fff0cf"), 0.45))
		instance.material_override = material
		var fade := instance.create_tween()
		fade.tween_method(func(value: float) -> void:
			material.set_shader_parameter("visual_time", value)
			material.set_shader_parameter("opacity", 1.0 - value / lifetime), 0.0, lifetime, lifetime)
	else:
		var material := _emissive(color, 1.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		instance.material_override = material
		instance.create_tween().tween_property(instance, "transparency", 1.0, lifetime)
	return instance

func _soften_particles(particles: GPUParticles3D, size: Vector2, opacity: float) -> void:
	# Reuse the existing particle ramp/material; a radial quad is a thin medium,
	# not a second hard glitter layer or a screen-covering additive cloud.
	var quad := QuadMesh.new()
	quad.size = size
	var material := particles.draw_pass_1.material as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.emission_energy_multiplier = 0.25
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, opacity))
	gradient.set_color(1, Color(1, 1, 1, 0))
	texture.gradient = gradient
	material.albedo_texture = texture
	quad.material = material
	particles.draw_pass_1 = quad

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

func _light_flash(pos: Vector3, color: Color, energy: float, radius: float, duration: float) -> OmniLight3D:
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
	return light

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

func ground_ring(pos: Vector3, color: Color, duration: float, scale_factor := 3.3) -> MeshInstance3D:
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
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(scale_factor, 0.1, scale_factor), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, duration)
	tween.chain().tween_callback(ring.queue_free)
	return ring

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
