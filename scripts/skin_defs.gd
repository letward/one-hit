class_name SkinDefs
extends RefCounted
## Skin-Definitionen: Body-Farbe + Akzent (Visier, Crosshair, Namensschild).

const ORDER: Array[String] = ["standard", "abyss", "magma", "venom", "royal", "gold"]

const DATA: Dictionary = {
	"standard": {
		"name": "Standard", "price": 0,
		"body": Color(0.15, 0.55, 0.85), "accent": Color(0.4, 0.9, 1.0),
	},
	"abyss": {
		"name": "Abyss", "price": 200,
		"body": Color(0.05, 0.20, 0.35), "accent": Color(0.2, 1.0, 0.9),
	},
	"magma": {
		"name": "Magma", "price": 350,
		"body": Color(0.40, 0.10, 0.08), "accent": Color(1.0, 0.45, 0.1),
	},
	"venom": {
		"name": "Venom", "price": 350,
		"body": Color(0.08, 0.35, 0.12), "accent": Color(0.45, 1.0, 0.3),
	},
	"royal": {
		"name": "Royal", "price": 600,
		"body": Color(0.20, 0.08, 0.45), "accent": Color(0.7, 0.4, 1.0),
	},
	"gold": {
		"name": "Gold", "price": 1000,
		"body": Color(0.45, 0.32, 0.08), "accent": Color(1.0, 0.8, 0.25),
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA.get(id, DATA["standard"])
