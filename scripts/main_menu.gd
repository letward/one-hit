extends Control
## Hauptmenü: Solo vs. Bots + Online-Lobby (self-hosted via ENet).
## Redesign: animierter Shader-Hintergrund, Ember-Partikel, gestaffelte
## Entrances, federnde Buttons, Modus-Cards, rotierende Tipps.

const ACCENT := Color(0.25, 0.85, 1.0)
const VIOLET := Color(0.55, 0.35, 1.0)
const TEXT_DIM := Color(0.65, 0.72, 0.85)

var _name_edit: LineEdit
var _sens_slider: HSlider
var _onehit_check: CheckBox
var _bots_slider: HSlider
var _bots_label: Label
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _status: Label
var _lobby_box: VBoxContainer
var _start_btn: Button
var _solo_btn: Button
var _online_btn: Button
var _title: Label
var _tip_label: Label
var _mode: String = "solo"
var _enter_rows: Array[Control] = []
var _btn_tw: Dictionary = {}
var _tip_idx: int = 0
var _tip_tw: Tween = null
var _embers: Array[CPUParticles2D] = []
var _credits_label: Label
var _stats_label: Label
var _skin_row: HBoxContainer
var _last_credits: int = -1

const TIPS: Array[String] = [
	"Tipp: Loot-Boxen geben neue Waffen, Heilung oder Munition.",
	"Tipp: Die Rail OneHit durchschlägt mehrere Gegner.",
	"Tipp: Rechte Maustaste = Zielen (weniger Streuung).",
	"Tipp: Im Online-Modus hostet einer, der Rest joint per IP.",
	"Tipp: Mit SHIFT sprintest du — gut zum Ausweichen.",
]


func _ready() -> void:
	GameConfig.set_captured(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_place_embers)
	_build()
	NetworkManager.lobby_changed.connect(_refresh_lobby)
	NetworkManager.connection_failed.connect(func() -> void: _set_status("Verbindung fehlgeschlagen. IP/Port prüfen."))
	NetworkManager.server_disconnected.connect(func() -> void: _set_status("Server weg. Wieder hosten/joinen."))
	_refresh_lobby()
	_refresh_mode_styles()
	_play_entrance()
	_start_title_pulse()
	_start_tips()


# ---------- Aufbau ----------

