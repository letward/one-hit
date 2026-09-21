class_name OHBot
extends CharacterBody3D
## Simple Gegner-KI: Wandern -> Jagen -> Strafen + Schießen.
## Absichtlich simpel + lesbar: Sichtlinie, Wunschdistanz, Zufalls-Strafe.

signal died(bot: OHBot, killer_name: String)

const GRAVITY = 20.0
const TURN_SPEED = 6.0

var display_name: String = "Bot"
var hp: float = 100.0
var alive: bool = true
var accuracy: float = 0.7
var fire_interval: float = 1.1
var damage: float = 12.0
var move_speed: float = 4.4
var skill: float = 0.5
var kind: String = "normal" # normal | heavy | runner

var target: Node3D = null
var _state: String = "wander"
var _wander_target: Vector3 = Vector3.ZERO
var _strafe_dir: float = 1.0
var _strafe_t: float = 0.0
var _shoot_cd: float = 1.0
var _think_t: float = 0.0
var _flash: float = 0.0
var _react_t: float = 0.0
var _burst_left: int = 0
var _burst_pause: float = 0.0
var _last_seen: Vector3 = Vector3.ZERO
var _has_seen: bool = false
var _separate: Vector3 = Vector3.ZERO
var _last_attacker: Node3D = null

static var _tracer_mesh: BoxMesh = null

var _body: MeshInstance3D
var _eye: MeshInstance3D
var _eye_light: OmniLight3D
var _mat: StandardMaterial3D
var _walk_t: float = 0.0
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func _ready() -> void:
	add_to_group("bot")
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	var palette := _palette_for(kind)
	if GameConfig.realistic:
		_build_soldier(palette)
	else:
		_build_classic(palette)
	match kind:
		"heavy":
			scale = Vector3.ONE * 1.22
		"runner":
			scale = Vector3.ONE * 0.9
	_wander_target = global_position
	_shoot_cd = randf_range(0.5, 1.5)
	_pick_wander()


func _palette_for(k: String) -> Dictionary:
	match k:
		"heavy":
			return {"uni": Color(0.22, 0.10, 0.10), "dark": Color(0.08, 0.08, 0.09),
				"helmet": Color(0.10, 0.10, 0.12), "visor": Color(1.0, 0.1, 0.1),
				"body": Color(0.5, 0.08, 0.08)}
		"runner":
			return {"uni": Color(0.45, 0.35, 0.20), "dark": Color(0.25, 0.18, 0.10),
				"helmet": Color(0.30, 0.24, 0.14), "visor": Color(1.0, 0.6, 0.1),
				"body": Color(0.9, 0.55, 0.15)}
	return {"uni": Color(0.28, 0.30, 0.22), "dark": Color(0.12, 0.11, 0.10),
		"helmet": Color(0.16, 0.17, 0.14), "visor": Color(1.0, 0.2, 0.15),
		"body": Color(0.85, 0.25, 0.15)}


