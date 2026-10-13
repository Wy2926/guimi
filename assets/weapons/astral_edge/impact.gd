extends Node3D
## Standalone hit accent; no damage, camera shake or gameplay dependencies.
const FLASH = preload("res://assets/weapons/astral_edge/impact.gdshader")
var age := 0.0
var material: ShaderMaterial
var flash: MeshInstance3D

func _ready() -> void:
	flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6,2.6)
	flash.mesh = quad
	material = ShaderMaterial.new()
	material.shader = FLASH
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 24
	particles.lifetime = 0.45
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-4,-4,-4),Vector3(8,8,8))
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3(0,-2.0,0)
	process.direction = Vector3.UP
	process.spread = 180
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 4.5
	process.scale_min = 0.35
	process.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.set_color(0,Color(0.7,0.9,1,1))
	gradient.add_point(0.2,Color(0.08,0.55,1,1))
	gradient.set_color(1,Color(0.02,0.1,0.7,0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var shard := PrismMesh.new()
	shard.size = Vector3(0.045,0.14,0.018)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.45,0.85,1)
	shard.material = mat
	particles.draw_pass_1 = shard
	add_child(particles)
	particles.emitting = true

func _process(delta: float) -> void:
	age += delta
	material.set_shader_parameter("progress", minf(age/0.5,1.0))
	var camera := get_viewport().get_camera_3d()
	if camera:
		flash.look_at(camera.global_position,Vector3.UP,true)
	if age > 0.65:
		queue_free()
