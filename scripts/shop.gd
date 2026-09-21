class_name OHShop
extends CanvasLayer
## Ingame-Item-Shop: Waffen, Heilung, Munition, Max-HP, Schild — gegen Schrott (⚙).
## Solo pausiert das Spiel, online läuft es in Echtzeit weiter.

var _game: OHGame = null
var _root: PanelContainer
var _credits_label: Label
var _items_box: VBoxContainer


func setup(game: OHGame) -> void:
	_game = game
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.custom_minimum_size = Vector2(430, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.15, 0.96)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.35, 0.85, 1.0, 0.35)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	_root.add_theme_stylebox_override("panel", sb)
	add_child(_root)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_root.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "Shop · [B]"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_credits_label = Label.new()
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_credits_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	vb.add_child(_credits_label)
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 5)
	vb.add_child(_items_box)


func open_shop() -> void:
	refresh()
	visible = true


func close_shop() -> void:
	visible = false


func refresh() -> void:
	if _game == null or _game.local_player == null:
		return
	_credits_label.text = "⚙ %d Schrott" % Save.credits
	for ch in _items_box.get_children():
		ch.queue_free()
	var p: OHPlayer = _game.local_player
	for wid in WeaponDefs.ORDER:
		var price := WeaponDefs.price_of(wid)
		if price <= 0:
			continue
		var def: Dictionary = WeaponDefs.get_def(wid)
		_add_row("🔫 " + str(def["name"]), str(def["desc"]), price, p.owned.has(wid),
			func() -> void: _game.buy_offer("weapon", wid))
	_add_row("❤ Feld-Heilung", "Heilt voll", 40, p.hp >= p.max_hp,
		func() -> void: _game.buy_offer("heal", ""))
	_add_row("📦 Munition", "Alle Magazine voll", 30, false,
		func() -> void: _game.buy_offer("ammo", ""))
	_add_row("❤️‍🩹 Max-HP +25", "Mehr Leben (diese Runde, max 200)", 120, p.max_hp >= 200,
		func() -> void: _game.buy_offer("maxhp", ""))
	_add_row("🛡 Schild", "Blockt den nächsten Treffer", 100, p.shield,
		func() -> void: _game.buy_offer("shield", ""))


func _add_row(title: String, desc: String, price: int, owned_or_max: bool, on_buy: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_items_box.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 14)
	info.add_child(t)
	var d := Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", 11)
	d.add_theme_color_override("font_color", Color(0.6, 0.66, 0.74))
	info.add_child(d)
	var b := Button.new()
	if owned_or_max:
		b.text = "✓"
		b.disabled = true
	else:
		b.text = "⚙ %d" % price
		b.disabled = Save.credits < price
		if not b.disabled:
			b.pressed.connect(func() -> void:
				on_buy.call()
				refresh())
	row.add_child(b)
