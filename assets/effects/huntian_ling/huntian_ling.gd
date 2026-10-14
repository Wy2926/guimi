extends Node3D
## The root is only the head/particle anchor. The ONE skinned cloth follows
## travelled world-space positions and never inherits this root's turns.

const MODEL = preload("res://assets/effects/huntian_ling/huntian_ling.glb")
const ENERGY = preload("res://assets/weapons/astral_edge/energy.gdshader")
const WISP = preload("res://assets/weapons/astral_edge/wisp.gdshader")
const BODY_LENGTH := 12.0
const SPINE_COUNT := 65
const SAMPLE_STEP := 0.085
const MAX_HISTORY := 384
const STRIKE_TIME := 0.30
const CONTACT_TIME := 0.12
const COIL_RADIUS := 0.56

var feedback: Node3D
var model: Node3D
var skeleton: Skeleton3D
var spine_bones: Array[int] = []
var rest_bases: Array[Basis] = []
var parent_inverses: Array[Transform3D] = []
var meshes: Array[MeshInstance3D] = []
var energy_meshes: Array[MeshInstance3D] = []
var emitters: Array[GPUParticles3D] = []
var fire_emitters: Array[GPUParticles3D] = []
var carrying_fire := false
var seam_material: ShaderMaterial
var history: Array[Vector3] = []
var history_distances: Array[float] = []
var trajectory := Curve3D.new()
var traveled := 0.0
var retraction := 0.0
var age := 0.0
var flash := 0.0
var coiling := false
var dissolving := false
var traced_curve: Curve3D
var traced_progress := 0.0

func _ready() -> void:
	model = MODEL.instantiate() as Node3D
	model.top_level = true
	add_child(model)
	model.global_transform = Transform3D.IDENTITY
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for i in SPINE_COUNT:
		var bone := skeleton.find_bone("Silk%02d" % i)
		spine_bones.append(bone)
		rest_bases.append((skeleton.global_transform*skeleton.get_bone_global_rest(bone)).basis)
		var parent := skeleton.get_bone_parent(bone)
		parent_inverses.append(skeleton.get_bone_global_rest(parent).affine_inverse() if parent >= 0 else Transform3D.IDENTITY)
	seam_material = ShaderMaterial.new()
	seam_material.shader = ENERGY
	seam_material.set_shader_parameter("tint", Color("f5a14a"))
	seam_material.set_shader_parameter("layer", 0.0)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(mesh)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if original != null and "SpiritSeam" in original.resource_name:
				mesh.set_surface_override_material(surface, seam_material)
				energy_meshes.append(mesh)
	trajectory.bake_interval = 0.035
	model.hide()
	# Keep the existing four directional particle layers and shared materials.
	for layer in 4:
		var particles: GPUParticles3D = feedback.attach_trail(self, [Color("ffc878"), Color("e74359"), Color("b87d74"), Color("f4b879")][layer], [40, 48, 12, 32][layer], [0.50, 0.72, 0.80, 0.48][layer])
		particles.name = ["GoldSelvedgeSparks", "CrimsonSilkWake", "ThinSilkWisps", "CoilMotes"][layer]
		var process := particles.process_material as ParticleProcessMaterial
		process.direction = Vector3.BACK
		process.spread = 24.0
		process.initial_velocity_min = 0.12
		process.initial_velocity_max = 0.6
		process.gravity = Vector3(0, 0.12, 0)
		process.particle_flag_align_y = true
		process.scale_min = 0.65
		process.scale_max = 1.15
		var spark := particles.draw_pass_1 as SphereMesh
		spark.radius = 0.026 if layer != 1 else 0.035
		spark.height = 0.16 if layer != 1 else 0.44
		if layer == 2:
			var mist := QuadMesh.new()
			mist.size = Vector2(0.42, 1.05)
			var veil := ShaderMaterial.new()
			veil.shader = WISP
			veil.set_shader_parameter("tint", Color("c17873"))
			mist.material = veil
			particles.draw_pass_1 = mist
		if layer == 3:
			# The head physically circles its victim; these motes stay on that
			# travelled loop instead of drawing another ring around a rigid model.
			process.emission_sphere_radius = 0.12
			particles.emitting = false
		emitters.append(particles)

func begin(origin: Vector3) -> void:
	history.assign([origin])
	history_distances.assign([0.0])
	trajectory.clear_points()
	trajectory.add_point(origin)
	traveled = 0.0
	_pose_body()
	model.show()

func _physics_process(delta: float) -> void:
	age += delta
	flash = maxf(0.0, flash-delta*6.5)
	if not dissolving:
		trace_path()
	_pose_body()
	for mesh in energy_meshes:
		mesh.set_instance_shader_parameter("visual_time", age)
		mesh.set_instance_shader_parameter("power", flash + (0.35 if carrying_fire else 0.0))
	emitters[2].set_instance_shader_parameter("visual_time", age)
	emitters[2].set_instance_shader_parameter("power", 0.24+flash*0.25)

