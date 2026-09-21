extends Node
## Autoload "Neocrom": Echte CromID-Integration (Fastify-API).
##
## Auth: POST /auth/login {identifier,password} / POST /auth/register
##       {handle,email,password} -> {jwt, session_token, user{handle,nickname,
##       cromid,avatar_path}}. JWT (900s) via GET /auth/session rotieren.
## Launcher-SSO: --launcher-token/--launcher-user -> POST /api/games/launch/verify.
## Cloud: PUT/GET /api/cloud/saves/one-hit/main (save_data-JSON).
## Bonus: echter Daily-Reward (/api/economy/...) + lokale +100 Schrott/Tag.
## Board/Invites/Lobbys/Access: /api/games/* (eigene Game-Services).
## Offline-first: ohne Backend läuft alles lokal weiter.

signal session_changed(active: bool)
signal login_finished(ok: bool, message: String)
signal cloud_finished(ok: bool, message: String)
signal board_finished(ok: bool, message: String)
signal bonus_claimed(granted: bool, amount: int, info: String)
signal avatar_ready
signal friends_updated
signal invites_updated
signal invite_received(inv: Dictionary)
signal invite_sent(ok: bool, message: String)
signal servers_updated
signal updates_checked(available: bool, info: Dictionary)
signal update_status(message: String)

const GAME_SLUG := "one-hit"
const GAME_TITLE := "OneHit"
const BOARD_CACHE := "user://neocrom_board.json"
const BONUS_AMOUNT := 100

var base_url := "https://neocrom.pro/api"
var game_id := 0
var active := false
var online := false
var crom_id := ""
var display_name := ""
var board: Array = []
var board_ts := 0
var board_cached := false
var avatar_tex: Texture2D = null
var avatar_url := ""
var friends: Array = []
var invites: Array = []
var servers: Array = []
var overlay: OHNeocromOverlay = null
var pending_setup_online := false
var publish_lobby := true
var _update_info: Dictionary = {}

var _jwt := ""
var _jwt_exp := 0
var _session_token := ""
var _busy := false
var _seen_invites: Dictionary = {}
var _inv_init := false
var _poll: Timer = null
var _access: Dictionary = {}
var _access_ts := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Save.neocrom_url.strip_edges() != "":
		base_url = Save.neocrom_url.strip_edges()
	publish_lobby = Save.publish_lobby
	overlay = OHNeocromOverlay.new()
	add_child(overlay)
	overlay.setup(self)
	_poll = Timer.new()
	_poll.wait_time = 20.0
	_poll.autostart = true
	_poll.timeout.connect(_on_poll)
	add_child(_poll)


func _on_poll() -> void:
	if active:
		fetch_invites(true)
	if publish_lobby and NetworkManager.is_host:
		_heartbeat_server()


func _heartbeat_server() -> void:
	_authed_call("POST", "/games/lobbies", {
		"game_slug": GAME_SLUG,
		"name": "%s Lobby" % display_name,
		"ip": Save.host_ip if Save.host_ip != "" else lan_ip(),
		"port": Save.host_port,
		"seed": GameConfig.arena_seed,
		"players": NetworkManager.players.size(),
		"max_players": NetworkManager.MAX_PLAYERS,
	}, _on_void)


func set_server_url(url: String) -> void:
	var clean := url.strip_edges().trim_suffix("/")
	if clean == "":
		return
	base_url = clean
	Save.neocrom_url = clean
	Save.mark_dirty()


func api_origin() -> String:
	var o := base_url.trim_suffix("/")
	if o.ends_with("/api"):
		o = o.left(o.length() - 4)
	return o


func overlay_open() -> bool:
	return overlay != null and overlay.is_open


func close_overlay() -> void:
	if overlay != null:
		overlay.close_overlay()


func consume_join_flag() -> bool:
	if pending_setup_online:
		pending_setup_online = false
		return true
	return false


static func lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a.is_valid_ip_address() and not a.begins_with("127.") and ":" not in a:
			return a
	return "127.0.0.1"


# ---------- Session / Auth ----------

