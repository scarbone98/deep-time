class_name Shop
extends RefCounted
## Everything you can buy for your time-traveller, with haul money, at the
## hub kiosk. Cosmetic only. Owned items and your look live in Run (saved on
## this device); your look travels with you into co-op rooms.

const SUITS := [
	{"id": "0", "name": "SUNNY", "color": Color(1.0, 0.78, 0.25), "cost": 0},
	{"id": "1", "name": "CHERRY", "color": Color(0.95, 0.35, 0.35), "cost": 0},
	{"id": "2", "name": "SKY", "color": Color(0.35, 0.62, 1.0), "cost": 0},
	{"id": "3", "name": "FERN", "color": Color(0.4, 0.82, 0.45), "cost": 0},
	{"id": "4", "name": "BUBBLEGUM", "color": Color(1.0, 0.55, 0.8), "cost": 60},
	{"id": "5", "name": "GRAPE", "color": Color(0.62, 0.42, 0.95), "cost": 60},
	{"id": "6", "name": "MINT", "color": Color(0.5, 0.95, 0.82), "cost": 80},
	{"id": "7", "name": "SNOW", "color": Color(0.95, 0.96, 1.0), "cost": 120},
	{"id": "8", "name": "MIDNIGHT", "color": Color(0.18, 0.18, 0.3), "cost": 150},
	{"id": "9", "name": "GOLD", "color": Color(1.0, 0.86, 0.35), "cost": 500},
]
const HATS := [
	{"id": "none", "name": "NO HAT", "cost": 0},
	{"id": "beanie", "name": "BEANIE", "cost": 40},
	{"id": "party", "name": "PARTY HAT", "cost": 60},
	{"id": "propeller", "name": "PROPELLER CAP", "cost": 120},
	{"id": "cowboy", "name": "COWBOY HAT", "cost": 180},
	{"id": "tophat", "name": "TOP HAT", "cost": 250},
	{"id": "dino", "name": "DINO HOOD", "cost": 400},
	{"id": "halo", "name": "HALO", "cost": 500},
	{"id": "crown", "name": "CROWN", "cost": 900},
]
const FACES := [
	{"id": "none", "name": "BARE FACE", "cost": 0},
	{"id": "glasses", "name": "ROUND SPECS", "cost": 50},
	{"id": "mustache", "name": "MUSTACHE", "cost": 80},
	{"id": "mask", "name": "DUST MASK", "cost": 90},
	{"id": "shades", "name": "SHADES", "cost": 150},
]


static func tab(kind: String) -> Array:
	return {"suit": SUITS, "hat": HATS, "face": FACES}[kind]


static func find(kind: String, id: String) -> Dictionary:
	for it in tab(kind):
		if it.id == id:
			return it
	return {}


static func suit_color(id: String) -> Color:
	var it := find("suit", id)
	return it.color if not it.is_empty() else SUITS[0].color


## Only known ids survive (looks arrive over the network).
static func clean_look(look: Variant) -> Dictionary:
	var out := {"suit": "0", "hat": "none", "face": "none"}
	if look is Dictionary:
		for k in out:
			if look.has(k) and not find(k, str(look[k])).is_empty():
				out[k] = str(look[k])
	return out
