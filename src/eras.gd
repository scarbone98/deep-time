class_name Eras
extends RefCounted
## One entry per level: the look, the sound, the shot list, the words.

const COUNT := 3  # eras you can drop into; the hub is level 0


## Eras open up as the run goes on: Hell Creek waits for your first quota.
static func unlocked(n: int, q: Dictionary) -> bool:
	return n - 1 <= int(q.get("round", 1))


## Every drop comes with conditions, forecast on the console. They depend
## only on the era and where the run is, so every machine agrees.
const CONDITIONS := [
	{"id": "clear", "name": "CLEAR", "about": "nothing out of the ordinary", "mult": 1.0, "w": 3},
	{"id": "fog", "name": "PEA-SOUP FOG", "about": "you'll hear it before you see it", "mult": 1.2, "w": 2},
	{"id": "night", "name": "NIGHT", "about": "bring the lamp", "mult": 1.3, "w": 2},
	{"id": "storm", "name": "STORM", "about": "rain drowns out your footsteps. lightning doesn't", "mult": 1.25, "w": 2},
	{"id": "restless", "name": "RESTLESS", "about": "the hunters are awake, and there are more of them", "mult": 1.5, "w": 1},
	{"id": "bountiful", "name": "BOUNTIFUL", "about": "more to find, and more things guarding it", "mult": 1.0, "w": 1},
]


static func condition(n: int, q: Dictionary) -> Dictionary:
	var h := hash([n, int(q.get("round", 1)), int(q.get("left", 3)), int(q.get("days", 0))])
	var total := 0
	for c in CONDITIONS:
		total += int(c.w)
	var pick := absi(h) % total
	for c in CONDITIONS:
		pick -= int(c.w)
		if pick < 0:
			return c
	return CONDITIONS[0]


static func get_era(n: int) -> Dictionary:
	if n == 0:
		return hub()
	if n == 2:
		return permian()
	if n == 3:
		return cretaceous()
	return carboniferous()


static func hub() -> Dictionary:
	return {
		"id": "hub",
		"title": "THE CHRONO HUB",
		"date": "CHRONO HUB  -  NOW-ISH",
		"intro": "",
		"tip": "",
		"fog": Color(0.1, 0.07, 0.22),
		"fog_density": 0.003,
		"ambient": Color(0.85, 0.8, 1.0),
		"ambient_energy": 1.6,
		"sun": Color(1.0, 0.9, 0.95),
		"sun_energy": 1.3,
		"sun_rot": Vector3(-55, 30, 0),
		"loops": [["res://audio/postdrone.ogg", -24.0], ["res://audio/desertwind.ogg", -40.0]],
		"loot": [],
		"exit": {},
	}


static func carboniferous() -> Dictionary:
	return {
		"id": "carboniferous",
		"title": "THE COAL FOREST",
		"date": "CARBONIFEROUS  -307,000,000",
		"intro": "307 million years before anyone.\nGrab what you can. Get back through the rift.\n\nIt cannot see you. It feels you move.",
		"tip": "it can't see you.  it feels you move.",
		"fog": Color(0.16, 0.19, 0.155),
		"fog_density": 0.05,
		"ambient": Color(0.32, 0.4, 0.32),
		"ambient_energy": 0.8,
		"sun": Color(0.75, 0.88, 0.78),
		"sun_energy": 0.55,
		"sun_rot": Vector3(-50, 35, 0),
		"loops": [["res://audio/frogswamp.ogg", -6.0], ["res://audio/darkrain.ogg", -15.0]],
		"blurb": "A drowned coal forest. Giant bugs.\nIts nest eggs are worth the most.",
		# where: nest (by the hunter's lair; taking one enrages it), pool, near_pool, scatter
		"loot": [
			{"id": "arthro_egg", "name": "ARTHROPLEURA EGG", "value": 150, "weight": 2.0, "where": "nest", "count": 4},
			{"id": "eryops_spawn", "name": "ERYOPS SPAWN", "value": 70, "weight": 1.0, "where": "near_pool", "count": 3},
			{"id": "amber", "name": "AMBER", "value": 45, "weight": 0.5, "where": "scatter", "count": 6},
			{"id": "wing", "name": "MEGANEURA WING", "value": 30, "weight": 0.5, "where": "scatter", "count": 4},
			{"id": "cone", "name": "SCALE-TREE CONE", "value": 15, "weight": 0.5, "where": "scatter", "count": 8},
			{"id": "chrono_core", "name": "CHRONO CORE", "value": 240, "weight": 2.2, "where": "outpost", "count": 2},
			{"id": "lost_tape", "name": "LOST TAPE", "value": 65, "weight": 0.5, "where": "outpost", "count": 3},
			{"id": "badge", "name": "BUREAU BADGE", "value": 40, "weight": 0.5, "where": "camp", "count": 4},
			{"id": "lost_tape", "name": "LOST TAPE", "value": 65, "weight": 0.5, "where": "camp", "count": 2},
		],
		"exit": {"wall": Color(0.74, 0.66, 0.36), "wall2": Color(0.68, 0.6, 0.31), "floor": Color(0.52, 0.46, 0.28),
			"light": Color(1.0, 0.95, 0.75), "door": Color(1.0, 0.9, 0.55)},
	}


