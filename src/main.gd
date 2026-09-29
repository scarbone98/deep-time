extends Node3D
## DEEP TIME: Backrooms through prehistory. One level of deep time, rebuilt
## from the era table in eras.gd.
##
## The same session runs in three modes:
##   solo    one player, everything local (Run carries progress between reloads)
##   server  authoritative: every player, creature, shot and death; no view.
##           The Net autoload runs one per room, inside a SubViewport.
##   client  draws the level from the server's snapshots: your own movement is
##           predicted and corrected, friends are Avatars, creatures are puppets
##
## World and creature placement come from the level seed, so the server and
## every client build the same level and creature lists line up by index.
##
## Dev flags (URL query on web, `-- key=value` on desktop):
##   play        skip the title card          seed=N   fixed layout
##   mill=D      put it D m in front of you   exit     start 12 m from the door
##   light       lamp on                      freeze   creatures hold still
##   yaw=deg / pitch=deg   look direction     die / win   trigger the ending
##   shots=N     first N shots already filmed near=eryops|scorp|scuto|dicy (+ neard=m)
##   level=N     play that level              attract  cabinet video scene
##   server [port=N]   run as the co-op server       server=URL   co-op server to use
##   host=NAME / join=CODE (+ name=, code=)  auto co-op    autostart  host starts at 2 players

const SNAP_EVERY := 3  # 20 Hz snapshots
const INPUT_EVERY := 2  # 30 Hz inputs
const EMOTES := {1: "wave", 2: "point", 3: "scream", 4: "flash"}

var mode := "solo"
var net_room: Dictionary = {}
var level := 1
var seed_ := -1
var my_id := 1
var era: Dictionary

var flags := {}
var sounds := {}
var world: World
var local: Player
var players := {}  # authority: peer id -> Player
var avatars := {}  # client: peer id -> Avatar
var net_players := {}  # client: peer id -> last snapshot entry
var mill: Node3D  # the first hunter
var exit_node: Exit
var hud: Hud
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
var netted: Array = []  # everything but hunters, in snapshot order
var env: Environment
var sun: DirectionalLight3D
var door_hint := 0.0
var shots: Array = []  # the local player's list
var pshots := {}  # authority: peer id -> that player's list
var lists_done := {}
var hunter2 := false
var win_text := ""
var win_foot := ""
var sim_on := false
var tick := 0
var in_seq := 0
var sent := {}  # client: input seq -> where we predicted we were
var spectating := false
var spec_id := 0
var spec_cam: Camera3D
var emote_cool := 0.0
var roster_t := 0.0
var lobby_level := 1
var menu := ""
var warned := false


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
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size_changed.connect(_fit)
	_fit()
	_input_map()
	Run.load_save()
	Net.level_start.connect(func() -> void: get_tree().reload_current_scene())
	if Net.online and Net.phase != "lobby":
		mode = "client"
		level = Net.level
		seed_ = Net.seed_
		my_id = Net.my_id
		Net.snapshot.connect(_on_snap)
		Net.event.connect(_on_event)
	else:
		level = clampi(int(flags.get("level", str(Run.level))), 1, Eras.COUNT)
		Run.level = level
		seed_ = int(flags.get("seed", str(randi() % 1000000)))
	Net.room_changed.connect(_on_room_changed)
	Net.status.connect(func(t: String) -> void: hud.status(t))
	Net.left.connect(_on_left)
	print("seed ", seed_)
	era = Eras.get_era(level)
	shots = _fresh_shots()
	sounds = Synth.all()
	touch = flags.has("touch") or DisplayServer.is_touchscreen_available()
	_build(true)
	local = _make_player(my_id, true, int(Net.members.get(my_id, {}).get("color", 0)) if mode == "client" else 0)
	local.bot = flags.has("bot")
	if mode == "solo":
		pshots[my_id] = shots
	exit_node.player = local
	spec_cam = Camera3D.new()
	spec_cam.fov = 72.0
	spec_cam.far = 160.0
	add_child(spec_cam)

	hud = Hud.new()
	add_child(hud)
	if touch:
		var pad := TouchPad.new()
		pad.player = local
		pad.coop = mode == "client"
		pad.emote.connect(_emote_pressed)
		pad.mic.connect(_toggle_mic)
		hud.add_touch(pad)
		local.touch = pad
	# field recordings (CC0, see audio/CREDITS.md)
	amb = _loop_player(era.loops[0][0], era.loops[0][1])
	rain = _loop_player(era.loops[1][0], era.loops[1][1])
	hud.date.text = era.date
	sfx = AudioStreamPlayer.new()
	add_child(sfx)
	hud.set_shots(shots)

	if mode == "client":
		world.ground_collider()
		if flags.has("yaw"):
			local.yaw = deg_to_rad(float(flags.yaw))
		if flags.has("light"):
			local.light.visible = true
		state = "loading"
		hud.show_card("ROOM  " + Net.code, "LEVEL %d  -  %s" % [level, era.title], era.intro, "waiting for the crew...")
		Net.loaded()
		return
	_apply_dev_flags()
	if flags.has("play") or Run.autostart:
		Run.autostart = false
		_start()
	else:
		_title()
	_auto_coop()


