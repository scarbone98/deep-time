class_name Run
extends RefCounted
## What survives a scene reload: which level you're on, what's unlocked,
## and best times, saved to user:// (IndexedDB on the web).

const PATH := "user://deeptime.cfg"

static var level := 1
static var autostart := false
static var unlocked := 1
static var best := {}
static var player_name := ""
static var _loaded := false


static func load_save() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		unlocked = int(c.get_value("run", "unlocked", 1))
		best = c.get_value("run", "best", {})
		player_name = str(c.get_value("run", "name", ""))


static func save() -> void:
	var c := ConfigFile.new()
	c.set_value("run", "unlocked", unlocked)
	c.set_value("run", "best", best)
	c.set_value("run", "name", player_name)
	c.save(PATH)


## Returns true when this is a new best.
static func record(lvl: int, secs: float) -> bool:
	unlocked = maxi(unlocked, mini(lvl + 1, Eras.COUNT))
	var better := not best.has(lvl) or secs < float(best[lvl])
	if better:
		best[lvl] = secs
	save()
	return better


static func clock(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]
