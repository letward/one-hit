extends Node
## Autoload: zentrale Einstellungen + Start-Parameter.
## Stellt auch sicher, dass alle Input-Actions existieren (robust ohne Editor-Setup).

signal settings_changed

var player_name: String = "Spieler"
var sensitivity: float = 0.0025
var invert_y: bool = false
var one_hit: bool = true
var bot_count: int = 5
var pending_mode: String = "solo" # "solo" | "online"
var arena_seed: int = 0
var mouse_captured: bool = false
var volume: float = 0.8
var base_fov: float = 75.0
var shake_enabled: bool = true
var is_fullscreen: bool = false
var vsync: bool = true
var msaa: int = 1 # 0=Aus, 1=2x, 2=4x, 3=8x
var glow: bool = true
var shadows: bool = true
var dust: bool = true
var realistic: bool = false
var ultra: bool = true
var res_idx: int = 0 # 0=720p, 1=900p, 2=1080p Full HD, 3=Nativ

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i.ZERO, # ZERO = nativ
]
const RES_NAMES: Array[String] = [
	"1280 × 720", "1600 × 900", "1920 × 1080 (Full HD)", "Nativ",
]


func _ready() -> void:
	_ensure_input()
	randomize()
	if arena_seed == 0:
		arena_seed = randi()


func set_captured(captured: bool) -> void:
	mouse_captured = captured
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	# Global: funktioniert in Menü UND Spiel
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()


func toggle_fullscreen() -> void:
	is_fullscreen = not is_fullscreen
	apply_display()
	Save.mark_dirty()


func apply_display() -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var r: Vector2i = RESOLUTIONS[clampi(res_idx, 0, 3)]
		if r == Vector2i.ZERO:
			r = DisplayServer.screen_get_size()
		DisplayServer.window_set_size(r)
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _ensure_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("jump", [KEY_SPACE])
	_key("interact", [KEY_E])
	_key("reload", [KEY_R])
	_key("weapon_1", [KEY_1])
	_key("weapon_2", [KEY_2])
	_key("weapon_3", [KEY_3])
	_key("weapon_4", [KEY_4])
	_key("weapon_5", [KEY_5])
	_key("weapon_6", [KEY_6])
	_key("pause", [KEY_ESCAPE])
	_key("shop", [KEY_B])
	_key("fps", [KEY_F3])
	_key("overlay", [KEY_F4])
	_key("fullscreen", [KEY_F11])
	_mouse("fire", [MOUSE_BUTTON_LEFT])
	_mouse("aim", [MOUSE_BUTTON_RIGHT])


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _mouse(action: String, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for b in buttons:
		var ev := InputEventMouseButton.new()
		ev.button_index = b
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
