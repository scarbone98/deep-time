extends Node3D
## DEEP TIME: Backrooms through prehistory. One scene, rebuilt per level
## from the era table in eras.gd; Run carries progress across reloads.
##
## Dev flags (URL query on web, `-- key=value` on desktop):
##   play        skip the title card          seed=N   fixed layout
##   mill=D      put it D m in front of you   exit     start 12 m from the door
##   light       lamp on                      freeze   creatures hold still
##   yaw=deg / pitch=deg   look direction     die / win   trigger the ending
##   shots=N     first N shots already filmed near=eryops|scorp  start by one
##   level=N     play that level              attract  cabinet video scene

var level := 1
var era: Dictionary

var flags := {}
var sounds := {}
var world: World
var player: Player
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
var env: Environment
var sun: DirectionalLight3D
var door_hint := 0.0
var shots: Array = []
var win_text := ""
var win_foot := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	flags = _parse_flags()
	get_tree().root.size_changed.connect(_fit)
	_fit()
	_input_map()
	Run.load_save()
	level = clampi(int(flags.get("level", str(Run.level))), 1, Eras.COUNT)
	Run.level = level
	era = Eras.get_era(level)
	shots = era.shots.duplicate(true)
	sounds = Synth.all()
	var seed_ := int(flags.get("seed", str(randi() % 1000000)))
	print("seed ", seed_)

	touch = flags.has("touch") or DisplayServer.is_touchscreen_available()
	world = World.new()
	world.lite = touch
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.generate(seed_, era.id)
	_environment()

	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.setup(world, sounds)
	player.position = world.spawn
	player.yaw = world.spawn_yaw
	player.noise.connect(_on_noise)

	exit_node = Exit.new()
	exit_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(exit_node)
	exit_node.setup(world, sounds, player, era.exit)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 99
	var mstart := _creature_start(rng, 60.0, 85.0)
	var facing := (world.spawn - mstart).normalized().rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
	mill = _spawn_hunter(mstart, facing)
	if era.id == "permian":
		_populate_permian(rng)
	else:
		_populate_carboniferous(rng)
	for sh in shots:
		sh.prog = 0.0
		sh.done = false

	hud = Hud.new()
	add_child(hud)
	if touch:
		var pad := TouchPad.new()
		pad.player = player
		hud.add_touch(pad)
		player.touch = pad
	# field recordings (CC0, see audio/CREDITS.md)
	amb = _loop_player(era.loops[0][0], era.loops[0][1])
	rain = _loop_player(era.loops[1][0], era.loops[1][1])
	hud.date.text = era.date
	sfx = AudioStreamPlayer.new()
	add_child(sfx)

	hud.set_shots(shots)
	_apply_dev_flags()
	if flags.has("play") or Run.autostart:
		Run.autostart = false
		_start()
	else:
		_title()


func _title() -> void:
	var controls := "left thumb move (drag past the ring to run)\nright thumb look" if touch else "WASD move    SHIFT run    C crouch    F lamp"
	hud.show_card("DEEP TIME", "LEVEL %d  -  %s" % [level, era.title], era.intro + "\n\n" + controls,
		"tap to start recording" if touch else "click to start recording")
	var stages := []
	for n in range(1, Eras.COUNT + 1):
		var e := Eras.get_era(n)
		var label := "%d %s" % [n, e.title]
		if n > Run.unlocked and n != level:
			label = "%d ??????" % n
		elif Run.best.has(n):
			label += " (%s)" % Run.clock(float(Run.best[n]))
		stages.append({"n": n, "label": label, "locked": n > Run.unlocked and n != level, "current": n == level})
	hud.show_stages(stages, _pick_stage)


func _pick_stage(n: int) -> void:
	if n == level:
		_start()
		return
	Run.level = n
	Run.autostart = true
	get_tree().reload_current_scene()


