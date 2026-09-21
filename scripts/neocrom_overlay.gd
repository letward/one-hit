class_name OHNeocromOverlay
extends CanvasLayer
## Neocrom-Overlay [F4]: Account + Profilbild, CromID-Login ingame,
## Friends einladen, Self-Hosted + offizielle Server. Läuft in Menü UND Spiel.

var is_open := false

var _nc = null
var _panel: PanelContainer
var _avatar: TextureRect
var _name_l: Label
var _sub_l: Label
var _dot: Label
var _account_box: VBoxContainer
var _login_box: VBoxContainer
var _login_id: LineEdit
var _login_status: Label
var _friends_rows: VBoxContainer
var _friends_status: Label
var _inv_rows: VBoxContainer
var _srv_rows: VBoxContainer
var _srv_status: Label
var _status: Label
var _toast_l: Label
var _toast_tw: Tween = null
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _last_credits: int = -1
var _last_online: bool = false


func setup(nc) -> void:
	_nc = nc
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	_nc.session_changed.connect(_on_session)
	_nc.avatar_ready.connect(_refresh_account)
	_nc.friends_updated.connect(_refresh_friends)
	_nc.invites_updated.connect(_refresh_invites)
	_nc.invite_received.connect(_on_invite_received)
	_nc.servers_updated.connect(_refresh_servers)
	_nc.invite_sent.connect(func(ok: bool, msg: String) -> void: _set_status(msg))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("overlay"):
		if is_open:
			close_overlay()
		else:
			open_overlay()


func open_overlay() -> void:
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_all()


func close_overlay() -> void:
	is_open = false
	visible = false
	_restore_mouse()


func _restore_mouse() -> void:
	var in_game := get_tree().current_scene != null and get_tree().current_scene.has_method("get_spawn_point")
	var frozen := get_tree().paused
	var shop := false
	if in_game:
		var games := get_tree().get_nodes_in_group("game")
		if not games.is_empty():
			shop = bool(games[0].get("shop_open"))
	if in_game and not frozen and not shop:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _in_game() -> bool:
	return get_tree().current_scene != null and get_tree().current_scene.has_method("get_spawn_point")


func _process(_delta: float) -> void:
	if not is_open:
		return
	if Save.credits != _last_credits or _nc.online != _last_online:
		_last_credits = Save.credits
		_last_online = _nc.online
		_refresh_account()


