class_name OHGame
extends Node3D
## Arena-Manager: baut Level prozedural, spawnt Spieler/Bots/Loot, Wellen + Pause + Win.

const PlayerScene = preload("res://scenes/player.tscn")
const BotScene = preload("res://scenes/bot.tscn")
const LootScene = preload("res://scenes/loot_box.tscn")

const ARENA_HALF = 20.0
const KILLS_TO_WIN_ONLINE = 10

var mode: String = "solo"
var online: bool = false
var rng := RandomNumberGenerator.new()

var local_player: OHPlayer = null
var players: Array[OHPlayer] = []
var bots: Array[OHBot] = []
var spawns: Array[Vector3] = []
var loot_boxes: Array[OHLootBox] = []

var kills: int = 0
var deaths: int = 0
var wave: int = 1
var wave_alive_target: int = 0
var paused: bool = false

var hud: OHHud
var pause_panel: PanelContainer
var shop: OHShop
var shop_open: bool = false
var _last_wave_text: String = ""
var _pause_sens: HSlider
var _pause_vol: HSlider
var _pause_shake: CheckBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Esc + Menü funktionieren auch pausiert
	add_to_group("game")
	mode = GameConfig.pending_mode
	online = (mode == "online") or NetworkManager.is_online
	rng.seed = GameConfig.arena_seed if GameConfig.arena_seed != 0 else randi()
	_build_environment()
	_build_arena()
	_build_hud()
	_build_pause_menu()
	_build_shop()
	Save.games_played += 1
	Save.mark_dirty()
	GameConfig.set_captured(true)
	if online:
		_spawn_online_players()
		NetworkManager.server_disconnected.connect(_on_server_lost)
		_set_wave_cached("Deathmatch: erste/r bei %d Kills gewinnt" % KILLS_TO_WIN_ONLINE)
		hud.feed("Online-Match gestartet (Seed %d)" % GameConfig.arena_seed)
	else:
		_spawn_solo()
		_start_wave(1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop"):
		toggle_shop()
	elif event.is_action_pressed("pause"):
		toggle_pause()


# ---------- Aufbau ----------

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.08, 0.18)
	sky_mat.sky_horizon_color = Color(0.15, 0.2, 0.35)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.08, 0.1, 0.16)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.14, 0.22)
	e.fog_density = 0.015
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.05
	e.adjustment_contrast = 1.08
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(1.0, 0.9, 0.8)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 12, 0)
	fill.light_color = Color(0.4, 0.6, 1.0)
	fill.light_energy = 0.8
	fill.omni_range = 40.0
	add_child(fill)


