extends Control
## Zen-Menü: ruhig, modern, nur das Nötigste.
## Home (Modus) -> Setup (Start) · Settings separat · dezente Fades, kein Bounce.

const ACCENT := Color(0.45, 0.75, 0.95)
const TEXT_DIM := Color(0.60, 0.66, 0.75)
const TEXT_FAINT := Color(0.42, 0.47, 0.55)

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
var _eco_label: Label
var _skin_rows: VBoxContainer
var _fs_check: CheckBox
var _solo_box: VBoxContainer
var _net_box: VBoxContainer
var _setup_title: Label
var _screens: Dictionary = {}
var _active_screen: String = "home"
var _set_tabs: Dictionary = {}
var _set_pages: Dictionary = {}
var _active_set: String = "pilot"
var _mode: String = "solo"
var _btn_tw: Dictionary = {}
var _embers: Array[CPUParticles2D] = []
var _last_credits: int = -1


func _ready() -> void:
	GameConfig.set_captured(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_place_embers)
	_build()
	NetworkManager.lobby_changed.connect(_refresh_lobby)
	NetworkManager.connection_failed.connect(func() -> void: _set_status("Verbindung fehlgeschlagen. IP/Port prüfen."))
	NetworkManager.server_disconnected.connect(func() -> void: _set_status("Server weg. Wieder hosten/joinen."))
	_refresh_lobby()
	_refresh_mode_visibility()
	_show_screen("home", false)
	_play_entrance()


func _process(_delta: float) -> void:
	if Save.credits != _last_credits:
		_update_economy_labels()
	if _fs_check != null and _fs_check.button_pressed != GameConfig.is_fullscreen:
		_fs_check.set_pressed_no_signal(GameConfig.is_fullscreen)


func _update_economy_labels() -> void:
	_eco_label.text = "⚙ %d   ·   🏆 %d   ·   🌊 %d" % [
		Save.credits, Save.total_kills, Save.best_wave]
	_last_credits = Save.credits


# ---------- Aufbau ----------

func _build() -> void:
	_build_background()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)
	_title_block(vb)
	# Screens
	_screens["home"] = _make_screen(vb)
	_screens["setup"] = _make_screen(vb)
	_screens["settings"] = _make_screen(vb)
	_build_home(_screens["home"])
	_build_setup(_screens["setup"])
	_build_settings(_screens["settings"])
	var ver := Label.new()
	ver.text = "v1.0 · Godot 4.7"
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", TEXT_FAINT)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ver)


func _title_block(vb: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "ONE-HIT"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.55, 0.8, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_track_pivot(title)
	_eco_label = Label.new()
	_eco_label.add_theme_font_size_override("font_size", 13)
	_eco_label.add_theme_color_override("font_color", TEXT_DIM)
	_eco_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_eco_label)
	_update_economy_labels()


func _make_screen(parent: VBoxContainer) -> VBoxContainer:
	var s := VBoxContainer.new()
	s.add_theme_constant_override("separation", 12)
	s.visible = false
	parent.add_child(s)
	return s


func _build_home(s: VBoxContainer) -> void:
	var sub := _dim_label("Arena-Shooter · Solo gegen Bots oder online gegen Freunde")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(sub)
	var b_solo := _make_button("Solo spielen", Vector2(0, 58), 19, true)
	b_solo.pressed.connect(func() -> void: _goto_setup("solo"))
	s.add_child(b_solo)
	var b_online := _make_button("Online spielen", Vector2(0, 58), 19)
	b_online.pressed.connect(func() -> void: _goto_setup("online"))
	s.add_child(b_online)
	var b_set := _make_button("Einstellungen", Vector2(0, 40), 14)
	b_set.pressed.connect(func() -> void: _show_screen("settings"))
	s.add_child(b_set)