# ---------- Aufbau ----------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.13, 0.97)
	sb.set_corner_radius_all(16)
	sb.border_color = Color(0.5, 0.65, 0.8, 0.2)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 22
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	# Kopf
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := Label.new()
	t.text = "Neocrom"
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_dot = Label.new()
	_dot.text = "●"
	_dot.add_theme_font_size_override("font_size", 16)
	head.add_child(_dot)
	var b_close := Button.new()
	b_close.text = "✕  [F4]"
	b_close.pressed.connect(close_overlay)
	head.add_child(b_close)
	# Account
	_account_box = VBoxContainer.new()
	_account_box.add_theme_constant_override("separation", 6)
	vb.add_child(_account_box)
	var acc_row := HBoxContainer.new()
	acc_row.add_theme_constant_override("separation", 12)
	_account_box.add_child(acc_row)
	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(56, 56)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	acc_row.add_child(_avatar)
	var acc_info := VBoxContainer.new()
	acc_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc_row.add_child(acc_info)
	_name_l = Label.new()
	_name_l.add_theme_font_size_override("font_size", 17)
	acc_info.add_child(_name_l)
	_sub_l = Label.new()
	_sub_l.add_theme_font_size_override("font_size", 12)
	_sub_l.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	acc_info.add_child(_sub_l)
	var b_out := Button.new()
	b_out.text = "Logout"
	b_out.pressed.connect(func() -> void: _nc.logout())
	acc_row.add_child(b_out)
	# Login (wenn ausgeloggt)
	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 8)
	vb.add_child(_login_box)
	_login_id = LineEdit.new()
	_login_id.placeholder_text = "CromID"
	_login_box.add_child(_login_id)
	var b_in := Button.new()
	b_in.text = "Anmelden"
	b_in.pressed.connect(_on_login)
	_login_box.add_child(b_in)
	_login_status = Label.new()
	_login_status.add_theme_font_size_override("font_size", 12)
	_login_status.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	_login_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_login_box.add_child(_login_status)
	var b_off := Button.new()
	b_off.text = "Offline spielen"
	b_off.pressed.connect(func() -> void: _nc.login_offline(_login_id.text))
	_login_box.add_child(b_off)
	# Freunde
	vb.add_child(_section("Freunde einladen"))
	_friends_status = Label.new()
	_friends_status.add_theme_font_size_override("font_size", 12)
	_friends_status.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	vb.add_child(_friends_status)
	_friends_rows = VBoxContainer.new()
	_friends_rows.add_theme_constant_override("separation", 4)
	vb.add_child(_friends_rows)
	# Einladungen
	_inv_rows = VBoxContainer.new()
	_inv_rows.add_theme_constant_override("separation", 4)
	vb.add_child(_inv_rows)
	# Self-hosted
	vb.add_child(_section("Self-hosted"))
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	vb.add_child(host_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP"
	_ip_edit.custom_minimum_size = Vector2(150, 0)
	host_row.add_child(_ip_edit)
	_port_edit = LineEdit.new()
	_port_edit.placeholder_text = "Port"
	_port_edit.custom_minimum_size = Vector2(64, 0)
	host_row.add_child(_port_edit)
	var b_host := Button.new()
	b_host.text = "Hosten"
	b_host.pressed.connect(_on_host)
	host_row.add_child(b_host)
	var b_join := Button.new()
	b_join.text = "Joinen"
	b_join.pressed.connect(_on_join)
	host_row.add_child(b_join)
	# Offizielle Server
	vb.add_child(_section("Offizielle Neocrom-Server"))
	_srv_status = Label.new()
	_srv_status.add_theme_font_size_override("font_size", 12)
	_srv_status.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	vb.add_child(_srv_status)
	_srv_rows = VBoxContainer.new()
	_srv_rows.add_theme_constant_override("separation", 4)
	vb.add_child(_srv_rows)
	var b_srv := Button.new()
	b_srv.text = "Serverliste aktualisieren"
	b_srv.pressed.connect(func() -> void: _nc.fetch_servers())
	vb.add_child(b_srv)
	# Status + Toast
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.45, 0.75, 0.95))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)
	_toast_l = Label.new()
	_toast_l.add_theme_font_size_override("font_size", 14)
	_toast_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_l.modulate.a = 0.0
	vb.add_child(_toast_l)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.5, 0.56, 0.65))
	return l


# ---------- Refresh ----------

func refresh_all() -> void:
	_login_id.text = Save.crom_id
	_ip_edit.text = Save.host_ip if Save.host_ip != "" else Neocrom.lan_ip()
	_port_edit.text = str(Save.host_port)
	_refresh_account()
	_refresh_friends()
	_refresh_invites()
	_refresh_servers()
	if _nc.active:
		_nc.fetch_friends()
		_nc.fetch_servers()
		_nc.fetch_invites(true)


func _refresh_account() -> void:
	var on: bool = _nc.active
	_account_box.visible = on
	_login_box.visible = not on
	if not on:
		_dot.add_theme_color_override("font_color", Color(0.4, 0.42, 0.46))
		return
	_dot.add_theme_color_override("font_color",
		Color(0.35, 0.9, 0.45) if _nc.online else Color(0.95, 0.75, 0.3))
	_name_l.text = _nc.display_name
	_sub_l.text = "%s · ⚙ %d Schrott" % ["Online" if _nc.online else "Offline", Save.credits]
	_avatar.texture = _nc.avatar_tex


func _refresh_friends() -> void:
	for ch in _friends_rows.get_children():
		ch.queue_free()
	if not _nc.active:
		_friends_status.text = "Anmelden, um Freunde zu sehen."
		return
	if _nc.friends.is_empty():
		_friends_status.text = "Keine Freunde gefunden (oder offline)."
		return
	_friends_status.text = "%d Freunde" % _nc.friends.size()
	var can_host := NetworkManager.is_host
	for f in _nc.friends:
		if not (f is Dictionary):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_friends_rows.add_child(row)
		var nm := str((f as Dictionary).get("name", (f as Dictionary).get("crom_id", "?")))
		var state := "offline"
		if bool((f as Dictionary).get("online", false)):
			state = "spielt" if bool((f as Dictionary).get("in_game", false)) else "online"
		var l := Label.new()
		l.text = "● %s (%s)" % [nm, state]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color",
			Color(0.35, 0.9, 0.45) if state != "offline" else Color(0.55, 0.58, 0.62))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = "Einladen"
		b.disabled = not can_host
		b.tooltip_text = "" if can_host else "Nur als Host"
		var cid := str((f as Dictionary).get("crom_id", nm))
		b.pressed.connect(func() -> void: _send_invite(cid))
		row.add_child(b)