func _store_session(data: Dictionary) -> void:
	_jwt = str(data.get("jwt", ""))
	_jwt_exp = _jwt_expires(_jwt)
	_session_token = str(data.get("session_token", _session_token))
	var u: Dictionary = data.get("user", {})
	var nick := str(u.get("nickname", ""))
	display_name = nick if nick != "" else str(u.get("handle", crom_id))
	var ap := str(u.get("avatar_path", ""))
	avatar_url = (api_origin() + ap) if ap != "" else ""
	Save.crom_token = _session_token
	Save.mark_dirty()


func _jwt_expires(jwt: String) -> int:
	var parts := jwt.split(".")
	if parts.size() != 3:
		return 0
	var payload := parts[1].replace("-", "+").replace("_", "/")
	while payload.length() % 4 != 0:
		payload += "="
	var data: Variant = JSON.parse_string(Marshalls.base64_to_raw(payload).get_string_from_utf8())
	if data is Dictionary:
		return int((data as Dictionary).get("exp", 0))
	return 0


func _jwt_ok() -> bool:
	if _jwt == "" or _jwt_exp <= 0:
		return false
	return _jwt_exp - int(Time.get_unix_time_from_system()) > 60


func ensure_auth(cb: Callable) -> void:
	if _jwt_ok():
		cb.call(true)
		return
	if _session_token == "":
		cb.call(false)
		return
	_raw_call("GET", "/auth/session", {}, false, func(resp: Dictionary) -> void:
		if bool(resp.get("_ok", false)):
			var data: Dictionary = resp.get("data", {})
			_jwt = str(data.get("jwt", _jwt))
			_jwt_exp = _jwt_expires(_jwt)
			cb.call(_jwt_ok())
		else:
			cb.call(false))


func _authed_call(method: String, path: String, body: Dictionary, cb: Callable) -> void:
	if _session_token == "" and _jwt == "":
		cb.call({"_ok": false, "_transport": false})
		return
	ensure_auth(func(ok_auth: bool) -> void:
		if not ok_auth:
			cb.call({"_ok": false, "_transport": false, "_auth": false})
			return
		_raw_call(method, path, body, true, func(resp: Dictionary) -> void:
			if int(resp.get("_http", 0)) == 401:
				_drop_session()
				cb.call({"_ok": false, "_transport": true, "_auth": false})
				return
			cb.call(resp)))


func _drop_session() -> void:
	_jwt = ""
	_jwt_exp = 0
	_session_token = ""
	Save.crom_token = ""
	Save.mark_dirty()
	if active:
		active = false
		online = false
		session_changed.emit(false)


func login(id: String, password: String) -> void:
	var clean := id.strip_edges()
	if clean.length() < 1:
		login_finished.emit(false, "CromID, Handle oder E-Mail eingeben.")
		return
	if password.length() < 1:
		login_finished.emit(false, "Bitte Passwort eingeben.")
		return
	if _busy:
		login_finished.emit(false, "Bitte kurz warten …")
		return
	_raw_call("POST", "/auth/login", {"identifier": clean, "password": password},
		false, _on_auth_reply.bind(clean), 6)


func register(handle: String, email: String, password: String) -> void:
	var clean := handle.strip_edges().trim_prefix("@")
	if clean.length() < 3:
		login_finished.emit(false, "Handle: min. 3 Zeichen.")
		return
	if password.length() < 8:
		login_finished.emit(false, "Passwort: min. 8 Zeichen.")
		return
	if _busy:
		login_finished.emit(false, "Bitte kurz warten …")
		return
	_raw_call("POST", "/auth/register",
		{"handle": clean, "email": email.strip_edges(), "password": password, "nickname": clean},
		false, _on_auth_reply.bind(clean), 8)


func login_launcher(launch_token: String) -> void:
	var tok := launch_token.strip_edges()
	if tok == "":
		return
	_raw_call("POST", "/games/launch/verify", {"launch_token": tok},
		false, _on_auth_reply.bind(""), 8)


