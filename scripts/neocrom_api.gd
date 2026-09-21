extends Node
## Autoload "Neocrom": CromID-Login, CromCloud-Stats, Tagesbonus, Rangliste.
##
## REST-Vertrag (JSON) gegen base_url — beiBackend-Anpassung NUR hier ändern:
##   POST {base}/auth/crom-id        {crom_id, game, device} -> {ok, token, name}
##   GET  {base}/cloud/stats         Bearer -> {credits,kills,deaths,games,best_wave,skins_owned,skin_selected}
##   PUT  {base}/cloud/stats         Bearer + Stats-Dict -> {ok}
##   POST {base}/cloud/bonus         Bearer {day} -> {granted, amount}
##   GET  {base}/leaderboard?game=X&limit=N -> {entries:[{name,kills,best_wave,games}]}
##   POST {base}/leaderboard/submit  Bearer {kills,best_wave,games} -> {ok, rank}
##
## Offline-first: Backend unerreichbar -> lokale CromID-Session + Datei-Cache,
## alles wird bei Verbindung transparent synchronisiert. Spiel bleibt spielbar.

signal session_changed(active: bool)
signal login_finished(ok: bool, message: String)
signal cloud_finished(ok: bool, message: String)
signal board_finished(ok: bool, message: String)
signal bonus_claimed(granted: bool, amount: int)

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

var _token := ""
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_busy() -> bool:
	return _busy


# ---------- Login ----------

func login(id: String) -> void:
	var clean := id.strip_edges()
	if clean.length() < 3:
		login_finished.emit(false, "CromID zu kurz (min. 3 Zeichen).")
		return
	if _busy:
		login_finished.emit(false, "Bitte kurz warten …")
		return
	_call("POST", "/auth/crom-id",
		{"crom_id": clean, "game": GAME_ID, "device": OS.get_unique_id()},
		false, _on_login_reply.bind(clean), 5)


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
	Save.crom_token = ""
	Save.mark_dirty()
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
