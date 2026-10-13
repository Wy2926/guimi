@tool
extends Node3D
## Small set dressing made entirely from Godot primitive meshes and materials.
@export var radius := 15.8

func _ready() -> void:
	var stone := _material(Color("24363d"), 0.88)
	var edge := _material(Color("17272e"), 0.78)
	var brass := _material(Color("8c7047"), 0.42, 0.68)
	var glow := _material(Color("f5b366"), 0.4)
	glow.emission_enabled = true
	glow.emission = Color("ffb958")
	glow.emission_energy_multiplier = 2.0
	_cylinder("Foundation", radius + 0.60, 0.75, Vector3(0, -0.64, 0), edge, 64)
	_cylinder("LowerLip", radius + 0.71, 0.15, Vector3(0, -0.87, 0), stone, 64)
	_cylinder("BrassBand", radius + 0.63, 0.07, Vector3(0, -0.38, 0), brass, 64)
	_cylinder("UpperRim", radius + 0.45, 0.3, Vector3(0, -0.17, 0), stone, 64)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = preload("res://shaders/stone.gdshader")
	_cylinder("Courtyard", radius, 0.15, Vector3(0, -0.065, 0), floor_mat, 96)
	_ring("InnerInlay", radius - 0.10, 0.022, 0.025, brass)
	_ring("OuterInlay", radius + 0.30, 0.026, 0.02, brass)
	_ring("CenterInlay", 4.2, 0.014, 0.025, brass)
	for i in 48:
		var a := i * TAU / 48.0
		var pos := Vector3(sin(a), 0, cos(a)) * (radius + 0.13)
		pos.y = 0.045
		var marker := _box("RimMark", Vector3(0.024, 0.018, 0.19 if i % 4 else 0.3), pos, brass)
		marker.rotation.y = a
	for i in 16:
		var a := i * TAU / 16.0
		var pos := Vector3(sin(a), 0, cos(a)) * (radius + 0.61)
		pos.y = -0.61
		var inset := _box("FoundationInset", Vector3(0.33, 0.26, 0.06), pos, brass)
		inset.rotation.y = a
	# Four low braziers, outside the playable disk: no navigational clutter.
	for i in 4:
		var a := PI * 0.25 + float(i) * PI * 0.5
		var pos := Vector3(sin(a), 0, cos(a)) * (radius + 0.13)
		_cylinder("BrazierFoot", 0.36, 0.16, pos + Vector3.UP * 0.10, edge, 8)
		_cylinder("BrazierColumn", 0.22, 0.65, pos + Vector3.UP * 0.45, stone, 8)
		_cylinder("BrazierCollar", 0.25, 0.09, pos + Vector3.UP * 0.76, brass, 8)
		_cylinder("BrazierBowl", 0.34, 0.15, pos + Vector3.UP * 0.87, edge, 8)
		_cylinder("Coals", 0.25, 0.07, pos + Vector3.UP * 0.96, glow, 12)
		var light := OmniLight3D.new()
		light.position = pos + Vector3.UP * 1.35
		light.light_color = Color("ffa554")
		light.light_energy = 2.2
		light.omni_range = 3.9
		light.omni_attenuation = 1.4
		add_child(light)
		_flame(pos + Vector3.UP * 1.02)
	# Solid boundary segments use native collision, not a movement subsystem.
	for i in 32:
		var a := i * TAU / 32.0
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		wall.position = Vector3(sin(a) * radius, 0.6, cos(a) * radius)
		wall.rotation.y = a
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * radius / 32.0 + 0.08, 2.0, 0.2)
		collider.shape = box
		wall.add_child(collider)
		add_child(wall)

func _material(color: Color, roughness: float, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	return material

func _cylinder(title: String, radius: float, height: float, pos: Vector3, material: Material, segments: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh(title, mesh, pos, material)

func _box(title: String, dimensions: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(title, mesh, pos, material)

func _ring(title: String, radius: float, width: float, y: float, material: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius + width
	mesh.rings = 96
	mesh.ring_segments = 6
	_mesh(title, mesh, Vector3(0, y, 0), material)

func _mesh(title: String, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	add_child(node)
	return node

func _flame(pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "BrazierEmbers"
	particles.position = pos
	particles.amount = 16
	particles.lifetime = 1.2
	particles.preprocess = 1.0
	particles.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 4, 2))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.75
	process.gravity = Vector3(0, 0.15, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.scale_min = 0.5
	process.scale_max = 1.3
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 0.77, 0.28, 0.9))
	gradient.add_point(0.4, Color(1, 0.3, 0.05, 0.65))
	gradient.set_color(1, Color(0.5, 0.13, 0.035, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var spark := SphereMesh.new()
	spark.radius = 0.046
	spark.height = 0.13
	spark.radial_segments = 6
	spark.rings = 3
	var mat := _material(Color.WHITE, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("ff7b22")
	mat.emission_energy_multiplier = 2.8
	spark.material = mat
	particles.draw_pass_1 = spark
	add_child(particles)