func _mat(color: Color, emission: Color = Color(0, 0, 0), e_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if e_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = e_energy
	return m


func _add_box(pos: Vector3, size: Vector3, mat: Material, col: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	if col:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	return body


func _build_arena() -> void:
	# Boden
	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_HALF * 2 + 4, 1, ARENA_HALF * 2 + 4),
		_mat(Color(0.09, 0.11, 0.16)))
	# Boden-Raster (dünne leuchtende Streifen für Orientierung)
	for i in range(-2, 3):
		var f: float = float(i) * 8.0
		_add_box(Vector3(f, 0.02, 0), Vector3(0.08, 0.04, ARENA_HALF * 2),
			_mat(Color(0.2, 0.5, 0.8), Color(0.2, 0.5, 0.9), 0.8), false)
		_add_box(Vector3(0, 0.02, f), Vector3(ARENA_HALF * 2, 0.04, 0.08),
			_mat(Color(0.2, 0.5, 0.8), Color(0.2, 0.5, 0.9), 0.8), false)
	# Wände
	var wall_mat := _mat(Color(0.13, 0.15, 0.22))
	var trim_mat := _mat(Color(0.1, 0.3, 0.5), Color(0.2, 0.6, 1.0), 1.2)
	var H := ARENA_HALF
	_add_box(Vector3(0, 3, -H - 0.5), Vector3(H * 2 + 2, 6, 1), wall_mat)
	_add_box(Vector3(0, 3, H + 0.5), Vector3(H * 2 + 2, 6, 1), wall_mat)
	_add_box(Vector3(-H - 0.5, 3, 0), Vector3(1, 6, H * 2 + 2), wall_mat)
	_add_box(Vector3(H + 0.5, 3, 0), Vector3(1, 6, H * 2 + 2), wall_mat)
	# Leucht-Trim oben an Wänden
	_add_box(Vector3(0, 5.6, -H - 0.4), Vector3(H * 2 + 2, 0.15, 0.15), trim_mat, false)
	_add_box(Vector3(0, 5.6, H + 0.4), Vector3(H * 2 + 2, 0.15, 0.15), trim_mat, false)
	# Cover-Boxen (deterministisch aus Seed)
	var cover_mats := [
		_mat(Color(0.16, 0.18, 0.26)),
		_mat(Color(0.2, 0.16, 0.2)),
		_mat(Color(0.14, 0.22, 0.24)),
	]
	for i in 14:
		var px := rng.randf_range(-H + 4, H - 4)
		var pz := rng.randf_range(-H + 4, H - 4)
		if absf(px) < 3.0 and absf(pz) < 3.0:
			px += 6.0 # Mitte freihalten
		var sx := rng.randf_range(1.2, 3.2)
		var sy := rng.randf_range(1.0, 2.6)
		var sz := rng.randf_range(1.2, 3.2)
		_add_box(Vector3(px, sy * 0.5, pz), Vector3(sx, sy, sz), cover_mats[i % cover_mats.size()])
		if rng.randf() < 0.35:
			_add_box(Vector3(px, sy + 0.5, pz), Vector3(sx * 0.7, 1.0, sz * 0.7), cover_mats[(i + 1) % cover_mats.size()])
	# Mittel-Plattform als Blickfang
	_add_box(Vector3(0, 0.25, 0), Vector3(6, 0.5, 6), _mat(Color(0.12, 0.16, 0.24)))
	_add_box(Vector3(0, 0.6, 0), Vector3(6.2, 0.08, 6.2), trim_mat, false)
	# Spawnpunkte (Kreis + Ecken)
	spawns.clear()
	for k in 8:
		var a := TAU * float(k) / 8.0
		spawns.append(Vector3(cos(a) * (H - 3), 1.0, sin(a) * (H - 3)))
	spawns.append(Vector3(-H + 2, 1.0, -H + 2))
	spawns.append(Vector3(H - 2, 1.0, H - 2))
	# Loot-Boxen an fixen Punkten
	var loot_pos := [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(-8, 0, 8), Vector3(8, 0, 8), Vector3(0, 0.5, 0)]
	for li in loot_pos.size():
		var lp: Vector3 = loot_pos[li]
		var lb := LootScene.instantiate() as OHLootBox
		lb.name = "Loot_%d" % li
		lb.position = lp
		add_child(lb)
		lb.opened.connect(_on_loot_opened)
		loot_boxes.append(lb)
	# Staub-Partikel für Atmosphäre
	var dust := GPUParticles3D.new()
	dust.amount = 120
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dpm.emission_box_extents = Vector3(H, 4, H)
	dpm.direction = Vector3(0, 1, 0)
	dpm.spread = 20.0
	dpm.initial_velocity_min = 0.1
	dpm.initial_velocity_max = 0.5
	dpm.gravity = Vector3.ZERO
	dpm.scale_min = 0.02
	dpm.scale_max = 0.06
	dpm.color = Color(0.6, 0.75, 1.0, 0.35)
	dust.process_material = dpm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.05, 0.05)
	dust.draw_pass_1 = dq
	dust.position = Vector3(0, 3, 0)
	add_child(dust)


func _build_hud() -> void:
	hud = OHHud.new()
	add_child(hud)


