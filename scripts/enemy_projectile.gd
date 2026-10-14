class_name EnemyProjectile
extends Area3D
## A native collision area; all outgoing damage still uses the shared damage rules.

var target: Node3D
var source_stats: BattleStats
var direction := Vector3.FORWARD
var speed := 6.0
var coefficient := 1.0
var element := DamageRules.Element.NONE
var _life := 4.0
var _spent := false

func configure(attacker: BattleStats, player: Node3D, heading: Vector3, travel_speed: float, multiplier: float, attack_element: int = DamageRules.Element.NONE) -> void:
	source_stats = attacker
	target = player
	direction = heading.normalized()
	speed = travel_speed
	coefficient = multiplier
	element = attack_element

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.23
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.17
	orb.height = 0.34
	orb.radial_segments = 8
	orb.rings = 4
	mesh.mesh = orb
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ff9670")
	material.emission_enabled = true
	material.emission = Color("ff6c3d")
	material.emission_energy_multiplier = 2.0
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(target) or target.dead:
		queue_free()
		return
	global_position += direction * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if _spent or body != target or source_stats == null or target.dead:
		return
	_spent = true
	set_deferred("monitoring", false)
	var result := DamageRules.calculate(source_stats, target.stats, 1, coefficient, element)
	target.receive_damage(result, direction)
	hide()
	queue_free()
