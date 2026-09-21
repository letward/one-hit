extends Node
## Autoload "Neocrom": CromID-Login, CromCloud-Stats, Tagesbonus, Rangliste.
##
## REST-Vertrag (JSON) gegen base_url — bei Backend-Anpassung NUR hier ändern:
##   POST {base}/auth/register       {crom_id, email, password} -> {ok, token, name} (409 belegt)
##   POST {base}/auth/login          {crom_id, password} -> {ok, token, name} (401 falsch)
##   GET  {base}/cloud/stats         Bearer -> {credits,kills,deaths,games,best_wave,skins_owned,skin_selected}
##   PUT  {base}/cloud/stats         Bearer + Stats-Dict -> {ok}
##   POST {base}/cloud/bonus         Bearer {day} -> {granted, amount}
##   GET  {base}/leaderboard?game=X&limit=N -> {entries:[{name,kills,best_wave,games}]}
##   POST {base}/leaderboard/submit  Bearer {kills,best_wave,games} -> {ok, rank}
##   GET  {base}/users/me             Bearer -> {name, avatar_url}
##   GET  {base}/friends              Bearer -> {friends:[{crom_id,name,online,in_game}]}
##   POST {base}/friends/add         Bearer {crom_id} -> {ok}
##   POST {base}/friends/invite       Bearer {to,game,join_ip,join_port} -> {ok}
##   GET  {base}/invites              Bearer -> {invites:[{id,from,from_name,join_ip,join_port,server_id,server_name,seed}]}
##   POST {base}/invites/{id}/accept  Bearer -> {ok}
##   POST {base}/invites/{id}/decline Bearer -> {ok}
##   GET  {base}/servers?game=X       -> {servers:[{id,name,ip,port,players,max_players,seed}]}
##   POST {base}/servers/register    Bearer {name,ip,port,seed,players,max_players} -> {ok}
##
## Offline-first: Backend unerreichbar -> lokale CromID-Session + Datei-Cache,
## alles wird bei Verbindung transparent synchronisiert. Spiel bleibt spielbar.

signal session_changed(active: bool)
signal login_finished(ok: bool, message: String)
signal cloud_finished(ok: bool, message: String)
signal board_finished(ok: bool, message: String)
signal bonus_claimed(granted: bool, amount: int)
signal avatar_ready
signal friends_updated
signal invites_updated
signal invite_received(inv: Dictionary)
signal invite_sent(ok: bool, message: String)
signal servers_updated

const GAME_ID := "one-hit"
const BOARD_CACHE := "user://neocrom_board.json"
const BONUS_AMOUNT := 100

var base_url := "https://neocrom.pro/api/v1"
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

var _token := ""
var _busy := false
var _seen_invites: Dictionary = {}
var _inv_init := false
var _poll: Timer = null
var publish_lobby := true


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
	_call("POST", "/servers/register", {
		"name": "%s Lobby" % display_name,
		"game": GAME_ID,
		"ip": Save.host_ip if Save.host_ip != "" else lan_ip(),
		"port": Save.host_port,
		"seed": GameConfig.arena_seed,
		"players": NetworkManager.players.size(),
		"max_players": NetworkManager.MAX_PLAYERS,
	}, true, _on_void)


func set_server_url(url: String) -> void:
	var clean := url.strip_edges().trim_suffix("/")
	if clean == "":
		return
	base_url = clean
	Save.neocrom_url = clean
	Save.mark_dirty()


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


func is_busy() -> bool:
	return _busy


# ---------- Login ----------

func login(id: String, password: String) -> void:
	var clean := id.strip_edges()
	if clean.length() < 3:
		login_finished.emit(false, "CromID zu kurz (min. 3 Zeichen).")
		return
	if password.length() < 1:
		login_finished.emit(false, "Bitte Passwort eingeben.")
		return
	if _busy:
		login_finished.emit(false, "Bitte kurz warten …")
		return
	_call("POST", "/auth/login",
		{"crom_id": clean, "password": password},
		false, _on_login_reply.bind(clean), 5)


func register(id: String, email: String, password: String) -> void:
	var clean := id.strip_edges()
	if clean.length() < 3:
		login_finished.emit(false, "CromID zu kurz (min. 3 Zeichen).")
		return
	if password.length() < 8:
		login_finished.emit(false, "Passwort: min. 8 Zeichen.")
		return
	if _busy:
		login_finished.emit(false, "Bitte kurz warten …")
		return
	_call("POST", "/auth/register",
		{"crom_id": clean, "email": email.strip_edges(), "password": password},
		false, _on_login_reply.bind(clean), 8)


