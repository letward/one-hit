class_name WeaponDefs
extends RefCounted
## Zentrale Waffen-Definitionen. Simpel: 3 Typen, klar unterscheidbar.

const ORDER: Array[String] = ["pistole", "streu", "rail"]

const DATA: Dictionary = {
	"pistole": {
		"name": "P-9 Blaster",
		"desc": "Schnell + präzise. Standard.",
		"damage": 34.0,
		"interval": 0.22,
		"auto": false,
		"mag": 12,
		"reload": 1.1,
		"spread_deg": 0.8,
		"pellets": 1,
		"range": 60.0,
		"kick": 0.012,
		"tracer": Color(0.3, 1.0, 1.0),
		"gun_color": Color(0.2, 0.7, 0.9),
	},
	"streu": {
		"name": "Scatter-6",
		"desc": "Schrot: stark nah, schwach fern.",
		"damage": 13.0,
		"interval": 0.95,
		"auto": false,
		"mag": 6,
		"reload": 1.8,
		"spread_deg": 4.2,
		"pellets": 7,
		"range": 26.0,
		"kick": 0.05,
		"tracer": Color(1.0, 0.6, 0.15),
		"gun_color": Color(0.9, 0.45, 0.15),
	},
	"rail": {
		"name": "Rail OneHit",
		"desc": "Langsam, aber ein Treffer = Kill.",
		"damage": 150.0,
		"interval": 1.30,
		"auto": false,
		"mag": 5,
		"reload": 2.0,
		"spread_deg": 0.1,
		"pellets": 1,
		"range": 120.0,
		"pierce": true,
		"kick": 0.07,
		"tracer": Color(0.7, 0.35, 1.0),
		"gun_color": Color(0.65, 0.3, 1.0),
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA.get(id, DATA["pistole"])


static func slot_of(id: String) -> int:
	return ORDER.find(id) + 1