func _populate_carboniferous(rng: RandomNumberGenerator) -> void:

	for k in 4:
		var f := Meganeura.new()
		f.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(f)
		f.setup(world, player, sounds, _creature_start(rng, 15.0, 45.0), _on_noise)
		flies.append(f)

	for at in world.pools(3):
		var e := Eryops.new()
		e.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(e)
		e.setup(world, player, sounds, at)
		eryopses.append(e)
	var spots := world.log_spots.duplicate()
	spots.shuffle()
	for spot in spots:
		if scorps.size() >= 5:
			break
		var lp: Vector3 = spot[0]
		if Vector2(lp.x - world.spawn.x, lp.z - world.spawn.z).length() < 25.0:
			continue
		var yaw: float = spot[1]
		var side := Vector3(sin(yaw), 0, cos(yaw)) * (1.4 if randf() < 0.5 else -1.4)
		var at := lp + side
		at.y = world.height_at(at.x, at.z)
		var sc := Scorpion.new()
		sc.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(sc)
		sc.setup(player, sounds, at, atan2(side.x, side.z))
		sc.struck.connect(func() -> void: _killed(sc.global_position + Vector3(0, 0.5, 0)))
		scorps.append(sc)


func _populate_permian(rng: RandomNumberGenerator) -> void:
	var sm := Meshes.scutosaurus()
	for h in 3:
		var c := _creature_start(rng, 35.0, 90.0)
		var herd := {"center": c}
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
			d.setup(world, player, sounds, dm, b)
			dicys.append(d)


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


func _spawn_hunter(at: Vector3, facing: Vector3) -> Node3D:
	var m: Node3D = Gorgon.new() if era.id == "permian" else Millipede.new()
	m.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(m)
	m.setup(world, player, sounds, at, facing)
	m.caught.connect(func() -> void: _killed(m.head_pos() + Vector3(0, 0.3, 0)))
	m.alerted.connect(func() -> void: player.fear = maxf(player.fear, 0.8))
	hunters.append(m)
	return m


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
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _apply_dev_flags() -> void:
	if flags.has("exit"):
		var back := Vector3(sin(world.exit_yaw), 0, cos(world.exit_yaw))
		var p := world.exit_pos + back * 12.0
		p.y = world.height_at(p.x, p.z)
		player.position = p
		player.yaw = world.exit_yaw
	if flags.has("yaw"):
		player.yaw = deg_to_rad(float(flags.yaw))
	if flags.has("pitch"):
		player.pitch = deg_to_rad(float(flags.pitch))
	if flags.has("light"):
		player.light.visible = true
	player.rotation.y = player.yaw
	player.head.rotation.x = player.pitch
	if flags.has("mill"):
		var fwd := Basis(Vector3.UP, player.yaw) * Vector3.FORWARD
		var at := player.position + fwd * float(flags.mill)
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
			player.position = p
			var to := target.global_position - p
			player.yaw = atan2(-to.x, -to.z)
			player.pitch = -0.12
			player.rotation.y = player.yaw
			player.head.rotation.x = player.pitch
	for k in int(flags.get("shots", "0")):
		shots[k].done = true
		_escalate(false)
	hud.set_shots(shots)
	if flags.has("fly"):
		for f in flies:
			f.position = player.position + Vector3(randf_range(-4, 4), 2.5, randf_range(-6, -2)).rotated(Vector3.UP, player.yaw)


func _start() -> void:
	state = "play"
	state_t = 0.0
	hud.hide_card()
	hud.show_stages([], Callable())
	player.begin()
	exit_node.begin()
	amb.play()
	rain.play(randf() * 60.0)
	if not flags.has("freeze"):
		for m in hunters:
			m.begin()
		for g in grazers:
			g.begin()
		for d in dicys:
			d.begin()
		for f in flies:
			f.begin()
		for e in eryopses:
			e.begin()
		for sc in scorps:
			sc.begin()
	if not flags.has("play") and not touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if flags.has("attract") and era.id == "carboniferous":
		_attract()
		# recording is slow: the capture script sets ts so a frame is 1/30 s
		Engine.time_scale = float(flags.get("ts", "1"))
		return
	hud.say([["", 1.5], ["fill the shot list.  keep them in frame.", 4.5], [era.tip, 4.5],
		["the lamp helps.  the flies like it too." if touch else "SHIFT run   C crouch   F lamp", 5.0]])


