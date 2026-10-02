extends Node3D
## DEEP TIME: a time-travelling heist. You start in the Chrono Hub, a little
## station floating outside time. Walk to the TIME CONSOLE to drop into an
## era; grab eggs and valuables while something hunts you; get back out
## through the rift. Whatever the crew brings home is paid out, and the SHOP
## kiosk in the hub turns it into hats.
##
## Level 0 is the hub; 1.. are eras (eras.gd). The same session runs as:
##   solo    one player, everything local (Run carries state across reloads)
##   server  authoritative: players, creatures, loot, deaths, the rift. No
##           view. The Net autoload runs one per room, inside a SubViewport.
##   client  draws the level from the server's snapshots: your own movement
##           is predicted and corrected, friends are Avatars, creatures are
##           puppets, loot moves by event
##
## World, creature and loot placement come from the level seed, so server
## and clients build the same level and every list lines up by index.
##
## Dev flags (URL query on web, `-- key=value` on desktop):
##   play        skip the title card          seed=N   fixed layout
##   level=N     start in that era            mill=D   hunter D m in front
##   exit        start by the rift            light    lamp on
##   freeze      creatures hold still         yaw= / pitch=  look (degrees)
##   die         get caught after 1 s         loot[=N] start next to some loot
##   money=N     set your money               near=eryops|scorp|scuto|dicy (+ neard=m)
##   attract     cabinet video scene (+ ts=)  debug    log positions
##   server [port=N] [mill=D]   run as the co-op server   server=URL   use that server
##   host=NAME [code=ABCD] / join=CODE [name=]   skip the co-op menus
##   bot         walk in circles              emote=N  emote on repeat
##   shop / console   open that panel at start

const SNAP_EVERY := 3  # 20 Hz snapshots
const INPUT_EVERY := 2  # 30 Hz inputs
const EMOTES := {1: "wave", 2: "point", 3: "scream", 4: "flash"}
const REACH := 3.0
const RIFT_TIME := 420.0  # seven minutes, then the rift collapses
const THROW_SPEED := 9.0

var mode := "solo"
var net_room: Dictionary = {}
var level := 0
var seed_ := -1
var my_id := 1
var era: Dictionary
var hub := false

var flags := {}
var sounds := {}
var world: World
var local: Player
var players := {}  # authority: peer id -> Player
var avatars := {}  # client: peer id -> Avatar
var net_players := {}  # client: peer id -> last snapshot entry
var bags := {}  # peer id -> Array of loot indices (clients learn it by event)
var mill: Node3D  # the first hunter
var exit_node: Exit
var hud: Hud
var shop_ui: ShopUI
var flies: Array[Meganeura] = []
var amb: AudioStreamPlayer
var rain: AudioStreamPlayer
var sfx: AudioStreamPlayer
var state := "title"
var state_t := 0.0
var elapsed := 0.0
var next_event := 30.0
var touch := false
var hunters: Array = []
var grazers: Array[Grazer] = []
var dicys: Array[Dicynodon] = []
var eryopses: Array[Eryops] = []
var scorps: Array[Scorpion] = []
var netted: Array = []  # every creature but the hunters, in snapshot order
var loot: Array[Loot] = []
var haul := 0  # the crew's take so far this drop
var nest_total := 0
var nest_taken := 0
var env: Environment
var sun: DirectionalLight3D
var hunter2 := false
var sim_on := false
var tick := 0
var in_seq := 0
var sent := {}  # client: input seq -> where we predicted we were
var spectating := false
var spec_id := 0
var spec_cam: Camera3D
var emote_cool := 0.0
var roster_t := 0.0
var ui := ""  # an open panel: "console", "shop", "coop", "title"
var target_loot: Loot
var target_spot := ""
var warned := false
var end_haul := -1
var decoys_out: Array[Decoy] = []
var strain_sent := 0
var rumble: AudioStreamPlayer
var banked_flash := 0.0
var jumped_since_send := false
var home_value := 0  # carried home through the door this drop
var outpost_tripped := false
var cond: Dictionary = {}  # this drop's conditions (eras.gd)
var herds: Array = []
var compys: Array[Compy] = []
var rift_len := RIFT_TIME
var scan_cd := 0.0
var scan_t := 0.0
var next_stampede := 0.0
var lightning := 0.0
var quota_msg := ""


# ================================================================ setup

func _ready() -> void:
	if mode == "server":
		_ready_server()
		return
	flags = _parse_flags()
	if flags.has("server") and flags.server == "1":
		Net.host_server(int(flags.get("port", "8910")), flags)
		set_process(false)
		set_physics_process(false)
		return
	if Run.booted:
		var keep := {}
		for k in ["server", "touch", "debug", "bot", "autostart", "emote", "yaw", "light", "throwat", "bankat"]:
			if flags.has(k):
				keep[k] = flags[k]
		flags = keep
	Run.booted = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size_changed.connect(_fit)
	_fit()
	_input_map()
	Run.load_save()
	if flags.has("money"):
		Run.money = int(flags.money)
	if flags.has("gear"):  # dev: every tool
		for k in Run.gear:
			Run.gear[k] = 1
	Net.level_start.connect(func() -> void: get_tree().reload_current_scene())
	if Net.online and Net.in_level:
		mode = "client"
		level = Net.level
		seed_ = Net.seed_
		my_id = Net.my_id
		Net.snapshot.connect(_on_snap)
		Net.event.connect(_on_event)
	else:
		level = clampi(int(flags.get("level", str(Run.level))), 0, Eras.COUNT)
		Run.level = level
		seed_ = int(flags.get("seed", str(randi() % 1000000)))
	Net.room_changed.connect(_on_room_changed)
	Net.status.connect(func(t: String) -> void: hud.status(t))
	Net.left.connect(_on_left)
	print("seed ", seed_)
	DinoModel.no_recolour = flags.has("norecolour")
	era = Eras.get_era(level)
	hub = level == 0
	cond = {} if hub else Eras.condition(level, _quota())
	era = _conditioned(era)
	sounds = Synth.all()
	touch = flags.has("touch") or DisplayServer.is_touchscreen_available()
	_build(true)
	var slot := int(Net.members.get(my_id, {}).get("color", 0)) if mode == "client" else 0
	local = _make_player(my_id, true, slot)
	local.bot = flags.has("bot")
	_gear_up(local, Run.net_look())
	bags[my_id] = local.slots
	if exit_node:
		exit_node.player = local
	spec_cam = Camera3D.new()
	spec_cam.fov = 72.0
	spec_cam.far = 160.0
	add_child(spec_cam)

	hud = Hud.new()
	add_child(hud)
	hud.clean = 0.8 if hub else 0.0
	if touch:
		var pad := TouchPad.new()
		pad.player = local
		pad.coop = mode == "client"
		pad.emote.connect(_emote_pressed)
		pad.mic.connect(_toggle_mic)
		pad.use.connect(_use)
		pad.drop.connect(_drop)
		pad.throw.connect(func() -> void: _drop(true))
		pad.swap.connect(func() -> void: _hold((local.held + 1) % local.slots.size()))
		pad.decoy.connect(_throw_decoy)
		pad.tool.connect(_tool)
		hud.add_touch(pad)
		local.touch = pad
	shop_ui = ShopUI.new()
	shop_ui.visible = false
	shop_ui.closed.connect(_close_ui)
	shop_ui.looked.connect(_on_look_changed)
	hud.add_panel(shop_ui)
	# field recordings (CC0, see audio/CREDITS.md)
	amb = _loop_player(era.loops[0][0], era.loops[0][1])
	rain = _loop_player(era.loops[1][0], era.loops[1][1])
	if hub:
		amb.stream = Synth.hub_music()
		amb.volume_db = -8.0
	hud.date.text = era.date + (("   " + str(cond.name)) if not cond.is_empty() and cond.id != "clear" else "")
	sfx = AudioStreamPlayer.new()
	add_child(sfx)
	_update_list()

	if mode == "client":
		world.ground_collider()
		if flags.has("yaw"):
			local.yaw = deg_to_rad(float(flags.yaw))
		if flags.has("light"):
			local.light.visible = true
		state = "loading"
		if not hub:
			hud.show_card("ROOM  " + Net.code, "DROPPING INTO  " + era.title, era.intro, "waiting for the crew...")
		Net.loaded()
		return
	_apply_dev_flags()
	if hub and not Run.titled and not flags.has("play") and not Run.autostart:
		_title()
	else:
		Run.autostart = false
		_start()
	_auto_coop()


func _ready_server() -> void:
	era = Eras.get_era(level)
	hub = level == 0
	cond = {} if hub else Eras.condition(level, net_room.quota)
	era = _conditioned(era)
	sounds = Synth.all()
	_build(false)
	state = "wait"
	if Net.dev.has("mill") and mill:  # dev: start it right by the spawn
		var at := world.spawn + Vector3(float(Net.dev.mill), 0, 0)
		hunters.erase(mill)
		mill.queue_free()
		mill = _spawn_hunter(at, Vector3.LEFT)


## World, light, the rift, every creature and every loot. Deterministic.
func _build(view: bool) -> void:
	world = World.new()
	world.lite = touch
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	if era.has("exit") and not era.exit.is_empty():
		world.look = era.exit
	world.generate(seed_, era.id)
	if view:
		_environment()
	if hub:
		return
	exit_node = Exit.new()
	exit_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(exit_node)
	exit_node.setup(world, sounds, null, era.exit)
	exit_node.activate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 99
	var mstart := _creature_start(rng, 60.0, 85.0)
	var facing := (world.spawn - mstart).normalized().rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
	mill = _spawn_hunter(mstart, facing)
	if era.id == "permian":
		_populate_permian(rng)
	elif era.id == "cretaceous":
		_populate_cretaceous(rng, mstart)
	else:
		_populate_carboniferous(rng)
	netted = []
	netted.append_array(flies)
	netted.append_array(eryopses)
	netted.append_array(scorps)
	netted.append_array(grazers)
	netted.append_array(dicys)
	netted.append_array(compys)
	if mode == "client":
		for c in netted:
			c.puppet = true
	# restless and bountiful drops start with a second hunter already out
	if cond.get("id", "") in ["restless", "bountiful"]:
		var r2 := RandomNumberGenerator.new()
		r2.seed = seed_ + 4242
		hunter2 = true
		_spawn_hunter(_creature_start(r2, 70.0, 110.0), Vector3.FORWARD)
	if cond.get("id", "") == "restless":
		for m in hunters:
			m.hunt_speed += 0.8
			m.drift = minf(0.9, m.drift + 0.25)
	_place_loot(mstart)
	# the crew's best rift stabilizer holds the rift open longer
	var stab := 0
	if mode == "server":
		for m in net_room.members.values():
			stab = maxi(stab, int(m.get("look", {}).get("stabilizer", 0)))
	elif mode == "client":
		for m in Net.members.values():
			stab = maxi(stab, int(m.get("look", {}).get("stabilizer", 0)))
	else:
		stab = int(Run.gear.get("stabilizer", 0))
	rift_len = RIFT_TIME + 60.0 * stab