func _on_auth_reply(resp: Dictionary, clean: String) -> void:
	if bool(resp.get("_ok", false)):
		var data: Dictionary = resp.get("data", {})
		if bool(data.get("requires_2fa", false)):
			login_finished.emit(false, "2FA aktiv — bitte im Browser anmelden.")
			return
		crom_id = clean if clean != "" else str(data.get("user", {}).get("handle", ""))
		_store_session(data)
		_start_session(crom_id, true, "Verbunden mit Neocrom.")
		download_cloud()
	else:
		var msg := str(resp.get("error", "Anmeldung fehlgeschlagen."))
		if not bool(resp.get("_transport", false)):
			# Offline-first: lokale CromID-Session
			display_name = clean
			_start_session(clean, false, "Neocrom offline — lokale CromID-Session.")
			cloud_finished.emit(false, "offline")
		else:
			login_finished.emit(false, msg)


func login_offline(id: String) -> void:
	var clean := id.strip_edges()
	if clean.length() < 3:
		login_finished.emit(false, "CromID zu kurz (min. 3 Zeichen).")
		return
	display_name = clean
	_jwt = ""
	_jwt_exp = 0
	_session_token = ""
	_start_session(clean, false, "Offline-Sitzung — Sync folgt bei Verbindung.")
	cloud_finished.emit(false, "offline")


func _start_session(clean: String, is_online: bool, msg: String) -> void:
	crom_id = clean
	active = true
	online = is_online
	Save.crom_id = clean
	Save.crom_token = _session_token
	Save.mark_dirty()
	session_changed.emit(true)
	login_finished.emit(true, msg)
	fetch_avatar()
	fetch_friends()


func resume() -> void:
	if Save.crom_id.strip_edges().length() < 3:
		return
	if Save.crom_token != "":
		_session_token = Save.crom_token
		ensure_auth(func(ok_auth: bool) -> void:
			if ok_auth:
				display_name = Save.crom_id
				_start_session(Save.crom_id, true, "Sitzung wiederhergestellt.")
				download_cloud()
			else:
				_offline_resume())
	else:
		_offline_resume()


func _offline_resume() -> void:
	display_name = Save.crom_id
	_start_session(Save.crom_id, false, "Offline-Sitzung.")
	cloud_finished.emit(false, "offline")


func logout() -> void:
	if _session_token != "" or _jwt != "":
		_raw_call("POST", "/auth/logout", {}, true, _on_void)
	_jwt = ""
	_jwt_exp = 0
	_session_token = ""
	crom_id = ""
	display_name = ""
	active = false
	online = false
	avatar_tex = null
	avatar_url = ""
	friends.clear()
	invites.clear()
	servers.clear()
	_seen_invites.clear()
	_inv_init = false
	_access = {}
	Save.crom_token = ""
	Save.mark_dirty()
	friends_updated.emit()
	invites_updated.emit()
	servers_updated.emit()
	avatar_ready.emit()
	session_changed.emit(false)


# ---------- Zugriff / Preview ----------

func check_access(cb: Callable) -> void:
	var now := int(Time.get_unix_time_from_system())
	if not _access.is_empty() and now - int(_access.get("_ts", 0)) < 300:
		cb.call(_access)
		return
	_raw_call("GET", "/games/access?slug=%s" % GAME_SLUG, {}, false, func(resp: Dictionary) -> void:
		var a := {"access": false, "reason": "offline", "game_id": 0}
		if bool(resp.get("_ok", false)):
			var d: Dictionary = resp.get("data", resp)
			a = {"access": bool(d.get("access", false)), "reason": str(d.get("reason", "")),
				"game_id": int(d.get("game_id", 0)),
				"preview_until": str(d.get("preview_until", ""))}
			game_id = int(a["game_id"])
		a["_ts"] = now
		_access = a
		cb.call(a))


func access_message(reason: String) -> String:
	match reason:
		"login_required":
			return "Exklusiv für Neocrom-Members — bitte anmelden."
		"preview_ended":
			return "Preview beendet (01.10.2026)."
		"offline":
			return "Offline — Zugriff wird geprüft, sobald Neocrom erreichbar ist."
	return "Kein Zugriff."


# ---------- CromCloud ----------

func cloud_stats() -> Dictionary:
	return {
		"credits": Save.credits,
		"kills": Save.total_kills,
		"deaths": Save.total_deaths,
		"games": Save.games_played,
		"best_wave": Save.best_wave,
		"skins_owned": Save.skins_owned,
		"skin_selected": Save.skin_selected,
	}


