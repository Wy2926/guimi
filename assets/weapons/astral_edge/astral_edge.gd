extends Node3D
## Presentation only. Caller owns transforms, targets, physics and damage.
## +Y is the tip, +Z is the front, origin is the pommel.

enum Motion { IDLE, CHARGE, FLIGHT, RETURN }
const ENERGY = preload("res://assets/weapons/astral_edge/energy.gdshader")
const WISP = preload("res://assets/weapons/astral_edge/wisp.gdshader")
const TRAIL = preload("res://assets/weapons/astral_edge/trail.gdshader")
@export var phase := 0.0
@export var enable_trail := true
var motion := Motion.IDLE
var clock := 0.0
var power := 0.0
var fins: Array[Node3D] = []
var fin_homes: Array[Vector3] = []
var energy_meshes: Array[GeometryInstance3D] = []
var history: Array[Vector3] = []
var wake: MeshInstance3D
var wake_mesh: ImmediateMesh
var ambient: GPUParticles3D
var model: Node3D

func _ready() -> void:
	model = $Model
	var materials: Dictionary = {}
	for item: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in item.mesh.get_surface_count():
			var original := item.mesh.surface_get_material(surface)
			if not original:
				continue
			var label := original.resource_name
			if "Crystal" not in label and "Runes" not in label and "Edge" not in label:
				continue
			if not materials.has(label):
				var energy_material := ShaderMaterial.new()
				energy_material.shader = ENERGY
				energy_material.set_shader_parameter("layer", 0.0 if "Crystal" in label else 1.0)
				materials[label] = energy_material
			item.set_surface_override_material(surface, materials[label])
		if item.get_surface_override_material_count() > 0:
			energy_meshes.append(item)
	for label in ["Fin_L", "Fin_R"]:
		var fin := model.find_child(label, true, false) as Node3D
		if fin:
			fins.append(fin)
			fin_homes.append(fin.position)
	for angle in [0.0, PI / 2.0]:
		var aura := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.95, 2.75)
		aura.mesh = quad
		aura.position = Vector3(0, 2.05, 0)
		aura.rotation.y = angle
		var aura_material := ShaderMaterial.new()
		aura_material.shader = WISP
		aura.material_override = aura_material
		aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(aura)
		energy_meshes.append(aura)
	_make_motes()
	wake = MeshInstance3D.new()
	wake.top_level = true
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake_mesh = ImmediateMesh.new()
	wake.mesh = wake_mesh
	var trail_material := ShaderMaterial.new()
	trail_material.shader = TRAIL
	wake.material_override = trail_material
	add_child(wake)

func set_motion(value: Motion) -> void:
	motion = value
	if value == Motion.IDLE:
		history.clear()

func _process(delta: float) -> void:
	clock += delta
	var target := [0.0, 0.75, 1.0, 0.3][motion] as float
	power = move_toward(power, target, delta * 5.0)
	# Local presentation never moves the gameplay root.
	model.position.y = sin(clock * 1.7 + phase) * 0.035 * (1.0 - power)
	for i in fins.size():
		var sign_value := -1.0 if i == 0 else 1.0
		fins[i].position = fin_homes[i] + Vector3(sign_value * (0.025*sin(clock*1.7+phase) + power*0.10), sin(clock*2.0+phase+i*PI)*0.055, sin(clock*1.4+phase+i*PI)*0.025)
	for item in energy_meshes:
		item.set_instance_shader_parameter("power", power)
		item.set_instance_shader_parameter("phase", phase)
		item.set_instance_shader_parameter("visual_time", clock)
	ambient.emitting = is_visible_in_tree() and motion != Motion.FLIGHT
	_update_wake(delta)

func _update_wake(_delta: float) -> void:
	wake.material_override.set_shader_parameter("visual_time", clock)
	if not enable_trail or not is_visible_in_tree():
		history.clear()
	elif motion in [Motion.CHARGE, Motion.FLIGHT, Motion.RETURN]:
		var point := to_global(Vector3(0, 0.7, 0))
		if history.is_empty() or history.back().distance_to(point) > 0.018:
			if not history.is_empty() and history.back().distance_to(point) > 3.0:
				history.clear()
			history.append(point)
			if history.size() > 32:
				history.pop_front()
	elif not history.is_empty():
		history.pop_front()
	wake_mesh.clear_surfaces()
	if history.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in history.size():
		var ratio := float(i) / float(history.size()-1)
		var tangent := history[mini(i+1,history.size()-1)]-history[maxi(0,i-1)]
		var side := tangent.cross(camera.global_position-history[i]).normalized()
		var width := (0.075+power*0.12)*ratio*global_basis.get_scale().x
		wake_mesh.surface_set_uv(Vector2(ratio,0))
		wake_mesh.surface_add_vertex(history[i]-side*width)
		wake_mesh.surface_set_uv(Vector2(ratio,1))
		wake_mesh.surface_add_vertex(history[i]+side*width)
	wake_mesh.surface_end()

func _make_motes() -> void:
	ambient = GPUParticles3D.new()
	ambient.amount = 14
	ambient.lifetime = 1.5
	ambient.visibility_aabb = AABB(Vector3(-2,-1,-2),Vector3(4,6,4))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.38,1.2,0.12)
	process.gravity = Vector3(0,0.05,0)
	process.direction = Vector3.UP
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.18
	process.scale_min = 0.2
	process.scale_max = 0.6
	var gradient := Gradient.new()
	gradient.set_color(0,Color(0.08,0.4,1,0))
	gradient.add_point(0.2,Color(0.3,0.75,1,0.8))
	gradient.set_color(1,Color(0.08,0.3,1,0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	ambient.process_material = process
	var spark := QuadMesh.new()
	spark.size = Vector2(0.055,0.055)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.3,0.7,1)
	var spot := GradientTexture2D.new()
	spot.width = 32
	spot.height = 32
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5,0.5)
	spot.fill_to = Vector2(1.0,0.5)
	var falloff := Gradient.new()
	falloff.set_color(0,Color.WHITE)
	falloff.set_color(1,Color(1,1,1,0))
	spot.gradient = falloff
	mat.albedo_texture = spot
	spark.material = mat
	ambient.draw_pass_1 = spark
	ambient.position.y = 2.0
	model.add_child(ambient)
