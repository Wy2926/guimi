class_name ExperienceGem
extends Area3D
## Pickups persist until collected. Only gems inside pickup range begin homing.

signal collected(amount: int)

var target: Node3D
var value := 8
var _collected := false
var _attracted := false
var _speed := 4.0
var _age := 0.0
var _mesh: MeshInstance3D

func configure(amount: int, player: Node3D) -> void:
	value = maxi(1, amount)
	target = player

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var gem := PrismMesh.new()
	gem.size = Vector3(0.25, 0.4, 0.25) * (1.35 if value >= 30 else 1.0)
	_mesh.mesh = gem
	_mesh.rotation.z = PI
	_mesh.position.y = 0.2
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffdc81") if value >= 30 else Color("74eed5")
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.8
	_mesh.material_override = material
	add_child(_mesh)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	_mesh.rotation.y += delta * 1.5
	_mesh.position.y = 0.22 + sin(_age * 3.0) * 0.055
	if _collected or not is_instance_valid(target) or target.dead:
		return
	var destination := target.global_position + Vector3.UP * 0.5
	var distance := global_position.distance_to(destination)
	if distance <= float(target.stats.pickup_radius):
		_attracted = true
	if _attracted:
		_speed = minf(_speed + delta * 16.0, 15.0)
		global_position = global_position.move_toward(destination, delta * _speed)
		if global_position.distance_to(destination) < 0.4:
			_collect()

func _on_body_entered(body: Node3D) -> void:
	if body == target:
		_collect()

func _collect() -> void:
	if _collected or not is_instance_valid(target) or target.dead:
		return
	_collected = true
	set_deferred("monitoring", false)
	hide()
	collected.emit(value)
	queue_free()