func _solid(color: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _glow_mat(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _part(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _build_classic(palette: Dictionary) -> void:
	_body = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.36
	cm.height = 1.7
	_body.mesh = cm
	_body.position = Vector3(0, 0.9, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = palette["body"]
	_mat.emission_enabled = true
	var ec: Color = palette["body"]
	_mat.emission = Color(ec.r * 0.6, ec.g * 0.6, ec.b * 0.6)
	_mat.emission_energy_multiplier = 0.7
	_body.material_override = _mat
	add_child(_body)
	# Auge (liest sich als "Gesicht" -> immersiver)
	_eye = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	_eye.mesh = sm
	_eye.position = Vector3(0, 1.5, -0.3)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1, 0.9, 0.3)
	em.emission_enabled = true
	em.emission = palette["visor"]
	em.emission_energy_multiplier = 2.0
	_eye.material_override = em
	add_child(_eye)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = palette["visor"]
	_eye_light.light_energy = 0.6
	_eye_light.omni_range = 4.0
	_eye.add_child(_eye_light)


func _build_soldier(palette: Dictionary) -> void:
	var uni := _solid(palette["uni"], 0.9)
	var dark := _solid(palette["dark"], 0.85)
	var helm := _solid(palette["helmet"], 0.8)
	var metal := _solid(Color(0.1, 0.1, 0.12), 0.4, 0.7)
	_mat = uni
	# Beine mit Hüft-Pivot (für Walk-Animation)
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.13, 0.85, 0)
	add_child(_leg_l)
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.13, 0.85, 0)
	add_child(_leg_r)
	_part(Vector3(0.17, 0.85, 0.19), Vector3(0, -0.42, 0), uni, _leg_l)
	_part(Vector3(0.17, 0.85, 0.19), Vector3(0, -0.42, 0), uni, _leg_r)
	_part(Vector3(0.18, 0.15, 0.27), Vector3(0, -0.78, -0.03), dark, _leg_l)
	_part(Vector3(0.18, 0.15, 0.27), Vector3(0, -0.78, -0.03), dark, _leg_r)
	# Torso + Weste + Rucksack
	_part(Vector3(0.52, 0.62, 0.32), Vector3(0, 1.16, 0), uni)
	_part(Vector3(0.56, 0.42, 0.36), Vector3(0, 1.18, 0), dark)
	_part(Vector3(0.40, 0.45, 0.18), Vector3(0, 1.20, 0.25), dark)
	# Arme mit Schulter-Pivot
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.34, 1.42, 0)
	add_child(_arm_l)
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.34, 1.42, 0)
	add_child(_arm_r)
	_part(Vector3(0.14, 0.60, 0.16), Vector3(0, -0.30, 0), uni, _arm_l)
	_part(Vector3(0.14, 0.60, 0.16), Vector3(0, -0.30, 0), uni, _arm_r)
	# Kopf + Helm + Visier
	_part(Vector3(0.26, 0.26, 0.26), Vector3(0, 1.60, 0), dark)
	_part(Vector3(0.32, 0.18, 0.32), Vector3(0, 1.74, 0), helm)
	_part(Vector3(0.36, 0.05, 0.36), Vector3(0, 1.66, 0), helm)
	_part(Vector3(0.20, 0.06, 0.03), Vector3(0, 1.60, -0.14), _glow_mat(palette["visor"], 2.5))
	# Waffe in Anschlag
	_part(Vector3(0.07, 0.12, 0.55), Vector3(0.18, 1.25, -0.35), metal)
	_part(Vector3(0.06, 0.18, 0.10), Vector3(0.18, 1.12, -0.25), dark)


func setup_bot(p_name: String, hp_mult: float = 1.0, dmg_mult: float = 1.0, p_skill: float = 0.5, p_kind: String = "normal") -> void:
	display_name = p_name
	hp = 100.0 * hp_mult
	damage = 12.0 * dmg_mult
	kind = p_kind
	skill = clampf(p_skill, 0.0, 1.0)
	accuracy = 0.5 + 0.45 * skill
	fire_interval = 1.3 - 0.6 * skill
	move_speed = 3.8 + 1.6 * skill


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_flash = maxf(0.0, _flash - delta * 5.0)
	_mat.emission_energy_multiplier = 0.7 + _flash * 3.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25
		_think()
	_update_move(delta)
	move_and_slide()
	_update_walk_anim(delta)
	_shoot_cd -= delta
	_react_t -= delta
	_burst_pause -= delta
	if _state == "attack" and _react_t <= 0.0 and _burst_pause <= 0.0 and _shoot_cd <= 0.0 and target != null and is_instance_valid(target):
		if _burst_left <= 0:
			_burst_left = 3
		_shoot_cd = fire_interval * randf_range(0.85, 1.3)
		_shoot_at_target()
		_burst_left -= 1
		if _burst_left <= 0:
			_burst_pause = randf_range(0.6, 1.1)