func _build_setup(s: VBoxContainer) -> void:
	_setup_title = Label.new()
	_setup_title.add_theme_font_size_override("font_size", 22)
	_setup_title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	_setup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(_setup_title)
	# Solo-Optionen
	_solo_box = VBoxContainer.new()
	_solo_box.add_theme_constant_override("separation", 8)
	s.add_child(_solo_box)
	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 14)
	opt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_solo_box.add_child(opt_row)
	_onehit_check = CheckBox.new()
	_onehit_check.text = "One-Hit Kills"
	_onehit_check.button_pressed = GameConfig.one_hit
	_onehit_check.toggled.connect(func(v: bool) -> void:
		GameConfig.one_hit = v
		Save.mark_dirty()
		_refresh_lobby())
	opt_row.add_child(_onehit_check)
	_bots_label = _dim_label("Bots: %d" % GameConfig.bot_count)
	opt_row.add_child(_bots_label)
	_bots_slider = HSlider.new()
	_bots_slider.min_value = 1
	_bots_slider.max_value = 10
	_bots_slider.step = 1
	_bots_slider.value = GameConfig.bot_count
	_bots_slider.custom_minimum_size = Vector2(130, 0)
	_bots_slider.value_changed.connect(func(v: float) -> void:
		GameConfig.bot_count = int(v)
		_bots_label.text = "Bots: %d" % int(v)
		Save.mark_dirty()
		_refresh_lobby())
	opt_row.add_child(_bots_slider)
	var real := CheckBox.new()
	real.text = "Realistisch-Modus"
	real.button_pressed = GameConfig.realistic
	real.toggled.connect(func(v: bool) -> void:
		GameConfig.realistic = v
		Save.mark_dirty()
		_refresh_lobby())
	_solo_box.add_child(real)
	# Netzwerk
	_net_box = VBoxContainer.new()
	_net_box.add_theme_constant_override("separation", 8)
	s.add_child(_net_box)
	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 8)
	_net_box.add_child(net_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP"
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(150, 0)
	net_row.add_child(_ip_edit)
	_port_edit = LineEdit.new()
	_port_edit.placeholder_text = "Port"
	_port_edit.text = "7777"
	_port_edit.custom_minimum_size = Vector2(64, 0)
	net_row.add_child(_port_edit)
	var b_host := _make_button("Hosten", Vector2(0, 0), 14)
	b_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_host.pressed.connect(_on_host)
	net_row.add_child(b_host)
	var b_join := _make_button("Joinen", Vector2(0, 0), 14)
	b_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_join.pressed.connect(_on_join)
	net_row.add_child(b_join)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_box.add_child(_status)
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 2)
	s.add_child(_lobby_box)
	_start_btn = _make_button("Starten", Vector2(0, 56), 20, true)
	_start_btn.pressed.connect(_on_start)
	s.add_child(_start_btn)
	var hint := _dim_label("WASD + Maus · E Loot · R Nachladen · B Shop · ESC Pause")
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(hint)
	var back := _make_button("‹ Zurück", Vector2(0, 36), 13)
	back.pressed.connect(func() -> void:
		NetworkManager.reset()
		_show_screen("home"))
	s.add_child(back)


func _build_settings(s: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	s.add_child(tabs)
	_set_pages["pilot"] = _make_screen(s)
	_set_pages["gfx"] = _make_screen(s)
	_set_pages["skins"] = _make_screen(s)
	for t in [["pilot", "Pilot"], ["gfx", "Grafik"], ["skins", "Skins"]]:
		var key := str(t[0])
		var b := _make_button(str(t[1]), Vector2(130, 36), 14)
		b.pressed.connect(_show_set.bind(key))
		tabs.add_child(b)
		_set_tabs[key] = b
	_build_set_pilot(_set_pages["pilot"])
	_build_set_gfx(_set_pages["gfx"])
	_build_set_skins(_set_pages["skins"])
	_show_set("pilot", false)
	var back := _make_button("‹ Zurück", Vector2(0, 36), 13)
	back.pressed.connect(func() -> void: _show_screen("home"))
	s.add_child(back)


func _build_set_pilot(p: VBoxContainer) -> void:
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	p.add_child(name_row)
	name_row.add_child(_dim_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.text = GameConfig.player_name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String) -> void:
		GameConfig.player_name = t
		Save.mark_dirty())
	name_row.add_child(_name_edit)
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 10)
	p.add_child(sens_row)
	sens_row.add_child(_dim_label("Maus"))
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.001
	_sens_slider.max_value = 0.006
	_sens_slider.step = 0.0001
	_sens_slider.value = GameConfig.sensitivity
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_slider.value_changed.connect(func(v: float) -> void:
		GameConfig.sensitivity = v
		Save.mark_dirty())
	sens_row.add_child(_sens_slider)
	var av_row := HBoxContainer.new()
	av_row.add_theme_constant_override("separation", 14)
	p.add_child(av_row)
	av_row.add_child(_dim_label("Volume"))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = GameConfig.volume
	vol.custom_minimum_size = Vector2(110, 0)
	vol.value_changed.connect(func(v: float) -> void:
		GameConfig.volume = v
		AudioManager.set_master_volume(v)
		Save.mark_dirty())
	av_row.add_child(vol)
	av_row.add_child(_dim_label("FOV"))
	var fov := HSlider.new()
	fov.min_value = 70.0
	fov.max_value = 90.0
	fov.step = 1.0
	fov.value = GameConfig.base_fov
	fov.custom_minimum_size = Vector2(80, 0)
	fov.value_changed.connect(func(v: float) -> void:
		GameConfig.base_fov = v
		Save.mark_dirty())
	av_row.add_child(fov)
	var shake := CheckBox.new()
	shake.text = "Shake"
	shake.button_pressed = GameConfig.shake_enabled
	shake.toggled.connect(func(v: bool) -> void:
		GameConfig.shake_enabled = v
		Save.mark_dirty())
	av_row.add_child(shake)


