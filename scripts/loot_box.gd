class_name OHLootBox
extends StaticBody3D
## Loot-Box: E drücken oder anschießen -> zufällige Belohnung (Waffe/Heal/Munition).
## Cover-Boxen sind reine Geometrie (siehe game.gd) und nutzen dieses Skript NICHT.

signal opened(box: OHLootBox, reward_text: String)

var is_open: bool = false
var respawn_time: float = 20.0
var _cd: float = 0.0

var _mesh: MeshInstance3D
var _lid: MeshInstance3D
var _light: OmniLight3D
var _mat: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	add_to_group("loot_box")
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	add_child(col)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.8, 1.0)
	_mesh.mesh = bm
	_mesh.position = Vector3(0, 0.4, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.15, 0.7, 0.4)
	_mat.emission_enabled = true
	_mat.emission = Color(0.1, 0.8, 0.4)
	_mat.emission_energy_multiplier = 0.8
	_mesh.material_override = _mat
	add_child(_mesh)
	_lid = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.0, 0.2, 1.0)
	_lid.mesh = lm
	_lid.position = Vector3(0, 0.9, 0)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.9, 0.75, 0.2)
	lmat.emission_enabled = true
	lmat.emission = Color(0.9, 0.7, 0.2)
	lmat.emission_energy_multiplier = 0.9
	_lid.material_override = lmat
	add_child(_lid)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.3, 1.0, 0.5)
	_light.light_energy = 0.7
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.6, 0)
	add_child(_light)
	_label = Label3D.new()
	_label.text = "LOOT"
	_label.position = Vector3(0, 1.7, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.pixel_size = 0.01
	_label.modulate = Color(0.6, 1.0, 0.7)
	add_child(_label)


func _process(delta: float) -> void:
	# Schweben/Rotieren für Lesbarkeit + Respawn-Timer
	if is_open:
		_cd -= delta
		if _cd <= 0.0:
			_close_respawn()
	else:
		_lid.position.y = 0.9 + sin(Time.get_ticks_msec() / 400.0) * 0.05
		_light.light_energy = 0.6 + sin(Time.get_ticks_msec() / 300.0) * 0.15


func interact(player: OHPlayer) -> void:
	if is_open or player == null:
		return
	_give(player)


func take_damage(_amount: float, attacker: Object) -> bool:
	if is_open:
		return false
	if attacker is OHPlayer:
		_give(attacker)
		return true
	return false


func _give(player: OHPlayer) -> void:
	is_open = true
	_cd = respawn_time
	var roll := randf()
	var text := ""
	if roll < 0.38:
		# Waffe (die, die fehlt, sonst Heal)
		var missing: Array[String] = []
		for w in WeaponDefs.ORDER:
			if not player.owned.has(w):
				missing.append(w)
		if missing.is_empty():
			player.heal(50)
			text = "+50 HP"
		else:
			var wid: String = missing[randi() % missing.size()]
			player.give_weapon(wid)
			text = "NEU: " + str(WeaponDefs.get_def(wid)["name"])
	elif roll < 0.72:
		player.heal(50)
		text = "+50 HP"
	else:
		for w in player.owned:
			player.mag_left[w] = WeaponDefs.get_def(w)["mag"]
		player._emit_ammo()
		text = "Munition voll"
	AudioManager.play_pickup()
	opened.emit(self, text)
	_set_open_visual()
	# Multiplayer: Zustand an alle (simpel, Host-agnostisch)
	if player.online:
		rpc("_net_open")
	# Kleiner Pop-Effekt
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(1.15, 0.8, 1.15), 0.12)
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.18)


func _set_open_visual() -> void:
	_mat.albedo_color = Color(0.25, 0.25, 0.28)
	_mat.emission = Color(0.1, 0.1, 0.1)
	_mat.emission_energy_multiplier = 0.2
	_light.light_energy = 0.1
	_label.text = "..."


func _close_respawn(announce: bool = true) -> void:
	is_open = false
	_set_closed_visual()
	if announce and multiplayer.has_multiplayer_peer():
		rpc("_net_close")


func _set_closed_visual() -> void:
	_mat.albedo_color = Color(0.15, 0.7, 0.4)
	_mat.emission = Color(0.1, 0.8, 0.4)
	_mat.emission_energy_multiplier = 0.8
	_label.text = "LOOT"


@rpc("any_peer", "unreliable")
func _net_open() -> void:
	if is_open:
		return
	is_open = true
	_cd = respawn_time
	_set_open_visual()


@rpc("any_peer", "unreliable")
func _net_close() -> void:
	_cd = respawn_time
	_close_respawn(false) # kein Re-Broadcast -> keine RPC-Schleife