func _think() -> void:
	target = _nearest_player()
	_update_separation()
	if target == null or not is_instance_valid(target):
		target = null
		_state = "wander"
		return
	var dist: float = global_position.distance_to(target.global_position)
	if _has_los(target):
		_last_seen = target.global_position
		_has_seen = true
		if dist > 16.0:
			_set_state("chase")
		elif dist < 7.0:
			_set_state("retreat")
		else:
			_set_state("attack")
	else:
		if _has_seen:
			# Letzte bekannte Position prüfen, dann aufgeben
			_set_state("chase")
			_wander_target = _last_seen
			if global_position.distance_to(_last_seen) < 2.0:
				_has_seen = false
		else:
			_state = "wander"
	_strafe_t -= 0.25
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.0, 2.5)
		_strafe_dir = -_strafe_dir if randf() < 0.7 else randf_range(-1.0, 1.0)


func _set_state(s: String) -> void:
	if _state != s:
		_state = s
		if s == "attack":
			# Reaktionsträgheit: nicht sofort losballern
			_react_t = randf_range(0.2, 0.5) * (1.3 - skill)
			_burst_left = 0
			_burst_pause = 0.0
	if target != null:
		_wander_target = target.global_position


func _update_separation() -> void:
	_separate = Vector3.ZERO
	for n in get_tree().get_nodes_in_group("bot"):
		if n == self or not (n is Node3D):
			continue
		var other := n as Node3D
		if other.get("alive") != null and not bool(other.get("alive")):
			continue
		var off: Vector3 = global_position - other.global_position
		off.y = 0
		var d := off.length()
		if d > 0.01 and d < 2.5:
			_separate += off.normalized() * (1.0 - d / 2.5)


func _update_move(delta: float) -> void:
	var wish := Vector3.ZERO
	match _state:
		"wander":
			if global_position.distance_to(_wander_target) < 1.5:
				_pick_wander()
			wish = (_wander_target - global_position)
			wish.y = 0
			wish = wish.normalized()
		"chase":
			wish = (_wander_target - global_position)
			wish.y = 0
			wish = wish.normalized()
		"retreat":
			wish = (global_position - target.global_position)
			wish.y = 0
			wish = wish.normalized()
		"attack":
			# Wunschdistanz halten + seitlich strafen
			var to_t: Vector3 = target.global_position - global_position
			to_t.y = 0
			var dist: float = to_t.length()
			var fwd := to_t.normalized()
			var side := fwd.cross(Vector3.UP).normalized()
			var radial := Vector3.ZERO
			if dist > 13.0:
				radial = fwd
			elif dist < 8.0:
				radial = -fwd
			wish = (radial * 0.8 + side * _strafe_dir).normalized()
	if _separate.length() > 0.01:
		if wish.length() > 0.01:
			wish = (wish + _separate * 0.9).normalized()
		else:
			wish = _separate.normalized()
	if wish.length() > 0.01:
		# Wand ausweichen: vorne prüfen, ggf. hüpfen
		if _blocked_ahead():
			wish = wish.rotated(Vector3.UP, 1.2)
			if _state == "chase" and is_on_floor():
				velocity.y = 4.0
		velocity.x = wish.x * move_speed
		velocity.z = wish.z * move_speed
		var target_yaw := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * TURN_SPEED)
	else:
		velocity.x = 0
		velocity.z = 0
	# Im Kampf immer zum Ziel schauen
	if target != null and is_instance_valid(target) and (_state == "attack" or _state == "retreat"):
		var look := target.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), delta * 8.0)


func _update_walk_anim(delta: float) -> void:
	if _leg_l == null:
		return
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.5 and is_on_floor():
		_walk_t += delta * (4.0 + spd * 0.8)
	var sw := sin(_walk_t) * clampf(spd / 4.0, 0.0, 1.0) * 0.55
	_leg_l.rotation.x = sw
	_leg_r.rotation.x = -sw
	_arm_l.rotation.x = -sw * 0.8
	_arm_r.rotation.x = sw * 0.8


