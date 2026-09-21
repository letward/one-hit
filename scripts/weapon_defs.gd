class_name WeaponDefs
extends RefCounted
## Zentrale Waffen-Definitionen: 6 Typen, klar unterscheidbar.

const ORDER: Array[String] = ["pistole", "streu", "rail", "wasp", "falke", "mauer"]

const PRICE: Dictionary = {
	"pistole": 0, "streu": 150, "rail": 500,
	"wasp": 300, "falke": 450, "mauer": 600,
}

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
		"desc": "Langsam, durchschlägt Gegner.",
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
	"wasp": {
		"name": "Wasp-9 SMG",
		"desc": "Vollauto-Nahkampf-Säge.",
		"damage": 16.0,
		"interval": 0.11,
		"auto": true,
		"mag": 30,
		"reload": 1.6,
		"spread_deg": 1.7,
		"pellets": 1,
		"range": 45.0,
		"kick": 0.008,
		"tracer": Color(0.65, 1.0, 0.25),
		"gun_color": Color(0.45, 0.7, 0.2),
	},
	"falke": {
		"name": "Falke DMR",
		"desc": "Präzise, hart auf Distanz.",
		"damage": 70.0,
		"interval": 0.5,
		"auto": false,
		"mag": 10,
		"reload": 1.5,
		"spread_deg": 0.3,
		"pellets": 1,
		"range": 100.0,
		"kick": 0.03,
		"tracer": Color(0.55, 0.75, 1.0),
		"gun_color": Color(0.35, 0.5, 0.85),
	},
	"mauer": {
		"name": "Mauer LMG",
		"desc": "60 Schuss Dauerfeuer.",
		"damage": 22.0,
		"interval": 0.16,
		"auto": true,
		"mag": 60,
		"reload": 2.6,
		"spread_deg": 2.2,
		"pellets": 1,
		"range": 55.0,
		"kick": 0.014,
		"tracer": Color(1.0, 0.85, 0.3),
		"gun_color": Color(0.7, 0.55, 0.2),
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA.get(id, DATA["pistole"])


static func price_of(id: String) -> int:
	return int(PRICE.get(id, 0))


static func slot_of(id: String) -> int:
	return ORDER.find(id) + 1