## Eggs in nests by the hunter's lair (and the herds), spawn by the pools,
## eggs at the burrows, teeth among the bones, the rest scattered.
func _place_loot(lair: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 777
	var nests := [lair]
	for g in grazers:
		var c: Vector3 = g.herd.center
		if nests.size() < 3 and c.distance_to(nests[-1]) > 20.0:
			nests.append(c)
	var pools := world.pools(4) if era.id == "carboniferous" else []
	for base_info in era.loot:
		var info: Dictionary = (base_info as Dictionary).duplicate()
		var count := int(info.count)
		if cond.get("id", "") == "bountiful":
			count = int(ceil(count * 1.5))
		info.value = int(round(float(info.value) * float(cond.get("mult", 1.0)) / 5.0) * 5.0)
		for k in count:
			var at := Vector3.ZERO
			match str(info.where):
				"nest":
					var c: Vector3 = nests[k % nests.size()]
					var off := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
					at = c + off
					if world.height_at(at.x, at.z) < 0.05:
						at = world.shore_near(at, rng)
					nest_total += 1
				"outpost":
					var ds: Array = world.outpost.dead_ends if world.outpost else []
					if ds.is_empty():
						at = world.dry_point(rng)
					else:
						at = ds[(k * 7 + rng.randi() % 3) % ds.size()] + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
				"camp":
					if world.camp_spots.is_empty():
						at = world.dry_point(rng)
					else:
						var a := rng.randf() * TAU
						at = world.camp_spots[k % world.camp_spots.size()] + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.8, 3.0)
				"near_pool":
					if pools.is_empty():
						at = world.dry_point(rng)
					else:
						at = world.shore_near(pools[k % pools.size()], rng)
				"burrow":
					if world.burrows.is_empty():
						at = world.dry_point(rng)
					else:
						at = world.burrows[rng.randi() % world.burrows.size()] + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
				"bones":
					var near_bones := world.bone_spots.filter(func(b: Vector3) -> bool: return b.distance_to(world.exit_pos) < 120.0)
					if near_bones.is_empty():
						at = world.dry_point(rng, 0.1, 40.0)
					else:
						at = near_bones[rng.randi() % near_bones.size()] + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
				_:
					# cheap things close in, better things further out
					var v := float(info.value)
					at = world.dry_point(rng, 0.1, 12.0 if v < 30 else 25.0, 60.0 if v < 30 else 110.0)
			at.y = world.height_at(at.x, at.z)
			var l := Loot.new()
			l.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(l)
			l.setup(loot.size(), info, at, world)
			loot.append(l)


## The era as today's conditions leave it.
func _conditioned(e: Dictionary) -> Dictionary:
	if cond.is_empty():
		return e
	e = e.duplicate(true)
	match str(cond.id):
		"fog":
			e.fog_density = float(e.fog_density) * 2.3
		"night":
			e.fog = (e.fog as Color) * 0.3
			e.ambient_energy = float(e.ambient_energy) * 0.35
			e.sun_energy = float(e.sun_energy) * 0.08
		"storm":
			e.fog = (e.fog as Color).darkened(0.35)
			e.fog_density = float(e.fog_density) * 1.4
			e.sun_energy = float(e.sun_energy) * 0.4
			e.loops = [e.loops[0], ["res://audio/darkrain.ogg", -4.0]]
	return e


func _authority() -> bool:
	return mode != "client"


func _make_player(id: int, view: bool, slot: int) -> Player:
	var p := Player.new()
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.id = id
	add_child(p)
	p.setup(world, sounds, view)
	var at := world.spawn
	if slot > 0:
		var a := slot * TAU / 4.0
		at += Vector3(cos(a), 0, sin(a)) * 1.8
		at.y = world.height_at(at.x, at.z)
	p.position = at
	p.yaw = world.spawn_yaw
	if _authority():
		p.noise.connect(_on_noise)
		players[id] = p
	return p


func _populate_carboniferous(rng: RandomNumberGenerator) -> void:
	for k in 4:
		var f := Meganeura.new()
		f.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(f)
		f.setup(world, self, sounds, _creature_start(rng, 15.0, 45.0), _on_noise)
		flies.append(f)
	for at in world.pools(3):
		var e := Eryops.new()
		e.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(e)
		e.setup(world, self, sounds, at)
		eryopses.append(e)
	var spots := world.log_spots.duplicate()
	for k in range(spots.size() - 1, 0, -1):  # seeded shuffle
		var j := rng.randi_range(0, k)
		var tmp = spots[k]
		spots[k] = spots[j]
		spots[j] = tmp
	for spot in spots:
		if scorps.size() >= 5:
			break
		var lp: Vector3 = spot[0]
		if Vector2(lp.x - world.spawn.x, lp.z - world.spawn.z).length() < 25.0:
			continue
		var yaw: float = spot[1]
		var side := Vector3(sin(yaw), 0, cos(yaw)) * (1.4 if rng.randf() < 0.5 else -1.4)
		var at := lp + side
		at.y = world.height_at(at.x, at.z)
		var sc := Scorpion.new()
		sc.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(sc)
		sc.setup(self, sounds, at, atan2(side.x, side.z))
		sc.struck.connect(func(v: Player) -> void: _kill(v, sc.global_position + Vector3(0, 0.5, 0)))
		scorps.append(sc)


func _populate_permian(rng: RandomNumberGenerator) -> void:
	var sm := Meshes.scutosaurus()
	for h in 3:
		var c := _creature_start(rng, 35.0, 90.0)
		var herd := {"center": c, "main": self}
		herds.append(herd)
		if _authority():
			var goal := _ring(c, 20.0, 50.0)
			var tw := create_tween().set_loops()
			tw.tween_method(func(v: Vector3) -> void: herd.center = v, c, goal, 90.0)
			tw.tween_method(func(v: Vector3) -> void: herd.center = v, goal, c, 90.0)
		for k in rng.randi_range(3, 5):
			var g := Grazer.new()
			g.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(g)
			g.setup(world, herd, sounds, sm)
			grazers.append(g)
	var dm := Meshes.dicynodon()
	for b in world.burrows:
		if rng.randf() < 0.6:
			var d := Dicynodon.new()
			d.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(d)
			d.setup(world, self, sounds, dm, b)
			dicys.append(d)


func _populate_cretaceous(rng: RandomNumberGenerator, lair: Vector3) -> void:
	# the pack's second raptor, a little way from the first
	var p2 := lair + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
	p2.y = world.height_at(p2.x, p2.z)
	_spawn_hunter(p2, Vector3.FORWARD, "raptor")
	# the rex, further out
	var rx := _creature_start(rng, 85.0, 120.0)
	_spawn_hunter(rx, (world.spawn - rx).normalized(), "rex")
	_add_compys(rng)
	var tm := {"model": "Triceratops", "size": 0.3}
	var pm := {"model": "Parasaurolophus", "size": 0.3}
	for h in 3:
		var c := _creature_start(rng, 40.0, 90.0)
		var herd := {"center": c, "main": self}
		herds.append(herd)
		if _authority():
			var goal := _ring(c, 20.0, 40.0)
			var tw := create_tween().set_loops()
			tw.tween_method(func(v: Vector3) -> void: herd.center = v, c, goal, 80.0)
			tw.tween_method(func(v: Vector3) -> void: herd.center = v, goal, c, 80.0)
		for k in rng.randi_range(3, 4):
			var g := Grazer.new()
			g.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(g)
			g.setup(world, herd, sounds, tm if h < 2 else pm)
			grazers.append(g)


func _add_compys(rng: RandomNumberGenerator) -> void:
	var hoard := world.dry_point(rng, 0.2, 35.0, 90.0)
	for k in 4:
		var c := Compy.new()
		c.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(c)
		var at := hoard + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		at.y = world.height_at(at.x, at.z)
		c.setup(world, self, sounds, at, k, hoard)
		compys.append(c)


## The compies' side of the rules (authority only).
func compy_find(c: Compy) -> Loot:
	var best: Loot = null
	var bd := 30.0
	for l in loot:
		if not l.on_ground() or l.claimed_by >= 0 and l.claimed_by != c.idx:
			continue
		if exit_node and exit_node.pad_has(l.position):
			continue
		var d := l.position.distance_to(c.position)
		if d < bd:
			bd = d
			best = l
	if best:
		best.claimed_by = c.idx
	return best


func compy_take(c: Compy, l: Loot) -> bool:
	if not l.on_ground():
		return false
	l.set_state(Loot.CARRIED, -100 - c.idx)
	_emit(["cpick", l.idx])
	return true


func compy_drop(c: Compy, i: int, at: Vector3) -> void:
	loot[i].claimed_by = -1
	loot[i].set_state(Loot.GROUND, 0, at)
	_emit(["drop", -1, i, at.x, at.y, at.z])


func compy_chirp(c: Compy) -> void:
	_on_noise(c.position, 16.0)
	_emit(["chirp", c.idx])


func _spawn_hunter(at: Vector3, facing: Vector3, kind := "") -> Node3D:
	if kind == "":
		kind = {"permian": "gorgon", "cretaceous": "raptor"}.get(era.id, "millipede")
	var m: Node3D
	match kind:
		"gorgon":
			m = Gorgon.new()
		"raptor":
			m = Raptor.new()
		"rex":
			m = TRex.new()
		_:
			m = Millipede.new()
	m.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(m)
	m.setup(world, self, sounds, at, facing)
	if mode == "client":
		m.puppet = true
	m.caught.connect(func(v: Player) -> void: _kill(v, m.head_pos() + Vector3(0, 0.3, 0)))
	m.alerted.connect(_alerted)
	hunters.append(m)
	return m


func _alerted() -> void:
	if local:
		local.fear = maxf(local.fear, 0.8)


# ================================================================ helpers the creatures use

func alive_players() -> Array:
	var out := []
	for p: Player in players.values():
		if p.alive and not p.through:
			out.append(p)
	return out


func nearest_player(at: Vector3) -> Player:
	var best: Player = null
	var bd := 1e9
	for p: Player in alive_players():
		var d := Vector2(p.position.x - at.x, p.position.z - at.z).length()
		if d < bd:
			bd = d
			best = p
	return best


## The nearest player with their lamp on, else just the nearest.
func lit_player(at: Vector3) -> Player:
	var best: Player = null
	var bd := 1e9
	for p: Player in alive_players():
		var d := p.position.distance_to(at)
		if p.light.visible and d < bd:
			bd = d
			best = p
	return best if best else nearest_player(at)


func _ring(center: Vector3, lo: float, hi: float) -> Vector3:
	var p := center
	for tries in 40:
		var a := randf() * TAU
		p = center + Vector3(cos(a), 0, sin(a)) * randf_range(lo, hi)
		var lim := World.BOUND - 10.0
		if absf(p.x) < lim and absf(p.z) < lim:
			break
	p.x = clampf(p.x, -World.BOUND + 10.0, World.BOUND - 10.0)
	p.z = clampf(p.z, -World.BOUND + 10.0, World.BOUND - 10.0)
	p.y = world.height_at(p.x, p.z)
	return p


func _creature_start(rng: RandomNumberGenerator, lo: float, hi: float) -> Vector3:
	var p := world.spawn
	for tries in 60:
		var a := rng.randf() * TAU
		p = world.spawn + Vector3(cos(a), 0, sin(a)) * rng.randf_range(lo, hi)
		var lim := World.BOUND - 10.0
		if absf(p.x) < lim and absf(p.z) < lim:
			break
	p.x = clampf(p.x, -World.BOUND + 10.0, World.BOUND - 10.0)
	p.z = clampf(p.z, -World.BOUND + 10.0, World.BOUND - 10.0)
	p.y = world.height_at(p.x, p.z)
	return p


## Same pixel budget in both orientations: 640x360 landscape, 360x640 portrait.
func _fit() -> void:
	var ws := DisplayServer.window_get_size()
	get_window().content_scale_size = Vector2i(360, 640) if ws.y > ws.x else Vector2i(640, 360)


func _loop_player(path: String, db: float) -> AudioStreamPlayer:
	var stream: AudioStreamOggVorbis = load(path)
	stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = era.fog
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = era.ambient
	env.ambient_light_energy = era.ambient_energy
	env.fog_enabled = true
	env.fog_light_color = era.fog
	env.fog_density = era.fog_density
	env.fog_sky_affect = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = era.sun_rot
	sun.light_color = era.sun
	sun.light_energy = era.sun_energy
	add_child(sun)


