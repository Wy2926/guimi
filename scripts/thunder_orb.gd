extends Area3D
## A slow, non-homing light projectile. Native area overlaps also cover enemies that stay inside.

signal expired(orb: Node3D)

const HIT_INTERVAL := 0.35

var manager: Node3D
var feedback: Node3D
var direction := Vector3.FORWARD
var speed := 2.8
var radius := 0.85
var visual_scale := 1.0
var life_left := 4.0
var age := 0.0
var arena_radius := 15.8
var coefficient := 0.6
var kind := DamageRules.Kind.MAGICAL
var element := DamageRules.Element.LIGHT

var _expired := false
var _next_hits: Dictionary = {}
var _visual: Node3D
var _rings: Array[MeshInstance3D] = []
var _arcs: MeshInstance3D
var _core: MeshInstance3D
var _core_material: StandardMaterial3D
var _flash_left := 0.0

func configure(source: Node3D, heading: Vector3, definition: SkillDefinition, level: int, reach: float, boundary: float) -> void:
	manager = source
	direction = Vector3(heading.x, 0.0, heading.z).normalized()
	radius = definition.radius_at(level) * reach
	visual_scale = definition.visual_scale_at(level) * reach
	life_left = definition.duration_at(level)
	coefficient = definition.coefficient_at(level)
	kind = definition.kind
	element = definition.element
	arena_radius = boundary

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitorable = false
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision.shape = sphere
	add_child(collision)
	_make_visuals()

func _physics_process(delta: float) -> void:
	if _expired:
		return
	if not is_instance_valid(manager) or not is_instance_valid(manager.player) or manager.player.dead or not manager.player.enabled:
		cancel()
		return
	age += delta
	life_left = maxf(0.0, life_left - delta)
	global_position += direction * speed * delta
	if life_left <= 0.0 or Vector2(global_position.x, global_position.z).length() > arena_radius:
		cancel()
		return
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or body.dead:
			continue
		var target_id := body.get_instance_id()
		if age + 0.00001 < float(_next_hits.get(target_id, 0.0)):
			continue
		_next_hits[target_id] = age + HIT_INTERVAL
		manager.contact(body, self)
		if _expired or manager.player.dead or not manager.player.enabled:
			return
	_update_visuals(delta)

func flash_hit() -> void:
	_flash_left = 0.11

func cancel() -> void:
	if _expired:
		return
	_expired = true
	set_physics_process(false)
	set_deferred("monitoring", false)
	hide()
	expired.emit(self)
	queue_free()

func _make_visuals() -> void:
	_visual = Node3D.new()
	_visual.scale = Vector3.ONE * visual_scale
	add_child(_visual)
	_core_material = _material(Color("f5fbff"), 2.8)
	_core = MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.25
	core_mesh.height = 0.5
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	_core.mesh = core_mesh
	_core.material_override = _core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_core)
	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.58
	shell_mesh.height = 1.16
	shell_mesh.radial_segments = 16
	shell_mesh.rings = 8
	shell.mesh = shell_mesh
	var shell_material := _material(Color(0.74, 0.88, 1.0, 0.08), 0.45)
	shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell.material_override = shell_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(shell)
	var ring_material := _material(Color("dcefff"), 1.6)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.62
	ring_mesh.outer_radius = 0.65
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 4
	for i in 3:
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.material_override = ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.rotation = Vector3(0.45 + float(i) * 0.8, float(i) * 1.1, float(i) * 0.55)
		_visual.add_child(ring)
		_rings.append(ring)
	_arcs = MeshInstance3D.new()
	var arcs_mesh := ImmediateMesh.new()
	arcs_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color.WHITE, 3.2))
	var arc_points := PackedVector3Array([
		Vector3(-0.62, -0.12, 0.05), Vector3(-0.34, 0.1, 0.18), Vector3(-0.2, -0.09, 0.24), Vector3(0.08, 0.18, 0.2), Vector3(0.3, 0.06, 0.12), Vector3(0.62, 0.22, -0.04),
	])
	for i in arc_points.size() - 1:
		arcs_mesh.surface_add_vertex(arc_points[i])
		arcs_mesh.surface_add_vertex(arc_points[i + 1])
		arcs_mesh.surface_add_vertex(Vector3(arc_points[i].z, arc_points[i].x, arc_points[i].y))
		arcs_mesh.surface_add_vertex(Vector3(arc_points[i + 1].z, arc_points[i + 1].x, arc_points[i + 1].y))
	arcs_mesh.surface_end()
	_arcs.mesh = arcs_mesh
	_arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_arcs)
	if is_instance_valid(feedback):
		var trail: GPUParticles3D = feedback.attach_trail(self, Color("e8f4ff"), 14, 0.22)
		var particles := trail.process_material as ParticleProcessMaterial
		particles.scale_min *= visual_scale
		particles.scale_max *= visual_scale

func _update_visuals(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	var flash := _flash_left / 0.11
	_core.scale = Vector3.ONE * (1.0 + sin(age * 13.0) * 0.08 + flash * 0.4)
	_core_material.emission_energy_multiplier = 2.8 + flash * 3.0
	for i in _rings.size():
		_rings[i].rotate_y(delta * (1.6 + float(i) * 0.5))
		_rings[i].rotate_z(delta * (0.8 if i % 2 == 0 else -0.9))
	_arcs.visible = _flash_left > 0.0 or int(age * 14.0) % 4 != 0
	_arcs.rotation = Vector3(age * 2.6, age * -1.7, age * 1.3)

func _material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	return material
