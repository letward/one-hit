class_name OHPlayer
extends CharacterBody3D
## First-Person-Controller: simpel, aber immersiv (Bob, Shake, FOV-Kick, Tracer).

signal health_changed(hp: int, max_hp: int)
signal ammo_changed(mag: int, mag_size: int, weapon_id: String, weapon_name: String)
signal died(victim_name: String, killer_name: String)
signal killed_enemy(victim_name: String)
signal hit_confirmed(kill: bool)
signal interact_hint(text: String)
signal weapon_changed(weapon_id: String)
signal shield_used
signal respawned

const GRAVITY = 20.0
const WALK_SPEED = 5.5
const SPRINT_SPEED = 8.0
const JUMP_VEL = 5.0
const MOUSE_Y_CLAMP = 1.45

var display_name: String = "Spieler"
var peer_id: int = 0
var online: bool = false

var max_hp: int = 100
var hp: int = 100
var alive: bool = true
var shield: bool = false
var protect_t: float = 0.0
var skin_accent: Color = Color(0.4, 0.9, 1.0)

var owned: Array[String] = ["pistole"]
var current: String = "pistole"
var mag_left: Dictionary = {}
var cooldown: float = 0.0
var reloading: float = 0.0
var ADS: bool = false

var head: Node3D
var camera: Camera3D
var gun_root: Node3D
var gun_mesh: MeshInstance3D
var gun_tip: Marker3D
var muzzle_light: OmniLight3D
var body_mesh: MeshInstance3D
var name_label: Label3D
var shield_bubble: MeshInstance3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _trauma: float = 0.0
var _bob_t: float = 0.0
var _step_t: float = 0.0
var _base_fov: float = 75.0
var _fov_kick: float = 0.0
var _respawn_t: float = 0.0
var _sync_t: float = 0.0
var _kills: int = 0
var _hold_fire: bool = false
var _prompt_t: float = 0.0
var _gun_tween: Tween = null
var _count_last: int = -1
var _ads_last: bool = false
var _sway_t: float = 0.0

static var _tracer_mesh: BoxMesh = null
static var _impact_quad: QuadMesh = null


func setup(p_peer_id: int, p_name: String, p_online: bool) -> void:
	peer_id = p_peer_id
	display_name = p_name
	online = p_online
	if online:
		# Authority = Besitzer-Client (Host hat id 1)
		set_multiplayer_authority(p_peer_id)


func is_local() -> bool:
	if not online:
		return true
	return is_multiplayer_authority()


func _ready() -> void:
	_base_fov = GameConfig.base_fov
	for w in WeaponDefs.ORDER:
		mag_left[w] = WeaponDefs.get_def(w)["mag"]
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	_build_body()
	_build_head()
	if online and not is_multiplayer_authority():
		# Remote-Spieler: kein Input, keine eigene Kamera
		if camera:
			camera.current = false
		set_physics_process(true) # weiter simulieren für Remote-Lerp
	else:
		if camera:
			camera.current = true
	health_changed.emit(hp, max_hp)
	_emit_ammo()
	protect_t = 2.0
	_update_shield_visual()


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	# Sichtbarer Körper für Multiplayer-Gegner (lokal unsichtbar)
	body_mesh = MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.36
	cap_mesh.height = 1.7
	body_mesh.mesh = cap_mesh
	body_mesh.position = Vector3(0, 0.9, 0)
	var skin: Dictionary = SkinDefs.get_def(Save.skin_selected)
	skin_accent = skin["accent"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = skin["body"]
	mat.roughness = 0.6
	body_mesh.material_override = mat
	add_child(body_mesh)
	name_label = Label3D.new()
	name_label.text = display_name
	name_label.position = Vector3(0, 2.15, 0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 48
	name_label.pixel_size = 0.008
	var lc := skin_accent
	lc.a = 0.95
	name_label.modulate = lc
	add_child(name_label)
	shield_bubble = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.1
	sp.height = 2.2
	shield_bubble.mesh = sp
	shield_bubble.position = Vector3(0, 1.0, 0)
	var sm2 := StandardMaterial3D.new()
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm2.albedo_color = Color(0.3, 0.8, 1.0, 0.22)
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_bubble.material_override = sm2
	shield_bubble.visible = false
	add_child(shield_bubble)
	# Eigenen Körper für lokale Kamera ausblenden (Schatten egal bei simpel)
	if not online or is_multiplayer_authority():
		# wird nach Authority gesetzt; sicherheitshalber im _ready deferred prüfen
		call_deferred("_maybe_hide_self")


func _maybe_hide_self() -> void:
	if is_local():
		body_mesh.visible = false
		name_label.visible = false


func _update_shield_visual() -> void:
	if shield_bubble:
		shield_bubble.visible = shield or protect_t > 0.0


func _shop_open() -> bool:
	var games := get_tree().get_nodes_in_group("game")
	if games.is_empty():
		return false
	return bool(games[0].get("shop_open"))


func _build_head() -> void:
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = _base_fov
	camera.near = 0.05
	camera.far = 200.0
	head.add_child(camera)
	gun_root = Node3D.new()
	gun_root.position = Vector3(0.32, -0.3, -0.55)
	camera.add_child(gun_root)
	_rebuild_gun()


func _rebuild_gun() -> void:
	if gun_root == null:
		return
	for ch in gun_root.get_children():
		gun_root.remove_child(ch)
		ch.free()
	if GameConfig.realistic:
		_build_gun_realistic()
	else:
		_build_gun_classic()


func _build_gun_classic() -> void:
	gun_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.55)
	gun_mesh.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = WeaponDefs.get_def(current)["gun_color"]
	gm.emission_enabled = true
	gm.emission = WeaponDefs.get_def(current)["gun_color"]
	gm.emission_energy_multiplier = 0.6
	gun_mesh.material_override = gm
	gun_root.add_child(gun_mesh)
	# Visier-Nase
	var sight := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.03, 0.05, 0.06)
	sight.mesh = sm
	sight.position = Vector3(0, 0.11, -0.1)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.1, 0.1, 0.12)
	smat.emission_enabled = true
	smat.emission = SkinDefs.get_def(Save.skin_selected)["accent"]
	smat.emission_energy_multiplier = 1.2
	sight.material_override = smat
	gun_root.add_child(sight)
	gun_tip = Marker3D.new()
	gun_tip.position = Vector3(0, 0.02, -0.35)
	gun_root.add_child(gun_tip)
	_make_muzzle_light()