func _ready_server() -> void:
	era = Eras.get_era(level)
	sounds = Synth.all()
	_build(false)
	state = "wait"
	if Net.dev.has("mill"):  # dev: start it right on top of the spawn
		var d := float(Net.dev.mill)
		var at := world.spawn + Vector3(d, 0, 0)
		hunters.erase(mill)
		mill.queue_free()
		mill = _spawn_hunter(at, Vector3.LEFT)


func _fresh_shots() -> Array:
	var list: Array = era.shots.duplicate(true)
	for sh in list:
		sh.prog = 0.0
		sh.done = false
	return list


## World, light, the door and every creature. Deterministic from the seed.
func _build(view: bool) -> void:
	world = World.new()
	world.lite = touch
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.generate(seed_, era.id)
	if view:
		_environment()
	exit_node = Exit.new()
	exit_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(exit_node)
	exit_node.setup(world, sounds, null, era.exit)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 99
	var mstart := _creature_start(rng, 60.0, 85.0)
	var facing := (world.spawn - mstart).normalized().rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
	mill = _spawn_hunter(mstart, facing)
	if era.id == "permian":
		_populate_permian(rng)
	else:
		_populate_carboniferous(rng)
	netted = []
	netted.append_array(flies)
	netted.append_array(eryopses)
	netted.append_array(scorps)
	netted.append_array(grazers)
	netted.append_array(dicys)
	if mode == "client":
		for c in netted:
			c.puppet = true


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
		var herd := {"center": c}
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


func _spawn_hunter(at: Vector3, facing: Vector3) -> Node3D:
	var m: Node3D = Gorgon.new() if era.id == "permian" else Millipede.new()
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
		if absf(p.x) < lim and absf(p.z) < lim and p.distance_to(world.exit_pos) > 40.0:
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
	var m := {
		"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "light": [KEY_F],
		"emote1": [KEY_1], "emote2": [KEY_2], "emote3": [KEY_3], "emote4": [KEY_4], "mute": [KEY_M],
	}
	for a in m:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in m[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)


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
	if flags.has("exit"):
		var back := Vector3(sin(world.exit_yaw), 0, cos(world.exit_yaw))
		var p := world.exit_pos + back * 12.0
		p.y = world.height_at(p.x, p.z)
		local.position = p
		local.yaw = world.exit_yaw
	if flags.has("yaw"):
		local.yaw = deg_to_rad(float(flags.yaw))
	if flags.has("pitch"):
		local.pitch = deg_to_rad(float(flags.pitch))
	if flags.has("light"):
		local.light.visible = true
	local.rotation.y = local.yaw
	local.head.rotation.x = local.pitch
	if flags.has("mill"):
		var fwd := Basis(Vector3.UP, local.yaw) * Vector3.FORWARD
		var at := local.position + fwd * float(flags.mill)
		var old := mill
		hunters.erase(old)
		old.queue_free()
		mill = _spawn_hunter(at, Basis(Vector3.UP, float(flags.get("mturn", "1.1"))) * -fwd)
	if flags.has("near"):
		var pool := {"eryops": eryopses, "scorp": scorps, "scuto": grazers, "dicy": dicys}.get(flags.near, []) as Array
		var target: Node3D = pool[0] if not pool.is_empty() else null
		if target:
			var dist := float(flags.get("neard", "12" if target is Eryops else "7"))
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
			local.pitch = -0.12
			local.rotation.y = local.yaw
			local.head.rotation.x = local.pitch
	for k in int(flags.get("shots", "0")):
		shots[k].done = true
		_escalate(false)
	if shots.all(func(sh: Dictionary) -> bool: return sh.done):
		lists_done[my_id] = true
	hud.set_shots(shots)
	if flags.has("fly"):
		for f in flies:
			f.position = local.position + Vector3(randf_range(-4, 4), 2.5, randf_range(-6, -2)).rotated(Vector3.UP, local.yaw)