## Cabinet video: lamp on, a slow look around while it crosses in front.
func _attract() -> void:
	player.control = false
	player.light.visible = true
	var fwd := Basis(Vector3.UP, player.yaw) * Vector3.FORWARD
	var right := Basis(Vector3.UP, player.yaw) * Vector3.RIGHT
	mill.pos[0] = player.position + fwd * 7.0 + right * 6.0
	for i in mill.pos.size():
		mill.pos[i] = mill.pos[0] + right * Millipede.SP * i
	mill.dir = -right
	mill.state = "investigate"
	mill.target = player.position + fwd * 5.0 - right * 20.0
	mill.hear_off = true
	for k in flies.size():
		flies[k].position = player.position + fwd * (4.0 + k) + Vector3(randf_range(-3, 3), 2.0, 0)
	var tw := create_tween()
	tw.tween_property(player, "pitch", -0.18, 4.0)
	tw.parallel().tween_property(player, "yaw", player.yaw + 0.5, 15.0)


func _on_noise(at: Vector3, radius: float) -> void:
	for m in hunters:
		m.hear(at, radius)
	for e in eryopses:
		e.hear(at, radius)


func _killed(at: Vector3) -> void:
	if state != "play":
		return
	state = "dead"
	state_t = 0.0
	for m in hunters:
		m.active = false
	player.die(at)
	hud.say([])
	sfx.stream = sounds.hiss
	sfx.volume_db = 2.0
	sfx.play()


func _win() -> void:
	state = "won"
	state_t = 0.0
	player.control = false
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


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	match state:
		"title":
			_start()
		"play":
			if not touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_tree().paused = false
				hud.paused_label.visible = false
		"dead", "won":
			if state_t > 1.5:
				get_tree().paused = false
				if state == "won":
					Run.level = level + 1 if level < Eras.COUNT else 1
				Run.autostart = true
				get_tree().reload_current_scene()


func _process(dt: float) -> void:
	state_t += dt
	if state == "play":
		_play_tick(dt)
	elif state == "dead":
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
	elif state == "won":
		hud.white = minf(1.0, state_t * 0.8)
		amb.volume_db = -6.0 - state_t * 12.0
		rain.volume_db = -15.0 - state_t * 12.0
		if state_t > 1.6:
			hud.white = 0.0
			hud.glitch = 0.0
			hud.show_card("NOCLIP", "you slipped through the layer", win_text, win_foot)
	if flags.has("die") and state == "play" and state_t > 1.0:
		flags.erase("die")
		_killed(mill.head_pos())
	if flags.has("win") and state == "play" and state_t > 1.0:
		flags.erase("win")
		_win()