func _input_map() -> void:
	# Arrows and the keys round them first: browser add-ons (Vim-style ones
	# like Surfingkeys) grab letters such as D and E before the game sees
	# them. The old letters still work as a second binding.
	var m := {
		"fwd": [KEY_UP, KEY_W], "back": [KEY_DOWN, KEY_S], "left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D],
		"sprint": [KEY_SHIFT], "crouch": [KEY_SLASH, KEY_C], "light": [KEY_PERIOD, KEY_F], "use": [KEY_ENTER, KEY_KP_ENTER, KEY_E],
		"drop": [KEY_BACKSPACE, KEY_G], "jump": [KEY_SPACE], "decoy": [KEY_COMMA, KEY_Q],
		"scan": [KEY_SEMICOLON, KEY_R], "stun": [KEY_APOSTROPHE, KEY_H],
		"sens_down": [KEY_BRACKETLEFT], "sens_up": [KEY_BRACKETRIGHT],
		"slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3], "slot4": [KEY_4], "slot5": [KEY_5], "slot6": [KEY_6],
		"throw": [KEY_BACKSLASH, KEY_T], "emote1": [KEY_Z], "emote2": [KEY_X], "emote3": [KEY_V], "emote4": [KEY_B], "mute": [KEY_M],
	}
	for a in m:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in m[a]:
			# by position (so WASD works on any layout) and by letter, in
			# case the browser only reports one of them
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
			var e2 := InputEventKey.new()
			e2.keycode = k
			InputMap.action_add_event(a, e2)
	# right mouse also grabs / uses, like a second E
	var rm := InputEventMouseButton.new()
	rm.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("use", rm)


