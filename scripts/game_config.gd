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
	_key("pause", [KEY_ESCAPE])
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