func _build() -> void:
	_build_background()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	_enter_rows.append(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	# Titel
	_title = Label.new()
	_title.text = "ONE-HIT"
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_shadow_color", Color(0.2, 0.85, 1.0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_track_pivot(_title)
	var sub := Label.new()
	sub.text = "Simpler Arena-Shooter · Solo gegen Bots oder Online gegen Freunde"
	sub.add_theme_color_override("font_color", TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	_credits_label = Label.new()
	_credits_label.add_theme_font_size_override("font_size", 18)
	_credits_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_credits_label)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", TEXT_DIM)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_stats_label)
	_update_economy_labels()
	vb.add_child(_header("MODUS"))
	# Modus-Cards
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(mode_row)
	_enter_rows.append(mode_row)
	_solo_btn = _make_button("🤖  SOLO vs. Bots", Vector2(250, 62), 18)
	_solo_btn.pressed.connect(func() -> void: _set_mode("solo"))
	mode_row.add_child(_solo_btn)
	_online_btn = _make_button("🌐  ONLINE Lobby", Vector2(250, 62), 18)
	_online_btn.pressed.connect(func() -> void: _set_mode("online"))
	mode_row.add_child(_online_btn)
	vb.add_child(_header("PILOT"))
	# Name + Sens
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	vb.add_child(name_row)
	_enter_rows.append(name_row)
	name_row.add_child(_dim_label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.text = GameConfig.player_name
	_name_edit.custom_minimum_size = Vector2(170, 0)
	_name_edit.text_changed.connect(func(t: String) -> void:
		GameConfig.player_name = t
		Save.mark_dirty())
	name_row.add_child(_name_edit)
	name_row.add_child(_dim_label("Sens:"))
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.001
	_sens_slider.max_value = 0.006
	_sens_slider.step = 0.0001
	_sens_slider.value = GameConfig.sensitivity
	_sens_slider.custom_minimum_size = Vector2(130, 0)
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_slider.value_changed.connect(func(v: float) -> void:
		GameConfig.sensitivity = v
		Save.mark_dirty())
	name_row.add_child(_sens_slider)
	# Optionen
	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 12)
	vb.add_child(opt_row)
	_enter_rows.append(opt_row)
	_onehit_check = CheckBox.new()
	_onehit_check.text = "One-Hit Kills"
	_onehit_check.button_pressed = GameConfig.one_hit
	_onehit_check.toggled.connect(func(v: bool) -> void:
		GameConfig.one_hit = v
		Save.mark_dirty())
	opt_row.add_child(_onehit_check)
	_bots_label = _dim_label("Bots: %d" % GameConfig.bot_count)
	opt_row.add_child(_bots_label)
	_bots_slider = HSlider.new()
	_bots_slider.min_value = 1
	_bots_slider.max_value = 10
	_bots_slider.step = 1
	_bots_slider.value = GameConfig.bot_count
	_bots_slider.custom_minimum_size = Vector2(110, 0)
	_bots_slider.value_changed.connect(func(v: float) -> void:
		GameConfig.bot_count = int(v)
		_bots_label.text = "Bots: %d" % int(v)
		Save.mark_dirty())
	opt_row.add_child(_bots_slider)
	var set_row := HBoxContainer.new()
	set_row.add_theme_constant_override("separation", 12)
	vb.add_child(set_row)
	_enter_rows.append(set_row)
	set_row.add_child(_dim_label("Volume:"))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = GameConfig.volume
	vol.custom_minimum_size = Vector2(100, 0)
	vol.value_changed.connect(func(v: float) -> void:
		GameConfig.volume = v
		AudioManager.set_master_volume(v)
		Save.mark_dirty())
	set_row.add_child(vol)
	set_row.add_child(_dim_label("FOV:"))
	var fov := HSlider.new()
	fov.min_value = 70.0
	fov.max_value = 90.0
	fov.step = 1.0
	fov.value = GameConfig.base_fov
	fov.custom_minimum_size = Vector2(80, 0)
	fov.value_changed.connect(func(v: float) -> void:
		GameConfig.base_fov = v
		Save.mark_dirty())
	set_row.add_child(fov)
	var shake := CheckBox.new()
	shake.text = "Shake"
	shake.button_pressed = GameConfig.shake_enabled
	shake.toggled.connect(func(v: bool) -> void:
		GameConfig.shake_enabled = v
		Save.mark_dirty())
	set_row.add_child(shake)
	vb.add_child(_header("SKIN"))
	_skin_row = HBoxContainer.new()
	_skin_row.add_theme_constant_override("separation", 8)
	_skin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_skin_row)
	_enter_rows.append(_skin_row)
	_refresh_skins()
	# Waffenkarte
	var w := Label.new()
	w.text = "[1] Blaster · [2] Scatter-6 · [3] Rail OneHit · [4] Wasp-9 SMG · [5] Falke DMR · [6] Mauer LMG"
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.add_theme_font_size_override("font_size", 13)
	w.add_theme_color_override("font_color", TEXT_DIM)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(w)
	var c := Label.new()
	c.text = "WASD + Maus · SHIFT Sprint · LEER Springen · E Loot · R Nachladen · B Shop · F3 FPS · ESC Pause"
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_theme_font_size_override("font_size", 13)
	c.add_theme_color_override("font_color", TEXT_DIM)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(c)
	vb.add_child(_header("NETZWERK · SELF-HOSTED"))
	# Online-Panel
	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 8)
	vb.add_child(net_row)
	_enter_rows.append(net_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP (z.B. 127.0.0.1)"
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(160, 0)
	net_row.add_child(_ip_edit)
	_port_edit = LineEdit.new()
	_port_edit.placeholder_text = "Port"
	_port_edit.text = "7777"
	_port_edit.custom_minimum_size = Vector2(70, 0)
	net_row.add_child(_port_edit)
	var b_host := _make_button("Hosten", Vector2(0, 0), 15)
	b_host.pressed.connect(_on_host)
	net_row.add_child(b_host)
	var b_join := _make_button("Joinen", Vector2(0, 0), 15)
	b_join.pressed.connect(_on_join)
	net_row.add_child(b_join)
	var b_leave := _make_button("Leave", Vector2(0, 0), 15)
	b_leave.pressed.connect(func() -> void: NetworkManager.reset(); _set_status("Lobby verlassen."))
	net_row.add_child(b_leave)
	_status = Label.new()
	_status.text = "Bereit."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", ACCENT)
	vb.add_child(_status)
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 2)
	vb.add_child(_lobby_box)
	_start_btn = _make_button("▶  SPIEL STARTEN", Vector2(0, 56), 20, true)
	_start_btn.pressed.connect(_on_start)
	vb.add_child(_start_btn)
	_enter_rows.append(_start_btn)
	# Footer: Tipps + Version
	_tip_label = Label.new()
	_tip_label.text = TIPS[0]
	_tip_label.add_theme_font_size_override("font_size", 13)
	_tip_label.add_theme_color_override("font_color", TEXT_DIM)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_tip_label)
	var ver := Label.new()
	ver.text = "v1.0 · Godot 4.7 · ENet Lobby bis 8 Spieler"
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ver)