# ================================================================ title and lobby

func _title() -> void:
	state = "title"
	menu = ""
	if Net.online:
		_room_menu()
		return
	var controls := "left thumb move (drag past the ring to run)\nright thumb look" if touch else "WASD move    SHIFT run    C crouch    F lamp"
	hud.show_card("DEEP TIME", "LEVEL %d  -  %s" % [level, era.title], era.intro + "\n\n" + controls,
		"tap to start recording" if touch else "click to start recording")
	hud.show_stages(_stage_list(level), _pick_stage)
	hud.show_menu([{"type": "button", "text": "PLAY WITH FRIENDS", "cb": _coop_menu}])


func _stage_list(current: int) -> Array:
	var stages := []
	for n in range(1, Eras.COUNT + 1):
		var e := Eras.get_era(n)
		var label := "%d %s" % [n, e.title]
		var locked := n > Run.unlocked and n != current
		if locked:
			label = "%d ??????" % n
		elif Run.best.has(n):
			label += " (%s)" % Run.clock(float(Run.best[n]))
		stages.append({"n": n, "label": label, "locked": locked, "current": n == current})
	return stages


func _pick_stage(n: int) -> void:
	if Net.online:
		lobby_level = n
		_room_menu()
		return
	if n == level:
		_start()
		return
	Run.level = n
	Run.autostart = true
	get_tree().reload_current_scene()