func _send_invite(cid: String) -> void:
	_save_addr()
	_nc.send_invite(cid, _ip_edit.text.strip_edges(), _port_int())


func _refresh_invites() -> void:
	for ch in _inv_rows.get_children():
		ch.queue_free()
	if not _nc.active or _nc.invites.is_empty():
		return
	for inv in _nc.invites:
		if not (inv is Dictionary):
			continue
		var from_nm := str((inv as Dictionary).get("from_name", (inv as Dictionary).get("from", "?")))
		var what := "Server \"%s\"" % str((inv as Dictionary).get("server_name", "?")) if str((inv as Dictionary).get("server_id", "")) != "" else "Lobby"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_inv_rows.add_child(row)
		var l := Label.new()
		l.text = "✉ %s lädt ein (%s)" % [from_nm, what]
		l.add_theme_font_size_override("font_size", 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var icopy: Dictionary = (inv as Dictionary).duplicate()
		var b_ok := Button.new()
		b_ok.text = "Annehmen"
		b_ok.pressed.connect(func() -> void: _nc.accept_invite(icopy))
		row.add_child(b_ok)
		var b_no := Button.new()
		b_no.text = "✕"
		b_no.pressed.connect(func() -> void: _nc.decline_invite(icopy))
		row.add_child(b_no)


func _refresh_servers() -> void:
	for ch in _srv_rows.get_children():
		ch.queue_free()
	if _nc.servers.is_empty():
		_srv_status.text = "Keine Server gefunden (oder offline)."
		return
	_srv_status.text = "%d Server" % _nc.servers.size()
	for s in _nc.servers:
		if not (s is Dictionary):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_srv_rows.add_child(row)
		var l := Label.new()
		l.text = "%s  ·  %d/%d" % [str((s as Dictionary).get("name", "?")),
			int((s as Dictionary).get("players", 0)), int((s as Dictionary).get("max_players", 8))]
		l.add_theme_font_size_override("font_size", 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var scopy: Dictionary = (s as Dictionary).duplicate()
		var b := Button.new()
		b.text = "Beitreten"
		b.pressed.connect(func() -> void:
			var err: String = _nc.join_server(scopy)
			if err != "":
				_set_status(err))
		row.add_child(b)


# ---------- Aktionen ----------

func _on_login() -> void:
	_login_status.text = "Verbinde …"
	_nc.login(_login_id.text)


func _on_session(_active: bool) -> void:
	if is_open:
		refresh_all()


func _on_host() -> void:
	_save_addr()
	if _in_game():
		_set_status("Zum Hosten erst ins Menü wechseln.")
		return
	var err := NetworkManager.host_game(_port_int(), _nc.display_name if _nc.active else GameConfig.player_name)
	if err != "":
		_set_status(err)
		return
	var menu := get_tree().current_scene
	if menu != null and menu.has_method("_goto_setup"):
		menu._goto_setup("online")
	_set_status("Server läuft — Freunde per Einladung holen.")
	refresh_all()


func _on_join() -> void:
	_save_addr()
	var err: String = _nc.join_lobby(_ip_edit.text.strip_edges(), _port_int(), 0, false)
	if err != "":
		_set_status(err)


func _save_addr() -> void:
	Save.host_ip = _ip_edit.text.strip_edges()
	Save.host_port = _port_int()
	Save.mark_dirty()


func _port_int() -> int:
	return clampi(int(_port_edit.text) if _port_edit.text.is_valid_int() else 7777, 1024, 65535)


func _on_invite_received(inv: Dictionary) -> void:
	var from_nm := str(inv.get("from_name", inv.get("from", "?")))
	_toast("Einladung von %s — [F4]" % from_nm)
	var huds := get_tree().get_nodes_in_group("hud")
	for h in huds:
		if h.has_method("feed"):
			h.feed("✉ Einladung von %s  ([F4])" % from_nm)
	if is_open:
		refresh_all()


func _set_status(t: String) -> void:
	_status.text = t


func _toast(text: String) -> void:
	_toast_l.text = text
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_l.modulate.a = 0.0
	_toast_tw.tween_property(_toast_l, "modulate:a", 1.0, 0.3)
	_toast_tw.tween_interval(2.4)
	_toast_tw.tween_property(_toast_l, "modulate:a", 0.0, 0.6)