func _process(_delta: float) -> void:
	if Save.credits != _last_credits:
		_update_economy_labels()


func _update_economy_labels() -> void:
	_credits_label.text = "⚙ %d Schrott" % Save.credits
	_stats_label.text = "🏆 %d Kills · 💀 %d Tode · 🌊 Best-Welle %d · 🎮 %d Runden" % [
		Save.total_kills, Save.total_deaths, Save.best_wave, Save.games_played]
	_last_credits = Save.credits


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(vec3(0.03, 0.05, 0.12), vec3(0.10, 0.05, 0.20), uv.y);
	float t = TIME * 0.35;
	vec2 p1 = vec2(0.5 + 0.35 * sin(t + uv.y * 2.0), 0.35 + 0.25 * cos(t * 0.7));
	float d1 = distance(uv * vec2(1.6, 1.0), p1 * vec2(1.6, 1.0));
	col += vec3(0.05, 0.35, 0.55) * smoothstep(0.55, 0.0, d1) * 0.5;
	vec2 p2 = vec2(0.5 + 0.4 * cos(t * 0.6 + 2.0), 0.7 + 0.2 * sin(t * 0.9));
	float d2 = distance(uv * vec2(1.6, 1.0), p2 * vec2(1.6, 1.0));
	col += vec3(0.35, 0.15, 0.6) * smoothstep(0.5, 0.0, d2) * 0.45;
	float vig = smoothstep(1.1, 0.35, distance(uv, vec2(0.5)));
	col *= mix(0.55, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_add_embers(Color(0.4, 0.9, 1.0, 0.5), 26)
	_add_embers(Color(0.7, 0.45, 1.0, 0.45), 20)


func _add_embers(color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(480, 20)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 34.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = color
	_embers.append(p)
	add_child(p)
	_place_embers()
	# Partikel liegen hinter dem Panel (bg=0), fangen keine Maus ab (Node2D)
	move_child(p, 1)


func _place_embers() -> void:
	var vp := get_viewport_rect().size
	for e in _embers:
		if is_instance_valid(e):
			e.position = Vector2(vp.x * 0.5, vp.y + 20.0)
			e.emission_rect_extents = Vector2(vp.x * 0.45, 20)


# ---------- Styling-Helfer ----------

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.09, 0.16, 0.93)
	s.set_corner_radius_all(18)
	s.border_color = Color(0.35, 0.8, 1.0, 0.22)
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 24
	return s


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", TEXT_DIM)
	return l


func _btn_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_button(text: String, min_size: Vector2, font_size: int, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	var base := Color(0.35, 0.7, 1.0) if primary else ACCENT
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.10, 0.14, 0.24), Color(base, 0.4), 1))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.14, 0.22, 0.36), Color(base, 0.95), 1))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.07, 0.10, 0.18), Color(base, 1.0), 2))
	b.add_theme_stylebox_override("focus", _btn_style(Color(0.10, 0.14, 0.24), Color(base, 0.4), 1))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	_track_pivot(b)
	b.mouse_entered.connect(func() -> void: _juice_to(b, Vector2(1.05, 1.05), 0.12))
	b.mouse_exited.connect(func() -> void: _juice_to(b, Vector2.ONE, 0.18))
	b.button_down.connect(func() -> void: _juice_to(b, Vector2(0.95, 0.95), 0.06))
	b.button_up.connect(func() -> void: _juice_to(b, Vector2(1.05, 1.05), 0.1))
	return b