func trace_path() -> void:
	# Sample the native route between physics ticks too. A low physics rate
	# must not replace a curved turn with a single long straight chord.
	var follow := get_parent() as PathFollow3D
	if follow == null or history.is_empty():
		return
	var path := follow.get_parent() as Path3D
	if path.curve == null:
		return
	if path.curve != traced_curve:
		traced_curve = path.curve
		traced_progress = 0.0
		_append_point(path.to_global(traced_curve.sample_baked(0.0)))
	var cursor := traced_progress+SAMPLE_STEP
	while cursor < follow.progress:
		_append_point(path.to_global(traced_curve.sample_baked(cursor, true)))
		cursor += SAMPLE_STEP
	_append_point(follow.global_position)
	traced_progress = follow.progress

func _append_point(point: Vector3) -> void:
	var distance: float = history.back().distance_to(point)
	if distance < 0.003:
		return
	traveled += distance
	history.append(point)
	history_distances.append(traveled)
	trajectory.add_point(point)
	# Keep by travelled LENGTH, not by elapsed time. Stopping the head cannot
	# make the back half expire, rotate or snap to the new heading.
	while history.size() > 2 and (traveled-history_distances[1] > BODY_LENGTH+0.3 or history.size() > MAX_HISTORY):
		history.pop_front()
		history_distances.pop_front()
		trajectory.remove_point(0)

func sample_path(distance: float) -> Transform3D:
	var offset := clampf(distance-history_distances[0], 0.0, trajectory.get_baked_length())
	var point := trajectory.sample_baked(offset, true)
	var tangent := trajectory.sample_baked(minf(offset+0.06, trajectory.get_baked_length()), true)-trajectory.sample_baked(maxf(0.0, offset-0.06), true)
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.FORWARD
	var up := Vector3.UP if absf(tangent.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(tangent, up), point)

func _pose_body() -> void:
	if history.is_empty():
		return
	var skin_inverse := skeleton.global_transform.affine_inverse()
	for i in spine_bones.size():
		var distance := traveled+retraction-BODY_LENGTH*(1.0-float(i)/float(SPINE_COUNT-1))
		var frame := sample_path(distance)
		# Fine rolling of the cross-section only; the centerline remains on its
		# own past route. Cloth, gold hems and clouds share the same skin weights.
		var roll := 0.16*sin(distance*1.1-age*2.4)+0.10*sin(distance*0.43-age*1.5)
		var reveal := maxf(0.001, smoothstep(-0.03, 0.15, distance)*(1.0-smoothstep(traveled, traveled+0.18, distance)))
		frame.basis = (frame.basis*Basis(Vector3.FORWARD, roll)*rest_bases[i]).scaled(Vector3.ONE*reveal)
		skeleton.set_bone_pose(spine_bones[i], parent_inverses[i]*skin_inverse*frame)
	# A skinned model's bind-pose box is irrelevant after it snakes across the
	# arena. Bound the current world-space body so the tail cannot be culled.
	var bounds := AABB(history.front(), Vector3.ZERO)
	for point in history:
		bounds = bounds.expand(point)
	for mesh in meshes:
		mesh.custom_aabb = mesh.global_transform.affine_inverse()*bounds.grow(0.8)

func flow() -> void:
	coiling = false
	for i in emitters.size():
		emitters[i].emitting = i < 3

func strike() -> void:
	coiling = true
	emitters[3].emitting = true

func hit() -> void:
	flash = 1.0

func set_carried_fire(enabled: bool) -> void:
	# Presentation follows the executor's existing burn snapshot, never a
	# separate lifetime. Both wakes are emitted by this actual moving head;
	# the warm seam is the original skinned cloth, not a duplicate fire ribbon.
	enabled = enabled and not dissolving
	if carrying_fire == enabled:
		return
	carrying_fire = enabled
	if enabled and fire_emitters.is_empty():
		for layer in 2:
			var particles: GPUParticles3D = feedback.attach_trail(self, Color("ff7439") if layer == 0 else Color("ffe3a6"), 12 if layer == 0 else 8, 0.38 if layer == 0 else 0.52)
			particles.name = "CarryFireFilaments" if layer == 0 else "CarryFireEmbers"
			var process := particles.process_material as ParticleProcessMaterial
			process.direction = Vector3.UP
			process.spread = 22.0 if layer == 0 else 48.0
			process.initial_velocity_min = 0.18
			process.initial_velocity_max = 0.75 if layer == 0 else 1.1
			process.gravity = Vector3(0, 0.55, 0)
			process.particle_flag_align_y = true
			var spark := particles.draw_pass_1 as SphereMesh
			spark.radius = 0.022 if layer == 0 else 0.012
			spark.height = 0.24 if layer == 0 else 0.045
			fire_emitters.append(particles)
	seam_material.set_shader_parameter("tint", Color("ff6834") if enabled else Color("f5a14a"))
	for particles in fire_emitters:
		particles.emitting = enabled

func dissolve() -> void:
	trace_path()
	set_carried_fire(false)
	dissolving = true
	for particles in emitters:
		particles.emitting = false
	# Feed the remaining body forward along the SAME path into the returned
	# head. No root scaling, duplicate mesh or simultaneous whole-body rotation.
	var fade := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	fade.tween_property(self, "retraction", BODY_LENGTH+0.2, 0.55)
	for mesh in meshes:
		fade.tween_property(mesh, "transparency", 1.0, 0.3).set_delay(0.25)