func _coop_menu() -> void:
	menu = "coop"
	hud.show_card("PLAY WITH FRIENDS", "up to 4 camcorders", "", "")
	hud.show_stages([], Callable())
	var saved := Run.player_name if Run.player_name != "" else ""
	hud.show_menu([
		{"type": "edit", "id": "name", "text": saved, "hint": "YOUR NAME"},
		{"type": "button", "text": "HOST A ROOM", "cb": func() -> void: _coop_go(true)},
		{"type": "row", "items": [
			{"type": "edit", "id": "code", "text": "", "hint": "CODE", "width": 70},
			{"type": "button", "text": "JOIN", "cb": func() -> void: _coop_go(false)},
		]},
		{"type": "button", "text": "BACK", "cb": _title},
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
	Net.join(Net.server_url(flags), n, c, create)


func _room_menu() -> void:
	menu = "room"
	var names := []
	for id in Net.members:
		var m: Dictionary = Net.members[id]
		names.append(m.name + ("  (host)" if int(id) == Net.host_id else "") + ("  (you)" if int(id) == Net.my_id else ""))
	hud.show_card("ROOM  " + Net.code, "tell your friends the code", "\n".join(names), "")
	var host := Net.host_id == Net.my_id
	lobby_level = clampi(lobby_level, 1, Eras.COUNT)
	hud.show_stages(_stage_list(lobby_level) if host else [], _pick_stage)
	var items := []
	if host:
		items.append({"type": "button", "text": "START  -  LEVEL %d" % lobby_level, "cb": func() -> void: Net.start_level(lobby_level)})
	else:
		items.append({"type": "label", "text": "waiting for %s to start" % Net.members.get(Net.host_id, {}).get("name", "the host")})
	items.append({"type": "label", "text": "mic on - they'll hear you when you're close" if Net.voice.mic_ok() else "no mic - you can still listen"})
	items.append({"type": "button", "text": "LEAVE", "cb": func() -> void: Net.leave()})
	items.append({"type": "status"})
	hud.show_menu(items)


func _on_room_changed() -> void:
	if mode == "client" and Net.phase == "lobby":
		get_tree().reload_current_scene()
		return
	if state == "title":
		_room_menu()
		_auto_start_check()


func _on_left() -> void:
	if mode == "client":
		get_tree().reload_current_scene()
	elif state == "title":
		_title()


## Dev: ?host=NAME (+code=ABCD, autostart) or ?join=CODE (+name=) to skip the menus.
func _auto_coop() -> void:
	if Net.online or state != "title":
		return
	if flags.has("host"):
		Net.join(Net.server_url(flags), flags.host, str(flags.get("code", "")), true)
	elif flags.has("join"):
		Net.join(Net.server_url(flags), str(flags.get("name", "")), flags.join, false)


func _auto_start_check() -> void:
	if flags.has("autostart") and Net.host_id == Net.my_id and Net.members.size() >= int(flags.get("autostart", "2")):
		Net.start_level(int(flags.get("level", "1")))


# ================================================================ playing

func _start() -> void:
	state = "play"
	state_t = 0.0
	hud.hide_card()
	hud.show_stages([], Callable())
	hud.show_menu([])
	local.begin()
	exit_node.begin()
	amb.play()
	rain.play(randf() * 60.0)
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
	var tips := [["", 1.5], ["fill the shot list.  keep them in frame.", 4.5], [era.tip, 4.5],
		["the lamp helps.  the flies like it too." if touch else "SHIFT run   C crouch   F lamp", 5.0]]
	if mode == "client":
		tips.append(["talking is noise too." if Net.voice.mic_ok() else "", 4.0])
		if not touch:
			tips.push_front(["click to grab the camera", 3.0])
			tips.append(["1 wave  2 point  3 scream  4 flash   M mute", 5.0])
	hud.say(tips)


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
	pshots[id] = _fresh_shots()
	if sim_on:
		p.begin()


func remove_net_player(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		pshots.erase(id)
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
	p.talk = clampf(a[6], 0.0, 1.0)


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
	for p: Player in alive_players():
		_film_for(p, dt)
	for p: Player in alive_players():
		if lists_done.get(p.id, false) and exit_node.inside(p):
			_through(p)
	if mode == "server":
		tick += 1
		if tick % SNAP_EVERY == 0:
			Net.room_snapshot(net_room, _snapshot())
		_check_end()


func _emit(ev: Array) -> void:
	if mode == "server":
		Net.room_event(net_room, ev)
	else:
		_on_event(ev)


func _kill(p: Player, at: Vector3) -> void:
	if p == null or not p.alive or p.through or not sim_on:
		return
	p.alive = false
	p.vanish()
	var push := (p.global_position - at)
	push.y = 0.0
	push = push.normalized() * 5.0
	_emit(["dead", p.id, at.x, at.y, at.z, push.x, push.z])


func _through(p: Player) -> void:
	p.through = true
	p.vanish()
	_emit(["through", p.id, elapsed])


func _check_end() -> void:
	if not sim_on or players.is_empty() or not alive_players().is_empty():
		return
	sim_on = false
	var cleared := false
	for p: Player in players.values():
		if p.through:
			cleared = true
	_emit(["end", 1 if cleared else 0])
	if mode == "server":
		Net.room_over(net_room, cleared)


## Filming: keep a creature near the centre of frame, close enough, with
## nothing in the way, and the shot fills up.
func _film_for(p: Player, dt: float) -> void:
	var list: Array = pshots.get(p.id, [])
	var best: Dictionary = {}
	for sh in list:
		if sh.done:
			continue
		var framed := false
		for pt in _film_points(sh.id):
			if _framed(p.cam, pt, sh.range, p):
				framed = true
				break
		if framed and best.is_empty():
			best = sh
		else:
			sh.prog = maxf(0.0, sh.prog - dt * 0.5)
	if p == local:
		hud.focus_name = "" if best.is_empty() else best.name
	if best.is_empty():
		return
	best.prog += dt
	if p == local:
		hud.focus_prog = clampf(best.prog / best.need, 0.0, 1.0)
	if best.prog < best.need:
		return
	best.done = true
	var n := 0
	for sh in list:
		if sh.done:
			n += 1
	_emit(["shot", p.id, list.find(best)])
	# the team's progress sets how bold the hunters are
	var most := 0
	for id in pshots:
		var c := 0
		for sh in pshots[id]:
			if sh.done:
				c += 1
		most = maxi(most, c)
	for m in hunters:
		m.drift = 0.45 + most * 0.1
		m.hunt_speed += 0.15
	if n == list.size():
		lists_done[p.id] = true
		if not hunter2:
			hunter2 = true
			var at := _ring(p.position, 45.0, 60.0)
			var m2 := _spawn_hunter(at, Vector3.FORWARD)
			m2.drift = 0.8
			m2.hunt_speed += 0.6
			m2.begin()
			_emit(["hunter2", at.x, at.y, at.z])


func _film_points(id: String) -> Array:
	var out := []
	match id:
		"fly":
			for f in flies:
				out.append(f.global_position)
		"eryops":
			for e in eryopses:
				if e.position.y > Eryops.SURFACE - 0.08:
					out.append(e.film_point())
		"scorp":
			for sc in scorps:
				out.append(sc.film_point())
		"hunter":
			for m in hunters:
				out.append_array(m.film_points())
		"scuto":
			for g in grazers:
				out.append(g.film_point())
		"dicy":
			for d in dicys:
				if d.out():
					out.append(d.film_point())
	return out


func _framed(cam: Camera3D, pt: Vector3, max_d: float, who: Player) -> bool:
	var from := cam.global_position
	var to := pt - from
	var d := to.length()
	if d > max_d or d < 0.3:
		return false
	var fwd := -cam.global_transform.basis.z
	if fwd.dot(to / d) < cos(deg_to_rad(14.0)):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, pt, 1)
	q.exclude = [who.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func emote(id: int, e: int) -> void:
	var p: Player = players.get(id)
	if p == null or not p.alive or p.through:
		return
	if e == 3:
		_on_noise(p.position, 28.0)
	elif e == 4:
		_on_noise(p.position, 8.0)
	_emit(["emote", id, e])


func _snapshot() -> PackedFloat32Array:
	var a := PackedFloat32Array([Time.get_ticks_msec() / 1000.0, players.size()])
	for id in players:
		var p: Player = players[id]
		var bits := (1 if p.crouching else 0) | (2 if p.light.visible else 0) | (4 if p.alive else 0) \
			| (8 if p.through else 0) | (16 if p.moving else 0)
		var done := 0
		for sh in pshots.get(id, []):
			if sh.done:
				done += 1
		var slot: int = net_room.members.get(id, {}).get("color", 0)
		a.append_array([slot, p.position.x, p.position.y, p.position.z, p.yaw, p.pitch, bits, p.seq,
			p.stamina, p.battery, done, p.talk])
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
	var bits := (1 if local.last_sprint else 0) | (2 if local.crouching else 0) | (4 if local.light.visible else 0)
	var talk := 0.0 if Net.voice.muted else Net.voice.level
	Net.send_input(PackedFloat32Array([in_seq, local.last_move.x, local.last_move.y, local.yaw, local.pitch, bits, talk]))
	sent[in_seq] = local.position


func _on_snap(a: PackedFloat32Array) -> void:
	if a.size() < 2:
		return
	var i := 2
	var present := {}
	for k in int(a[1]):
		var pid := _id_for_slot(int(a[i]))
		var pos := Vector3(a[i + 1], a[i + 2], a[i + 3])
		var bits := int(a[i + 6])
		var entry := {"pos": pos, "yaw": a[i + 4], "pitch": a[i + 5], "alive": bits & 4 != 0, "through": bits & 8 != 0,
			"done": int(a[i + 10]), "talk": a[i + 11]}
		if pid == my_id:
			_reconcile(pos, int(a[i + 7]), a[i + 8], a[i + 9])
		elif pid != -1:
			var av: Avatar = avatars.get(pid)
			if av == null:
				var info: Dictionary = Net.members.get(pid, {"name": "?", "color": 0})
				av = Avatar.new()
				add_child(av)
				av.setup(pid, info.name, Net.COLORS[int(info.color) % Net.COLORS.size()], sounds)
				avatars[pid] = av
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
	if sent.has(seq):
		var err: Vector3 = pos - sent[seq]
		err.y = 0.0
		var fix := Vector3.ZERO
		if err.length() > 4.0:
			fix = err
		elif err.length() > 0.05:
			fix = err * 0.2
		local.position += fix
		for k in sent.keys():
			if k <= seq:
				sent.erase(k)
			else:
				sent[k] += fix
	if absf(local.stamina - stam) > 0.15:
		local.stamina = stam
	local.battery = batt
	if batt <= 0.0:
		local.light.visible = false


# ================================================================ events (solo applies them directly)

func _name(id: int) -> String:
	return str(Net.members.get(id, {}).get("name", "someone"))


func _on_event(ev: Array) -> void:
	match str(ev[0]):
		"go":
			_start()
		"shot":
			if int(ev[1]) == my_id:
				var idx := int(ev[2])
				if idx >= 0 and idx < shots.size():
					shots[idx].done = true
				hud.focus_name = ""
				hud.flash = 1.2
				sfx.stream = sounds.beep
				sfx.volume_db = -4.0
				sfx.play()
				hud.set_shots(shots)
				_escalate(true)
		"hunter2":
			if mode == "client" and not hunter2:
				hunter2 = true
				var m := _spawn_hunter(Vector3(ev[1], ev[2], ev[3]), Vector3.FORWARD)
				m.begin()
			sfx.stream = sounds.crack
			sfx.volume_db = 4.0
			sfx.play()
			hud.say([["something else woke up.", 4.0]])
		"dead":
			var at := Vector3(ev[2], ev[3], ev[4])
			if int(ev[1]) == my_id:
				_local_dead(at)
			else:
				var av: Avatar = avatars.get(int(ev[1]))
				if av:
					var rd := Ragdoll.new()
					add_child(rd)
					rd.setup(av.parts, av.global_position, av.yaw, Vector3(ev[5], 2.0, ev[6]))
					av.visible = false
					get_tree().create_timer(40.0).timeout.connect(rd.queue_free)
				hud.say([["%s  -  SIGNAL LOST" % _name(int(ev[1])), 3.5]])
		"through":
			if int(ev[1]) == my_id:
				_local_through()
			else:
				hud.say([["%s slipped through" % _name(int(ev[1])), 3.5]])
		"end":
			if mode == "client":
				_end_card(int(ev[1]) == 1)
		"emote":
			_show_emote(int(ev[1]), int(ev[2]))


func _local_dead(at: Vector3) -> void:
	state = "dead"
	state_t = 0.0
	local.vanish()
	local.die(at)
	hud.say([])
	sfx.stream = sounds.hiss
	sfx.volume_db = 2.0
	sfx.play()
	if mode == "solo":
		for m in hunters:
			m.active = false


func _local_through() -> void:
	if mode == "solo":
		_win()
		return
	state = "through"
	state_t = 0.0
	local.through = true
	local.vanish()
	sfx.stream = sounds.hum
	sfx.play()
	Run.record(level, elapsed)
	hud.say([["you slipped through.", 3.0], ["watching the others...", 3.0]])


func _end_card(cleared: bool) -> void:
	state = "card"
	state_t = 0.0
	spectating = false
	var made := 0
	for e in net_players.values():
		if e.through:
			made += 1
	if cleared:
		hud.show_card("NOCLIP", "%d of %d made it through" % [made, net_players.size()],
			era.title + "  -  " + Run.clock(elapsed), "going deeper in a moment..." if level < Eras.COUNT else "that's the whole tape. back to the room...", 0.85)
	else:
		hud.show_card("SIGNAL LOST", "nobody made it", era.title, "rewinding the tape...", 0.85)


func _win() -> void:
	state = "won"
	state_t = 0.0
	local.control = false
	for m in hunters:
		m.active = false
	hud.say([])
	sfx.stream = sounds.hum
	sfx.play()
	var prev_best: float = float(Run.best.get(level, -1.0))
	var fresh := Run.record(level, elapsed)
	var times := "%s   (%s)" % [Run.clock(elapsed), "new best" if fresh else "best " + Run.clock(float(Run.best[level]))]
	if prev_best < 0.0:
		times = Run.clock(elapsed)
	var more := level < Eras.COUNT
	var next_line := "next:  LEVEL %d  -  %s" % [level + 1, Eras.get_era(level + 1).title] if more \
		else "that's everything on the tape so far.\nmore of deep time is coming."
	win_text = "%s  -  %d of %d shots  -  %s\n\n%s" % [era.title, shots.size(), shots.size(), times, next_line]
	win_foot = ("tap" if touch else "click") + (" to keep going down" if more else " to start again")


# ================================================================ emotes and voice

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
## dead (and those already through) hear everyone.
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
		Net.voice.peer(pid, e.pos + Vector3(0, 1.6, 0), gain, out and me_out)


func _roster_tick(dt: float) -> void:
	roster_t -= dt
	if roster_t > 0.0:
		return
	roster_t = 0.25
	var lines := []
	for id in Net.members:
		var m: Dictionary = Net.members[id]
		var e: Dictionary = net_players.get(int(id), {})
		var tag := ""
		if int(id) == my_id:
			tag = " *"
		var st := ""
		if not e.is_empty():
			if e.through:
				st = "  >>"
			elif not e.alive:
				st = "  x"
			else:
				st = "  %d/%d" % [e.done, shots.size()]
			if e.alive and float(e.talk) > 0.03:
				st += "  )))"
		lines.append([str(m.name) + tag + st, Net.COLORS[int(m.color) % Net.COLORS.size()]])
	hud.set_roster(lines, "MIC OFF" if Net.voice.muted else ("MIC" if Net.voice.mic_ok() else ""))


# ================================================================ frame

func _unhandled_input(e: InputEvent) -> void:
	if mode == "client" and state == "play":
		for k in EMOTES:
			if e.is_action_pressed("emote%d" % k):
				_emote_pressed(k)
		if e.is_action_pressed("mute"):
			_toggle_mic()
	if mode == "client" and spectating and e is InputEventMouseButton and e.pressed:
		_next_spec()
	if not (e is InputEventMouseButton and e.pressed):
		return
	match state:
		"title":
			if not Net.online and menu == "":
				_start()
		"play":
			if not touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_tree().paused = false
				hud.paused_label.visible = false
		"dead", "won":
			if mode == "solo" and state_t > 1.5:
				get_tree().paused = false
				if state == "won":
					Run.level = level + 1 if level < Eras.COUNT else 1
				Run.autostart = true
				get_tree().reload_current_scene()


func _process(dt: float) -> void:
	if mode == "server":
		return
	state_t += dt
	emote_cool -= dt
	if state == "play":
		_play_tick(dt)
	elif state == "dead":
		if mode == "client":
			_dead_client(dt)
		else:
			_dead_solo(dt)
	elif state == "through" and state_t > 2.0 and not spectating:
		_spectate()
	elif state == "won":
		hud.white = minf(1.0, state_t * 0.8)
		amb.volume_db = -6.0 - state_t * 12.0
		rain.volume_db = -15.0 - state_t * 12.0
		if state_t > 1.6:
			hud.white = 0.0
			hud.glitch = 0.0
			hud.show_card("NOCLIP", "you slipped through the layer", win_text, win_foot)
	if mode == "client":
		if state != "won":
			hud.white = maxf(0.0, hud.white - dt * 0.7)
		if spectating:
			_spec_tick(dt)
		_voice_tick()
		_roster_tick(dt)
	if flags.has("die") and state == "play" and state_t > 1.0:
		flags.erase("die")
		_kill(local, mill.head_pos())
	if flags.has("win") and state == "play" and state_t > 1.0:
		flags.erase("win")
		_win()


func _dead_solo(dt: float) -> void:
	hud.glitch = minf(1.0, hud.glitch + dt * 2.0) if state_t < 1.9 else 0.15
	if state_t > 0.9 and state_t - dt <= 0.9:
		sfx.stream = sounds.death
		sfx.play()
		amb.stop()
		rain.stop()
	if state_t > 0.9:
		hud.static_amt = minf(1.0, (state_t - 0.9) * 3.0)
	if state_t > 1.9:
		hud.static_amt = 0.4
		hud.show_card("SIGNAL LOST", "", "the tape ends at %s" % hud.tc.text, "tap to rewind" if touch else "click to rewind", 0.6)


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
	# their lamp is your lamp now
	hud.glitch = 0.08


func _play_tick(dt: float) -> void:
	if mode == "client":
		elapsed += dt  # the authority counts it in _physics_process
	if flags.has("debug") and int(elapsed * 2.0) != int((elapsed - dt) * 2.0):
		var others := ""
		for pid in avatars:
			others += " | %s at %.1f,%.1f" % [avatars[pid].pname, avatars[pid].position.x, avatars[pid].position.z]
		print("pos %.1f,%.1f yaw %.2f  hunter %s%s" % [local.position.x, local.position.z, local.yaw,
			mill.state + (" seen %.2f" % mill.seen if mill is Gorgon else ""), others])
	hud.clock = elapsed
	hud.set_battery(local.battery, local.light.visible)
	var d := 999.0
	var hunted := 0.0
	for m in hunters:
		d = minf(d, Vector2(local.position.x - m.head_pos().x, local.position.z - m.head_pos().z).length())
		if m.is_hunting():
			hunted = 1.0
	var near := clampf(1.0 - d / 22.0, 0.0, 1.0)
	hud.glitch = lerpf(hud.glitch, near * near * 0.4, 1.0 - exp(-dt * 4.0))
	hud.dark = lerpf(hud.dark, 1.0 - local.stamina, 1.0 - exp(-dt * 3.0))
	local.fear = lerpf(local.fear, maxf(near, hunted * 0.7), 1.0 - exp(-dt * 1.5))
	# the frogs go quiet when it's close
	amb.volume_db = lerpf(amb.volume_db, lerpf(era.loops[0][1], -30.0, local.fear), 1.0 - exp(-dt * 1.2))
	if mode == "client":
		_film_preview(dt)
		if flags.has("emote") and emote_cool <= -2.0:  # dev: emote on repeat
			_emote_pressed(int(flags.emote))
	if not exit_node.on and exit_node.near_door():
		door_hint -= dt
		if door_hint <= 0.0:
			door_hint = 12.0
			hud.say([["it's dark.  your shot list isn't finished.", 4.0]])
	# the swamp is never quite silent
	next_event -= dt
	if next_event <= 0.0:
		next_event = randf_range(25.0, 60.0)
		_distant_event()
	if flags.has("attract"):
		local.rotation.y = local.yaw
		local.head.rotation.x = local.pitch
	if mode == "solo" and not flags.has("play") and not touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		get_tree().paused = true
		hud.paused_label.visible = true


## Client: the viewfinder brackets are drawn locally; the server decides
## when a shot is actually done.
func _film_preview(dt: float) -> void:
	var best: Dictionary = {}
	for sh in shots:
		if sh.done:
			continue
		for pt in _film_points(sh.id):
			if _framed(local.cam, pt, sh.range, local):
				best = sh
				break
		if not best.is_empty():
			break
	for sh in shots:
		if sh != best:
			sh.prog = maxf(0.0, sh.prog - dt * 0.5)
	if best.is_empty():
		hud.focus_name = ""
		return
	best.prog = minf(best.prog + dt, best.need)
	hud.focus_name = best.name
	hud.focus_prog = clampf(best.prog / best.need, 0.0, 1.0)


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


## Every finished shot pulls the dark in closer. (What it does to the hunters
## is the authority's business, in _film_for.)
func _escalate(live: bool) -> void:
	var n := 0
	for sh in shots:
		if sh.done:
			n += 1
	var k := n / float(shots.size())
	var base: Color = era.fog
	var fog := base.lerp(base * 0.5, k)
	fog.a = 1.0
	env.fog_light_color = fog
	env.background_color = fog
	env.ambient_light_energy = lerpf(era.ambient_energy, era.ambient_energy * 0.45, k)
	sun.light_energy = lerpf(era.sun_energy, era.sun_energy * 0.3, k)
	if n == shots.size():
		exit_node.activate()
	if not live:
		return
	if n < shots.size():
		hud.say([["SHOT %d / %d" % [n, shots.size()], 2.5], ["it's getting darker.", 3.5]])
	else:
		hud.say([["SHOT LIST COMPLETE", 3.0], ["somewhere, a light came on.", 4.0]])