static func permian() -> Dictionary:
	return {
		"id": "permian",
		"title": "THE RED WASTE",
		"date": "PERMIAN  -259,000,000",
		"intro": "Seven million years before the world nearly ends.\nGrab what you can. Get back through the rift.\n\nIt cannot hear you. It sees everything. Keep rock between you.",
		"tip": "it can't hear you.  don't let it see you.",
		"fog": Color(0.42, 0.24, 0.15),
		"fog_density": 0.022,
		"ambient": Color(0.5, 0.36, 0.34),
		"ambient_energy": 0.55,
		"sun": Color(1.0, 0.58, 0.34),
		"sun_energy": 1.3,
		"sun_rot": Vector3(-24, 70, 0),
		"loops": [["res://audio/desertwind.ogg", -5.0], ["res://audio/postdrone.ogg", -14.0]],
		"blurb": "Red dunes and stone. It hunts by sight.\nBigger eggs, less cover.",
		"loot": [
			{"id": "scuto_egg", "name": "SCUTOSAURUS EGG", "value": 170, "weight": 2.5, "where": "nest", "count": 4},
			{"id": "dicy_egg", "name": "DICYNODON EGG", "value": 85, "weight": 1.0, "where": "burrow", "count": 4},
			{"id": "tooth", "name": "GORGON TOOTH", "value": 60, "weight": 0.5, "where": "bones", "count": 4},
			{"id": "amber", "name": "AMBER", "value": 45, "weight": 0.5, "where": "scatter", "count": 5},
			{"id": "leaf", "name": "GLOSSOPTERIS FOSSIL", "value": 25, "weight": 0.5, "where": "scatter", "count": 7},
			{"id": "chrono_core", "name": "CHRONO CORE", "value": 240, "weight": 2.2, "where": "outpost", "count": 2},
			{"id": "lost_tape", "name": "LOST TAPE", "value": 65, "weight": 0.5, "where": "outpost", "count": 3},
			{"id": "badge", "name": "BUREAU BADGE", "value": 40, "weight": 0.5, "where": "camp", "count": 4},
			{"id": "lost_tape", "name": "LOST TAPE", "value": 65, "weight": 0.5, "where": "camp", "count": 2},
		],
		"exit": {"wall": Color(0.82, 0.86, 0.85), "wall2": Color(0.74, 0.8, 0.8), "floor": Color(0.62, 0.72, 0.74),
			"light": Color(0.8, 0.95, 1.0), "door": Color(0.75, 0.95, 1.0)},
	}


static func cretaceous() -> Dictionary:
	return {
		"id": "cretaceous",
		"title": "HELL CREEK",
		"date": "CRETACEOUS  -66,000,000",
		"blurb": "Dinosaurs. Raptors hunt in pairs, by sight and sound.\nThe big one only sees you move.",
		"intro": "The last summer of the dinosaurs.\nGrab what you can. Get back through the rift.\n\nThe raptors hear you and see you.\nThe big one only sees what moves.",
		"tip": "if the ground shakes: stand still.",
		"fog": Color(0.2, 0.24, 0.2),
		"fog_density": 0.035,
		"ambient": Color(0.42, 0.5, 0.4),
		"ambient_energy": 0.8,
		"sun": Color(1.0, 0.85, 0.6),
		"sun_energy": 0.8,
		"sun_rot": Vector3(-30, 140, 0),
		"loops": [["res://audio/junglenight.ogg", -7.0], ["res://audio/darkrain.ogg", -18.0]],
		"loot": [
			{"id": "trike_egg", "name": "TRICERATOPS EGG", "value": 190, "weight": 2.5, "where": "nest", "count": 4},
			{"id": "rex_tooth", "name": "T. REX TOOTH", "value": 120, "weight": 0.5, "where": "bones", "count": 3},
			{"id": "feather", "name": "RAPTOR FEATHER", "value": 45, "weight": 0.5, "where": "scatter", "count": 5},
			{"id": "amber", "name": "AMBER", "value": 45, "weight": 0.5, "where": "scatter", "count": 5},
			{"id": "ammonite", "name": "AMMONITE", "value": 35, "weight": 1.0, "where": "near_pool", "count": 4},
			{"id": "flower", "name": "FIRST FLOWER", "value": 20, "weight": 0.5, "where": "scatter", "count": 6},
			{"id": "chrono_core", "name": "CHRONO CORE", "value": 240, "weight": 2.2, "where": "outpost", "count": 2},
			{"id": "lost_tape", "name": "LOST TAPE", "value": 65, "weight": 0.5, "where": "outpost", "count": 3},
			{"id": "badge", "name": "BUREAU BADGE", "value": 40, "weight": 0.5, "where": "camp", "count": 4},
			{"id": "lost_tape", "name": "LOST TAPE", "value": 65, "weight": 0.5, "where": "camp", "count": 2},
		],
		"exit": {"wall": Color(0.55, 0.7, 0.62), "wall2": Color(0.5, 0.64, 0.57), "floor": Color(0.35, 0.36, 0.4),
			"light": Color(0.85, 1.0, 0.9), "door": Color(0.8, 1.0, 0.85)},
	}
