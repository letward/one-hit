extends Node
## Autoload: simples self-hosted Online-Spiel via ENet.
## Einer hostet (Port freigeben / gleiche LAN), Freunde joinen per IP + Port.

signal lobby_changed
signal connection_failed
signal server_disconnected

const DEFAULT_PORT = 7777
const MAX_PLAYERS = 8

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var is_online: bool = false
var players: Dictionary = {} # peer_id -> player_name
var my_name: String = "Spieler"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_lost)


func reset() -> void:
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	is_online = false
	lobby_changed.emit()


func host_game(port: int, player_name: String) -> String:
	reset()
	my_name = player_name.strip_edges() if player_name.strip_edges() != "" else "Host"
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "Host fehlgeschlagen (Port belegt?): %s" % err
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_online = true
	players[multiplayer.get_unique_id()] = my_name
	lobby_changed.emit()
	return ""


func join_game(ip: String, port: int, player_name: String) -> String:
	reset()
	my_name = player_name.strip_edges() if player_name.strip_edges() != "" else "Gast"
	peer = ENetMultiplayerPeer.new()
	var clean_ip := ip.strip_edges() if ip.strip_edges() != "" else "127.0.0.1"
	var err := peer.create_client(clean_ip, port)
	if err != OK:
		return "Join fehlgeschlagen: %s" % err
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = false
	return "" # Lobby-Update kommt nach connect


func lobby_list() -> Array:
	var out: Array = []
	var ids := players.keys()
	ids.sort()
	for id in ids:
		out.append({"id": id, "name": str(players.get(id, "?")), "host": id == 1})
	return out


func start_online_game() -> void:
	if not is_host:
		return
	var seed_value := randi()
	rpc("rpc_start_game", seed_value)
	_do_start(seed_value)


@rpc("authority", "call_local", "reliable")
func rpc_start_game(seed_value: int) -> void:
	_do_start(seed_value)


func _do_start(seed_value: int) -> void:
	GameConfig.pending_mode = "online"
	GameConfig.arena_seed = seed_value
	get_tree().change_scene_to_file("res://scenes/arena.tscn")


func _on_peer_connected(_id: int) -> void:
	# Clients melden sich per Hello beim Host; der Host verteilt die Lobby.
	pass


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	if is_host and is_online:
		rpc("rpc_lobby_full", players)
	lobby_changed.emit()


func _on_connected_ok() -> void:
	rpc_id(1, "rpc_hello", my_name)


func _on_connected_fail() -> void:
	reset()
	connection_failed.emit()


func _on_server_lost() -> void:
	reset()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func rpc_hello(player_name: String) -> void:
	# Nur der Host verwaltet die Lobby und verteilt sie an alle
	if not is_host:
		return
	players[multiplayer.get_remote_sender_id()] = player_name.strip_edges()
	rpc("rpc_lobby_full", players)
	lobby_changed.emit()


@rpc("authority", "reliable")
func rpc_lobby_full(full: Dictionary) -> void:
	players.clear()
	for k in full.keys():
		players[int(k)] = str(full[k])
	lobby_changed.emit()