func _build_set_gfx(p: VBoxContainer) -> void:
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 12)
	r1.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(r1)
	r1.add_child(_dim_label("Auflösung"))
	var res := OptionButton.new()
	for i in GameConfig.RES_NAMES.size():
		res.add_item(GameConfig.RES_NAMES[i], i)
	res.selected = clampi(GameConfig.res_idx, 0, 3)
	res.item_selected.connect(func(idx: int) -> void:
		GameConfig.res_idx = idx
		GameConfig.apply_display()
		Save.mark_dirty())
	r1.add_child(res)
	_fs_check = CheckBox.new()
	_fs_check.text = "Vollbild [F11]"
	_fs_check.button_pressed = GameConfig.is_fullscreen
	_fs_check.toggled.connect(func(v: bool) -> void:
		GameConfig.is_fullscreen = v
		GameConfig.apply_display()
		Save.mark_dirty())
	r1.add_child(_fs_check)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 12)
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(r2)
	r2.add_child(_dim_label("MSAA"))
	var msaa := OptionButton.new()
	msaa.add_item("Aus", 0)
	msaa.add_item("2x", 1)
	msaa.add_item("4x", 2)
	msaa.add_item("8x", 3)
	msaa.selected = clampi(GameConfig.msaa, 0, 3)
	msaa.item_selected.connect(func(idx: int) -> void:
		GameConfig.msaa = idx
		Save.mark_dirty())
	r2.add_child(msaa)
	_add_gfx_check(r2, "glow", "Glow")
	_add_gfx_check(r2, "shadows", "Schatten")
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 12)
	r3.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(r3)
	_add_gfx_check(r3, "dust", "Staub")
	_add_gfx_check(r3, "vsync", "VSync", true)
	_add_gfx_check(r3, "ultra", "Ultra-FX")
	var hint := _dim_label("Grafik gilt ab Rundenstart · F3 zeigt FPS")
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(hint)


func _add_gfx_check(row: HBoxContainer, key: String, text: String, applies_display: bool = false) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(GameConfig.get(key))
	cb.toggled.connect(func(v: bool) -> void:
		GameConfig.set(key, v)
		if applies_display:
			GameConfig.apply_display()
		Save.mark_dirty())
	row.add_child(cb)


func _build_set_skins(p: VBoxContainer) -> void:
	_skin_rows = VBoxContainer.new()
	_skin_rows.add_theme_constant_override("separation", 8)
	p.add_child(_skin_rows)
	_refresh_skins()


func _show_set(name: String, animate: bool = true) -> void:
	_active_set = name
	for k in _set_pages.keys():
		(_set_pages[k] as Control).visible = (k == name)
	for k in _set_tabs.keys():
		var b: Button = _set_tabs[k]
		var sel: bool = _active_set == k
		b.add_theme_stylebox_override("normal", _btn_style(
			Color(0.12, 0.17, 0.26) if sel else Color(0.09, 0.12, 0.20),
			Color(ACCENT, 0.9 if sel else 0.3), 1))
	if animate:
		_fade_children(_set_pages[name])


