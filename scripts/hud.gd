class_name OHHud
extends CanvasLayer
## Simples, lesbares HUD: Crosshair, Hitmarker, HP, Munition, Slots, Feed, Messages.

var _cross: Label
var _dot: Label
var _hit: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _ammo: Label
var _weapon: Label
var _slots: Label
var _score: Label
var _wave: Label
var _feed: VBoxContainer
var _prompt: Label
var _msg: Label
var _vignette: ColorRect
var _hit_t: float = 0.0
var _msg_t: float = 0.0
var _last_hp: int = 100
var _player: OHPlayer
var _hp_fill: StyleBoxFlat
var _msg_tween: Tween = null
var _last_mag: int = -1
var _cross_base: int = 34
var _ch_alive: bool = true
var _ch_ads: bool = false
var _fps_label: Label
var _show_fps: bool = false


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_build()
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fps"):
		_show_fps = not _show_fps
		_fps_label.visible = _show_fps


func _build() -> void:
	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 34)
	_cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_cross.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_cross.add_theme_constant_override("shadow_offset_x", 2)
	_cross.add_theme_constant_override("shadow_offset_y", 2)
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.position = Vector2(-12, -24)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)
	_dot = Label.new()
	_dot.text = "•"
	_dot.add_theme_font_size_override("font_size", 12)
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.position = Vector2(-4, -8)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dot)
	_hit = Label.new()
	_hit.text = "✕"
	_hit.add_theme_font_size_override("font_size", 30)
	_hit.add_theme_color_override("font_color", Color(1, 0.3, 0.2, 0.0))
	_hit.set_anchors_preset(Control.PRESET_CENTER)
	_hit.position = Vector2(-11, -22)
	_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit)
	# HP unten links
	_hp_bar = ProgressBar.new()
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.custom_minimum_size = Vector2(240, 22)
	_hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_bar.position = Vector2(20, -56)
	_hp_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.05, 0.07, 0.12, 0.85)
	hp_bg.set_corner_radius_all(6)
	hp_bg.border_color = Color(1, 1, 1, 0.18)
	hp_bg.set_border_width_all(1)
	_hp_bar.add_theme_stylebox_override("background", hp_bg)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.3, 0.9, 0.45)
	_hp_fill.set_corner_radius_all(6)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	add_child(_hp_bar)
	_hp_text = Label.new()
	_hp_text.text = "100 HP"
	_hp_text.add_theme_font_size_override("font_size", 18)
	_hp_text.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_text.position = Vector2(20, -84)
	add_child(_hp_text)
	# Munition unten rechts
	_ammo = Label.new()
	_ammo.text = "12 / 12"
	_ammo.add_theme_font_size_override("font_size", 32)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-180, -70)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ammo)
	_weapon = Label.new()
	_weapon.text = "P-9 Blaster"
	_weapon.add_theme_font_size_override("font_size", 16)
	_weapon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon.position = Vector2(-260, -100)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_weapon)
	_slots = Label.new()
	_slots.text = ""
	_slots.add_theme_font_size_override("font_size", 14)
	_slots.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_slots.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_slots.position = Vector2(-320, -124)
	_slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_slots)
	# Score oben
	_score = Label.new()
	_score.text = "Kills: 0"
	_score.add_theme_font_size_override("font_size", 22)
	_score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score.position = Vector2(-60, 12)
	add_child(_score)
	_wave = Label.new()
	_wave.text = ""
	_wave.add_theme_font_size_override("font_size", 16)
	_wave.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_wave.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave.position = Vector2(-60, 42)
	add_child(_wave)
	# Feed rechts oben
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-320, 12)
	_feed.custom_minimum_size = Vector2(300, 100)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_feed)
	# Interact-Prompt
	_prompt = Label.new()
	_prompt.text = ""
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-120, -160)
	add_child(_prompt)
	# Center-Message
	_msg = Label.new()
	_msg.text = ""
	_msg.add_theme_font_size_override("font_size", 40)
	_msg.set_anchors_preset(Control.PRESET_CENTER)
	_msg.position = Vector2(-200, -80)
	_msg.custom_minimum_size = Vector2(400, 60)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.pivot_offset = Vector2(200, 30)
	add_child(_msg)
	# Damage-Vignette
	_vignette = ColorRect.new()
	_vignette.color = Color(1, 0, 0, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	# FPS-Anzeige (F3)
	_fps_label = Label.new()
	_fps_label.text = "60 FPS"
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fps_label.position = Vector2(12, 8)
	_fps_label.visible = false
	add_child(_fps_label)


func _process(delta: float) -> void:
	if _show_fps:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _hit_t > 0.0:
		_hit_t -= delta
		var a := clampf(_hit_t / 0.3, 0.0, 1.0)
		_hit.add_theme_color_override("font_color", Color(1, 0.3, 0.2, a))
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_msg.text = ""
	var v: Color = _vignette.color
	if v.a > 0.0:
		v.a = maxf(0.0, v.a - delta * 1.8)
		_vignette.color = v


func bind_player(p: OHPlayer) -> void:
	_player = p
	_last_hp = p.hp
	p.health_changed.connect(_on_hp)
	p.ammo_changed.connect(_on_ammo)
	p.hit_confirmed.connect(_on_hit)
	p.interact_hint.connect(_on_prompt)
	p.weapon_changed.connect(_on_weapon_changed)
	p.died.connect(func(_v: String, _k: String) -> void: _set_crosshair_visible(false))
	p.respawned.connect(func() -> void: _set_crosshair_visible(true))
	_cross.add_theme_color_override("font_color", p.skin_accent)
	_on_hp(p.hp, p.max_hp)
	_on_ammo(int(p.mag_left.get(p.current, 0)), int(WeaponDefs.get_def(p.current)["mag"]), p.current, str(WeaponDefs.get_def(p.current)["name"]))
	_refresh_slots()


func _set_crosshair_visible(v: bool) -> void:
	_ch_alive = v
	_apply_ch()


func set_crosshair_ads(hidden: bool) -> void:
	_ch_ads = hidden
	_apply_ch()


func _apply_ch() -> void:
	var v := _ch_alive and not _ch_ads
	_cross.visible = v
	_dot.visible = v


func _on_hp(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_text.text = "%d HP" % hp
	var frac := float(hp) / float(maxi(max_hp, 1))
	_hp_fill.bg_color = Color(0.95, 0.25, 0.25).lerp(Color(0.3, 0.9, 0.45), clampf(frac, 0.0, 1.0))
	if hp < _last_hp:
		var v: Color = _vignette.color
		v.a = 0.45
		_vignette.color = v
	_last_hp = hp


func _on_ammo(mag: int, mag_size: int, weapon_id: String, weapon_name: String) -> void:
	_ammo.text = "%d / %d" % [mag, mag_size]
	_ammo.add_theme_color_override("font_color",
		Color(1.0, 0.35, 0.3) if mag * 4 <= mag_size else Color.WHITE)
	_weapon.text = weapon_name
	var spread := float(WeaponDefs.get_def(weapon_id)["spread_deg"])
	_cross_base = int(28 + spread * 2.0)
	_cross.add_theme_font_size_override("font_size", _cross_base)
	if _last_mag >= 0 and mag < _last_mag:
		_punch_cross()
	_last_mag = mag
	_refresh_slots()


func _punch_cross() -> void:
	var tw := create_tween()
	tw.tween_method(_set_cross_size, float(_cross_base) + 12.0, float(_cross_base), 0.15)


func _set_cross_size(s: float) -> void:
	_cross.add_theme_font_size_override("font_size", int(s))


func _on_weapon_changed(_wid: String) -> void:
	_refresh_slots()


func _refresh_slots() -> void:
	if _player == null:
		return
	var parts: PackedStringArray = []
	for i in WeaponDefs.ORDER.size():
		var wid: String = WeaponDefs.ORDER[i]
		var tag := "[%d] %s" % [i + 1, str(WeaponDefs.get_def(wid)["name"])]
		if not _player.owned.has(wid):
			tag = "[?] ???"
		elif wid == _player.current:
			tag = "> " + tag + " <"
		parts.append(tag)
	_slots.text = "   ".join(parts)


func _on_hit(kill: bool) -> void:
	_hit_t = 0.3 if not kill else 0.6
	_hit.add_theme_font_size_override("font_size", 44 if kill else 30)
	AudioManager.play_hit()


func _on_prompt(text: String) -> void:
	_prompt.text = text


func set_score(kills: int, deaths: int) -> void:
	_score.text = "Kills: %d   Tode: %d" % [kills, deaths]


func set_wave(text: String) -> void:
	_wave.text = text


func feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_feed.add_child(l)
	l.modulate.a = 0.0
	var fin := l.create_tween()
	fin.tween_property(l, "modulate:a", 1.0, 0.25)
	while _feed.get_child_count() > 5:
		# queue_free ist deferred -> erst remove_child, sonst Endlosschleife + Freeze!
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func show_message(text: String, dur: float = 2.0) -> void:
	_msg.text = text
	_msg_t = dur
	if _msg_tween != null and _msg_tween.is_valid():
		_msg_tween.kill()
	_msg.scale = Vector2(0.85, 0.85)
	_msg_tween = create_tween()
	_msg_tween.tween_property(_msg, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