func _track_pivot(c: Control) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	call_deferred("_fix_pivot", c)


func _fix_pivot(c: Control) -> void:
	if is_instance_valid(c):
		c.pivot_offset = c.size * 0.5


func _juice_to(b: Button, target: Vector2, dur: float) -> void:
	if _btn_tw.has(b):
		var old: Tween = _btn_tw[b]
		if old != null and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.tween_property(b, "scale", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_btn_tw[b] = tw


# ---------- Animationen ----------

func _play_entrance() -> void:
	for i in _enter_rows.size():
		var c: Control = _enter_rows[i]
		c.modulate.a = 0.0
		c.scale = Vector2(0.96, 0.96)
		_track_pivot(c)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.4).set_delay(0.05 + i * 0.06)
		tw.tween_property(c, "scale", Vector2.ONE, 0.45).set_delay(0.05 + i * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _start_title_pulse() -> void:
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_title, "scale", Vector2(1.03, 1.03), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE)


func _start_tips() -> void:
	var timer := Timer.new()
	timer.wait_time = 6.0
	timer.autostart = true
	timer.timeout.connect(_next_tip)
	add_child(timer)


func _next_tip() -> void:
	_tip_idx = (_tip_idx + 1) % TIPS.size()
	if _tip_tw != null and _tip_tw.is_valid():
		_tip_tw.kill()
	_tip_tw = create_tween()
	_tip_tw.tween_property(_tip_label, "modulate:a", 0.0, 0.4)
	_tip_tw.tween_callback(func() -> void: _tip_label.text = TIPS[_tip_idx])
	_tip_tw.tween_property(_tip_label, "modulate:a", 1.0, 0.4)


# ---------- Logik ----------

func _refresh_skins() -> void:
	for ch in _skin_row.get_children():
		ch.queue_free()
	for sid in SkinDefs.ORDER:
		var def: Dictionary = SkinDefs.get_def(sid)
		var owned := Save.owns_skin(sid)
		var selected := Save.skin_selected == sid
		var label := str(def["name"])
		if not owned:
			label += "\n⚙ %d" % int(def["price"])
		elif selected:
			label += "\n✓ aktiv"
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(92, 54)
		var body: Color = def["body"]
		var bg := Color(body.r * 0.35 + 0.04, body.g * 0.35 + 0.04, body.b * 0.35 + 0.06, 1.0)
		var accent: Color = def["accent"]
		b.add_theme_stylebox_override("normal", _btn_style(bg, Color(accent, 1.0 if selected else 0.35), 2 if selected else 1))
		b.add_theme_stylebox_override("hover", _btn_style(bg.lightened(0.15), Color(accent, 1.0), 2))
		b.add_theme_stylebox_override("pressed", _btn_style(bg.darkened(0.2), Color(accent, 1.0), 2))
		b.add_theme_stylebox_override("focus", _btn_style(bg, Color(accent, 0.35), 1))
		var id_copy := sid
		var price := int(def["price"])
		b.pressed.connect(func() -> void: _on_skin_pressed(id_copy, price))
		b.mouse_entered.connect(func() -> void: _juice_to(b, Vector2(1.06, 1.06), 0.12))
		b.mouse_exited.connect(func() -> void: _juice_to(b, Vector2.ONE, 0.18))
		_track_pivot(b)
		_skin_row.add_child(b)


func _on_skin_pressed(sid: String, price: int) -> void:
	if Save.owns_skin(sid):
		Save.select_skin(sid)
		_set_status("Skin aktiv: " + str(SkinDefs.get_def(sid)["name"]))
	elif Save.buy_skin(sid, price):
		Save.select_skin(sid)
		_set_status("Skin gekauft: " + str(SkinDefs.get_def(sid)["name"]))
	else:
		_set_status("Nicht genug Schrott (⚙ %d nötig)." % price)
		return
	_refresh_skins()
	_update_economy_labels()