func _goto_setup(m: String) -> void:
	_mode = m
	_setup_title.text = "Solo" if m == "solo" else "Online"
	_refresh_mode_visibility()
	_refresh_lobby()
	_show_screen("setup")


func _show_screen(name: String, animate: bool = true) -> void:
	_active_screen = name
	for k in _screens.keys():
		(_screens[k] as Control).visible = (k == name)
	if animate:
		_fade_children(_screens[name])


func _fade_children(page: VBoxContainer) -> void:
	var i := 0
	for ch in page.get_children():
		if ch is Control:
			(ch as Control).modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(ch, "modulate:a", 1.0, 0.3).set_delay(i * 0.04).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			i += 1


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(vec3(0.025, 0.04, 0.10), vec3(0.07, 0.05, 0.15), uv.y);
	float t = TIME * 0.18;
	vec2 p1 = vec2(0.5 + 0.35 * sin(t + uv.y * 2.0), 0.35 + 0.25 * cos(t * 0.7));
	float d1 = distance(uv * vec2(1.6, 1.0), p1 * vec2(1.6, 1.0));
	col += vec3(0.05, 0.30, 0.48) * smoothstep(0.55, 0.0, d1) * 0.32;
	vec2 p2 = vec2(0.5 + 0.4 * cos(t * 0.6 + 2.0), 0.7 + 0.2 * sin(t * 0.9));
	float d2 = distance(uv * vec2(1.6, 1.0), p2 * vec2(1.6, 1.0));
	col += vec3(0.30, 0.14, 0.52) * smoothstep(0.5, 0.0, d2) * 0.28;
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
	_add_embers(Color(0.4, 0.85, 1.0, 0.30), 18)


func _add_embers(color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(480, 20)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	_embers.append(p)
	add_child(p)
	_place_embers()
	move_child(p, 1)


func _place_embers() -> void:
	var vp := get_viewport_rect().size
	for e in _embers:
		if is_instance_valid(e):
			e.position = Vector2(vp.x * 0.5, vp.y + 20.0)
			e.emission_rect_extents = Vector2(vp.x * 0.45, 20)


# ---------- Styling ----------

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.08, 0.14, 0.94)
	s.set_corner_radius_all(20)
	s.border_color = Color(0.5, 0.65, 0.8, 0.14)
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 28
	return s


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(12)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _make_button(text: String, min_size: Vector2, font_size: int, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	var base := Color(0.55, 0.75, 0.95) if primary else ACCENT
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.10, 0.13, 0.21), Color(base, 0.35), 1))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.13, 0.18, 0.29), Color(base, 0.8), 1))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.07, 0.10, 0.17), Color(base, 0.9), 1))
	b.add_theme_stylebox_override("focus", _btn_style(Color(0.10, 0.13, 0.21), Color(base, 0.35), 1))
	b.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	_track_pivot(b)
	b.mouse_entered.connect(func() -> void: _juice_to(b, Vector2(1.03, 1.03), 0.15))
	b.mouse_exited.connect(func() -> void: _juice_to(b, Vector2.ONE, 0.2))
	b.button_down.connect(func() -> void: _juice_to(b, Vector2(0.97, 0.97), 0.08))
	b.button_up.connect(func() -> void: _juice_to(b, Vector2(1.03, 1.03), 0.12))
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


# ---------- Animation ----------

func _play_entrance() -> void:
	var panel := get_node_or_null("MenuPanel")
	if panel == null:
		for ch in get_children():
			if ch is PanelContainer:
				panel = ch
	if panel != null:
		(panel as Control).modulate.a = 0.0
		(panel as Control).scale = Vector2(0.98, 0.98)
		_track_pivot(panel)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------- Logik ----------

func _refresh_skins() -> void:
	for ch in _skin_rows.get_children():
		ch.queue_free()
	var chunks := [SkinDefs.ORDER.slice(0, 4), SkinDefs.ORDER.slice(4)]
	for chunk in chunks:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_skin_rows.add_child(row)
		for sid in chunk:
			_add_skin_button(row, str(sid))


