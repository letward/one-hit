class_name OHBarrel
extends StaticBody3D
## Explosiv-Fass: anschießen -> große Explosion mit Flächenschaden.
## Vorsicht: verletzt auch den Schützen!

signal exploded(barrel: OHBarrel)

const RADIUS := 5.5
const DAMAGE := 150.0

var hp: float = 30.0
var _dead: bool = false
var _attacker: Object = null

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _blink_t: float = 0.0


func _ready() -> void:
	add_to_group("barrel")
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 1.1
	col.shape = shape
	col.position = Vector3(0, 0.55, 0)
	add_child(col)
	_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.45
	cm.height = 1.1
	_mesh.mesh = cm
	_mesh.position = Vector3(0, 0.55, 0)
	_mat = TexFactory.mat("metal", Color(1.5, 0.28, 0.24), 2.0, 0.3, 0.5)
	_mat.emission_enabled = true
	_mat.emission = Color(0.7, 0.1, 0.08)
	_mat.emission_energy_multiplier = 0.3
	_mesh.material_override = _mat
	add_child(_mesh)
	# Warn-Banderole
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.46
	bm.bottom_radius = 0.46
	bm.height = 0.18
	band.mesh = bm
	band.position = Vector3(0, 0.75, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.9, 0.75, 0.1)
	bmat.emission_enabled = true
	bmat.emission = Color(0.9, 0.7, 0.1)
	bmat.emission_energy_multiplier = 0.8
	band.material_override = bmat
	add_child(band)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.15)
	_light.light_energy = 0.4
	_light.omni_range = 4.0
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)


func _process(delta: float) -> void:
	if _dead:
		return
	_blink_t += delta
	_light.light_energy = 0.4 + (sin(_blink_t * 5.0) * 0.5 + 0.5) * 0.4


func take_damage(amount: float, attacker: Object) -> bool:
	if _dead:
		return false
	_attacker = attacker
	hp -= amount
	_mat.emission_energy_multiplier = 1.5
	if hp <= 0.0:
		explode()
		return true
	return false


func explode() -> void:
	if _dead:
		return
	_dead = true
	exploded.emit(self)
	AudioManager.play_explosion()
	# Blitzlicht
	_light.light_energy = 8.0
	_light.omni_range = 14.0
	var flash := create_tween()
	flash.tween_property(_light, "light_energy", 0.0, 0.6)
	# Feuerball-Partikel
	var p := GPUParticles3D.new()
	p.amount = 42
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.08
	pm.scale_max = 0.2
	pm.color = Color(1.0, 0.55, 0.15)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.albedo_color = Color(1.0, 0.6, 0.2)
	p.draw_pass_1 = quad
	p.material_override = qm
	get_tree().current_scene.add_child(p)
	p.global_position = global_position + Vector3(0, 0.8, 0)
	p.emitting = true
	# Flächenschaden (trifft auch den Schützen!)
	for n in get_tree().get_nodes_in_group("bot"):
		if n is OHBot and (n as OHBot).alive:
			if (n as Node3D).global_position.distance_to(global_position) <= RADIUS:
				(n as OHBot).take_damage(DAMAGE, _attacker)
	for n in get_tree().get_nodes_in_group("player"):
		if n != null and n.has_method("take_damage"):
			if (n as Node3D).global_position.distance_to(global_position) <= RADIUS:
				n.call("take_damage", DAMAGE, _attacker)
	# Hülle verstecken, Kollision aus, später aufräumen
	_mesh.visible = false
	(get_child(0) as CollisionShape3D).set_deferred("disabled", true)
	var t := get_tree().create_timer(1.4)
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		if is_instance_valid(self):
			queue_free())
