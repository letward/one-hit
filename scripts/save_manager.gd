extends Node
## Autoload "Save": Credits, Skin-Fortschritt, Statistiken, Einstellungen.
## Persistiert nach user://onehit_save.cfg (mit 1s-Schreib-Debounce).

const PATH := "user://onehit_save.cfg"

var credits: int = 0
var skins_owned: Array = ["standard"]
var skin_selected: String = "standard"
var total_kills: int = 0
var total_deaths: int = 0
var games_played: int = 0
var best_wave: int = 0
var crom_id: String = ""
var crom_token: String = ""
var last_bonus_day: String = ""
var host_ip: String = ""
var host_port: int = 7777

var _dirty: bool = false
var _save_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_all()


func _process(delta: float) -> void:
	if _dirty:
		_save_t -= delta
		if _save_t <= 0.0:
			_dirty = false
			_write()


func mark_dirty() -> void:
	_dirty = true
	_save_t = 1.0


func save_now() -> void:
	_dirty = false
	_write()


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	credits = int(cfg.get_value("economy", "credits", 0))
	skins_owned = Array(cfg.get_value("economy", "skins_owned", ["standard"]))
	if skins_owned.is_empty():
		skins_owned = ["standard"]
	skin_selected = str(cfg.get_value("economy", "skin_selected", "standard"))
	total_kills = int(cfg.get_value("stats", "kills", 0))
	total_deaths = int(cfg.get_value("stats", "deaths", 0))
	games_played = int(cfg.get_value("stats", "games", 0))
	best_wave = int(cfg.get_value("stats", "best_wave", 0))
	crom_id = str(cfg.get_value("neocrom", "crom_id", ""))
	crom_token = str(cfg.get_value("neocrom", "token", ""))
	last_bonus_day = str(cfg.get_value("neocrom", "last_bonus", ""))
	host_ip = str(cfg.get_value("neocrom", "host_ip", ""))
	host_port = int(cfg.get_value("neocrom", "host_port", 7777))
	# Einstellungen zurück in GameConfig/AudioManager spielen
	GameConfig.player_name = str(cfg.get_value("settings", "name", GameConfig.player_name))
	GameConfig.sensitivity = float(cfg.get_value("settings", "sens", GameConfig.sensitivity))
	GameConfig.one_hit = bool(cfg.get_value("settings", "one_hit", GameConfig.one_hit))
	GameConfig.bot_count = int(cfg.get_value("settings", "bots", GameConfig.bot_count))
	GameConfig.volume = float(cfg.get_value("settings", "volume", 0.8))
	GameConfig.base_fov = float(cfg.get_value("settings", "fov", 75.0))
	GameConfig.shake_enabled = bool(cfg.get_value("settings", "shake", true))
	GameConfig.is_fullscreen = bool(cfg.get_value("settings", "fullscreen", false))
	GameConfig.vsync = bool(cfg.get_value("settings", "vsync", true))
	GameConfig.msaa = int(cfg.get_value("settings", "msaa", 1))
	GameConfig.glow = bool(cfg.get_value("settings", "glow", true))
	GameConfig.shadows = bool(cfg.get_value("settings", "shadows", true))
	GameConfig.dust = bool(cfg.get_value("settings", "dust", true))
	GameConfig.realistic = bool(cfg.get_value("settings", "realistic", false))
	GameConfig.ultra = bool(cfg.get_value("settings", "ultra", true))
	GameConfig.res_idx = int(cfg.get_value("settings", "res", 0))
	AudioManager.set_master_volume(GameConfig.volume)
	GameConfig.apply_display()


func _write() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("economy", "credits", credits)
	cfg.set_value("economy", "skins_owned", skins_owned)
	cfg.set_value("economy", "skin_selected", skin_selected)
	cfg.set_value("stats", "kills", total_kills)
	cfg.set_value("stats", "deaths", total_deaths)
	cfg.set_value("stats", "games", games_played)
	cfg.set_value("stats", "best_wave", best_wave)
	cfg.set_value("neocrom", "crom_id", crom_id)
	cfg.set_value("neocrom", "token", crom_token)
	cfg.set_value("neocrom", "last_bonus", last_bonus_day)
	cfg.set_value("neocrom", "host_ip", host_ip)
	cfg.set_value("neocrom", "host_port", host_port)
	cfg.set_value("settings", "name", GameConfig.player_name)
	cfg.set_value("settings", "sens", GameConfig.sensitivity)
	cfg.set_value("settings", "one_hit", GameConfig.one_hit)
	cfg.set_value("settings", "bots", GameConfig.bot_count)
	cfg.set_value("settings", "volume", GameConfig.volume)
	cfg.set_value("settings", "fov", GameConfig.base_fov)
	cfg.set_value("settings", "shake", GameConfig.shake_enabled)
	cfg.set_value("settings", "fullscreen", GameConfig.is_fullscreen)
	cfg.set_value("settings", "vsync", GameConfig.vsync)
	cfg.set_value("settings", "msaa", GameConfig.msaa)
	cfg.set_value("settings", "glow", GameConfig.glow)
	cfg.set_value("settings", "shadows", GameConfig.shadows)
	cfg.set_value("settings", "dust", GameConfig.dust)
	cfg.set_value("settings", "realistic", GameConfig.realistic)
	cfg.set_value("settings", "ultra", GameConfig.ultra)
	cfg.set_value("settings", "res", GameConfig.res_idx)
	cfg.save(PATH)


func add_credits(n: int) -> void:
	credits = maxi(0, credits + n)
	mark_dirty()


func spend(n: int) -> bool:
	if credits < n:
		return false
	credits -= n
	mark_dirty()
	return true


func owns_skin(id: String) -> bool:
	return skins_owned.has(id)


func buy_skin(id: String, price: int) -> bool:
	if owns_skin(id):
		return true
	if not spend(price):
		return false
	skins_owned.append(id)
	return true


func select_skin(id: String) -> void:
	if owns_skin(id):
		skin_selected = id
		mark_dirty()


func record_kill() -> void:
	total_kills += 1
	mark_dirty()


func record_death() -> void:
	total_deaths += 1
	mark_dirty()


func record_game(wave_reached: int) -> void:
	games_played += 1
	best_wave = maxi(best_wave, wave_reached)
	mark_dirty()