func login_offline(id: String) -> void:
	# Bewusst offline: lokale CromID-Session ohne Backend-Kontakt
	var clean := id.strip_edges()
	if clean.length() < 3:
		login_finished.emit(false, "CromID zu kurz (min. 3 Zeichen).")
		return
	display_name = clean
	_token = ""
	_start_session(clean, false, "Offline-Sitzung — Sync folgt bei Verbindung.")
	cloud_finished.emit(false, "offline")


func _on_login_reply(resp: Dictionary, clean: String) -> void:
	if bool(resp.get("_ok", false)):
		var data: Dictionary = resp.get("data", {})
		_token = str(data.get("token", ""))
		display_name = str(data.get("name", clean))
		_start_session(clean, true, "Verbunden mit Neocrom.")
		download_cloud()
	else:
		# Offline-first: lokale CromID-Session, Sync später
		display_name = clean
		_start_session(clean, false, "Neocrom offline — lokale CromID-Session.")
		cloud_finished.emit(false, "offline")


func _start_session(clean: String, is_online: bool, msg: String) -> void:
	crom_id = clean
	active = true
	online = is_online
	Save.crom_id = clean
	Save.crom_token = _token
	Save.mark_dirty()
	session_changed.emit(true)
	login_finished.emit(true, msg)
	fetch_avatar()
	fetch_friends()


func resume() -> void:
	# Stillers Re-Login beim Start, falls Session gespeichert
	if Save.crom_id.strip_edges().length() < 3:
		return
	if Save.crom_token != "":
		_token = Save.crom_token
		_validate_token()
	else:
		_offline_resume()


func _validate_token() -> void:
	_call("GET", "/cloud/stats", {}, true, _on_validate_reply)


func _on_validate_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		display_name = str(resp.get("data", {}).get("name", Save.crom_id))
		_start_session(Save.crom_id, true, "Sitzung wiederhergestellt.")
		_apply_cloud_stats(resp.get("data", {}))
		cloud_finished.emit(true, "Cloud geladen.")
	else:
		_offline_resume()


func _offline_resume() -> void:
	display_name = Save.crom_id
	_token = ""
	_start_session(Save.crom_id, false, "Offline-Sitzung.")
	cloud_finished.emit(false, "offline")


func logout() -> void:
	_token = ""
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
	Save.crom_token = ""
	Save.mark_dirty()
	friends_updated.emit()
	invites_updated.emit()
	servers_updated.emit()
	avatar_ready.emit()
	session_changed.emit(false)


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
	_call("GET", "/cloud/stats", {}, true, _on_cloud_down)


