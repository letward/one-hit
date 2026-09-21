extends Node
## Autoload: prozedurale SFX ohne Assets (WAV-Synthese, kleiner Player-Pool).

var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
const MIX = 22050


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func set_master_volume(v: float) -> void:
	var db := linear_to_db(clampf(v, 0.001, 1.0))
	if v <= 0.01:
		db = -60.0
	AudioServer.set_bus_volume_db(0, db)


func _play(stream: AudioStreamWAV, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch * randf_range(0.96, 1.04)
			p.play()
			return
	# Fallback: ältesten Player wiederverwenden
	var p0: AudioStreamPlayer = _pool[0]
	p0.stream = stream
	p0.volume_db = volume_db
	p0.pitch_scale = pitch
	p0.play()


func _synth(key: String, dur: float, fn: Callable) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var n := int(MIX * dur)
	var data := PackedByteArray()
	data.resize(n)
	for i in n:
		var t := float(i) / MIX
		var v: float = clampf(fn.call(t, float(i) / n), -1.0, 1.0)
		data[i] = int((v * 0.5 + 0.5) * 255.0)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = MIX
	w.data = data
	_cache[key] = w
	return w


func play_shoot(weapon_id: String) -> void:
	match weapon_id:
		"pistole", "wasp":
			_play(_synth("sh_p", 0.14, func(t: float, k: float) -> float:
				return (1.0 - k) * (0.7 * sign(sin(t * 900.0)) + 0.3 * randf_range(-1.0, 1.0))), -8.0, 1.15 if weapon_id == "wasp" else 1.0)
		"streu", "mauer":
			_play(_synth("sh_s", 0.3, func(t: float, k: float) -> float:
				return (1.0 - k) * (0.5 * sign(sin(t * 300.0)) + 0.5 * randf_range(-1.0, 1.0))), -4.0, 1.1 if weapon_id == "mauer" else 0.9)
		"rail", "falke":
			_play(_synth("sh_r", 0.5, func(t: float, k: float) -> float:
				return (1.0 - k) * sin(t * 2400.0 - k * 12.0)), -6.0, 1.25 if weapon_id == "falke" else 1.0)


func play_hit() -> void:
	_play(_synth("hit", 0.08, func(t: float, k: float) -> float:
		return (1.0 - k) * sign(sin(t * 2200.0))), -10.0, 1.0)


func play_kill() -> void:
	_play(_synth("kill", 0.25, func(t: float, k: float) -> float:
		return (1.0 - k) * sin(t * (600.0 + k * 900.0))), -8.0, 1.0)


func play_hurt() -> void:
	_play(_synth("hurt", 0.2, func(t: float, k: float) -> float:
		return (1.0 - k) * sin(t * 220.0)), -8.0, 0.8)


func play_pickup() -> void:
	_play(_synth("pick", 0.18, func(t: float, k: float) -> float:
		return (1.0 - k) * sin(t * (700.0 + t * 2500.0))), -10.0, 1.0)


func play_empty() -> void:
	_play(_synth("empty", 0.06, func(t: float, k: float) -> float:
		return (1.0 - k) * sign(sin(t * 3200.0)) * 0.5), -14.0, 1.0)


func play_reload() -> void:
	_play(_synth("rel", 0.16, func(t: float, k: float) -> float:
		return (1.0 - k) * sign(sin(t * 1400.0)) * 0.6), -12.0, 1.0)


func play_step() -> void:
	_play(_synth("step", 0.07, func(t: float, k: float) -> float:
		return (1.0 - k) * randf_range(-0.4, 0.4)), -20.0, randf_range(0.9, 1.1))


func play_explosion() -> void:
	_play(_synth("boom", 0.6, func(t: float, k: float) -> float:
		return (1.0 - k) * (sin(t * (160.0 - 100.0 * k)) * 0.8 + randf_range(-0.5, 0.5))), -4.0, 1.0)
