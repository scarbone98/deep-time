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
static var sens := 1.0  # mouse / thumb look sensitivity
static var gear := {"pack": 0, "battery": 0}  # permanent upgrades
static var decoys := 0
## The Chrono Bureau's quota: bank the target within three drops, or
## you're fired and your credits are wiped (cosmetics stay).
static var quota := new_quota()
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
		sens = float(c.get_value("run", "sens", 1.0))
		var g: Dictionary = c.get_value("run", "gear", {})
		for k in gear:
			gear[k] = int(g.get(k, 0))
		decoys = int(c.get_value("run", "decoys", 0))
		var q: Dictionary = c.get_value("run", "quota", {})
		if q.has("target"):
			quota = q


static func save() -> void:
	var c := ConfigFile.new()
	c.set_value("run", "money", money)
	c.set_value("run", "owned", owned)
	c.set_value("run", "look", look)
	c.set_value("run", "best", best)
	c.set_value("run", "name", player_name)
	c.set_value("run", "sens", sens)
	c.set_value("run", "gear", gear)
	c.set_value("run", "decoys", decoys)
	c.set_value("run", "quota", quota)
	c.save(PATH)


## Your look plus your upgrades: what friends' games and the server need.
static func net_look() -> Dictionary:
	var l := look.duplicate()
	l.pack = gear.pack
	l.battery = gear.battery
	return l


## Buy a gear item. Upgrades go up a level; decoys stack.
static func buy_gear(id: String) -> String:
	var it := Shop.find("gear", id)
	if it.is_empty():
		return "?"
	var cost := Shop.gear_cost(id)
	if cost < 0:
		return "maxed out"
	if money < cost:
		return "need %s more" % cash(cost - money)
	money -= cost
	if id == "decoy":
		decoys += 1
	else:
		gear[id] = int(gear[id]) + 1
	save()
	return ""


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


static func new_quota() -> Dictionary:
	return {"target": 300, "banked": 0, "left": 3, "round": 1}


## Count a drop's haul against a quota. Returns "met", "fired" or "".
static func quota_step(q: Dictionary, haul: int) -> String:
	q.banked = int(q.banked) + haul
	q.left = int(q.left) - 1
	if int(q.banked) >= int(q.target):
		q.round = int(q.round) + 1
		q.target = int(int(q.target) * 1.6 + 100)
		q.banked = 0
		q.left = 3
		return "met"
	if int(q.left) <= 0:
		var fresh := new_quota()
		for k in fresh:
			q[k] = fresh[k]
		return "fired"
	return ""


static func quota_line(q: Dictionary) -> String:
	return "QUOTA  %s / %s   %d drop%s left" % [cash(int(q.banked)), cash(int(q.target)), int(q.left), "" if int(q.left) == 1 else "s"]