func _add_skin_button(row: HBoxContainer, sid: String) -> void:
		var def: Dictionary = SkinDefs.get_def(sid)
		var owned := Save.owns_skin(sid)
		var selected := Save.skin_selected == sid
		var label := str(def["name"])
		if not owned:
			label += "\n⚙ %d" % int(def["price"])
		elif selected:
			label += "\n✓"
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(104, 50)
		var body: Color = def["body"]
		var bg := Color(body.r * 0.35 + 0.04, body.g * 0.35 + 0.04, body.b * 0.35 + 0.06, 1.0)
		var accent: Color = def["accent"]
		b.add_theme_stylebox_override("normal", _btn_style(bg, Color(accent, 0.9 if selected else 0.3), 1))
		b.add_theme_stylebox_override("hover", _btn_style(bg.lightened(0.12), Color(accent, 0.8), 1))
		b.add_theme_stylebox_override("pressed", _btn_style(bg.darkened(0.15), Color(accent, 0.8), 1))
		b.add_theme_stylebox_override("focus", _btn_style(bg, Color(accent, 0.3), 1))
		var id_copy := sid
		var price := int(def["price"])
		b.pressed.connect(func() -> void: _on_skin_pressed(id_copy, price))
		b.mouse_entered.connect(func() -> void: _juice_to(b, Vector2(1.04, 1.04), 0.15))
		b.mouse_exited.connect(func() -> void: _juice_to(b, Vector2.ONE, 0.2))
		_track_pivot(b)
		row.add_child(b)


func _on_skin_pressed(sid: String, price: int) -> void:
	if Save.owns_skin(sid):
		Save.select_skin(sid)
	elif not Save.buy_skin(sid, price):
		return
	Save.select_skin(sid)
	_refresh_skins()
	_update_economy_labels()


func _refresh_mode_visibility() -> void:
	if _solo_box != null:
		_solo_box.visible = (_mode == "solo")
	if _net_box != null:
		_net_box.visible = (_mode == "online")


func _set_status(t: String) -> void:
	if _status == null:
		return
	_status.text = t
	_status.modulate.a = 0.2
	var tw := create_tween()
	tw.tween_property(_status, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _port() -> int:
	var p := int(_port_edit.text) if _port_edit.text.is_valid_int() else 7777
	return clampi(p, 1024, 65535)


func _on_host() -> void:
	var err := NetworkManager.host_game(_port(), _name_edit.text)
	if err != "":
		_set_status(err)
	else:
		_set_status("Server auf Port %d · Freunde joinen mit deiner IP." % _port())
	_refresh_lobby()


func _on_join() -> void:
	var err := NetworkManager.join_game(_ip_edit.text, _port(), _name_edit.text)
	if err != "":
		_set_status(err)
	else:
		_set_status("Verbinde zu %s:%d …" % [_ip_edit.text, _port()])
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _lobby_box == null:
		return
	for ch in _lobby_box.get_children():
		ch.queue_free()
	var lobby: Array = NetworkManager.lobby_list()
	if _mode == "solo":
		var tags := "One-Hit" if GameConfig.one_hit else "Normal"
		if GameConfig.realistic:
			tags += " · Realistisch"
		var l := Label.new()
		l.text = "%d Bots · %s" % [GameConfig.bot_count, tags]
		l.add_theme_color_override("font_color", TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lobby_box.add_child(l)
		_start_btn.text = "Starten"
	else:
		if not lobby.is_empty():
			var l := Label.new()
			l.text = "Lobby (%d/%d)" % [lobby.size(), NetworkManager.MAX_PLAYERS]
			l.add_theme_color_override("font_color", TEXT_DIM)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_lobby_box.add_child(l)
			for entry in lobby:
				var pl := Label.new()
				var tag := " · Host" if bool(entry.get("host", false)) else ""
				pl.text = "%s%s" % [str(entry.get("name", "?")), tag]
				pl.add_theme_color_override("font_color", ACCENT if tag != "" else Color(0.88, 0.90, 0.94))
				pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_lobby_box.add_child(pl)
		_start_btn.text = "Match starten (Host)"
	_fade_children(_lobby_box)


func _on_start() -> void:
	GameConfig.player_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Spieler"
	if _mode == "solo":
		NetworkManager.reset()
		GameConfig.pending_mode = "solo"
		GameConfig.arena_seed = randi()
		get_tree().change_scene_to_file("res://scenes/arena.tscn")
	else:
		if not NetworkManager.is_online:
			_set_status("Erst Hosten oder Joinen.")
			return
		if not NetworkManager.is_host:
			_set_status("Nur der Host kann starten.")
			return
		NetworkManager.start_online_game()