func _blocked_ahead() -> bool:
	var params := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.0, 0),
		global_position + Vector3(0, 1.0, 0) - global_transform.basis.z * 1.6)
	params.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	return not hit.is_empty()


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("player"):
		if n == self:
			continue
		if n.get("alive") != null and not bool(n.get("alive")):
			continue
		# Remote-Spieler ohne Authority trotzdem als Ziel ok
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _has_los(t: Node3D) -> bool:
	var from := global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = (t.global_position + Vector3(0, 1.4, 0))
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 3 # Welt + Spieler; andere Bots blockieren die Sicht nicht
	params.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return true
	var c := hit.get("collider") as Object
	return c == t


func _shoot_at_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := global_position + Vector3(0, 1.5, 0)
	var aim: Vector3 = (target.global_position + Vector3(0, 1.3, 0)) - from
	var dist := aim.length()
	aim = aim.normalized()
	# Fehler wächst mit Distanz
	var miss := lerpf(0.02, 0.09, clampf(dist / 30.0, 0.0, 1.0)) * (1.2 - accuracy)
	aim = aim.rotated(Vector3.UP, randf_range(-miss, miss))
	aim = aim.rotated(Vector3.RIGHT, randf_range(-miss, miss))
	var params := PhysicsRayQueryParameters3D.create(from, from + aim * 40.0)
	params.collision_mask = 3 # kein Friendly-Fire durch andere Bots hindurch
	params.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	var end: Vector3 = from + aim * 40.0
	if not hit.is_empty():
		end = hit["position"]
		var c := hit.get("collider") as Object
		if c != null and c.has_method("take_damage"):
			var dmg := damage
			if GameConfig.one_hit:
				dmg = 1000.0
			c.take_damage(dmg, self)
	_spawn_tracer(from, end)
	AudioManager.play_shoot("pistole")


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3.ONE
	mi.mesh = _tracer_mesh
	mi.scale = Vector3(0.025, 0.025, len)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.3, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.25, 0.15)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)


func take_damage(amount: float, attacker: Object) -> bool:
	if not alive:
		return false
	hp -= amount
	_flash = 1.0
	# Aggro: Angreifer sofort jagen
	if attacker is Node3D:
		_last_attacker = attacker
		target = attacker
		_last_seen = attacker.global_position
		_has_seen = true
		_state = "chase"
	if hp <= 0.0:
		var killer := "?"
		if attacker != null and "display_name" in attacker:
			killer = str(attacker.get("display_name"))
			if attacker.has_method("add_kill"):
				attacker.add_kill()
		die(killer)
		return true
	return false


func die(killer_name: String) -> void:
	if not alive:
		return
	alive = false
	died.emit(self, killer_name)
	AudioManager.play_kill()
	# Alarm: Bots in der Nähe jagen den Killer weiter
	if _last_attacker != null and is_instance_valid(_last_attacker):
		for n in get_tree().get_nodes_in_group("bot"):
			if n == self or not (n is OHBot):
				continue
			var b := n as OHBot
			if b.alive and b.global_position.distance_to(global_position) < 12.0:
				b.target = _last_attacker
				b._last_seen = _last_attacker.global_position
				b._has_seen = true
				b._state = "chase"
	# Sterbe-Effekt: umfallen + versinken + aufräumen
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation:x", -1.4, 0.35).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "position:y", position.y - 1.2, 0.9).set_delay(0.35)
	tw.chain().tween_callback(queue_free).set_delay(0.9)


func _pick_wander() -> void:
	_wander_target = global_position + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
	_wander_target.x = clampf(_wander_target.x, -19.0, 19.0)
	_wander_target.z = clampf(_wander_target.z, -19.0, 19.0)
