class_name Run
extends RefCounted
## What survives a scene reload and a closed tab: where you are (the hub is
## level 0), your money, what you own, what you're wearing, best hauls.
## Saved to user:// (IndexedDB on the web).

const PATH := "user://deeptime.cfg"

static var level := 0
static var autostart := false
static var titled := false
static var booted := false  # dev flags only apply to the first load
static var money := 0
static var owned := ["suit:0", "suit:1", "suit:2", "suit:3", "hat:none", "face:none"]
static var look := {"suit": "0", "hat": "none", "face": "none"}
static var best := {}
static var player_name := ""
static var last_haul := -1
static var _loaded := false


static func load_save() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		money = int(c.get_value("run", "money", 0))
		var o: Array = c.get_value("run", "owned", [])
		for k in o:
			if not owned.has(k):
				owned.append(k)
		look = Shop.clean_look(c.get_value("run", "look", look))
		best = c.get_value("run", "best", {})
		player_name = str(c.get_value("run", "name", ""))


static func save() -> void:
	var c := ConfigFile.new()
	c.set_value("run", "money", money)
	c.set_value("run", "owned", owned)
	c.set_value("run", "look", look)
	c.set_value("run", "best", best)
	c.set_value("run", "name", player_name)
	c.save(PATH)


static func owns(kind: String, id: String) -> bool:
	return owned.has(kind + ":" + id)


static func buy(kind: String, id: String) -> bool:
	var it := Shop.find(kind, id)
	if it.is_empty() or owns(kind, id) or money < int(it.cost):
		return false
	money -= int(it.cost)
	owned.append(kind + ":" + id)
	save()
	return true


## Paid out after a drop. Returns true for a new best haul on that era.
static func payout(lvl: int, haul: int) -> bool:
	money += haul
	last_haul = haul
	var better := haul > int(best.get(lvl, 0))
	if better:
		best[lvl] = haul
	save()
	return better


static func cash(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "$" + s + out


static func clock(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]