func _on_cloud_down(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		_apply_cloud_stats(resp.get("data", {}))
		online = true
		cloud_finished.emit(true, "Cloud geladen.")
	else:
		online = false
		cloud_finished.emit(false, "Cloud offline — lokale Daten.")


func _apply_cloud_stats(data: Dictionary) -> void:
	if data.is_empty():
		return
	# Merge ohne Verlust: Maxima gewinnen, Skins werden vereint
	Save.credits = maxi(Save.credits, int(data.get("credits", 0)))
	Save.total_kills = maxi(Save.total_kills, int(data.get("kills", 0)))
	Save.total_deaths = maxi(Save.total_deaths, int(data.get("deaths", 0)))
	Save.games_played = maxi(Save.games_played, int(data.get("games", 0)))
	Save.best_wave = maxi(Save.best_wave, int(data.get("best_wave", 0)))
	for s in Array(data.get("skins_owned", [])):
		if not Save.skins_owned.has(str(s)):
			Save.skins_owned.append(str(s))
	var sel := str(data.get("skin_selected", ""))
	if sel != "" and Save.skins_owned.has(sel):
		Save.skin_selected = sel
	Save.save_now()


func upload_cloud() -> void:
	if not active:
		return
	_call("PUT", "/cloud/stats", cloud_stats(), true, _on_cloud_up)


func _on_cloud_up(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		online = true
		cloud_finished.emit(true, "Gespeichert in der CromCloud.")
	else:
		online = false
		cloud_finished.emit(false, "Cloud offline — lokal gespeichert.")


# ---------- Tagesbonus ----------

func claim_bonus() -> void:
	var today := Time.get_date_string_from_system()
	if not active:
		bonus_claimed.emit(false, 0)
		return
	if online or _token != "":
		_call("POST", "/cloud/bonus", {"day": today}, true, _on_bonus_reply.bind(today))
	else:
		_grant_local_bonus(today)


func _on_bonus_reply(resp: Dictionary, today: String) -> void:
	if bool(resp.get("_ok", false)) and bool(resp.get("data", {}).get("granted", false)):
		var amount := int(resp.get("data", {}).get("amount", BONUS_AMOUNT))
		Save.add_credits(amount)
		Save.last_bonus_day = today
		Save.save_now()
		bonus_claimed.emit(true, amount)
	else:
		_grant_local_bonus(today)


func _grant_local_bonus(today: String) -> void:
	if Save.last_bonus_day == today:
		bonus_claimed.emit(false, 0)
		return
	Save.add_credits(BONUS_AMOUNT)
	Save.last_bonus_day = today
	Save.save_now()
	bonus_claimed.emit(true, BONUS_AMOUNT)


# ---------- Rangliste ----------

func fetch_board(limit: int = 25) -> void:
	_call("GET", "/leaderboard?game=%s&limit=%d" % [GAME_ID, limit], {}, false, _on_board_reply)


func _on_board_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		board = Array(resp.get("data", {}).get("entries", []))
		board_ts = int(Time.get_unix_time_from_system())
		board_cached = false
		online = true
		_write_board_cache()
		board_finished.emit(true, "Rangliste aktuell.")
	else:
		online = false
		_read_board_cache()
		board_finished.emit(false, "Offline-Cache." if not board.is_empty() else "Keine Verbindung.")


func submit_score() -> void:
	if not active:
		return
	_call("POST", "/leaderboard/submit", {
		"kills": Save.total_kills,
		"best_wave": Save.best_wave,
		"games": Save.games_played,
	}, true, _on_submit_reply)


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
	if not active or _token == "":
		_make_identicon()
		return
	_call("GET", "/users/me", {}, true, _on_profile_reply)


func _on_profile_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		var data: Dictionary = resp.get("data", {})
		if str(data.get("name", "")) != "":
			display_name = str(data.get("name"))
		avatar_url = str(data.get("avatar_url", ""))
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


# ---------- Freunde & Einladungen ----------

func fetch_friends() -> void:
	if not active:
		friends.clear()
		friends_updated.emit()
		return
	_call("GET", "/friends", {}, true, _on_friends_reply)


func _on_friends_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		online = true
		friends = Array(resp.get("data", {}).get("friends", []))
	else:
		online = false
	friends_updated.emit()


func send_invite(to_crom: String, join_ip: String, join_port: int) -> void:
	if not active:
		invite_sent.emit(false, "Nicht angemeldet.")
		return
	_call("POST", "/friends/invite",
		{"to": to_crom, "game": GAME_ID, "join_ip": join_ip, "join_port": join_port},
		true, _on_invite_sent)


func _on_invite_sent(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		invite_sent.emit(true, "Einladung gesendet.")
	else:
		invite_sent.emit(false, "Einladung fehlgeschlagen (offline?).")


func fetch_invites(silent: bool = false) -> void:
	if not active:
		return
	_call("GET", "/invites", {}, true, _on_invites_reply.bind(silent))


func _on_invites_reply(resp: Dictionary, silent: bool) -> void:
	if bool(resp.get("_ok", false)):
		online = true
		invites = Array(resp.get("data", {}).get("invites", []))
		for inv in invites:
			if inv is Dictionary:
				var iid := str((inv as Dictionary).get("id", ""))
				if iid != "" and not _seen_invites.has(iid):
					_seen_invites[iid] = true
					if _inv_init:
						invite_received.emit(inv)
		_inv_init = true
	else:
		online = false
	invites_updated.emit()


func accept_invite(inv: Dictionary) -> void:
	var iid := str(inv.get("id", ""))
	if _token != "" and iid != "":
		_call("POST", "/invites/%s/accept" % iid, {}, true, _on_void)
	_dismiss_invite(iid)
	join_lobby(str(inv.get("join_ip", "")), int(inv.get("join_port", 7777)),
		int(inv.get("seed", 0)), str(inv.get("server_id", "")) != "")


func decline_invite(inv: Dictionary) -> void:
	var iid := str(inv.get("id", ""))
	if _token != "" and iid != "":
		_call("POST", "/invites/%s/decline" % iid, {}, true, _on_void)
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


# ---------- Offizielle Server ----------

func fetch_servers() -> void:
	_call("GET", "/servers?game=%s" % GAME_ID, {}, false, _on_servers_reply)


func _on_servers_reply(resp: Dictionary) -> void:
	if bool(resp.get("_ok", false)):
		servers = Array(resp.get("data", {}).get("servers", []))
	else:
		servers.clear()
	servers_updated.emit()


func join_server(srv: Dictionary) -> String:
	return join_lobby(str(srv.get("ip", "")), int(srv.get("port", 7777)),
		int(srv.get("seed", 0)), true)


# ---------- Transport ----------

func _call(method: String, path: String, body: Dictionary, auth: bool, cb: Callable, timeout_s: int = 8) -> void:
	if auth and _token == "":
		cb.call({"_ok": false, "_transport": false})
		return
	_busy = true
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if auth:
		headers.append("Authorization: Bearer " + _token)
	var m := HTTPClient.METHOD_GET
	if method == "POST":
		m = HTTPClient.METHOD_POST
	elif method == "PUT":
		m = HTTPClient.METHOD_PUT
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
	cb.call(resp)