func _play_tick(dt: float) -> void:
	elapsed += dt
	if flags.has("debug") and int(elapsed * 2.0) != int((elapsed - dt) * 2.0):
		print("pos %.1f,%.1f yaw %.2f  hunter %s" % [player.position.x, player.position.z, player.yaw,
			mill.state + (" seen %.2f" % mill.seen if mill is Gorgon else "")])
	hud.clock = elapsed
	hud.set_battery(player.battery, player.light.visible)
	var d := 999.0
	var hunted := 0.0
	for m in hunters:
		d = minf(d, Vector2(player.position.x - m.head_pos().x, player.position.z - m.head_pos().z).length())
		if m.is_hunting():
			hunted = 1.0
	var near := clampf(1.0 - d / 22.0, 0.0, 1.0)
	hud.glitch = lerpf(hud.glitch, near * near * 0.4, 1.0 - exp(-dt * 4.0))
	hud.dark = lerpf(hud.dark, 1.0 - player.stamina, 1.0 - exp(-dt * 3.0))
	player.fear = lerpf(player.fear, maxf(near, hunted * 0.7), 1.0 - exp(-dt * 1.5))
	# the frogs go quiet when it's close
	amb.volume_db = lerpf(amb.volume_db, lerpf(-6.0, -30.0, player.fear), 1.0 - exp(-dt * 1.2))
	if not flags.has("attract"):
		_film(dt)
	if exit_node.on and exit_node.inside():
		_win()
	elif not exit_node.on and exit_node.near_door():
		door_hint -= dt
		if door_hint <= 0.0:
			door_hint = 12.0
			hud.say([["it's dark.  the shot list isn't finished.", 4.0]])
	# the swamp is never quite silent
	next_event -= dt
	if next_event <= 0.0:
		next_event = randf_range(25.0, 60.0)
		_distant_event()
	if flags.has("attract"):
		player.rotation.y = player.yaw
		player.head.rotation.x = player.pitch
	if not flags.has("play") and not touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		get_tree().paused = true
		hud.paused_label.visible = true


func _distant_event() -> void:
	var a := randf() * TAU
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds.call if randf() < 0.5 else sounds.crack
	p.unit_size = 30.0
	p.max_distance = 200.0
	p.pitch_scale = randf_range(0.7, 1.1)
	add_child(p)
	p.global_position = player.global_position + Vector3(cos(a), 2.0, sin(a)) * randf_range(50.0, 90.0)
	p.play()
	p.finished.connect(p.queue_free)


## Filming: keep a creature near the centre of frame, close enough, with
## nothing in the way, and the shot fills up.
func _film(dt: float) -> void:
	var best: Dictionary = {}
	for sh in shots:
		if sh.done:
			continue
		var framed := false
		for pt in _film_points(sh.id):
			if _framed(pt, sh.range):
				framed = true
				break
		if framed and best.is_empty():
			best = sh
		else:
			sh.prog = maxf(0.0, sh.prog - dt * 0.5)
	if best.is_empty():
		hud.focus_name = ""
		return
	best.prog += dt
	hud.focus_name = best.name
	hud.focus_prog = clampf(best.prog / best.need, 0.0, 1.0)
	if best.prog >= best.need:
		best.done = true
		hud.focus_name = ""
		hud.flash = 1.2
		sfx.stream = sounds.beep
		sfx.volume_db = -4.0
		sfx.play()
		hud.set_shots(shots)
		_escalate(true)


func _film_points(id: String) -> Array:
	var out := []
	match id:
		"fly":
			for f in flies:
				out.append(f.global_position)
		"eryops":
			for e in eryopses:
				if e.surfaced():
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


func _framed(pt: Vector3, max_d: float) -> bool:
	var from := player.cam.global_position
	var to := pt - from
	var d := to.length()
	if d > max_d or d < 0.3:
		return false
	var fwd := -player.cam.global_transform.basis.z
	if fwd.dot(to / d) < cos(deg_to_rad(14.0)):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, pt)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Every finished shot pulls the dark in closer and makes it bolder.
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
	for m in hunters:
		m.drift = 0.45 + n * 0.1
		m.hunt_speed += 0.15
	if not live:
		if n == shots.size():
			exit_node.activate()
		return
	if n < shots.size():
		hud.say([["SHOT %d / %d" % [n, shots.size()], 2.5], ["the swamp is getting darker.", 3.5]])
		return
	# the list is done: the way out wakes up, and so does something else
	exit_node.activate()
	sfx.stream = sounds.crack
	sfx.volume_db = 4.0
	sfx.play()
	var m2 := _spawn_hunter(_ring(player.position, 45.0, 60.0), Vector3.FORWARD)
	m2.drift = 0.8
	m2.hunt_speed += 0.6
	m2.begin()
	hud.say([["SHOT LIST COMPLETE", 3.0], ["somewhere, a light came on.", 4.0], ["something else woke up with it.", 4.5]])
