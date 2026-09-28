extends Node3D
## DEEP TIME, Level 1: the Coal Forest.
##
## Dev flags (URL query on web, `-- key=value` on desktop):
##   play        skip the title card          seed=N   fixed layout
##   mill=D      put it D m in front of you   exit     start 12 m from the door
##   light       lamp on                      freeze   creatures hold still
##   yaw=deg / pitch=deg   look direction     die / win   trigger the ending

const FOG := Color(0.16, 0.19, 0.155)

var flags := {}
var sounds := {}
var world: World
var player: Player
var mill: Millipede
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	flags = _parse_flags()
	get_tree().root.size_changed.connect(_fit)
	_fit()
	_input_map()
	sounds = Synth.all()
	var seed_ := int(flags.get("seed", str(randi() % 1000000)))
	print("seed ", seed_)

	touch = flags.has("touch") or DisplayServer.is_touchscreen_available()
	world = World.new()
	world.lite = touch
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.generate(seed_)
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
	exit_node.setup(world, sounds, player)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 99
	var mstart := _creature_start(rng, 60.0, 85.0)
	var facing := (world.spawn - mstart).normalized().rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
	mill = Millipede.new()
	mill.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(mill)
	mill.setup(world, player, sounds, mstart, facing)
	mill.caught.connect(_on_caught)
	mill.alerted.connect(func() -> void: player.fear = maxf(player.fear, 0.8))

	for k in 4:
		var f := Meganeura.new()
		f.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(f)
		f.setup(world, player, sounds, _creature_start(rng, 15.0, 45.0), _on_noise)
		flies.append(f)

	hud = Hud.new()
	add_child(hud)
	if touch:
		var pad := TouchPad.new()
		pad.player = player
		hud.add_touch(pad)
		player.touch = pad
	# field recordings (CC0, see audio/CREDITS.md): frogs and insects over dripping canopy
	amb = _loop_player("res://audio/frogswamp.ogg", -6.0)
	rain = _loop_player("res://audio/darkrain.ogg", -15.0)
	sfx = AudioStreamPlayer.new()
	add_child(sfx)

	_apply_dev_flags()
	if flags.has("play"):
		_start()
	else:
		hud.show_card("DEEP TIME", "LEVEL 1  -  THE COAL FOREST",
			"307 million years before anyone.\nSomewhere in the fog there is a way through.\n\nIt cannot see you. It feels you move.\n\n" + ("left thumb move (drag past the ring to run)\nright thumb look" if touch else "WASD move    SHIFT run    C crouch    F lamp"),
			"tap to start recording" if touch else "click to start recording")


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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.4, 0.32)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = FOG
	env.fog_density = 0.05
	env.fog_sky_affect = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color(0.75, 0.88, 0.78)
	sun.light_energy = 0.55
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
		mill = Millipede.new()
		mill.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(mill)
		mill.setup(world, player, sounds, at, Basis(Vector3.UP, float(flags.get("mturn", "1.1"))) * -fwd)
		mill.caught.connect(_on_caught)
		old.queue_free()
	if flags.has("fly"):
		for f in flies:
			f.position = player.position + Vector3(randf_range(-4, 4), 2.5, randf_range(-6, -2)).rotated(Vector3.UP, player.yaw)


func _start() -> void:
	state = "play"
	state_t = 0.0
	hud.hide_card()
	player.begin()
	exit_node.begin()
	amb.play()
	rain.play(randf() * 60.0)
	if not flags.has("freeze"):
		mill.begin()
		for f in flies:
			f.begin()
	if not flags.has("play") and not touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.say([["", 1.5], ["find a way through", 4.0], ["it can't see you.  it feels you move.", 4.5],
		["the lamp helps.  the flies like it too." if touch else "SHIFT run   C crouch   F lamp", 5.0]])


func _on_noise(at: Vector3, radius: float) -> void:
	if mill:
		mill.hear(at, radius)


func _on_caught() -> void:
	if state != "play":
		return
	state = "dead"
	state_t = 0.0
	player.die(mill.head_pos() + Vector3(0, 0.3, 0))
	hud.say([])
	sfx.stream = sounds.hiss
	sfx.volume_db = 2.0
	sfx.play()


func _win() -> void:
	state = "won"
	state_t = 0.0
	player.control = false
	mill.active = false
	hud.say([])
	sfx.stream = sounds.hum
	sfx.play()


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
			hud.show_card("NOCLIP", "you slipped through the layer",
				"THE COAL FOREST  -  cleared in %s\n\nnext:  LEVEL 2  -  THE PERMIAN\n(not yet recorded)" % hud.tc.text,
				"tap to go again" if touch else "click to go again")
	if flags.has("die") and state == "play" and state_t > 1.0:
		flags.erase("die")
		_on_caught()
	if flags.has("win") and state == "play" and state_t > 1.0:
		flags.erase("win")
		_win()


func _play_tick(dt: float) -> void:
	elapsed += dt
	if flags.has("debug") and int(elapsed * 2.0) != int((elapsed - dt) * 2.0):
		print("pos %.1f,%.1f yaw %.2f" % [player.position.x, player.position.z, player.yaw])
	hud.clock = elapsed
	hud.set_battery(player.battery, player.light.visible)
	var d := Vector2(player.position.x - mill.head_pos().x, player.position.z - mill.head_pos().z).length()
	var near := clampf(1.0 - d / 22.0, 0.0, 1.0)
	hud.glitch = lerpf(hud.glitch, near * near * 0.4, 1.0 - exp(-dt * 4.0))
	hud.dark = lerpf(hud.dark, 1.0 - player.stamina, 1.0 - exp(-dt * 3.0))
	var hunted := 1.0 if mill.state == "hunt" else 0.0
	player.fear = lerpf(player.fear, maxf(near, hunted * 0.7), 1.0 - exp(-dt * 1.5))
	# the frogs go quiet when it's close
	amb.volume_db = lerpf(amb.volume_db, lerpf(-6.0, -30.0, player.fear), 1.0 - exp(-dt * 1.2))
	if exit_node.inside():
		_win()
	# the swamp is never quite silent
	next_event -= dt
	if next_event <= 0.0:
		next_event = randf_range(25.0, 60.0)
		_distant_event()
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
