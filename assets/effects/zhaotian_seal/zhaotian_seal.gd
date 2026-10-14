extends Node3D
## Presentation only. SwordStorm remains the sole flight/damage owner.

const MODEL = preload("res://assets/effects/zhaotian_seal/zhaotian_seal.glb")
const ENERGY = preload("res://assets/weapons/astral_edge/energy.gdshader")
const WISP = preload("res://assets/weapons/astral_edge/wisp.gdshader")
const SHATTER_TIME := 1.2

var feedback: Node3D
var flight_vector := Vector3.UP
var landed := false
var age := 0.0
var model: Node3D
var animation: AnimationPlayer
var emitters: Array[GPUParticles3D] = []
var energy_meshes: Array[MeshInstance3D] = []
var flame: Node3D

func _ready() -> void:
	model = MODEL.instantiate() as Node3D
	add_child(model)
	var vein := ShaderMaterial.new()
	vein.shader = ENERGY
	vein.set_shader_parameter("tint", Color("fa762a"))
	vein.set_shader_parameter("layer", 0.0)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material != null and "FireVein" in material.resource_name:
				mesh.set_surface_override_material(surface, vein)
				energy_meshes.append(mesh)
	animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation != null:
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		animation.stop()
	# Reuse the existing emitter, gradient and mesh materials. Three wakes have
	# distinct jobs: fast golden sparks, fine red streaks and thin rising fire.
	for layer in 3:
		var particles: GPUParticles3D = feedback.attach_trail(self, [Color("ffce81"), Color("ed652b"), Color("b64c24")][layer], [32, 24, 12][layer], [0.38, 0.52, 0.65][layer])
		particles.name = ["GoldSparks", "CinnabarStreaks", "FireWisps"][layer]
		particles.position.y = 0.65
		var process := particles.process_material as ParticleProcessMaterial
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		process.emission_ring_axis = Vector3.UP
		process.emission_ring_radius = 0.7
		process.emission_ring_inner_radius = 0.52
		process.emission_ring_height = 0.08
		process.direction = flight_vector
		process.spread = 12.0 + layer * 8.0
		process.initial_velocity_min = 0.7 + layer * 0.25
		process.initial_velocity_max = 1.7 + layer * 0.35
		process.gravity = Vector3(0, 0.45, 0)
		process.particle_flag_align_y = true
		process.scale_min = 0.35
		process.scale_max = 0.9
		var mesh := particles.draw_pass_1 as SphereMesh
		mesh.radius = 0.015 if layer < 2 else 0.045
		mesh.height = 0.13 + layer * 0.15
		emitters.append(particles)
	# Two crossed wisps light the open knob without hiding its metal silhouette.
	flame = Node3D.new()
	flame.name = "KnobFlame"
	flame.position.y = 1.13
	add_child(flame)
	var material := ShaderMaterial.new()
	material.shader = WISP
	material.set_shader_parameter("tint", Color("ff852c"))
	for i in 2:
		var wisp := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 1.0)
		wisp.mesh = quad
		wisp.material_override = material
		wisp.rotation.y = i * PI / 2.0
		wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.add_child(wisp)

func _physics_process(delta: float) -> void:
	age += delta
	var power := maxf(0.0, 1.0 - (age / SHATTER_TIME)) if landed else 0.14
	for mesh in energy_meshes:
		mesh.set_instance_shader_parameter("visual_time", age)
		mesh.set_instance_shader_parameter("power", power)
	for wisp: MeshInstance3D in flame.get_children():
		wisp.set_instance_shader_parameter("visual_time", age)
		wisp.set_instance_shader_parameter("power", power)

func shatter() -> void:
	if landed:
		return
	landed = true
	age = 0.0
	for particles in emitters:
		particles.emitting = false
	# The imported clip animates the very same stone and metal pieces. There is
	# no hidden full seal left underneath and no second damage event in the clip.
	if animation != null and animation.has_animation("SealShatter"):
		animation.play("SealShatter")
		animation.advance(0.0)
	var fade := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	fade.tween_property(flame, "scale", Vector3.ONE * 0.01, 0.18)
	fade.tween_interval(SHATTER_TIME + 0.12 - 0.18)
	fade.tween_callback(queue_free)