func _build_pause_menu() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.custom_minimum_size = Vector2(360, 0)
	pause_panel.visible = false
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	pause_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)
	var hint := Label.new()
	hint.text = "WASD Laufen · Maus Schießen · 1/2/3 Waffen · E Loot · R Nachladen"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	vb.add_child(hint)
	var b_resume := Button.new()
	b_resume.text = "Weiter (Esc)"
	b_resume.pressed.connect(toggle_pause)
	vb.add_child(b_resume)
	var b_shop := Button.new()
	b_shop.text = "Shop [B]  (⚙ %d)" % Save.credits
	b_shop.pressed.connect(toggle_shop)
	vb.add_child(b_shop)
	var sens_row := HBoxContainer.new()
	vb.add_child(sens_row)
	var sens_l := Label.new()
	sens_l.text = "Sens:"
	sens_row.add_child(sens_l)
	_pause_sens = HSlider.new()
	_pause_sens.min_value = 0.001
	_pause_sens.max_value = 0.006
	_pause_sens.step = 0.0001
	_pause_sens.value = GameConfig.sensitivity
	_pause_sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_sens.value_changed.connect(func(v: float) -> void:
		GameConfig.sensitivity = v
		Save.mark_dirty())
	sens_row.add_child(_pause_sens)
	var vol_row := HBoxContainer.new()
	vb.add_child(vol_row)
	var vol_l := Label.new()
	vol_l.text = "Volume:"
	vol_row.add_child(vol_l)
	_pause_vol = HSlider.new()
	_pause_vol.min_value = 0.0
	_pause_vol.max_value = 1.0
	_pause_vol.step = 0.01
	_pause_vol.value = GameConfig.volume
	_pause_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_vol.value_changed.connect(func(v: float) -> void:
		GameConfig.volume = v
		AudioManager.set_master_volume(v)
		Save.mark_dirty())
	vol_row.add_child(_pause_vol)
	_pause_shake = CheckBox.new()
	_pause_shake.text = "Kamera-Shake"
	_pause_shake.button_pressed = GameConfig.shake_enabled
	_pause_shake.toggled.connect(func(v: bool) -> void:
		GameConfig.shake_enabled = v
		Save.mark_dirty())
	vb.add_child(_pause_shake)
	var b_restart := Button.new()
	b_restart.text = "Neustart"
	b_restart.pressed.connect(func() -> void:
		paused = false
		get_tree().paused = false
		get_tree().reload_current_scene())
	vb.add_child(b_restart)
	var b_quit := Button.new()
	b_quit.text = "Zum Menü"
	b_quit.pressed.connect(func() -> void:
		get_tree().paused = false
		NetworkManager.reset()
		GameConfig.set_captured(false)
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	vb.add_child(b_quit)
	# Pause-UI braucht eigenen CanvasLayer über HUD (muss pausiert noch laufen)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(pause_panel)
	add_child(layer)


func toggle_pause() -> void:
	if shop_open:
		shop_open = false
		shop.close_shop()
	else:
		paused = not paused
	_apply_time_state()


func toggle_shop() -> void:
	if local_player == null:
		return
	shop_open = not shop_open
	if shop_open:
		shop.open_shop()
	else:
		shop.close_shop()
	_apply_time_state()


func _apply_time_state() -> void:
	var freeze := paused or (shop_open and not online)
	get_tree().paused = freeze
	pause_panel.visible = paused and not shop_open
	GameConfig.set_captured(not paused and not shop_open)


func _build_shop() -> void:
	shop = OHShop.new()
	add_child(shop)
	shop.setup(self)


func buy_offer(kind: String, id: String) -> bool:
	if local_player == null or not local_player.alive:
		return false
	match kind:
		"weapon":
			var price := WeaponDefs.price_of(id)
			if local_player.owned.has(id) or not Save.spend(price):
				return false
			local_player.give_weapon(id)
			hud.feed("Gekauft: " + str(WeaponDefs.get_def(id)["name"]))
		"heal":
			if local_player.hp >= local_player.max_hp or not Save.spend(40):
				return false
			local_player.heal(100)
			hud.feed("Gekauft: Feld-Heilung")
		"ammo":
			if not Save.spend(30):
				return false
			local_player.refill_ammo()
			hud.feed("Gekauft: Munition voll")
		"maxhp":
			if local_player.max_hp >= 200 or not Save.spend(120):
				return false
			local_player.upgrade_max_hp()
			hud.feed("Gekauft: Max-HP +25")
		"shield":
			if local_player.shield or not Save.spend(100):
				return false
			local_player.shield = true
			local_player._update_shield_visual()
			hud.feed("Gekauft: Schild")
		_:
			return false
	AudioManager.play_pickup()
	return true


# ---------- Spawns ----------

func get_spawn_point(_for_node: Node3D) -> Vector3:
	if spawns.is_empty():
		return Vector3(0, 1, 8)
	# Freien Spawn suchen (Abstand zu Lebenden)
	var best: Vector3 = spawns[rng.randi() % spawns.size()]
	var best_score := -1.0
	for s in spawns:
		var min_d := 100.0
		for p in players:
			if is_instance_valid(p) and p.alive:
				min_d = minf(min_d, s.distance_to(p.global_position))
		for b in bots:
			if is_instance_valid(b) and b.alive:
				min_d = minf(min_d, s.distance_to(b.global_position))
		var score := min_d + rng.randf() * 3.0
		if score > best_score:
			best_score = score
			best = s
	return best


func _spawn_solo() -> void:
	var p := PlayerScene.instantiate() as OHPlayer
	p.name = "LocalPlayer"
	p.setup(0, GameConfig.player_name, false)
	add_child(p)
	p.global_position = Vector3(0, 1, 12)
	local_player = p
	players.append(p)
	_wire_player(p)


func _spawn_online_players() -> void:
	# Jeder Client spawnt alle bekannten Spieler lokal (Authority = Besitzer)
	var ids: Array = NetworkManager.players.keys()
	if ids.is_empty():
		ids = [multiplayer.get_unique_id()]
	ids.sort()
	var used: Dictionary = {}
	for i in ids.size():
		var pid := int(ids[i])
		var pname := str(NetworkManager.players.get(pid, "Spieler %d" % pid))
		if used.has(pname):
			pname = "%s#%d" % [pname, pid]
		used[pname] = true
		var p := PlayerScene.instantiate() as OHPlayer
		p.name = "Player_%d" % pid
		p.setup(pid, pname, true)
		add_child(p)
		p.global_position = spawns[i % spawns.size()]
		players.append(p)
		_wire_player(p)
		if pid == multiplayer.get_unique_id():
			local_player = p


func _wire_player(p: OHPlayer) -> void:
	if p.is_local():
		hud.bind_player(p)
		p.killed_enemy.connect(_on_local_kill)
		p.died.connect(_on_player_died)
		p.shield_used.connect(func() -> void: hud.show_message("🛡 Schild hat gehalten!", 1.2))
		hud.set_score(kills, deaths)
	else:
		p.died.connect(_on_player_died)


func _spawn_bot(wave_mult_hp: float = 1.0) -> void:
	var b := BotScene.instantiate() as OHBot
	add_child(b)
	b.global_position = get_spawn_point(b)
	var bot_names := ["Vex", "Rook", "Nova", "Jax", "Kilo", "Mira", "Onyx", "Pax"]
	b.setup_bot(bot_names[rng.randi() % bot_names.size()] + "-%d" % (bots.size() + 1),
		wave_mult_hp, 1.0 + (wave - 1) * 0.08,
		clampf(0.35 + float(wave) * 0.08 + rng.randf_range(0.0, 0.2), 0.0, 1.0))
	b.died.connect(_on_bot_died)
	bots.append(b)


# ---------- Spielregeln ----------

func _start_wave(w: int) -> void:
	wave = w
	if w > Save.best_wave:
		Save.best_wave = w
		Save.mark_dirty()
	# Welle skaliert sanft: Basis + 2 pro Welle
	var count := GameConfig.bot_count + (w - 1) * 2
	wave_alive_target = count
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	for i in count:
		_spawn_bot(1.0 + (w - 1) * 0.15)
	_set_wave_cached("Welle %d · Bots: %d%s" % [w, count, " · One-Hit AN" if GameConfig.one_hit else ""])
	hud.show_message("Welle %d" % w, 2.0)
	hud.feed("Welle %d gestartet (%d Bots)" % [w, count])


func _set_wave_cached(t: String) -> void:
	# Label nur bei Änderung anfassen (spart Layout-/String-Churn pro Frame)
	if t != _last_wave_text:
		_last_wave_text = t
		hud.set_wave(t)


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	if not online:
		# Wellen-Logik: alle Bots tot -> nächste Welle
		var alive := 0
		for b in bots:
			if is_instance_valid(b) and b.alive:
				alive += 1
		_set_wave_cached("Welle %d · Bots übrig: %d%s" % [wave, alive, " · One-Hit AN" if GameConfig.one_hit else ""])
		if alive == 0 and local_player != null:
			Save.add_credits(50)
			hud.feed("+50 ⚙ Wellen-Bonus · Shop: [B]")
			_start_wave(wave + 1)
			local_player.heal(25)


func _on_bot_died(bot: OHBot, killer_name: String) -> void:
	bots.erase(bot)
	if not online:
		kills += 1
		Save.record_kill()
		Save.add_credits(25)
		hud.set_score(kills, deaths)
		hud.feed("%s 💥 %s  (+25 ⚙)" % [killer_name, bot.display_name])
		if local_player:
			hud.show_message("+1 Kill", 0.6)
		_check_online_win()


func _on_local_kill(victim_name: String) -> void:
	# Online: eigener Kill (Meldung kommt via RPC notify_kill)
	if online:
		kills += 1
		Save.record_kill()
		Save.add_credits(25)
		hud.set_score(kills, deaths)
		hud.feed("%s 💥 %s  (+25 ⚙)" % [GameConfig.player_name, victim_name])
		_check_online_win()


func _on_player_died(victim_name: String, killer_name: String) -> void:
	hud.feed("%s 💥 %s" % [killer_name, victim_name])
	if local_player != null and victim_name == local_player.display_name:
		deaths += 1
		Save.record_death()
		hud.set_score(kills, deaths)
		hud.show_message("Getroffen! Respawn…", 2.0)


func on_kill_feed(killer: String, victim: String) -> void:
	hud.feed("%s 💥 %s" % [killer, victim])
	if local_player != null:
		if victim == local_player.display_name:
			deaths += 1
			Save.record_death()
			hud.set_score(kills, deaths)
			hud.show_message("Getroffen! Respawn…", 2.0)
		elif killer == local_player.display_name:
			pass # Zählung via notify_kill


@rpc("any_peer", "reliable", "call_local")
func net_feed(killer: String, victim: String) -> void:
	on_kill_feed(killer, victim)


func _check_online_win() -> void:
	if not online:
		return
	if kills >= KILLS_TO_WIN_ONLINE:
		hud.show_message("SIEG! 🎉", 5.0)
		hud.feed("Du hast das Match gewonnen!")
		GameConfig.set_captured(false)


func _on_server_lost() -> void:
	if not online:
		return
	GameConfig.set_captured(false)
	get_tree().paused = false
	hud.show_message("Server weg.", 2.5)
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	NetworkManager.reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_loot_opened(_box: OHLootBox, reward: String) -> void:
	if local_player:
		hud.feed("Loot: " + reward)
		hud.show_message(reward, 1.2)