func _set_mode(m: String) -> void:
	_mode = m
	_refresh_mode_styles()
	_refresh_lobby()
	var target := _solo_btn if m == "solo" else _online_btn
	_juice_to(target, Vector2(1.1, 1.1), 0.1)
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_callback(func() -> void: _juice_to(target, Vector2.ONE, 0.2))


func _refresh_mode_styles() -> void:
	for pair in [[_solo_btn, "solo"], [_online_btn, "online"]]:
		var b: Button = pair[0]
		var sel: bool = _mode == pair[1]
		var bw := 2 if sel else 1
		b.add_theme_stylebox_override("normal", _btn_style(
			Color(0.13, 0.2, 0.32) if sel else Color(0.10, 0.14, 0.24),
			Color(ACCENT, 1.0 if sel else 0.4), bw))


func _set_status(t: String) -> void:
	_status.text = t
	_status.modulate.a = 0.2
	var tw := create_tween()
	tw.tween_property(_status, "modulate:a", 1.0, 0.4)


func _port() -> int:
	var p := int(_port_edit.text) if _port_edit.text.is_valid_int() else 7777
	return clampi(p, 1024, 65535)


func _on_host() -> void:
	var err := NetworkManager.host_game(_port(), _name_edit.text)
	if err != "":
		_set_status(err)
	else:
		_mode = "online"
		_refresh_mode_styles()
		_set_status("Server läuft auf Port %d. Freunde joinen mit deiner IP + Port." % _port())
	_refresh_lobby()


func _on_join() -> void:
	var err := NetworkManager.join_game(_ip_edit.text, _port(), _name_edit.text)
	if err != "":
		_set_status(err)
	else:
		_mode = "online"
		_refresh_mode_styles()
		_set_status("Verbinde zu %s:%d …" % [_ip_edit.text, _port()])
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _lobby_box == null:
		return
	for ch in _lobby_box.get_children():
		ch.queue_free()
	var lobby: Array = NetworkManager.lobby_list()
	var rows: Array[Label] = []
	if _mode == "solo":
		var l := Label.new()
		l.text = "Modus: SOLO — du gegen %d Bots. Drücke SPIEL STARTEN." % GameConfig.bot_count
		_lobby_box.add_child(l)
		rows.append(l)
		_start_btn.text = "▶  SOLO STARTEN"
	else:
		var l := Label.new()
		if lobby.is_empty():
			l.text = "Modus: ONLINE — erst Hosten oder Joinen (self-hosted, bis 8 Spieler)."
		else:
			l.text = "Modus: ONLINE — Lobby (%d/%d):" % [lobby.size(), NetworkManager.MAX_PLAYERS]
		_lobby_box.add_child(l)
		rows.append(l)
		for entry in lobby:
			var pl := Label.new()
			var tag := " (Host)" if bool(entry.get("host", false)) else ""
			pl.text = "• %s%s" % [str(entry.get("name", "?")), tag]
			pl.add_theme_color_override("font_color", ACCENT if tag != "" else Color.WHITE)
			_lobby_box.add_child(pl)
			rows.append(pl)
		_start_btn.text = "▶  ONLINE-MATCH STARTEN (nur Host)"
	for i in rows.size():
		var r: Label = rows[i]
		r.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(r, "modulate:a", 1.0, 0.3).set_delay(i * 0.05)


func _on_start() -> void:
	GameConfig.player_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Spieler"
	if _mode == "solo":
		NetworkManager.reset()
		GameConfig.pending_mode = "solo"
		GameConfig.arena_seed = randi()
		get_tree().change_scene_to_file("res://scenes/arena.tscn")
	else:
		if not NetworkManager.is_online:
			_set_status("Erst Hosten oder Joinen, dann starten.")
			return
		if not NetworkManager.is_host:
			_set_status("Nur der Host kann starten. Warte auf den Host.")
			return
		NetworkManager.start_online_game()