func _make_muzzle_light() -> void:
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.85, 0.4)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 6.0
	gun_tip.add_child(muzzle_light)


func _gun_spec(wid: String) -> Dictionary:
	match wid:
		"streu":
			return {"r": 0.34, "bl": 0.30, "br": 0.045, "extra": "pump"}
		"rail":
			return {"r": 0.36, "bl": 0.55, "br": 0.020, "extra": "coils"}
		"wasp":
			return {"r": 0.28, "bl": 0.15, "br": 0.025, "extra": "rail_top"}
		"falke":
			return {"r": 0.34, "bl": 0.50, "br": 0.022, "extra": "scope"}
		"mauer":
			return {"r": 0.36, "bl": 0.35, "br": 0.030, "extra": "drum"}
	return {"r": 0.30, "bl": 0.12, "br": 0.025, "extra": ""}


func _gmat(color: Color, metal: float, rough: float, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m


func _gbox(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	gun_root.add_child(mi)
	return mi


func _gcyl(radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = PI * 0.5
	gun_root.add_child(mi)
	return mi


func _build_gun_realistic() -> void:
	var spec := _gun_spec(current)
	var def := WeaponDefs.get_def(current)
	var metal := TexFactory.mat("metal", Color(0.42, 0.42, 0.46), 2.0, 0.85, 0.4)
	var poly := TexFactory.mat("concrete", Color(0.30, 0.29, 0.28), 1.5, 0.0, 0.8)
	var accent: Color = def["gun_color"]
	var aglow := _gmat(accent, 0.2, 0.4, 0.9)
	var skin_glow := _gmat(SkinDefs.get_def(Save.skin_selected)["accent"], 0.0, 0.5, 1.5)
	var rl: float = spec["r"]
	# Receiver
	gun_mesh = _gbox(Vector3(0.09, 0.13, rl), Vector3.ZERO, metal)
	# Akzent-Streifen + Skin-Leiste
	_gbox(Vector3(0.095, 0.02, rl * 0.7), Vector3(0, 0.03, 0.02), aglow)
	_gbox(Vector3(0.095, 0.012, rl * 0.5), Vector3(0, -0.045, 0.03), skin_glow)
	# Lauf
	var bl: float = spec["bl"]
	var front_z := -(rl * 0.5 + bl * 0.5)
	_gcyl(float(spec["br"]), bl, Vector3(0, 0.01, front_z), metal)
	# Griff + Schaft
	_gbox(Vector3(0.07, 0.14, 0.09), Vector3(0, -0.12, 0.10), poly)
	if rl > 0.32:
		_gbox(Vector3(0.08, 0.11, 0.16), Vector3(0, -0.01, rl * 0.5 + 0.07), poly)
	_gbox(Vector3(0.06, 0.16, 0.09), Vector3(0, -0.13, -0.05), poly)
	# Visierung
	_gbox(Vector3(0.02, 0.05, 0.03), Vector3(0, 0.09, 0.05), metal)
	_gbox(Vector3(0.015, 0.04, 0.015), Vector3(0, 0.085, front_z + bl * 0.5 - 0.03), metal)
	# Extras pro Waffe
	match str(spec["extra"]):
		"pump":
			_gbox(Vector3(0.09, 0.07, 0.14), Vector3(0, -0.05, front_z), poly)
		"coils":
			for i in 3:
				_gbox(Vector3(0.07, 0.07, 0.03), Vector3(0, 0.01, front_z - 0.12 + i * 0.12), aglow)
		"rail_top":
			_gbox(Vector3(0.05, 0.02, rl * 0.8), Vector3(0, 0.075, 0), metal)
		"scope":
			_gcyl(0.035, 0.18, Vector3(0, 0.11, 0.02), metal)
			_gbox(Vector3(0.03, 0.05, 0.03), Vector3(0, 0.08, 0.02), metal)
		"drum":
			var dm := MeshInstance3D.new()
			var dc := CylinderMesh.new()
			dc.top_radius = 0.09
			dc.bottom_radius = 0.09
			dc.height = 0.08
			dm.mesh = dc
			dm.material_override = poly
			dm.position = Vector3(0, -0.14, -0.05)
			gun_root.add_child(dm)
	# Mündung
	gun_tip = Marker3D.new()
	gun_tip.position = Vector3(0, 0.01, front_z - bl * 0.5 - 0.02)
	gun_root.add_child(gun_tip)
	_make_muzzle_light()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or not alive:
		return
	if _shop_open():
		return
	if Neocrom.overlay_open():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameConfig.sensitivity
		_yaw -= event.relative.x * sens
		var dy: float = event.relative.y * sens * (-1.0 if GameConfig.invert_y else 1.0)
		_pitch = clampf(_pitch - dy, -MOUSE_Y_CLAMP, MOUSE_Y_CLAMP)
		rotation.y = _yaw
		head.rotation.x = _pitch
	if event.is_action_pressed("fire"):
		_hold_fire = true
		try_shoot()
	elif event.is_action_released("fire"):
		_hold_fire = false
	if event.is_action_pressed("reload"):
		start_reload()
	if event.is_action_pressed("interact"):
		try_interact()
	if event.is_action_pressed("weapon_1"):
		switch_weapon(0)
	if event.is_action_pressed("weapon_2"):
		switch_weapon(1)
	if event.is_action_pressed("weapon_3"):
		switch_weapon(2)
	if event.is_action_pressed("weapon_4"):
		switch_weapon(3)
	if event.is_action_pressed("weapon_5"):
		switch_weapon(4)
	if event.is_action_pressed("weapon_6"):
		switch_weapon(5)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			switch_weapon(_current_index() - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			switch_weapon(_current_index() + 1)


func _current_index() -> int:
	return owned.find(current)


func switch_weapon(idx: int) -> void:
	if owned.is_empty():
		return
	idx = (idx + owned.size()) % owned.size()
	var nid: String = owned[idx]
	if nid == current:
		return
	current = nid
	reloading = 0.0
	cooldown = maxf(cooldown, 0.15)
	_rebuild_gun()
	weapon_changed.emit(current)
	_emit_ammo()
	AudioManager.play_reload()


func give_weapon(wid: String) -> bool:
	if owned.has(wid):
		mag_left[wid] = WeaponDefs.get_def(wid)["mag"]
		_emit_ammo()
		return false
	owned.append(wid)
	mag_left[wid] = WeaponDefs.get_def(wid)["mag"]
	current = wid
	_rebuild_gun()
	reloading = 0.0
	cooldown = 0.25
	weapon_changed.emit(current)
	_emit_ammo()
	AudioManager.play_pickup()
	return true


func heal(amount: int) -> void:
	if not alive:
		return
	hp = mini(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)
	AudioManager.play_pickup()


func start_reload() -> void:
	if reloading > 0.0 or not alive:
		return
	var def: Dictionary = WeaponDefs.get_def(current)
	if int(mag_left[current]) >= int(def["mag"]):
		return
	reloading = float(def["reload"])
	AudioManager.play_reload()


func _physics_process(delta: float) -> void:
	# Remote-Spieler im Online-Modus: nur Gravitation/simpel, Transform kommt via RPC
	if online and not is_multiplayer_authority():
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
			move_and_slide()
		return
	if not alive:
		_respawn_t -= delta
		var left := int(ceil(maxf(_respawn_t, 0.0)))
		if left != _count_last:
			_count_last = left
			var h := get_tree().get_first_node_in_group("hud")
			if h != null and h.has_method("show_message"):
				h.show_message("Respawn in %d …" % maxi(left, 1), 1.0)
		if _respawn_t <= 0.0:
			respawn()
		return
	cooldown = maxf(0.0, cooldown - delta)
	if protect_t > 0.0:
		protect_t -= delta
		_update_shield_visual()
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var def: Dictionary = WeaponDefs.get_def(current)
			mag_left[current] = int(def["mag"])
			_emit_ammo()
	# ADS (rechte Maustaste = Zielen)
	ADS = Input.is_action_pressed("aim") and is_local()
	if ADS != _ads_last:
		_ads_last = ADS
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("set_crosshair_ads"):
			hud.set_crosshair_ads(ADS and GameConfig.realistic)
	# Dauerfeuer nur für Auto-Waffen
	if _hold_fire and is_local():
		var d: Dictionary = WeaponDefs.get_def(current)
		if bool(d.get("auto", false)):
			try_shoot()
	# Bewegung
	var input_dir := Vector2.ZERO
	if is_local():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := is_local() and Input.is_action_pressed("sprint") and input_dir.y < -0.1
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if ADS:
		speed *= 0.55
	var dir3 := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized() if input_dir.length() > 0.01 else Vector3.ZERO
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif is_local() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VEL
	velocity.x = dir3.x * speed
	velocity.z = dir3.z * speed
	move_and_slide()
	# Head-Bob + Schritte
	if dir3.length() > 0.1 and is_on_floor():
		_bob_t += delta * (11.0 if sprinting else 8.0)
		_step_t += delta * speed
		if _step_t > 3.2:
			_step_t = 0.0
			AudioManager.play_step()
	else:
		_bob_t = lerpf(_bob_t, 0.0, delta * 6.0)
	var bob := sin(_bob_t) * 0.045
	head.position.y = 1.62 + bob
	if GameConfig.realistic:
		# Atmung: kaum merkliches Schwanken im Stillstand
		_sway_t += delta
		head.position.x = sin(_sway_t * 0.9) * 0.008
	else:
		head.position.x = 0.0
	# FOV: Sprint + Schuss-Kick + ADS-Zoom
	var target_fov := _base_fov
	if sprinting:
		target_fov += 8.0
	if ADS:
		target_fov = 45.0 if GameConfig.realistic else 52.0
	_fov_kick = lerpf(_fov_kick, 0.0, delta * 8.0)
	camera.fov = lerpf(camera.fov, target_fov + _fov_kick, delta * 10.0)
	# Screenshake (abschaltbar)
	_trauma = maxf(0.0, _trauma - delta * 2.2)
	if _trauma > 0.0 and GameConfig.shake_enabled:
		var s := _trauma * _trauma * 0.12
		camera.h_offset = randf_range(-s, s)
		camera.v_offset = randf_range(-s, s)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	# Gun-Sway
	gun_root.position.x = lerpf(gun_root.position.x, 0.32 if not ADS else 0.0, delta * 10.0)
	gun_root.position.y = lerpf(gun_root.position.y, -0.3 if not ADS else -0.22, delta * 10.0)
	# Muzzle-Licht abklingen
	muzzle_light.light_energy = maxf(0.0, muzzle_light.light_energy - delta * 30.0)
	# Interact-Hinweis (gedrosselt auf ~8 Hz statt jedem Physics-Frame)
	if is_local():
		_prompt_t -= delta
		if _prompt_t <= 0.0:
			_prompt_t = 0.12
			_update_interact_hint()
	# Online-Transform sync (20 Hz)
	if online:
		_sync_t += delta
		if _sync_t >= 0.05:
			_sync_t = 0.0
			rpc("_net_transform", global_position, _yaw, _pitch)


func try_interact() -> void:
	var box := _aimed_box(3.2)
	if box != null and box.has_method("interact"):
		box.interact(self)


func _update_interact_hint() -> void:
	var box := _aimed_box(3.2)
	if box != null:
		interact_hint.emit("[E] Loot-Box öffnen")
	else:
		interact_hint.emit("")


func _aimed_box(max_dist: float) -> Object:
	var params := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_transform.basis.z * max_dist)
	params.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var c := hit.get("collider") as Object
	if c != null and c.is_in_group("loot_box"):
		return c
	return null


func try_shoot() -> void:
	if not alive or cooldown > 0.0 or reloading > 0.0:
		return
	var def: Dictionary = WeaponDefs.get_def(current)
	if int(mag_left.get(current, 0)) <= 0:
		AudioManager.play_empty()
		cooldown = 0.3
		start_reload()
		return
	mag_left[current] = int(mag_left[current]) - 1
	cooldown = float(def["interval"])
	_emit_ammo()
	AudioManager.play_shoot(current)
	# Feel: Kick, Licht, FOV
	_trauma = minf(1.0, _trauma + float(def["kick"]) * 8.0)
	_pitch = clampf(_pitch + float(def["kick"]) * 0.6, -MOUSE_Y_CLAMP, MOUSE_Y_CLAMP)
	rotation.y = _yaw
	head.rotation.x = _pitch
	_fov_kick += 2.5 if current != "rail" else 6.0
	muzzle_light.light_energy = 3.0
	gun_root.position.z = -0.45
	if _gun_tween != null and _gun_tween.is_valid():
		_gun_tween.kill()
	_gun_tween = create_tween()
	_gun_tween.tween_property(gun_root, "position:z", -0.55, 0.12)
	var from: Vector3 = gun_tip.global_position
	var pellets: int = int(def["pellets"])
	var spread: float = deg_to_rad(float(def["spread_deg"])) * (0.35 if ADS else 1.0)
	for i in pellets:
		var dir: Vector3 = -camera.global_transform.basis.z
		dir = dir.rotated(camera.global_transform.basis.x.normalized(), randf_range(-spread, spread))
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
		_fire_single_ray(def, from, dir.normalized())
	if online:
		rpc("_net_fx", current, from)


func _fire_single_ray(def: Dictionary, from: Vector3, dir: Vector3) -> void:
	var max_range: float = float(def["range"])
	var pierce: bool = bool(def.get("pierce", false))
	var exclude: Array[RID] = [get_rid()]
	var origin: Vector3 = from
	var end: Vector3 = from + dir * max_range
	var space := get_world_3d().direct_space_state
	var max_hits := 4 if pierce else 1
	for _h in max_hits:
		var params := PhysicsRayQueryParameters3D.create(origin, from + dir * max_range)
		params.collision_mask = 7
		params.exclude = exclude
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			end = from + dir * max_range
			break
		end = hit["position"]
		var c := hit.get("collider") as Object
		_spawn_impact(end, hit.get("normal", Vector3.UP))
		if c != null:
			var dmg: float = float(def["damage"])
			if GameConfig.one_hit and (c.is_in_group("bot") or c.is_in_group("player")):
				dmg = 1000.0
			if c.has_method("take_damage"):
				if online and c.is_in_group("player") and c != self:
					# Schaden an Remote-Spieler via RPC an dessen Authority
					c.rpc("net_damage", dmg, peer_id, display_name, 0)
				else:
					var killed: bool = c.take_damage(dmg, self)
					hit_confirmed.emit(killed)
				AudioManager.play_hit()
			if c.is_in_group("bot") or c.is_in_group("player"):
				_spawn_damage_number(end, dmg)
			# Railgun durchschlägt Charaktere, stoppt an Welt-Geometrie
			if pierce and (c.is_in_group("bot") or c.is_in_group("player")):
				if c is CollisionObject3D:
					exclude.append((c as CollisionObject3D).get_rid())
				origin = end + dir * 0.05
				continue
		break
	_spawn_tracer(from, end, def["tracer"])


func _spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mi := MeshInstance3D.new()
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3.ONE
	mi.mesh = _tracer_mesh
	mi.scale = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = normal
	pm.spread = 35.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.03
	pm.scale_max = 0.07
	pm.color = Color(1.0, 0.8, 0.4)
	p.process_material = pm
	if _impact_quad == null:
		_impact_quad = QuadMesh.new()
		_impact_quad.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.albedo_color = Color(1, 0.85, 0.5)
	p.draw_pass_1 = _impact_quad
	p.material_override = qm
	get_tree().current_scene.add_child(p)
	p.global_position = pos + normal * 0.05
	p.emitting = true
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


func _spawn_damage_number(pos: Vector3, dmg: float) -> void:
	var l := Label3D.new()
	l.text = "%d" % int(round(dmg))
	l.font_size = 72
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.75, 0.25)
	get_tree().current_scene.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.3, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(l.queue_free)


func _emit_ammo() -> void:
	var def: Dictionary = WeaponDefs.get_def(current)
	ammo_changed.emit(int(mag_left.get(current, 0)), int(def["mag"]), current, str(def["name"]))


func refill_ammo() -> void:
	for w in owned:
		mag_left[w] = WeaponDefs.get_def(w)["mag"]
	_emit_ammo()
	AudioManager.play_pickup()


func upgrade_max_hp() -> void:
	if max_hp >= 200:
		return
	max_hp = mini(200, max_hp + 25)
	heal(25)


func heal_full() -> void:
	hp = max_hp
	health_changed.emit(hp, max_hp)


func take_damage(amount: float, attacker: Object) -> bool:
	## Gibt true zurück, wenn das Ziel dadurch stirbt. (Solo + Bot-Angriffe)
	if not alive:
		return false
	if protect_t > 0.0:
		return false
	if shield:
		shield = false
		_update_shield_visual()
		shield_used.emit()
		AudioManager.play_hit()
		return false
	if online and not is_multiplayer_authority():
		return false
	hp -= int(round(amount))
	health_changed.emit(hp, max_hp)
	AudioManager.play_hurt()
	_trauma = minf(1.0, _trauma + 0.45)
	if hp <= 0:
		var killer := "?"
		if attacker != null and "display_name" in attacker:
			killer = str(attacker.get("display_name"))
		die(killer)
		return true
	return false


@rpc("any_peer", "reliable")
func net_damage(amount: float, killer_id: int, killer_name: String, _unused: int = 0) -> void:
	# Wird auf der Authority des Opfers ausgeführt
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	if protect_t > 0.0:
		return
	if shield:
		shield = false
		_update_shield_visual()
		shield_used.emit()
		return
	hp -= int(round(amount))
	health_changed.emit(hp, max_hp)
	AudioManager.play_hurt()
	if is_local():
		_trauma = minf(1.0, _trauma + 0.45)
	if hp <= 0:
		die(killer_name)
		# Killer über Kill informieren (Score)
		if killer_id != 0 and killer_id != peer_id:
			rpc_id(killer_id, "notify_kill", display_name)


@rpc("any_peer", "reliable")
func notify_kill(victim_name: String) -> void:
	_kills += 1
	killed_enemy.emit(victim_name)
	hit_confirmed.emit(true)
	AudioManager.play_kill()


@rpc("any_peer", "unreliable")
func _net_fx(weapon_id: String, from: Vector3) -> void:
	if is_multiplayer_authority():
		return
	muzzle_light.light_energy = 2.0
	AudioManager.play_shoot(weapon_id)


@rpc("any_peer", "unreliable")
func _net_transform(pos: Vector3, yaw: float, pitch: float) -> void:
	if is_multiplayer_authority():
		return
	global_position = global_position.lerp(pos, 0.5)
	_yaw = yaw
	_pitch = pitch
	rotation.y = yaw
	if head:
		head.rotation.x = pitch


func die(killer_name: String) -> void:
	if not alive:
		return
	alive = false
	_respawn_t = 2.5
	AudioManager.play_kill()
	if online:
		# Einheitlich über net_feed (call_local) -> kein doppeltes Zählen auf der Opfer-Seite
		var games := get_tree().get_nodes_in_group("game")
		for g in games:
			if g.has_method("net_feed"):
				g.rpc("net_feed", killer_name, display_name)
	else:
		died.emit(display_name, killer_name)


func respawn() -> void:
	heal_full()
	alive = true
	protect_t = 2.0
	_count_last = -1
	_update_shield_visual()
	respawned.emit()
	for w in WeaponDefs.ORDER:
		mag_left[w] = WeaponDefs.get_def(w)["mag"] if owned.has(w) else mag_left.get(w, 0)
	cooldown = 0.0
	reloading = 0.0
	_emit_ammo()
	var games := get_tree().get_nodes_in_group("game")
	if not games.is_empty() and games[0].has_method("get_spawn_point"):
		global_position = games[0].get_spawn_point(self)
		_yaw = randf() * TAU
		_pitch = 0.0
		rotation.y = _yaw
		head.rotation.x = 0.0
	velocity = Vector3.ZERO


func kill_count() -> int:
	return _kills


func add_kill() -> void:
	_kills += 1