func _parse_flags() -> Dictionary:
	var q := ""
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("window.location.search", true)
		q = str(v) if v != null else ""
	else:
		q = "&".join(OS.get_cmdline_user_args())
	var out := {}
	for part in q.trim_prefix("?").split("&", false):
		var kv := part.split("=")
		out[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else "1"
	return out


func _apply_dev_flags() -> void:
	DinoModel.probe = flags.has("probe")
	if flags.has("yaw"):
		local.yaw = deg_to_rad(float(flags.yaw))
	if flags.has("pitch"):
		local.pitch = deg_to_rad(float(flags.pitch))
	if flags.has("light"):
		local.light.visible = true
	if hub:
		local.rotation.y = local.yaw
		local.head.rotation.x = local.pitch
		return
	if flags.has("exit"):
		var back := Vector3(sin(world.exit_yaw), 0, cos(world.exit_yaw))
		var p := world.exit_pos + back * 12.0
		p.y = world.height_at(p.x, p.z)
		local.position = p
		local.yaw = world.exit_yaw
	if flags.has("mill"):
		var fwd := Basis(Vector3.UP, local.yaw) * Vector3.FORWARD
		var at := local.position + fwd * float(flags.mill)
		var old := mill
		hunters.erase(old)
		old.queue_free()
		mill = _spawn_hunter(at, Basis(Vector3.UP, float(flags.get("mturn", "1.1"))) * -fwd)
	var target: Node3D = null
	if flags.has("near"):
		var pool := {"eryops": eryopses, "scorp": scorps, "scuto": grazers, "dicy": dicys}.get(flags.near, []) as Array
		target = pool[0] if not pool.is_empty() else null
	if flags.has("loot") and not loot.is_empty():
		target = loot[clampi(int(flags.loot) if flags.loot != "1" else 0, 0, loot.size() - 1)]
	if target:
		var dist := float(flags.get("neard", "1.8" if target is Loot else ("12" if target is Eryops else "7")))
		var a := randf() * TAU
		var p := target.global_position + Vector3(cos(a), 0, sin(a)) * dist
		for k in 24:
			if world.height_at(p.x, p.z) > -0.2:
				break
			a += 0.26
			p = target.global_position + Vector3(cos(a), 0, sin(a)) * dist
		p.y = world.height_at(p.x, p.z)
		local.position = p
		var to := target.global_position - p
		local.yaw = atan2(-to.x, -to.z)
		local.pitch = -0.6 if target is Loot else -0.12
	local.rotation.y = local.yaw
	local.head.rotation.x = local.pitch
	if flags.has("rex"):  # dev: the rex, D m ahead, side on
		var fwd := Basis(Vector3.UP, local.yaw) * Vector3.FORWARD
		var at := local.position + fwd * float(flags.rex)
		at.y = world.height_at(at.x, at.z)
		_spawn_hunter(at, fwd.rotated(Vector3.UP, 1.4), "rex")
	if flags.has("outpost") and world.outpost:  # dev: at the outpost door (outpost=D metres out; negative is inside)
		var o := world.outpost
		var p := o.to_global_pre(Vector3(0, 0, o.n * Outpost.C * 0.5 + float(flags.outpost if flags.outpost != "1" else "8")))
		p.y = world.height_at(p.x, p.z)
		local.position = p
		local.yaw = o.rotation.y
	if flags.has("pit") and not world.pits.is_empty():  # dev: at the edge of a pit
		var c: Vector3 = world.pits[0][0]
		local.position = c + Vector3(0, 0, float(world.pits[0][1]) + 3.0)
		local.position.y = world.height_at(local.position.x, local.position.z)
		local.yaw = 0.0
	if flags.has("compy") and not compys.is_empty():
		local.position = compys[0].position + Vector3(0, 0, 5)
		local.position.y = world.height_at(local.position.x, local.position.z)
		local.yaw = 0.0
	if flags.has("stampede"):
		next_stampede = 3.0
	if flags.has("camp") and not world.camp_spots.is_empty():
		var c: Vector3 = world.camp_spots[0]
		local.position = c + Vector3(0, 0, 7)
		local.position.y = world.height_at(local.position.x, local.position.z)
		local.yaw = 0.0
	if flags.has("pad"):  # dev: start on the rift's carpet, facing out
		local.position = exit_node.to_global(Vector3(0.8, 0, 2.5))
		local.yaw = world.exit_yaw + PI
	if flags.has("rift"):  # dev: seconds left on the rift
		elapsed = rift_len - float(flags.rift)
		strain_sent = 1 if float(flags.rift) < rift_len * 0.5 else 0
	if flags.has("give"):  # dev: start carrying these (comma list)
		for i in str(flags.give).split(","):
			var l := loot[clampi(int(i), 0, loot.size() - 1)]
			l.position = local.position
			sim_on = true
			act(my_id, 1, l.idx)
			sim_on = false
	if flags.has("fly"):
		for f in flies:
			f.position = local.position + Vector3(randf_range(-4, 4), 2.5, randf_range(-6, -2)).rotated(Vector3.UP, local.yaw)


# ================================================================ the hub: title, console, shop, co-op

## The key list, for the title card and whenever the mouse is let go.
func _controls_text() -> String:
	var t := "ARROWS  move     SHIFT  run     SPACE  jump     /  crouch     .  lamp\n" \
		+ "ENTER  grab / use     BACKSPACE  drop     \\  throw     1-4 or wheel  switch hands\n" \
		+ ",  decoy     ;  scan     '  flash     [ ]  look speed     ESC  let go of the mouse"
	if mode == "client":
		t += "\nZ X V B  emotes     M  mute"
	return t


func _title() -> void:
	state = "title"
	ui = "title"
	hud.show_card("DEEP TIME", "a time-travelling heist",
		"Drop into prehistory. Grab the eggs and the treasure.\nGet back through the rift before something gets you.\nSpend the haul on hats.",
		"" if touch else _controls_text(), 0.8)
	hud.show_menu([
		{"type": "button", "text": "PLAY", "cb": func() -> void:
			Run.titled = true
			_start()},
		{"type": "button", "text": "PLAY WITH FRIENDS", "cb": func() -> void:
			Run.titled = true
			_start()
			_coop_menu()},
	])


func _open(name_: String) -> void:
	ui = name_
	local.control = false
	local.velocity = Vector3.ZERO
	if not touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_ui() -> void:
	ui = ""
	get_viewport().gui_release_focus()
	hud.hide_card()
	hud.show_menu([])
	hud.show_stages([], Callable())
	shop_ui.visible = false
	if state == "play" and local.alive and not local.through:
		local.control = true
		if not touch:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _console() -> void:
	_open("console")
	var host := mode == "solo" or Net.host_id == Net.my_id
	var q := _quota()
	hud.show_card("TIME CONSOLE", ("ROOM  %s  -  " % Net.code if mode == "client" else "") + Run.quota_line(q) + "   -   day %d" % (int(q.get("days", 0)) + 1), "", "", 0.88)
	var items := []
	# one row per era: the drop button, the era, and today's forecast there
	for n in range(1, Eras.COUNT + 1):
		var e := Eras.get_era(n)
		var open := Eras.unlocked(n, q)
		var c := Eras.condition(n, q)
		var line := "%s   -   %s" % [e.title, (str(c.name) + ("  x%.2f" % float(c.mult) if float(c.mult) != 1.0 else "") + "  (" + str(c.about) + ")") if open else "LOCKED  -  meet quota %d to open" % (n - 1)]
		var row := [{"type": "label", "text": line}]
		if host and open:
			row.push_front({"type": "button", "text": "DROP IN", "cb": _drop_into.bind(n), "width": 90})
		items.append({"type": "row", "items": row})
	if not host:
		items.append({"type": "label", "text": "%s drives the console" % Net.members.get(Net.host_id, {}).get("name", "the host")})
	var bottom := [{"type": "button", "text": "CLOSE  (Esc)", "cb": _close_ui, "width": 120}]
	if mode == "client":
		bottom.append({"type": "button", "text": "LEAVE ROOM", "cb": func() -> void: Net.leave(), "width": 120})
	else:
		bottom.append({"type": "button", "text": "PLAY WITH FRIENDS", "cb": _coop_menu, "width": 150})
	items.append({"type": "row", "items": bottom})
	hud.show_menu(items)

func _drop_into(n: int) -> void:
	if mode == "client":
		Net.start_level(n)
		return
	Run.level = n
	Run.autostart = true
	get_tree().reload_current_scene()


func _shop() -> void:
	_open("shop")
	shop_ui.open()


func _on_look_changed() -> void:
	_update_list()
	_gear_up(local, Run.net_look())
	if mode == "client":
		Net.set_look(Run.net_look())


func _coop_menu() -> void:
	_open("coop")
	hud.show_card("PLAY WITH FRIENDS", "up to 4 time-travellers", "", "", 0.88)
	hud.show_menu([
		{"type": "edit", "id": "name", "text": Run.player_name, "hint": "YOUR NAME"},
		{"type": "button", "text": "HOST A ROOM", "cb": func() -> void: _coop_go(true)},
		{"type": "row", "items": [
			{"type": "edit", "id": "code", "text": "", "hint": "CODE", "width": 70},
			{"type": "button", "text": "JOIN", "cb": func() -> void: _coop_go(false)},
		]},
		{"type": "button", "text": "BACK", "cb": _close_ui},
		{"type": "status"},
	])


func _coop_go(create: bool) -> void:
	var n := hud.menu_value("name")
	Run.player_name = Net.clean_name(n)
	Run.save()
	Net.voice.prime()
	var c := hud.menu_value("code")
	if not create and c.strip_edges().length() != 4:
		hud.status("the code is 4 letters")
		return
	Net.join(Net.server_url(flags), n, c, create, Run.net_look())


func _on_room_changed() -> void:
	for pid in avatars:
		var m: Dictionary = Net.members.get(pid, {})
		if not m.is_empty() and Shop.clean_look(m.get("look", {})) != avatars[pid].look:
			avatars[pid].set_look(m.look)
			_refresh_carry(pid)
	if ui == "console":
		_console()


func _on_left() -> void:
	Run.level = 0
	Run.autostart = true
	get_tree().reload_current_scene()


## Dev: ?host=NAME (+code=ABCD) or ?join=CODE (+name=) skip the menus.
func _auto_coop() -> void:
	if Net.online:
		return
	if flags.has("host"):
		Net.join(Net.server_url(flags), flags.host, str(flags.get("code", "")), true, Run.net_look())
	elif flags.has("join"):
		Net.join(Net.server_url(flags), str(flags.get("name", "")), flags.join, false, Run.net_look())


# ================================================================ starting

func _start() -> void:
	get_viewport().gui_release_focus()
	state = "play"
	state_t = 0.0
	ui = ""
	hud.hide_card()
	hud.show_stages([], Callable())
	hud.show_menu([])
	local.begin()
	if exit_node:
		exit_node.begin()
	amb.play()
	rain.play(randf() * 30.0)
	if not flags.has("freeze"):
		for m in hunters:
			m.begin()
		for c in netted:
			c.begin()
	sim_on = _authority()
	if not flags.has("play") and not touch and mode == "solo":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if flags.has("attract") and era.id == "carboniferous":
		_attract()
		# recording is slow: the capture script sets ts so a frame is 1/30 s
		Engine.time_scale = float(flags.get("ts", "1"))
		return
	var tips := []
	if hub:
		if Run.last_haul >= 0:
			tips.append([("+%s" % Run.cash(Run.last_haul)) if Run.last_haul > 0 else "came home empty-handed", 3.5])
			Run.last_haul = -1
		tips.append(["the TIME CONSOLE drops you in.  the SHOP sells hats.", 5.0])
	else:
		tips = [["", 1.0], ["%s  -  %s" % [cond.get("name", "CLEAR"), cond.get("about", "")], 4.0], ["the rift stays open for 7 minutes.", 3.5],
			["carry loot back and set it down on the rift's carpet.  it all comes home with you.", 5.5],
			["eggs are worth the most.  their parents disagree.", 4.0], [era.tip, 4.0],
			["ENTER grab   BACKSPACE drop   \\ throw   1-4 / wheel switch hands   , decoy" if not touch else "GRAB it.  DROP it on the rift's carpet.", 5.0]]
	if mode == "client":
		if not touch:
			tips.push_front(["click to grab the camera", 3.0])
			tips.append(["Z wave  X point  V scream  B flash   M mute", 5.0])
		if Net.voice.mic_ok() and not hub:
			tips.append(["talking is noise too.", 3.0])
	hud.say(tips)
	if flags.has("shop") and hub:
		_shop()
	elif flags.has("console") and hub:
		_console()


## Server: everyone's loaded (or the wait timed out). Let it begin.
func go() -> void:
	state = "play"
	sim_on = true
	for p: Player in players.values():
		p.begin()
	for m in hunters:
		m.begin()
	for c in netted:
		c.begin()


func add_net_player(id: int, info: Dictionary) -> void:
	if players.has(id):
		return
	var p := _make_player(id, false, int(info.color))
	p.input_mode = "net"
	_gear_up(p, info.get("look", {}))
	if Net.dev.has("give"):  # dev: everyone starts holding two things
		for l in loot:
			if l.on_ground() and p.items().size() < 2 and not l.two_handed:
				l.position = p.position
				var was := sim_on
				sim_on = true
				act(id, 1, l.idx)
				sim_on = was
	bags[id] = p.slots
	if sim_on:
		p.begin()


func _gear_up(p: Player, look: Dictionary) -> void:
	p.gear = look.duplicate()
	p.flash_left = 3 if int(look.get("flash", 0)) > 0 else 0
	p.set_slot_count(4 + int(look.get("pack", 0)))
	p.battery_life = 300.0 * (2.0 if int(look.get("battery", 0)) > 0 else 1.0)


func remove_net_player(id: int) -> void:
	if players.has(id):
		var p: Player = players[id]
		if p.alive and not p.through:
			_spill(p)
		p.queue_free()
		players.erase(id)
	_check_end()


func net_input(id: int, a: PackedFloat32Array) -> void:
	var p: Player = players.get(id)
	if p == null or not p.alive or p.through:
		return
	p.seq = int(a[0])
	p.net_move = Vector2(a[1], a[2])
	p.yaw = a[3]
	p.pitch = clampf(a[4], -1.4, 1.4)
	var bits := int(a[5])
	p.net_sprint = bits & 1 != 0
	p.net_crouch = bits & 2 != 0
	p.net_light = bits & 4 != 0
	if bits & 8 != 0:
		p.net_jump = true
	p.talk = clampf(a[6], 0.0, 1.0)
	# Where the client says it is. Its own movement is what the player sees,
	# so trust it unless it's moved further than it could have.
	if a.size() >= 9:
		var now := Time.get_ticks_msec() / 1000.0
		var gap := clampf(now - p.last_input_t, 0.0, 0.5) if p.last_input_t > 0.0 else 0.05
		p.last_input_t = now
		var claim := Vector3(a[7], 0.0, a[8])
		var reach := Player.RUN * 1.6 * gap + 0.6
		if Vector2(claim.x - p.position.x, claim.z - p.position.z).length() <= reach:
			p.position.x = claim.x
			p.position.z = claim.z


## Cabinet video: lamp on, a slow look around while it crosses in front.
func _attract() -> void:
	local.control = false
	local.light.visible = true
	var fwd := Basis(Vector3.UP, local.yaw) * Vector3.FORWARD
	var right := Basis(Vector3.UP, local.yaw) * Vector3.RIGHT
	mill.pos[0] = local.position + fwd * 7.0 + right * 6.0
	for i in mill.pos.size():
		mill.pos[i] = mill.pos[0] + right * Millipede.SP * i
	mill.dir = -right
	mill.state = "investigate"
	mill.target = local.position + fwd * 5.0 - right * 20.0
	mill.hear_off = true
	for k in flies.size():
		flies[k].position = local.position + fwd * (4.0 + k) + Vector3(randf_range(-3, 3), 2.0, 0)
	var tw := create_tween()
	tw.tween_property(local, "pitch", -0.18, 4.0)
	tw.parallel().tween_property(local, "yaw", local.yaw + 0.5, 15.0)


func _on_noise(at: Vector3, radius: float) -> void:
	if cond.get("id", "") == "storm":
		radius *= 0.7  # the rain covers you
	for m in hunters:
		m.hear(at, radius)
	for e in eryopses:
		e.hear(at, radius)


# ================================================================ authority: the rules

func _physics_process(dt: float) -> void:
	if mode == "client":
		_client_tick()
		return
	if not sim_on:
		return
	elapsed += dt
	if exit_node:
		for p: Player in alive_players():
			if exit_node.inside(p):
				_through(p)
		_rift_clock()
		_fly_loot()
		_hazards(get_physics_process_delta_time())
		if not outpost_tripped and world.outpost:
			for p: Player in alive_players():
				if world.outpost.contains(p.position):
					outpost_tripped = true
					var door := world.outpost.to_global_pre(Vector3(0, 0, world.outpost.n * Outpost.C * 0.5))
					for m in hunters:
						m.alarm(door)
					_emit(["outpost", p.id])
					break
	if mode == "server":
		tick += 1
		if tick % SNAP_EVERY == 0:
			Net.room_snapshot(net_room, _snapshot())
	_check_end()


func _emit(ev: Array) -> void:
	if mode == "server" and Net.dev.has("debug"):
		print("event ", ev.slice(0, 3))
	if mode == "server":
		Net.room_event(net_room, ev)
	else:
		_on_event(ev)


## A player (or their client) asked to do something. kind 1: pick up loot
## #arg. 2: drop what's in hand. 3: throw a decoy. 4: go home.
## 5: hold slot #arg. 6: throw what's in hand.
func act(id: int, kind: int, arg: int) -> void:
	var p: Player = players.get(id)
	if p == null or not p.alive or p.through or hub or not sim_on:
		return
	var h := p.held_item()
	var two := h >= 0 and loot[h].two_handed
	match kind:
		1:
			if arg < 0 or arg >= loot.size() or two:
				return
			var l := loot[arg]
			var slot := p.free_slot()
			if slot < 0 or not l.on_ground() or l.position.distance_to(p.position) > REACH + 0.6:
				return
			l.set_state(Loot.CARRIED, id)
			p.slots[slot] = arg
			p.held = slot
			_reweigh(p)
			_emit(["pick", id, arg, slot])
			if l.nest and not l.taken:
				l.taken = true
				_nest_taken(p, l.position)
		2, 6:
			if h < 0:
				return
			p.slots[p.held] = -1
			_reweigh(p)
			var th := _throw_vec(p) if kind == 6 else _drop_vec(p)
			loot[h].throw_from(th[0], th[1], id)
			_emit(["throw", id, h, th[0].x, th[0].y, th[0].z, th[1].x, th[1].y, th[1].z])
		3:
			var th := _throw_vec(p)
			_spawn_decoy(th[0], th[1], true)
			_emit(["decoy", id, th[0].x, th[0].y, th[0].z, th[1].x, th[1].y, th[1].z])
		4:
			if exit_node and exit_node.near_door_of(p):
				_through(p)
		5:
			if two or arg < 0 or arg >= p.slots.size():
				return
			p.held = arg
			_emit(["hold", id, arg])
		7:
			_swing(p)
		8:
			_stun_flash(p)


## The shovel: stuns a hunter, makes a compy drop what it has, and sends a
## friend staggering with whatever was in their hands flying.
func _swing(p: Player) -> void:
	if int(p.gear.get("shovel", 0)) <= 0 or p.swing_cd > 0.0:
		return
	p.swing_cd = 0.8
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var reach := p.position + fwd * 1.4
	var hit := ""
	for c in compys:
		if hit == "" and c.position.distance_to(reach) < 1.6:
			c.whack(p.position)
			hit = "compy"
	for m in hunters:
		if hit == "" and (m.head_pos().distance_to(reach + Vector3(0, 1.0, 0)) < 2.4 or m.position.distance_to(reach) < 2.4):
			m.stun(3.0)
			hit = "hunter"
	for q: Player in alive_players():
		if hit == "" and q != p and q.position.distance_to(reach) < 1.3:
			var h := q.held_item()
			if h >= 0:
				q.slots[q.held] = -1
				_reweigh(q)
				var v := fwd * 5.0 + Vector3(0, 3.0, 0)
				loot[h].throw_from(q.position + Vector3(0, 1.3, 0), v, q.id)
				_emit(["throw", q.id, h, q.position.x, q.position.y + 1.3, q.position.z, v.x, v.y, v.z])
			hit = "friend"
	_on_noise(p.position, 10.0 if hit != "" else 4.0)
	_emit(["swing", p.id, hit])


## The stun flash: every hunter with a line of sight to you is blinded.
func _stun_flash(p: Player) -> void:
	if p.flash_left <= 0:
		return
	p.flash_left -= 1
	var eye := p.position + Vector3(0, 1.5, 0)
	for m in hunters:
		var h: Vector3 = m.head_pos()
		if h.distance_to(eye) < 20.0 and world.clear_line(eye, h):
			m.stun(4.5)
	_emit(["stunflash", p.id, p.flash_left])


func _reweigh(p: Player) -> void:
	p.carry = 0.0
	for i in p.items():
		p.carry += loot[i].weight

## Where a throw starts and how fast it goes: out of the camera, along
## the look, a bit of loft, plus however fast they were moving.
func _throw_vec(p: Player) -> Array:
	var dir := Basis(Vector3.UP, p.yaw) * Basis(Vector3.RIGHT, p.pitch) * Vector3.FORWARD
	var at := p.position + Vector3(0, 1.35, 0) + dir * 0.5
	var v := dir * THROW_SPEED + Vector3(0, 2.2, 0) + Vector3(p.velocity.x, 0, p.velocity.z) * 0.5
	return [at, v]


## Setting something down: just in front of your feet, gently.
func _drop_vec(p: Player) -> Array:
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var at := p.position + fwd * 0.7 + Vector3(0, 0.5, 0)
	return [at, Vector3(0, -1.0, 0)]

func _spawn_decoy(at: Vector3, v: Vector3, authority: bool) -> void:
	var d := Decoy.new()
	d.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(d)
	d.setup(world, sounds, at, v)
	if authority:
		d.on_squeak = func(pos: Vector3) -> void:
			_on_noise(pos, 26.0)
			for m in hunters:
				if m is Gorgon and m.position.distance_to(pos) < 45.0:
					m.alarm(pos)
	decoys_out.append(d)


## The loot sitting on the rift's carpet: what the crew takes home.
func _pad_value() -> int:
	var v := 0
	if exit_node == null:
		return 0
	for l in loot:
		if l.state == Loot.GROUND and exit_node.pad_has(l.position):
			v += l.value
	return v

## Seven minutes. Halfway, the era starts to notice. The last minute, the
## rift strains. Then it collapses, and anyone still out there is gone.
func _rift_clock() -> void:
	var left := rift_len - elapsed
	if strain_sent == 0 and elapsed > rift_len * 0.5:
		strain_sent = 1
		for m in hunters:
			m.drift = minf(0.9, m.drift + 0.2)
			m.hunt_speed += 0.3
		_emit(["strain", 1])
	elif strain_sent == 1 and left < 60.0:
		strain_sent = 2
		_emit(["strain", 2])
	elif strain_sent == 2 and left < 20.0:
		strain_sent = 3
		_emit(["strain", 3])
	elif strain_sent == 3 and left <= 0.0:
		strain_sent = 4
		_emit(["collapse"])
		for p: Player in alive_players():
			for i in p.items():
				loot[i].set_state(Loot.GONE)
			p.slots.fill(-1)
			var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
			_kill(p, p.position + fwd * 2.0 + Vector3(0, 1.0, 0))


## Thrown and dropped loot: friends catch throws by being in the way;
## eggs that fall hard crack; every landing is noise.
func _fly_loot() -> void:
	for l in loot:
		if l.state != Loot.FLYING:
			continue
		if l.air > 0.2 and l.vel.length() > 3.0:
			for p: Player in alive_players():
				if p.id == l.thrower and l.air < 0.9:
					continue
				var h := p.held_item()
				if h >= 0 and loot[h].two_handed:
					continue
				var slot := p.free_slot()
				if slot < 0 or (l.two_handed and slot != p.held):
					continue
				if l.position.distance_to(p.position + Vector3(0, 1.1, 0)) < 1.5:
					l.set_state(Loot.CARRIED, p.id)
					p.slots[slot] = l.idx
					p.held = slot
					_reweigh(p)
					_emit(["catch", p.id, l.idx, slot])
					break
		if l.state == Loot.FLYING and l.landed:
			var broke := l.fragile and not l.cracked and l.fall_speed > 7.0
			if broke:
				l.crack()
			l.set_state(Loot.GROUND, 0, l.position)
			_on_noise(l.position, 12.0 if l.fall_speed > 4.0 else 3.0)
			_emit(["land", l.idx, l.position.x, l.position.y, l.position.z, 1 if broke else 0])

## The land itself: stampedes now and then, and pits that swallow you.
func _hazards(dt: float) -> void:
	for p: Player in players.values():
		p.swing_cd = maxf(0.0, p.swing_cd - dt)
	for p: Player in alive_players():
		if p.sink >= 1.0:
			_kill(p, p.position + Vector3(0, 0.3, 0))
	for h in herds:
		if float(h.get("dash_t", 0.0)) > 0.0:
			h.dash_t = float(h.dash_t) - dt
	if herds.is_empty():
		return
	if next_stampede == 0.0:
		next_stampede = randf_range(90.0, 200.0)
	next_stampede -= dt
	if next_stampede > 0.0:
		return
	next_stampede = randf_range(120.0, 240.0)
	var h: Dictionary = herds[randi() % herds.size()]
	var c: Vector3 = h.center
	var target := nearest_player(c)
	if target == null or target.position.distance_to(c) > 90.0:
		return
	var d := target.position - c
	d.y = 0.0
	h.dash = d.normalized()
	h.dash_t = 9.0
	_emit(["stampede", c.x, c.y, c.z])


## Somebody took an egg: its parent knows.
func _nest_taken(p: Player, at: Vector3) -> void:
	nest_taken += 1
	for m in hunters:
		m.alarm(at)
	if not hunter2 and hunters.size() == 1:
		hunter2 = true
		var spot := _ring(p.position, 45.0, 60.0)
		var m2 := _spawn_hunter(spot, Vector3.FORWARD)
		m2.drift = 0.8
		m2.hunt_speed += 0.6
		m2.begin()
		_emit(["hunter2", spot.x, spot.y, spot.z])
	for m in hunters:
		m.drift = minf(0.9, 0.45 + nest_taken * 0.1)
	_emit(["nest", nest_taken, at.x, at.y, at.z])


## Everything they carried falls where they were.
func _spill(p: Player) -> void:
	for k in p.slots.size():
		var i := p.slots[k]
		if i < 0:
			continue
		p.slots[k] = -1
		var at := p.position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		at.y = world.height_at(at.x, at.z)
		loot[i].set_state(Loot.GROUND, 0, at)
		_emit(["drop", p.id, i, at.x, at.y, at.z])
	p.carry = 0.0

func _kill(p: Player, at: Vector3) -> void:
	if p == null or not p.alive or p.through or not sim_on:
		return
	var qd := _quota()
	qd.deaths = int(qd.get("deaths", 0)) + 1
	if mode == "server" and Net.dev.has("debug"):
		print("kill ", p.id, " at ", p.position, " by ", at, " ", get_stack().slice(1, 3))
	_spill(p)
	p.alive = false
	p.vanish()
	var push := (p.global_position - at)
	push.y = 0.0
	push = push.normalized() * 5.0
	_emit(["dead", p.id, at.x, at.y, at.z, push.x, push.z])


func _through(p: Player) -> void:
	var brought := 0
	for i in p.items():
		brought += loot[i].value
		loot[i].set_state(Loot.GONE)
	p.slots.fill(-1)
	p.carry = 0.0
	home_value += brought
	p.through = true
	p.vanish()
	_emit(["through", p.id, brought, home_value])

func _check_end() -> void:
	if hub or not sim_on or players.is_empty() or not alive_players().is_empty():
		return
	sim_on = false
	haul = home_value + _pad_value()
	_emit(["end", haul])
	if mode == "server":
		Net.room_over(net_room, haul)

func emote(id: int, e: int) -> void:
	var p: Player = players.get(id)
	if p == null or not p.alive or p.through:
		return
	if e == 3:
		_on_noise(p.position, 28.0)
	elif e == 4:
		_on_noise(p.position, 8.0)
	_emit(["emote", id, e])


## A late joiner needs to know where every bit of loot is.
func sync_loot(id: int) -> void:
	if hub:
		return
	var a := PackedFloat32Array()
	for l in loot:
		var slot := -1
		if l.state == Loot.CARRIED and players.has(l.holder):
			slot = (players[l.holder] as Player).slots.find(l.idx)
		a.append_array([l.state, l.holder, slot, l.position.x, l.position.y, l.position.z])
	var held := {}
	for pid in players:
		held[pid] = players[pid].held
	Net.room_event_to(id, ["lootall", a, home_value, held])

func _snapshot() -> PackedFloat32Array:
	var a := PackedFloat32Array([elapsed, players.size()])
	for id in players:
		var p: Player = players[id]
		var bits := (1 if p.crouching else 0) | (2 if p.light.visible else 0) | (4 if p.alive else 0) \
			| (8 if p.through else 0) | (16 if p.moving else 0)
		var slot: int = net_room.members.get(id, {}).get("color", 0)
		a.append_array([slot, p.position.x, p.position.y, p.position.z, p.yaw, p.pitch, bits, p.seq,
			p.stamina, p.battery, p.items().size(), p.talk])
	a.append(hunters.size())
	for m in hunters:
		m.net_get(a)
	a.append(netted.size())
	for c in netted:
		c.net_get(a)
	return a


# ================================================================ client: snapshots in, inputs out

func _id_for_slot(slot: int) -> int:
	for id in Net.members:
		if int(Net.members[id].color) == slot:
			return int(id)
	return -1


func _client_tick() -> void:
	tick += 1
	if state != "play" or not local.alive or local.through or tick % INPUT_EVERY != 0:
		return
	in_seq += 1
	var bits := (1 if local.last_sprint else 0) | (2 if local.crouching else 0) | (4 if local.light.visible else 0) \
		| (8 if jumped_since_send else 0)
	jumped_since_send = false
	var talk := 0.0 if Net.voice.muted else Net.voice.level
	Net.send_input(PackedFloat32Array([in_seq, local.last_move.x, local.last_move.y, local.yaw, local.pitch, bits, talk,
		local.position.x, local.position.z]))
	sent[in_seq] = local.position


func _on_snap(a: PackedFloat32Array) -> void:
	if a.size() < 2:
		return
	elapsed = a[0]
	var i := 2
	var present := {}
	for k in int(a[1]):
		var pid := _id_for_slot(int(a[i]))
		var pos := Vector3(a[i + 1], a[i + 2], a[i + 3])
		var bits := int(a[i + 6])
		var entry := {"pos": pos, "yaw": a[i + 4], "pitch": a[i + 5], "alive": bits & 4 != 0, "through": bits & 8 != 0,
			"bag": int(a[i + 10]), "talk": a[i + 11]}
		if pid == my_id:
			_reconcile(pos, int(a[i + 7]), a[i + 8], a[i + 9])
		elif pid != -1:
			var av: Avatar = avatars.get(pid)
			if av == null:
				var info: Dictionary = Net.members.get(pid, {"name": "?", "color": 0})
				av = Avatar.new()
				add_child(av)
				av.setup(pid, info.name, info.get("look", {}), sounds)
				avatars[pid] = av
				_refresh_carry(pid)
			av.net_set(pos, a[i + 4], a[i + 5], bits & 1 != 0, bits & 2 != 0, entry.alive, entry.through, entry.talk)
		if pid != -1:
			net_players[pid] = entry
			present[pid] = true
		i += 12
	for pid in avatars.keys():
		if not present.has(pid):
			avatars[pid].queue_free()
			avatars.erase(pid)
			net_players.erase(pid)
	var nh := int(a[i])
	i += 1
	while hunters.size() < nh:
		var m := _spawn_hunter(Vector3(a[i], a[i + 1], a[i + 2]), Vector3.FORWARD)
		if state == "play":
			m.begin()
	for m in hunters:
		i = m.net_set(a, i)
	var nc := int(a[i])
	i += 1
	if nc != netted.size():
		if not warned:
			warned = true
			push_warning("snapshot has %d creatures, this level has %d" % [nc, netted.size()])
		return
	for c in netted:
		i = c.net_set(a, i)


## Where the server says we are, against where we predicted we'd be when we
## sent that input. Small drift is eased out; big gaps snap.
func _reconcile(pos: Vector3, seq: int, stam: float, batt: float) -> void:
	if not local.alive or local.through:
		return
	# Our own movement is trusted; the server only overrules a big gap
	# (it refused a move, or we fell badly out of step).
	if sent.has(seq):
		var err: Vector3 = pos - sent[seq]
		err.y = 0.0
		if err.length() > 3.0:
			local.position += err
			sent.clear()
		else:
			for k in sent.keys():
				if k <= seq:
					sent.erase(k)
	if absf(local.stamina - stam) > 0.15:
		local.stamina = stam
	local.battery = batt
	if batt <= 0.0:
		local.light.visible = false


# ================================================================ events (solo applies them directly)

func _name(id: int) -> String:
	if id == my_id and mode == "solo":
		return "you"
	return str(Net.members.get(id, {}).get("name", "someone"))


## What someone has: the held item in their hands, the rest on the pack.
func _refresh_carry(pid: int) -> void:
	var sl: Array = bags.get(pid, [])
	if pid == my_id and local:
		var h := local.held_item()
		local.set_hand(loot[h].mesh if h >= 0 else null, h >= 0 and loot[h].two_handed)
		return
	var av: Avatar = avatars.get(pid)
	if av == null:
		return
	var back := []
	var hand: Mesh = null
	for k in sl.size():
		var i: int = sl[k]
		if i < 0:
			continue
		if k == av.held:
			hand = loot[i].mesh
		else:
			back.append(loot[i].mesh)
	av.set_carry(back)
	av.set_hand(hand)

func _bag_of(pid: int) -> Array:
	if not bags.has(pid):
		var a: Array[int] = [-1, -1, -1, -1, -1, -1]
		bags[pid] = a
	return bags[pid]

func _on_event(ev: Array) -> void:
	match str(ev[0]):
		"go":
			_start()
		"pick", "catch":
			var pid := int(ev[1])
			var i := int(ev[2])
			var slot := int(ev[3])
			if mode == "client":
				loot[i].set_state(Loot.CARRIED, pid)
				_bag_of(pid)[slot] = i
				if pid == my_id:
					local.held = slot
					_reweigh(local)
				elif avatars.has(pid):
					avatars[pid].held = slot
			_refresh_carry(pid)
			if pid == my_id:
				sfx.stream = sounds.beep
				sfx.volume_db = -6.0
				sfx.play()
				if ev[0] == "catch":
					hud.say([["caught it!", 1.5]])
			elif ev[0] == "catch":
				hud.say([["%s caught the %s" % [_name(pid), loot[i].item_name.to_lower()], 2.5]])
			_update_list()
		"drop", "throw":
			var pid := int(ev[1])
			var i := int(ev[2])
			if mode == "client":
				var sl := _bag_of(pid)
				var k := sl.find(i)
				if k >= 0:
					sl[k] = -1
				if ev[0] == "throw":
					loot[i].throw_from(Vector3(ev[3], ev[4], ev[5]), Vector3(ev[6], ev[7], ev[8]), pid)
				else:
					loot[i].set_state(Loot.GROUND, 0, Vector3(ev[3], ev[4], ev[5]))
				if pid == my_id:
					_reweigh(local)
			if ev[0] == "throw" and Vector3(ev[6], ev[7], ev[8]).length() > 3.0:
				_sound_at(sounds.whoosh, Vector3(ev[3], ev[4], ev[5]), 4.0)
			_refresh_carry(pid)
			_update_list()
		"hold":
			var pid := int(ev[1])
			if pid == my_id:
				if mode == "client":
					local.held = int(ev[2])
			elif avatars.has(pid):
				avatars[pid].held = int(ev[2])
			_refresh_carry(pid)
			_update_list()
		"lootall":
			var a: PackedFloat32Array = ev[1]
			home_value = int(ev[2])
			var held: Dictionary = ev[3]
			for pid in bags:
				bags[pid].fill(-1)
			for i in loot.size():
				var st := int(a[i * 6])
				var who := int(a[i * 6 + 1])
				var slot := int(a[i * 6 + 2])
				loot[i].set_state(st, who, Vector3(a[i * 6 + 3], a[i * 6 + 4], a[i * 6 + 5]))
				if st == Loot.CARRIED and slot >= 0:
					_bag_of(who)[slot] = i
			for pid in held:
				if int(pid) == my_id:
					local.held = int(held[pid])
				elif avatars.has(int(pid)):
					avatars[int(pid)].held = int(held[pid])
			_reweigh(local)
			for pid in avatars:
				_refresh_carry(pid)
			_refresh_carry(my_id)
			_update_list()
		"quota":
			Net.quota = ev[1]
			_quota_result(str(ev[2]))
		"through":
			var pid := int(ev[1])
			if mode == "client":
				for i in _bag_of(pid):
					if i >= 0:
						loot[i].set_state(Loot.GONE)
				_bag_of(pid).fill(-1)
			home_value = int(ev[3])
			_refresh_carry(pid)
			_update_list()
			if pid == my_id:
				_local_through(int(ev[2]))
			else:
				hud.say([["%s went home  +%s" % [_name(pid), Run.cash(int(ev[2]))], 3.5]])
		"land":
			var i := int(ev[1])
			var at := Vector3(ev[2], ev[3], ev[4])
			if mode == "client":
				loot[i].set_state(Loot.GROUND, 0, at)
				if int(ev[5]) == 1:
					loot[i].crack()
			if int(ev[5]) == 1:
				_sound_at(sounds.crack_egg, at, 6.0)
				if local.position.distance_to(at) < 30.0:
					hud.say([["it cracked.  half price now.", 2.5]])
			else:
				_sound_at(sounds.step, at, 3.0)
		"decoy":
			if mode == "client":
				_spawn_decoy(Vector3(ev[2], ev[3], ev[4]), Vector3(ev[5], ev[6], ev[7]), false)
		"strain":
			var lvl := int(ev[1])
			if exit_node:
				exit_node.strain = [0.0, 0.0, 0.5, 1.0][lvl]
			if lvl == 1:
				hud.say([["the era knows you're here.", 3.5]])
			elif lvl == 2:
				hud.say([["ONE MINUTE.  the rift is straining.", 4.0]])
				_start_rumble(-14.0)
			elif lvl == 3:
				hud.say([["THE RIFT IS CLOSING", 4.0]])
				_start_rumble(-4.0)
		"outpost":
			if world.outpost:
				world.outpost.trip()
			_sound_at(sounds.crack, world.outpost_at, 20.0)
			if int(ev[1]) == my_id:
				hud.say([["the door banged shut behind you.", 3.0], ["something outside heard it.", 3.5]])
			else:
				hud.say([["%s went into the outpost." % _name(int(ev[1])), 3.0]])
		"swing":
			var pid := int(ev[1])
			var hit := str(ev[2])
			var at: Vector3 = local.position if pid == my_id else (avatars[pid].position if avatars.has(pid) else local.position)
			_sound_at(sounds.whoosh, at + Vector3(0, 1.4, 0), 4.0)
			if hit != "":
				_sound_at(sounds.step, at + Vector3(0, 1.2, 0), 8.0)
			if pid == my_id:
				local.swing_anim = 0.3
				if hit == "hunter":
					hud.say([["STUNNED IT.  run.", 2.0]])
			elif avatars.has(pid):
				avatars[pid].emote(2)
		"stunflash":
			var pid := int(ev[1])
			var at: Vector3 = local.position if pid == my_id else (avatars[pid].eye() if avatars.has(pid) else local.position)
			_sound_at(sounds.flash, at, 10.0)
			if pid == my_id:
				local.flash_left = int(ev[2])
				hud.white = 0.6
				_update_list()
			elif local.cam.global_position.distance_to(at) < 20.0:
				hud.white = maxf(hud.white, 0.7)
		"cpick":
			if mode == "client":
				loot[int(ev[1])].set_state(Loot.CARRIED, -1)
		"chirp":
			var c: Compy = compys[int(ev[1])] if int(ev[1]) < compys.size() else null
			if c:
				c.chirp.pitch_scale = randf_range(1.5, 1.9)
				c.chirp.play()
		"stampede":
			var at := Vector3(ev[1], ev[2], ev[3])
			_sound_at(sounds.rumble, at, 40.0)
			if local.position.distance_to(at) < 90.0:
				hud.say([["STAMPEDE!  get out of the way!", 3.5]])
				local.shake = maxf(local.shake, 0.6)
		"collapse":
			if rumble:
				rumble.stop()
			if local.alive and not local.through:
				hud.say([["the rift closed without you.", 4.0]])
		"nest":
			if mode == "client":
				nest_taken = int(ev[1])
			_escalate()
			var p := AudioStreamPlayer3D.new()
			p.stream = sounds.hiss
			p.unit_size = 20.0
			p.max_distance = 200.0
			p.pitch_scale = 0.6
			add_child(p)
			p.global_position = Vector3(ev[2], ev[3], ev[4])
			p.play()
			p.finished.connect(p.queue_free)
			hud.say([["something heard its nest.", 3.5]])
		"hunter2":
			if mode == "client" and not hunter2:
				hunter2 = true
				var m := _spawn_hunter(Vector3(ev[1], ev[2], ev[3]), Vector3.FORWARD)
				m.begin()
			sfx.stream = sounds.crack
			sfx.volume_db = 4.0
			sfx.play()
			hud.say([["and something else woke up.", 4.0]])
		"dead":
			var pid := int(ev[1])
			var at := Vector3(ev[2], ev[3], ev[4])
			if pid == my_id:
				_local_dead(at)
			else:
				var av: Avatar = avatars.get(pid)
				if av:
					var rd := Ragdoll.new()
					add_child(rd)
					rd.setup(av.parts, av.global_position, av.yaw, Vector3(ev[5], 2.0, ev[6]))
					av.visible = false
					get_tree().create_timer(40.0).timeout.connect(rd.queue_free)
				hud.say([["%s  -  SIGNAL LOST.  their loot is where they fell." % _name(pid), 4.0]])
		"end":
			_end(int(ev[1]))
		"emote":
			_show_emote(int(ev[1]), int(ev[2]))


func _sound_at(stream: AudioStream, at: Vector3, unit: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = 80.0
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func _start_rumble(db: float) -> void:
	if rumble == null:
		rumble = AudioStreamPlayer.new()
		rumble.stream = sounds.rumble
		add_child(rumble)
	rumble.volume_db = db
	if not rumble.playing:
		rumble.play()


func _quota_result(result: String) -> void:
	var q := _quota()
	match result:
		"met":
			quota_msg = "QUOTA MET!  next quota: %s in 3 drops" % Run.cash(int(q.target))
			if int(q.round) == 2:
				quota_msg += "\nHELL CREEK is open on the console."
		"fired":
			var L: Dictionary = q.get("last", {})
			quota_msg = "YOU'RE FIRED.   %s of %s.\n%d drops  -  %d quota%s met  -  %s hauled  -  %d lost in time\ncredits and gear confiscated.  (your hats are yours.)" % [
				Run.cash(int(L.get("banked", 0))), Run.cash(int(L.get("target", 0))), int(L.get("days", 0)), int(L.get("quotas", 0)),
				"" if int(L.get("quotas", 0)) == 1 else "s", Run.cash(int(L.get("total", 0))), int(L.get("deaths", 0))]
			Run.fired()
		_:
			quota_msg = "%s more needed  -  %d drop%s left" % [Run.cash(int(q.target) - int(q.banked)), int(q.left), "" if int(q.left) == 1 else "s"]
	if mode == "client" and state == "card":
		hud.card_body.text = hud.card_body.text + "\n\n" + quota_msg


func _local_dead(at: Vector3) -> void:
	state = "dead"
	state_t = 0.0
	local.vanish()
	local.die(at)
	local.carry = 0.0
	_update_list()
	hud.say([])
	sfx.stream = sounds.hiss
	sfx.volume_db = 2.0
	sfx.play()


func _local_through(brought: int) -> void:
	state = "through"
	state_t = 0.0
	local.through = true
	local.vanish()
	local.carry = 0.0
	sfx.stream = sounds.hum
	sfx.play()
	hud.white = 0.9
	if mode == "client":
		hud.say([["home safe  +%s" % Run.cash(brought), 3.0], ["watching the others...", 3.0]])


func _end(total: int) -> void:
	end_haul = total
	var fresh := Run.payout(level, total)
	if mode == "solo":
		_quota_result(Run.quota_step(Run.quota, total))
		Run.save()
	var was := state
	state = "card"
	state_t = 0.0 if mode == "client" or was != "dead" else state_t
	spectating = false
	if mode == "solo":
		return  # the card comes after the death / rift animation
	var made := 0
	for e in net_players.values():
		if e.through:
			made += 1
	if local.through:
		made += 1
	hud.show_card("HAUL  " + Run.cash(total), "%d of %d made it home" % [made, net_players.size() + 1],
		era.title + ("   -   new best!" if fresh and total > 0 else "") + "\neveryone gets paid the crew's haul.",
		"back to the hub in a moment...", 0.85)


# ================================================================ loot: grabbing and dropping

## What's in reach: the loot (or hub spot) nearest the centre of your view.
func _find_target() -> void:
	target_loot = null
	target_spot = ""
	if state != "play" or not local.alive or local.through or ui != "":
		return
	if hub:
		for k in world.spots:
			var p: Vector3 = world.spots[k]
			if Vector2(p.x - local.position.x, p.z - local.position.z).length() < 3.2:
				target_spot = k
		return
	if exit_node and exit_node.near_door_of(local) and local.held_item() < 0:
		target_spot = "rift"
	var h := local.held_item()
	if local.free_slot() < 0 or (h >= 0 and loot[h].two_handed):
		return
	var eye := local.cam.global_position
	var fwd := -local.cam.global_transform.basis.z
	var best := -1e9
	for l in loot:
		if not l.on_ground():
			continue
		var flat := Vector2(l.position.x - local.position.x, l.position.z - local.position.z).length()
		if flat > REACH:
			continue
		var to := (l.global_position + Vector3(0, 0.2, 0) - eye).normalized()
		var facing := fwd.dot(to)
		# anything close at your feet counts; further off, roughly look at it
		if facing < 0.45 and flat > 1.3:
			continue
		var score := facing - flat * 0.25
		if score > best:
			best = score
			target_loot = l

func _use() -> void:
	if target_spot == "rift":
		if mode == "client":
			Net.act(4, 0)
		else:
			act(my_id, 4, 0)
	elif target_spot == "console":
		_console()
	elif target_spot == "shop":
		_shop()
	elif target_loot:
		if mode == "client":
			Net.act(1, target_loot.idx)
		else:
			act(my_id, 1, target_loot.idx)


func _drop(throw := false) -> void:
	if local.held_item() < 0 or hub:
		return
	var kind := 6 if throw else 2
	if mode == "client":
		Net.act(kind, 0)
	else:
		act(my_id, kind, 0)

## Tools: the shovel and stun flash go through the rules; the scanner is
## just for you.
func _tool(t: String) -> void:
	if hub or state != "play" or not local.alive or local.through:
		return
	match t:
		"shovel":
			if int(Run.gear.get("shovel", 0)) <= 0:
				return
			local.swing_anim = 0.3
			if mode == "client":
				Net.act(7, 0)
			else:
				act(my_id, 7, 0)
		"flash":
			if int(Run.gear.get("flash", 0)) <= 0:
				hud.say([["no stun flash.  the kiosk sells them.", 2.0]])
				return
			if mode == "client":
				Net.act(8, 0)
			else:
				act(my_id, 8, 0)
		"scan":
			if int(Run.gear.get("scanner", 0)) <= 0:
				hud.say([["no scanner.  the kiosk sells them.", 2.0]])
				return
			if scan_cd > 0.0:
				return
			scan_cd = 8.0
			scan_t = 4.0
			sfx.stream = sounds.beep
			sfx.pitch_scale = 0.7
			sfx.play()
			for l in loot:
				if l.on_ground() and l.position.distance_to(local.position) < 45.0:
					l.scan_t = 4.0


func _scan_tick(dt: float) -> void:
	scan_cd = maxf(0.0, scan_cd - dt)
	scan_t = maxf(0.0, scan_t - dt)
	if scan_t <= 0.0:
		hud.set_radar([])
		return
	var blips := []
	var inv := Basis(Vector3.UP, local.yaw).inverse()
	var add := func(p: Vector3, c: Color) -> void:
		var r: Vector3 = inv * (p - local.position)
		if r.length() < 45.0:
			blips.append([Vector2(r.x, r.z) / 45.0, c])
	for m in hunters:
		add.call(m.head_pos(), Color(1.0, 0.25, 0.2))
	for c in netted:
		if not (c is Meganeura):
			add.call(c.global_position, Color(1.0, 0.85, 0.3))
	for pid in avatars:
		add.call(avatars[pid].position, Color(0.4, 0.9, 1.0))
	hud.set_radar(blips)


## Switch hands, unless both are full of egg.
func _hold(k: int) -> void:
	if hub or k == local.held:
		return
	var h := local.held_item()
	if h >= 0 and loot[h].two_handed:
		hud.say([["both hands are full", 1.2]])
		return
	local.held = k
	_refresh_carry(my_id)
	_update_list()
	if mode == "client":
		Net.act(5, k)
	else:
		act(my_id, 5, k)


func _throw_decoy() -> void:
	if hub or Run.decoys <= 0 or state != "play" or not local.alive or local.through:
		if Run.decoys <= 0 and not hub:
			hud.say([["no decoys.  the kiosk sells them.", 2.0]])
		return
	Run.decoys -= 1
	Run.save()
	if mode == "client":
		Net.act(3, 0)
	else:
		act(my_id, 3, 0)
	_update_list()


func _quota() -> Dictionary:
	if mode == "server":
		return net_room.quota
	return Net.quota if Net.online and not Net.quota.is_empty() else Run.quota


func _quota_text() -> String:
	return Run.quota_line(_quota())


func _update_list() -> void:
	if hud == null:
		return
	if hub:
		hud.set_list("CREDITS  " + Run.cash(Run.money) + "\n\n" + _quota_text())
		if world.quota_board:
			var q := _quota()
			world.quota_board.text = "CHRONO BUREAU  -  QUOTA %d\n%s of %s\n%d drop%s left" % [int(q.round), Run.cash(int(q.banked)),
				Run.cash(int(q.target)), int(q.left), "" if int(q.left) == 1 else "s"]
		hud.set_slots([], 0, false)
		return
	var names := []
	for i in local.slots:
		names.append(loot[i].item_name if i >= 0 else "")
	var h := local.held_item()
	hud.set_slots(names, local.held, h >= 0 and loot[h].two_handed)
	var lines := ["IN THE RIFT  " + Run.cash(_pad_value() + home_value)]
	if h >= 0:
		lines.append("HOLDING  " + loot[h].item_name + "  " + Run.cash(loot[h].value))
	lines.append("")
	lines.append(_quota_text())
	if Run.decoys > 0:
		lines.append("DECOYS  %d%s" % [Run.decoys, "" if touch else "  ( , )"])
	var tools := []
	if int(Run.gear.get("shovel", 0)) > 0:
		tools.append("SHOVEL" + ("" if touch else " (click)"))
	if int(Run.gear.get("scanner", 0)) > 0:
		tools.append("SCAN" + ("" if touch else " ( ; )"))
	if int(Run.gear.get("flash", 0)) > 0:
		tools.append("FLASH x%d" % local.flash_left + ("" if touch else " ( ' )"))
	if not tools.is_empty():
		lines.append("  ".join(tools))
	hud.set_list("\n".join(lines))

func _emote_pressed(e: int) -> void:
	if emote_cool > 0.0 or state != "play" or not local.alive or local.through:
		return
	emote_cool = 1.2
	if mode == "client":
		Net.emote(e)
	else:
		emote(my_id, e)


func _show_emote(pid: int, e: int) -> void:
	if pid == my_id:
		match e:
			3:
				sfx.stream = sounds.scream
				sfx.volume_db = -2.0
				sfx.play()
			4:
				sfx.stream = sounds.flash
				sfx.play()
				hud.white = maxf(hud.white, 0.3)
		return
	var av: Avatar = avatars.get(pid)
	if av == null:
		return
	av.emote(e)
	# a camera flash in the face whites you out
	if e == 4 and local.alive and not local.through:
		var to := av.eye() - local.cam.global_position
		var d := to.length()
		if d < 14.0 and (-local.cam.global_transform.basis.z).dot(to / d) > 0.75 and world.clear_line(local.cam.global_position, av.eye()):
			hud.white = 0.95


func _toggle_mic() -> void:
	Net.voice.set_muted(not Net.voice.muted)
	hud.say([["mic muted" if Net.voice.muted else "mic on", 1.5]])


## Place every voice at its speaker. The living can't hear the dead; the
## dead (and those already home) hear everyone.
func _voice_tick() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	Net.voice.listener(cam.global_position, -cam.global_transform.basis.z)
	var me_out := not local.alive or local.through
	for pid in net_players:
		var e: Dictionary = net_players[pid]
		var out: bool = not e.alive or e.through
		var gain := 1.0
		if out and not me_out:
			gain = 0.0
		# walkie-talkies: both carrying one, you hear each other from anywhere
		var radio := not out and not me_out and int(Run.gear.get("walkie", 0)) > 0 \
			and int(Net.members.get(pid, {}).get("look", {}).get("walkie", 0)) > 0
		Net.voice.peer(pid, e.pos + Vector3(0, 1.5, 0), gain * (0.8 if radio else 1.0), (out and me_out) or radio)


func _roster_tick(dt: float) -> void:
	roster_t -= dt
	if roster_t > 0.0:
		return
	roster_t = 0.25
	var lines := []
	for id in Net.members:
		var m: Dictionary = Net.members[id]
		var e: Dictionary = net_players.get(int(id), {})
		var st := ""
		if int(id) == my_id:
			st = "  (you)"
		elif not e.is_empty() and not hub:
			if e.through:
				st = "  home"
			elif not e.alive:
				st = "  x"
			elif int(e.bag) > 0:
				st = "  carrying %d" % e.bag
		if not e.is_empty() and e.alive and float(e.talk) > 0.03:
			st += "  )))"
		lines.append([str(m.name) + st, Shop.suit_color(Shop.clean_look(m.get("look", {})).suit)])
	hud.set_roster(lines, ("ROOM %s   " % Net.code) + ("MIC OFF" if Net.voice.muted else ("MIC" if Net.voice.mic_ok() else "")))


# ================================================================ frame

func _unhandled_input(e: InputEvent) -> void:
	# the press that opens the console or shop mustn't also close it below
	var ui_was := ui
	if state == "play" and local.alive and not local.through and ui == "":
		if e.is_action_pressed("use"):
			_use()
		elif e.is_action_pressed("drop"):
			_drop()
		elif e.is_action_pressed("throw"):
			_drop(true)
		elif e.is_action_pressed("decoy"):
			_throw_decoy()
		elif e.is_action_pressed("scan"):
			_tool("scan")
		elif e.is_action_pressed("stun"):
			_tool("flash")
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_tool("shovel")
		for k in local.slots.size():
			if e.is_action_pressed("slot%d" % (k + 1)):
				_hold(k)
		if e is InputEventMouseButton and e.pressed and not hub:
			if e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_hold((local.held + 1) % local.slots.size())
			elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_hold((local.held + local.slots.size() - 1) % local.slots.size())
		if mode == "client":
			for k in EMOTES:
				if e.is_action_pressed("emote%d" % k):
					_emote_pressed(k)
			if e.is_action_pressed("mute"):
				_toggle_mic()
	if e.is_action_pressed("sens_down") or e.is_action_pressed("sens_up"):
		Run.sens = clampf(Run.sens + (0.1 if e.is_action_pressed("sens_up") else -0.1), 0.2, 3.0)
		Run.save()
		hud.say([["look sensitivity  %.1f   ( [ and ] )" % Run.sens, 1.5]])
	if e.is_action_pressed("use") and (ui_was == "console" or ui_was == "shop"):
		_close_ui()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_cancel") and ui != "" and ui != "title":
		_close_ui()
	if mode == "client" and spectating and e is InputEventMouseButton and e.pressed:
		_next_spec()
	if not (e is InputEventMouseButton and e.pressed):
		return
	match state:
		"play":
			if not touch and ui == "" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_tree().paused = false
				hud.paused_label.visible = false
		"card":
			if mode == "solo" and state_t > 2.5:
				_back_to_hub()


func _back_to_hub() -> void:
	get_tree().paused = false
	Run.level = 0
	Run.autostart = true
	get_tree().reload_current_scene()


func _process(dt: float) -> void:
	if mode == "server":
		return
	state_t += dt
	emote_cool -= dt
	if state == "play":
		_play_tick(dt)
	elif state == "dead" and mode == "client":
		_dead_client(dt)
	elif state == "through" and state_t > 2.0 and not spectating and mode == "client":
		_spectate()
	elif state == "card" and mode == "solo":
		_solo_card(dt)
	if mode == "client":
		hud.white = maxf(0.0, hud.white - dt * 0.7)
		if spectating:
			_spec_tick(dt)
		_voice_tick()
		_roster_tick(dt)
	elif state != "card":
		hud.white = maxf(0.0, hud.white - dt * 0.7)
	if flags.has("die") and state == "play" and state_t > 1.0 and mill:
		flags.erase("die")
		_kill(local, mill.head_pos())


## Solo: the rift's white-out or the tape's static, then the haul.
func _solo_card(dt: float) -> void:
	if local.through:
		hud.white = maxf(0.0, 1.0 - state_t * 0.6)
	else:
		hud.glitch = minf(1.0, hud.glitch + dt * 2.0) if state_t < 1.9 else 0.15
		if state_t > 0.9 and state_t - dt <= 0.9:
			sfx.stream = sounds.death
			sfx.play()
			amb.stop()
			rain.stop()
		if state_t > 0.9:
			hud.static_amt = minf(1.0, (state_t - 0.9) * 3.0) if state_t < 1.9 else 0.4
	if state_t > 1.9 and state_t - dt <= 1.9:
		var foot := ("tap" if touch else "click") + " to go back to the hub"
		if local.through:
			hud.show_card("HAUL  " + Run.cash(end_haul), "you made it home", era.title + "  -  " + Run.clock(elapsed) + "\n\n" + quota_msg, foot, 0.85)
		else:
			var why := "the rift closed without you" if strain_sent >= 4 else "caught.  your bag is still out there"
			hud.show_card("SIGNAL LOST", why, era.title + ("   -   the rift brought back " + Run.cash(end_haul) if end_haul > 0 else "") + "\n\n" + quota_msg, foot, 0.6)


## Co-op death: the grab, a burst of static, then you watch your friends.
func _dead_client(dt: float) -> void:
	if state_t < 1.6:
		hud.glitch = minf(1.0, hud.glitch + dt * 2.0)
		hud.static_amt = clampf((state_t - 0.9) * 3.0, 0.0, 1.0)
		return
	if not spectating:
		hud.static_amt = 0.0
		hud.glitch = 0.1
		_spectate()


func _spectate() -> void:
	spectating = true
	local.cam.current = false
	spec_cam.current = true
	_next_spec()


func _next_spec() -> void:
	var ids := []
	for pid in avatars:
		if avatars[pid].alive and not avatars[pid].through:
			ids.append(pid)
	if ids.is_empty():
		hud.spec("", touch)
		return
	ids.sort()
	var k := ids.find(spec_id)
	spec_id = ids[(k + 1) % ids.size()]
	hud.spec(_name(spec_id), touch)


func _spec_tick(dt: float) -> void:
	var av: Avatar = avatars.get(spec_id)
	if av == null or not av.alive or av.through:
		_next_spec()
		return
	var k := 1.0 - exp(-dt * 10.0)
	spec_cam.global_position = spec_cam.global_position.lerp(av.eye() - av.look_dir() * 0.3, k)
	spec_cam.rotation = Vector3(av.pitch, av.yaw, 0.0)
	hud.glitch = 0.08


func _play_tick(dt: float) -> void:
	if mode == "client":
		elapsed += dt  # the authority counts it in _physics_process
	if flags.has("debug") and int(elapsed * 2.0) != int((elapsed - dt) * 2.0):
		var others := ""
		for pid in avatars:
			others += " | %s at %.1f,%.1f" % [avatars[pid].pname, avatars[pid].position.x, avatars[pid].position.z]
		print("pos %.1f,%.1f yaw %.2f  bag %d haul %d loot %s%s%s" % [local.position.x, local.position.z, local.yaw, local.items().size(), haul,
			str(loot.slice(0, 3).map(func(l: Loot) -> int: return l.state)),
			("  hunter " + mill.state) if mill else "", others])
	hud.clock = elapsed
	hud.set_battery(local.battery, local.light.visible)
	if local.last_jump:
		jumped_since_send = true
	var was: Loot = target_loot
	_find_target()
	if was and was != target_loot:
		was.targeted = false
	if target_loot:
		target_loot.targeted = true
		hud.prompt(("GRAB" if touch else "ENTER  grab") + "  %s" % target_loot.item_name)
	elif target_spot == "rift":
		hud.prompt(("HOME" if touch else "ENTER") + "  go home now   (the crew takes " + Run.cash(_pad_value() + home_value) + ")")
	elif target_spot != "":
		hud.prompt(("USE" if touch else "ENTER") + "  " + {"console": "TIME CONSOLE", "shop": "SHOP"}[target_spot])
	elif local.held_item() >= 0 and exit_node and exit_node.on_pad(local):
		hud.prompt(("DROP" if touch else "BACKSPACE") + "  set it down on the carpet")
	elif local.held_item() >= 0 and loot[local.held_item()].two_handed and not hub:
		hud.prompt("both hands full" + ("" if touch else "  -  BACKSPACE drop   \\ throw"))
	elif local.free_slot() < 0 and not hub:
		hud.prompt("hands full  -  take it back to the rift")
	else:
		hud.prompt("")
	if not hub and int(state_t * 4.0) != int((state_t - dt) * 4.0):
		_update_list()
	if not hub:
		hud.set_rift(rift_len - elapsed)
	if local.touch:
		local.touch.use_label = "GRAB" if target_loot else ({"rift": "HOME"}.get(target_spot, "USE") if target_spot != "" else "")
		local.touch.can_drop = local.held_item() >= 0 and not hub
		local.touch.decoys = Run.decoys if not hub else 0
		local.touch.tools = [] if hub else ["shovel", "scan", "flash"].filter(func(k: String) -> bool:
			return int(Run.gear.get({"scan": "scanner"}.get(k, k), 0)) > 0)
	if mode == "client" and flags.has("emote") and emote_cool <= -2.0:
		_emote_pressed(int(flags.emote))
	if mode == "client" and flags.has("throwat") and state_t > float(flags.throwat) and local.held_item() >= 0:
		flags.erase("throwat")
		_drop(true)
	if mode == "client" and flags.has("bankat") and state_t > float(flags.bankat):
		flags.erase("bankat")
		local.position = exit_node.to_global(Vector3(0, 0, 2.0))
	# the key list shows whenever the mouse is let go
	hud.controls_label.visible = not touch and state == "play" and ui == "" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if hud.controls_label.visible and hud.controls_label.text == "":
		hud.controls_label.text = _controls_text()
	if hub:
		# dev: the host drops the crew in once enough have arrived (autostart=LEVEL,PLAYERS)
		if mode == "client" and flags.has("autostart") and Net.host_id == my_id and state_t > 3.0:
			var parts := str(flags.autostart).split(",")
			if Net.members.size() >= (int(parts[1]) if parts.size() > 1 else 2):
				flags.erase("autostart")
				Net.start_level(int(parts[0]))
		return
	var d := 999.0
	var hunted := 0.0
	for m in hunters:
		d = minf(d, Vector2(local.position.x - m.head_pos().x, local.position.z - m.head_pos().z).length())
		if m.is_hunting():
			hunted = 1.0
	var near := clampf(1.0 - d / 22.0, 0.0, 1.0)
	for m in hunters:
		if m is TRex:
			local.shake = maxf(local.shake, m.quake_at(local.position))
	hud.glitch = lerpf(hud.glitch, near * near * 0.4, 1.0 - exp(-dt * 4.0))
	hud.stamina = local.stamina
	hud.winded = local.exhausted
	local.fear = lerpf(local.fear, maxf(near, hunted * 0.7), 1.0 - exp(-dt * 1.5))
	# the frogs go quiet when it's close
	amb.volume_db = lerpf(amb.volume_db, lerpf(era.loops[0][1], -30.0, local.fear), 1.0 - exp(-dt * 1.2))
	if cond.get("id", "") == "storm":
		_storm(dt)
	_scan_tick(dt)
	if local.sink > 0.05:
		hud.prompt("SINKING  -  get out!")
	# the swamp is never quite silent
	next_event -= dt
	if next_event <= 0.0:
		next_event = randf_range(25.0, 60.0)
		_distant_event()
	if flags.has("attract"):
		local.rotation.y = local.yaw
		local.head.rotation.x = local.pitch
	if mode == "solo" and ui == "" and not flags.has("play") and not touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		get_tree().paused = true
		hud.paused_label.visible = true


## Lightning: the whole world blinks white, then thunder rolls in.
func _storm(dt: float) -> void:
	lightning -= dt
	if lightning <= 0.0:
		lightning = randf_range(7.0, 20.0)
		hud.white = maxf(hud.white, 0.45)
		env.ambient_light_energy += 2.0
		get_tree().create_timer(0.12).timeout.connect(func() -> void: env.ambient_light_energy -= 2.0)
		var p := AudioStreamPlayer.new()
		p.stream = sounds.crack
		p.pitch_scale = randf_range(0.35, 0.5)
		p.volume_db = 4.0
		add_child(p)
		get_tree().create_timer(randf_range(0.6, 2.5)).timeout.connect(p.play)
		p.finished.connect(p.queue_free)


func _distant_event() -> void:
	var a := randf() * TAU
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds.call if randf() < 0.5 else sounds.crack
	p.unit_size = 30.0
	p.max_distance = 200.0
	p.pitch_scale = randf_range(0.7, 1.1)
	add_child(p)
	p.global_position = local.global_position + Vector3(cos(a), 2.0, sin(a)) * randf_range(50.0, 90.0)
	p.play()
	p.finished.connect(p.queue_free)


## Every egg taken pulls the dark in closer.
func _escalate() -> void:
	if env == null or nest_total == 0:
		return
	var k := clampf(float(nest_taken) / nest_total, 0.0, 1.0)
	var base: Color = era.fog
	var fog := base.lerp(base * 0.5, k)
	fog.a = 1.0
	env.fog_light_color = fog
	env.background_color = fog
	env.ambient_light_energy = lerpf(era.ambient_energy, era.ambient_energy * 0.45, k)
	sun.light_energy = lerpf(era.sun_energy, era.sun_energy * 0.3, k)