func download_cloud() -> void:
	if not active:
		return
	_authed_call("GET", "/cloud/saves?gameId=%s" % GAME_SLUG, {}, _on_cloud_down)


func _on_cloud_down(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		var saves: Array = Array(resp.get("data", {}).get("saves", []))
		if not saves.is_empty() and saves[0] is Dictionary:
			_apply_cloud_stats((saves[0] as Dictionary).get("save_data", {}))
		online = true
		cloud_finished.emit(true, "Cloud geladen.")
	else:
		online = false
		cloud_finished.emit(false, "Cloud offline — lokale Daten.")


func _apply_cloud_stats(data: Variant) -> void:
	if not (data is Dictionary):
		return
	var d := data as Dictionary
	Save.credits = maxi(Save.credits, int(d.get("credits", 0)))
	Save.total_kills = maxi(Save.total_kills, int(d.get("kills", 0)))
	Save.total_deaths = maxi(Save.total_deaths, int(d.get("deaths", 0)))
	Save.games_played = maxi(Save.games_played, int(d.get("games", 0)))
	Save.best_wave = maxi(Save.best_wave, int(d.get("best_wave", 0)))
	for s in Array(d.get("skins_owned", [])):
		if not Save.skins_owned.has(str(s)):
			Save.skins_owned.append(str(s))
	var sel := str(d.get("skin_selected", ""))
	if sel != "" and Save.skins_owned.has(sel):
		Save.skin_selected = sel
	Save.save_now()


func upload_cloud(playtime_seconds: int = 0) -> void:
	if not active:
		return
	_authed_call("PUT", "/cloud/saves/%s/main" % GAME_SLUG, {
		"game_title": GAME_TITLE,
		"save_name": "OneHit Stand",
		"save_data": cloud_stats(),
		"playtime_seconds": playtime_seconds,
	}, _on_cloud_up)


func _on_cloud_up(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		online = true
		cloud_finished.emit(true, "Gespeichert in der CromCloud.")
	else:
		online = false
		cloud_finished.emit(false, "Cloud offline — lokal gespeichert.")


# ---------- Tagesbonus (echt + lokal) ----------

func claim_bonus() -> void:
	if not active:
		bonus_claimed.emit(false, 0, "")
		return
	_authed_call("POST", "/economy/daily-reward", {}, _on_bonus_reply)


func _on_bonus_reply(resp: Dictionary) -> void:
	var coins := 0
	var granted := false
	if bool(resp.get("_ok", false)):
		var d: Dictionary = resp.get("data", resp)
		if bool(d.get("claimed", d.get("ok", false))):
			granted = true
			coins = int(d.get("reward_coins", 0))
	if granted:
		_grant_local_bonus(coins)
	else:
		bonus_claimed.emit(false, 0, "")


func _grant_local_bonus(coins: int) -> void:
	var today := Time.get_date_string_from_system()
	if Save.last_bonus_day != today:
		Save.add_credits(BONUS_AMOUNT)
		Save.last_bonus_day = today
		Save.save_now()
		var info := "Tagesbonus +100 ⚙"
		if coins > 0:
			info += " · +%d CromCoins" % coins
		bonus_claimed.emit(true, BONUS_AMOUNT, info)
	else:
		bonus_claimed.emit(false, 0, "")


# ---------- Rangliste ----------

func fetch_board(limit: int = 25) -> void:
	_raw_call("GET", "/games/leaderboard?slug=%s&limit=%d" % [GAME_SLUG, limit], {},
		false, _on_board_reply)


func _on_board_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		var raw: Array = Array(resp.get("data", {}).get("entries", []))
		board = []
		for e in raw:
			if e is Dictionary:
				var nm := str((e as Dictionary).get("nickname", ""))
				if nm == "":
					nm = str((e as Dictionary).get("handle", "?"))
				board.append({"name": nm,
					"kills": int((e as Dictionary).get("kills", 0)),
					"best_wave": int((e as Dictionary).get("bestWave", (e as Dictionary).get("best_wave", 0)))})
		board_ts = int(Time.get_unix_time_from_system())
		board_cached = false
		_write_board_cache()
		board_finished.emit(true, "Rangliste aktuell.")
	else:
		_read_board_cache()
		board_finished.emit(false, "Offline-Cache." if not board.is_empty() else "Keine Verbindung.")


func submit_score() -> void:
	if not active:
		return
	_authed_call("POST", "/games/scores", {
		"game_slug": GAME_SLUG,
		"kills": Save.total_kills,
		"best_wave": Save.best_wave,
		"games_played": Save.games_played,
	}, _on_submit_reply)


func _on_submit_reply(resp: Dictionary) -> void:
	online = bool(resp.get("_ok", false))


func _write_board_cache() -> void:
	var f := FileAccess.open(BOARD_CACHE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ts": board_ts, "entries": board}))


func _read_board_cache() -> void:
	board.clear()
	if not FileAccess.file_exists(BOARD_CACHE):
		return
	var f := FileAccess.open(BOARD_CACHE, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		board = Array((data as Dictionary).get("entries", []))
		board_ts = int((data as Dictionary).get("ts", 0))
		board_cached = true


# ---------- Profil & Avatar ----------

func fetch_avatar() -> void:
	if avatar_url != "":
		_download_avatar()
	else:
		_make_identicon()


func _avatar_file() -> String:
	return "user://avatars/avatar_" + str(absi(hash(crom_id))) + ".png"


func _download_avatar() -> void:
	if FileAccess.file_exists(_avatar_file()):
		var cached: Image = Image.load_from_file(_avatar_file())
		if cached != null and not cached.is_empty():
			avatar_tex = ImageTexture.create_from_image(cached)
			avatar_ready.emit()
			return
	var http := HTTPRequest.new()
	http.timeout = 10
	add_child(http)
	http.request_completed.connect(_on_avatar_done.bind(http))
	if http.request(avatar_url) != OK:
		http.queue_free()
		_make_identicon()


func _on_avatar_done(result: int, code: int, _h: PackedByteArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if is_instance_valid(http):
		http.queue_free()
	var img := Image.new()
	var ok := false
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		if img.load_png_from_buffer(body) == OK or img.load_jpg_from_buffer(body) == OK:
			ok = true
	if ok:
		img.resize(96, 96)
		DirAccess.make_dir_recursive_absolute("user://avatars")
		img.save_png_to_file(_avatar_file())
		avatar_tex = ImageTexture.create_from_image(img)
	else:
		_make_identicon()
		return
	avatar_ready.emit()


func _make_identicon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(crom_id + "_nc"))
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var bg := Color(0.10, 0.12, 0.18)
	var fg := Color.from_hsv(rng.randf(), 0.55, 0.9)
	var cell := 8
	for gy in 4:
		for gx in 4:
			var on := rng.randf() < 0.5
			for py in cell:
				for px in cell:
					var c := fg if on else bg
					img.set_pixel(gx * cell + px, gy * cell + py, c)
					img.set_pixel(63 - (gx * cell + px), gy * cell + py, c)
	avatar_tex = ImageTexture.create_from_image(img)
	avatar_ready.emit()


# ---------- Freunde ----------

func fetch_friends() -> void:
	if not active:
		friends.clear()
		friends_updated.emit()
		return
	_authed_call("GET", "/friends", {}, _on_friends_reply)


func _on_friends_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		online = true
		friends = []
		for f in Array(resp.get("data", {}).get("friends", [])):
			if f is Dictionary:
				var u: Dictionary = (f as Dictionary).get("user", f)
				var nm := str(u.get("nickname", ""))
				if nm == "":
					nm = str(u.get("handle", "?"))
				friends.append({"crom_id": str(u.get("handle", "")),
					"name": nm,
					"online": bool(u.get("is_online", u.get("isOnline", false))),
					"in_game": false})
	else:
		online = false
	friends_updated.emit()


func add_friend(identifier: String) -> void:
	if not active:
		invite_sent.emit(false, "Nicht angemeldet.")
		return
	_authed_call("POST", "/friends/add", {"identifier": identifier.strip_edges()}, _on_friend_add)


func _on_friend_add(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		fetch_friends()
		invite_sent.emit(true, "Anfrage gesendet.")
	else:
		invite_sent.emit(false, str(resp.get("error", "Fehlgeschlagen.")))


func send_invite(to_crom: String, join_ip: String, join_port: int) -> void:
	if not active:
		invite_sent.emit(false, "Nicht angemeldet.")
		return
	_authed_call("POST", "/games/invites",
		{"to": to_crom, "game_slug": GAME_SLUG, "join_ip": join_ip,
			"join_port": join_port, "seed": GameConfig.arena_seed},
		_on_invite_sent)


func _on_invite_sent(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		invite_sent.emit(true, "Einladung gesendet.")
	else:
		invite_sent.emit(false, "Einladung fehlgeschlagen (offline?).")


func fetch_invites(silent: bool = false) -> void:
	if not active:
		return
	_authed_call("GET", "/games/invites", {}, _on_invites_reply.bind(silent))


func _on_invites_reply(resp: Dictionary, silent: bool) -> void:
	if bool(resp.get("_ok", false)):
		online = true
		invites = Array(resp.get("data", {}).get("invites", []))
		for inv in invites:
			if inv is Dictionary:
				var iid := str((inv as Dictionary).get("id", ""))
				if iid != "" and not _seen_invites.has(iid):
					_seen_invites[iid] = true
					if _inv_init and not silent:
						invite_received.emit(inv)
		_inv_init = true
	else:
		online = false
	invites_updated.emit()


func accept_invite(inv: Dictionary) -> void:
	var iid := str(inv.get("id", ""))
	if iid != "":
		_authed_call("POST", "/games/invites/%s/accept" % iid, {}, _on_void)
	_dismiss_invite(iid)
	join_lobby(str(inv.get("join_ip", "")), int(inv.get("join_port", 7777)),
		int(inv.get("seed", 0)), false)


func decline_invite(inv: Dictionary) -> void:
	var iid := str(inv.get("id", ""))
	if iid != "":
		_authed_call("POST", "/games/invites/%s/decline" % iid, {}, _on_void)
	_dismiss_invite(iid)


func _dismiss_invite(iid: String) -> void:
	_seen_invites.erase(iid)
	var rest: Array = []
	for e in invites:
		if e is Dictionary and str((e as Dictionary).get("id", "")) != iid:
			rest.append(e)
	invites = rest
	invites_updated.emit()


func _on_void(_resp: Dictionary) -> void:
	pass


func join_lobby(ip: String, port: int, seed_value: int, direct: bool) -> String:
	if ip.strip_edges() == "":
		return "Keine Adresse."
	close_overlay()
	var err := NetworkManager.join_game(ip, port, display_name)
	if err != "":
		return err
	GameConfig.pending_mode = "online"
	if direct:
		GameConfig.arena_seed = seed_value if seed_value != 0 else randi()
		get_tree().change_scene_to_file("res://scenes/arena.tscn")
	else:
		pending_setup_online = true
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	return ""


func join_server(srv: Dictionary) -> String:
	return join_lobby(str(srv.get("ip", "")), int(srv.get("port", 7777)),
		int(srv.get("seed", 0)), true)


# ---------- Offizielle Server (publizierte Lobbys) ----------

func fetch_servers() -> void:
	_raw_call("GET", "/games/lobbies?slug=%s" % GAME_SLUG, {}, false, _on_servers_reply)


func _on_servers_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		servers = Array(resp.get("data", {}).get("lobbies", []))
	else:
		servers.clear()
	servers_updated.emit()


# ---------- Präsenz ----------

func heartbeat(session_key: String) -> void:
	if not active or game_id <= 0:
		return
	_authed_call("POST", "/presence/heartbeat",
		{"session_key": session_key, "game_id": game_id}, _on_void)


func heartbeat_stop(session_key: String) -> void:
	if not active or session_key == "":
		return
	_authed_call("DELETE", "/presence/heartbeat/%s" % session_key, {}, _on_void)


# ---------- Auto-Update (Windows) ----------

func local_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.0.0"))


static func is_newer(latest: String, current: String) -> bool:
	var pa := latest.split(".")
	var pb := current.split(".")
	for i in maxi(pa.size(), pb.size()):
		var a := int(pa[i]) if i < pa.size() else 0
		var b := int(pb[i]) if i < pb.size() else 0
		if a != b:
			return a > b
	return false


func check_updates() -> void:
	_raw_call("GET", "/games/updates?slug=%s&version=%s" % [GAME_SLUG, local_version()],
		{}, false, _on_updates_reply)


func _on_updates_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		var d: Dictionary = resp.get("data", {})
		_update_info = d
		updates_checked.emit(bool(d.get("update_available", false)), d)
	else:
		updates_checked.emit(false, {})


func can_self_update() -> bool:
	return OS.has_feature("windows") and not OS.has_feature("editor")


func download_update() -> void:
	if not can_self_update():
		update_status.emit("Auto-Update nur in der Windows-Version.")
		return
	if _update_info.is_empty() or not bool(_update_info.get("update_available", false)):
		update_status.emit("Kein Update verfügbar.")
		return
	var dl := str(_update_info.get("download_url", ""))
	if dl == "":
		update_status.emit("Kein Download-Link.")
		return
	if dl.begins_with("/"):
		dl = api_origin() + dl
	var exe_dir := OS.get_executable_path().get_base_dir()
	var target := exe_dir.path_join("OneHit.new.exe")
	update_status.emit("Lade Update …")
	var http := HTTPRequest.new()
	http.timeout = 900
	http.download_file = target
	add_child(http)
	http.request_completed.connect(_on_update_done.bind(http, target, exe_dir))


func _on_update_done(result: int, code: int, _h: PackedByteArray, _b: PackedByteArray, http: HTTPRequest, target: String, exe_dir: String) -> void:
	if is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		update_status.emit("Download fehlgeschlagen.")
		return
	if not FileAccess.file_exists(target):
		update_status.emit("Download unvollständig.")
		return
	var bat := exe_dir.path_join("onehit_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		update_status.emit("Kein Schreibzugriff im Spielordner.")
		return
	f.store_string("@echo off\r\n")
	f.store_string(":waitloop\r\n")
	f.store_string("tasklist /FI \"PID eq %%1\" 2>NUL | findstr /C:\"%%1\" >NUL\r\n")
	f.store_string("if %%ERRORLEVEL%%==0 ( timeout /t 1 /nobreak >NUL & goto waitloop )\r\n")
	f.store_string("move /Y \"%%~dp0OneHit.new.exe\" \"%%~dp0OneHit.exe\" >NUL\r\n")
	f.store_string("start \"\" \"%%~dp0OneHit.exe\"\r\n")
	f.store_string("del \"%%~f0\"\r\n")
	f.close()
	update_status.emit("Installiere Update …")
	OS.create_process("cmd.exe", PackedStringArray(["/c", bat, str(OS.get_process_id())]))
	get_tree().quit()


# ---------- Transport ----------

func _raw_call(method: String, path: String, body: Dictionary, auth: bool, cb: Callable, timeout_s: int = 8) -> void:
	if auth and _jwt == "" and _session_token == "":
		cb.call({"_ok": false, "_transport": false})
		return
	_busy = true
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if auth:
		headers.append("Authorization: Bearer " + _jwt)
		if _session_token != "":
			headers.append("X-Session-Token: " + _session_token)
	var m := HTTPClient.METHOD_GET
	if method == "POST":
		m = HTTPClient.METHOD_POST
	elif method == "PUT":
		m = HTTPClient.METHOD_PUT
	elif method == "DELETE":
		m = HTTPClient.METHOD_DELETE
	var data := ""
	if m != HTTPClient.METHOD_GET and not body.is_empty():
		data = JSON.stringify(body)
	http.request_completed.connect(_on_http_done.bind(http, cb))
	var err := http.request(base_url + path, headers, m, data)
	if err != OK:
		_busy = false
		http.queue_free()
		cb.call({"_ok": false, "_transport": false})


func _on_http_done(result: int, code: int, _headers: PackedByteArray, body: PackedByteArray, http: HTTPRequest, cb: Callable) -> void:
	_busy = false
	var resp := {"_ok": false, "_transport": false, "_http": code}
	if is_instance_valid(http):
		http.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			resp["_ok"] = bool((data as Dictionary).get("ok", true))
			resp["data"] = (data as Dictionary)
			resp["_transport"] = true
			if (data as Dictionary).has("error"):
				resp["error"] = str((data as Dictionary)["error"])
	cb.call(resp)
