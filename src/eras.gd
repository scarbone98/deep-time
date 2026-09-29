class_name Eras
extends RefCounted
## One entry per level: the look, the sound, the shot list, the words.

const COUNT := 2


static func get_era(n: int) -> Dictionary:
	if n == 2:
		return permian()
	return carboniferous()


static func carboniferous() -> Dictionary:
	return {
		"id": "carboniferous",
		"title": "THE COAL FOREST",
		"date": "CARBONIFEROUS  -307,000,000",
		"intro": "307 million years before anyone.\nFilm what lives here. Then find the way through.\n\nIt cannot see you. It feels you move.",
		"tip": "it can't see you.  it feels you move.",
		"fog": Color(0.16, 0.19, 0.155),
		"fog_density": 0.05,
		"ambient": Color(0.32, 0.4, 0.32),
		"ambient_energy": 0.8,
		"sun": Color(0.75, 0.88, 0.78),
		"sun_energy": 0.55,
		"sun_rot": Vector3(-50, 35, 0),
		"loops": [["res://audio/frogswamp.ogg", -6.0], ["res://audio/darkrain.ogg", -15.0]],
		"shots": [
			{"id": "fly", "name": "MEGANEURA", "need": 2.0, "range": 7.0},
			{"id": "eryops", "name": "ERYOPS", "need": 2.0, "range": 16.0},
			{"id": "scorp", "name": "PULMONOSCORPIUS", "need": 2.0, "range": 10.0},
			{"id": "hunter", "name": "ARTHROPLEURA", "need": 3.0, "range": 14.0},
		],
		"exit": {"wall": Color(0.74, 0.66, 0.36), "wall2": Color(0.68, 0.6, 0.31), "floor": Color(0.52, 0.46, 0.28),
			"light": Color(1.0, 0.95, 0.75), "door": Color(1.0, 0.9, 0.55)},
	}


static func permian() -> Dictionary:
	return {
		"id": "permian",
		"title": "THE RED WASTE",
		"date": "PERMIAN  -259,000,000",
		"intro": "Seven million years before the world nearly ends.\nFilm what lives here. Then find the way through.\n\nIt cannot hear you. It sees everything. Keep rock between you.",
		"tip": "it can't hear you.  don't let it see you.",
		"fog": Color(0.42, 0.24, 0.15),
		"fog_density": 0.022,
		"ambient": Color(0.5, 0.36, 0.34),
		"ambient_energy": 0.55,
		"sun": Color(1.0, 0.58, 0.34),
		"sun_energy": 1.3,
		"sun_rot": Vector3(-24, 70, 0),
		"loops": [["res://audio/desertwind.ogg", -5.0], ["res://audio/postdrone.ogg", -14.0]],
		"shots": [
			{"id": "scuto", "name": "SCUTOSAURUS", "need": 2.0, "range": 22.0},
			{"id": "dicy", "name": "DICYNODON", "need": 2.0, "range": 12.0},
			{"id": "hunter", "name": "INOSTRANCEVIA", "need": 3.0, "range": 18.0},
		],
		"exit": {"wall": Color(0.82, 0.86, 0.85), "wall2": Color(0.74, 0.8, 0.8), "floor": Color(0.62, 0.72, 0.74),
			"light": Color(0.8, 0.95, 1.0), "door": Color(0.75, 0.95, 1.0)},
	}
