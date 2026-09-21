class_name TexFactory
extends RefCounted
## Prozedurale PBR-Texturen (Albedo/Roughness/Normal), einmal generiert, dann cached.
## Keine externen Assets nötig. Muster neutral-grau -> Tönung via albedo_color.

static var _tex_cache: Dictionary = {}


static func mat(kind: String, tint: Color, uv: float = 4.0, metallic: float = 0.0, rough: float = 0.9) -> StandardMaterial3D:
	var t: Dictionary = tex(kind)
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = t["alb"]
	m.roughness = rough
	m.roughness_texture = t["rgh"]
	m.metallic = metallic
	m.normal_texture = t["nrm"]
	m.normal_scale = 0.8
	m.uv1_scale = Vector3(uv, uv, uv)
	return m


static func tex(kind: String) -> Dictionary:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var size := 256 if kind == "ground" else 128
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rgh := Image.create(size, size, false, Image.FORMAT_RGB8)
	var h := PackedFloat32Array()
	h.resize(size * size)
	var n1 := FastNoiseLite.new()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.045 if kind == "ground" else 0.09
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.35
	var n3 := FastNoiseLite.new()
	n3.seed = 1234
	n3.frequency = 0.9
	for y in size:
		for x in size:
			var i := y * size + x
			var base := 0.5 + 0.5 * n1.get_noise_2d(float(x), float(y))
			var detail := 0.5 + 0.5 * n2.get_noise_2d(float(x), float(y))
			var grain := 0.5 + 0.5 * n3.get_noise_2d(float(x), float(y))
			var v := 0.0
			var r := 0.85
			match kind:
				"ground":
					# Asphalt: dunkel, fleckig, raue Körnung
					v = 0.32 + base * 0.22 + (detail - 0.5) * 0.12
					if grain > 0.93:
						v += 0.25 # helle Steinchen
					r = 0.9 + (detail - 0.5) * 0.15
					h[i] = base * 0.6 + detail * 0.4
				"concrete":
					# Beton: mittelgrau, weiche Wolken + feine Poren
					v = 0.52 + (base - 0.5) * 0.28 + (detail - 0.5) * 0.1
					if grain < 0.06:
						v -= 0.2 # Poren
					r = 0.85 + (base - 0.5) * 0.2
					h[i] = base * 0.7 + detail * 0.3
				"metal":
					# Gebürstetes Metall: horizontale Linien + Kratzer
					var lines := 0.5 + 0.5 * sin(float(y) * 1.7 + base * 6.0)
					v = 0.55 + (lines - 0.5) * 0.16 + (detail - 0.5) * 0.08
					if grain > 0.96:
						v -= 0.3 # Kratzer
					r = 0.45 + (lines - 0.5) * 0.25
					h[i] = lines * 0.5 + detail * 0.5
				_: # "fabric": Stoff, feines Gewebe
					var weave := 0.5 + 0.5 * sin(float(x) * 2.4) * sin(float(y) * 2.4)
					v = 0.5 + (base - 0.5) * 0.22 + (weave - 0.5) * 0.1
					r = 0.95
					h[i] = weave * 0.4 + base * 0.6
			var b := clampi(int(v * 255.0), 0, 255)
			alb.set_pixel(x, y, Color8(b, b, b))
			var rb := clampi(int(clampf(r, 0.0, 1.0) * 255.0), 0, 255)
			rgh.set_pixel(x, y, Color8(rb, rb, rb))
	var nrm := _normal_from_height(h, size, 1.6)
	alb.generate_mipmaps()
	rgh.generate_mipmaps()
	var out := {
		"alb": ImageTexture.create_from_image(alb),
		"rgh": ImageTexture.create_from_image(rgh),
		"nrm": ImageTexture.create_from_image(nrm),
	}
	_tex_cache[kind] = out
	return out


static func _normal_from_height(h: PackedFloat32Array, size: int, strength: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var xm := h[y * size + maxi(x - 1, 0)]
			var xp := h[y * size + mini(x + 1, size - 1)]
			var ym := h[maxi(y - 1, 0) * size + x]
			var yp := h[mini(y + 1, size - 1) * size + x]
			var dx := (xp - xm) * strength
			var dy := (yp - ym) * strength
			var inv := 1.0 / sqrt(dx * dx + dy * dy + 1.0)
			img.set_pixel(x, y, Color8(
				int((-dx * inv * 0.5 + 0.5) * 255.0),
				int((-dy * inv * 0.5 + 0.5) * 255.0),
				int((inv * 0.5 + 0.5) * 255.0)))
	img.generate_mipmaps()
	return img
