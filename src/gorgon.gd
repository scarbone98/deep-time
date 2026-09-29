class_name Gorgon
extends Node3D
## Inostrancevia. Deaf to footsteps, but its eyes miss nothing: awareness
## builds while you're in its sight (faster when close, moving, or lit),
## and it charges faster than you can run. Break line of sight behind rock
## and it goes to where it last saw you, and searches.

signal caught(victim: Player)
signal alerted

## Tunables that the dinosaurs (Raptor, TRex) change.
var size := 1.25
var catch_range := 2.7
var head_off := Vector3(0, 0.85, -2.0)
var eye_off := Vector3(0, 1.1, -2.4)
var sight := 40.0
var lit_sight := 75.0
var stalk_speed := 2.3
var prowl_speed := 1.6
var thud_pitch := 0.58
var gait_rate := 2.4
var jaw: Node3D
var stunned := 0.0

var world: World
var session: Node
var player: Player
var puppet := false
var feeding := 0.0
var net_pos := Vector3.ZERO
var dir := Vector3.FORWARD
var speed := 0.0
var want_speed := 1.6
var state := "prowl"
var target := Vector3.ZERO
var last_seen := Vector3.ZERO
var seen := 0.0
var lost := 0.0
var timer := 0.0
var t := 0.0
var gait := 0.0
var active := false
var drift := 0.45
var hunt_speed := 6.7
var hear_off := false
var sees := false
var rig: Node3D
var head: Node3D
var legs: Array[Node3D] = []
var growl: AudioStreamPlayer3D
var roar: AudioStreamPlayer3D
var thud: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()


func setup(w: World, sess: Node, s: Dictionary, at: Vector3, facing: Vector3) -> void:
	world = w
	session = sess
	rng.randomize()
	dir = Vector3(facing.x, 0, facing.z).normalized()
	position = Vector3(at.x, world.height_at(at.x, at.z), at.z)
	_tune()
	scale = Vector3.ONE * size
	rig = Node3D.new()
	rig.position.y = 0.42
	add_child(rig)
	_build_body()
	growl = _audio(s.growl, 6.0, 60.0)
	roar = _audio(s.roar, 14.0, 140.0)
	thud = _audio(s.step, 8.0, 50.0)
	_voice()
	target = position + dir * 10.0
	net_pos = position
	_pose()


## Subclasses set their numbers here.
func _tune() -> void:
	pass


## Subclasses pitch their voices here.
func _voice() -> void:
	pass


func _build_body() -> void:
	var m := Meshes.gorgon()
	var body := MeshInstance3D.new()
	body.mesh = m.body
	rig.add_child(body)
	for hip in [[0.36, -0.72, false], [-0.36, -0.72, false], [0.36, 0.7, true], [-0.36, 0.7, true]]:
		var pv := Node3D.new()
		pv.position = Vector3(hip[0], 0.3, hip[1])
		rig.add_child(pv)
		var lm := MeshInstance3D.new()
		lm.mesh = m.leg_b if hip[2] else m.leg_f
		lm.scale = Vector3(signf(hip[0]), 1, 1)
		pv.add_child(lm)
		legs.append(pv)


func _audio(stream: AudioStream, unit: float, far: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.unit_size = unit
	a.max_distance = far
	a.position = Vector3(0, 0.8, -1.6)
	add_child(a)
	return a


func begin() -> void:
	active = true


func head_pos() -> Vector3:
	return to_global(head_off)


func is_hunting() -> bool:
	return state == "charge"


func film_points() -> Array:
	return [head_pos(), to_global(Vector3(0, 0.8, 0))]


## Its nest was robbed: it comes looking, already half-sure.
func alarm(at: Vector3) -> void:
	if not active or feeding > 0.0:
		return
	last_seen = Vector3(at.x, 0, at.z)
	seen = maxf(seen, 0.6)
	state = "search"
	timer = 14.0
	target = last_seen
	growl.play()


func hear(_at: Vector3, _radius: float) -> void:
	pass  # it doesn't


const STATES := ["prowl", "stalk", "charge", "search"]


func net_get(out: PackedFloat32Array) -> void:
	out.append_array([position.x, position.y, position.z, dir.x, dir.z, speed, 5 if stunned > 0.0 else (STATES.find(state) if feeding <= 0.0 else 4)])


func net_set(a: PackedFloat32Array, i: int) -> int:
	net_pos = Vector3(a[i], a[i + 1], a[i + 2])
	var d := Vector3(a[i + 3], 0, a[i + 4])
	if d.length() > 0.01:
		dir = d.normalized()
	speed = a[i + 5]
	var si := int(a[i + 6])
	stunned = 1.0 if si == 5 else 0.0
	if si == 5:
		si = STATES.find(state)
	if si == 4 and feeding <= 0.0:
		_bite()
	feeding = 1.0 if si == 4 else 0.0
	var st: String = STATES[clampi(si, 0, 3)] if si < 4 else state
	if st != state:
		if st == "stalk":
			growl.play()
		elif st == "charge":
			roar.play()
	state = st
	return i + 7


func _puppet(dt: float) -> void:
	if net_pos.distance_to(position) > 8.0:
		position = net_pos
	position = position.lerp(net_pos, 1.0 - exp(-dt * 10.0))
	var prev := gait
	gait += speed * dt * gait_rate
	_footfall(prev)
	_pose()


func _footfall(prev: float) -> void:
	if (state == "charge" or thud_pitch < 0.4) and speed > 0.5 and int(prev / PI) != int(gait / PI):
		thud.pitch_scale = thud_pitch * rng.randf_range(0.9, 1.1)
		thud.play()


func _physics_process(dt: float) -> void:
	if puppet:
		_puppet(dt)
		return
	if not active:
		return
	t += dt
	if stunned > 0.0:
		stunned -= dt
		want_speed = 0.0
		speed = move_toward(speed, 0.0, dt * 12.0)
		seen = 0.0
	elif feeding > 0.0:
		feeding -= dt
		want_speed = 0.0
		seen = 0.0
	else:
		_look(dt)
		if player == null:
			want_speed = 0.0
		else:
			_think(dt)
	var to := target - position
	to.y = 0.0
	var want := dir
	if to.length() > 0.4:
		want = to.normalized()
	if state == "search":
		want = want.rotated(Vector3.UP, sin(t * 1.3) * 0.9)
	var ahead := position + dir * 3.0
	for tr in world.trunks_near(ahead.x, ahead.z, 8.0):
		var away := Vector3(ahead.x - tr.x, 0, ahead.z - tr.y)
		var dd := away.length()
		var lim: float = tr.z + 2.2
		if dd < lim and dd > 0.01:
			want += away / dd * (lim - dd) / lim * 3.0
	var lim_b := World.BOUND - 8.0
	if absf(position.x) > lim_b:
		want.x -= signf(position.x) * 2.0
	if absf(position.z) > lim_b:
		want.z -= signf(position.z) * 2.0
	want.y = 0.0
	want = want.normalized()
	var turn := 2.6 if state == "charge" else 1.6
	var nd := dir.lerp(want, 1.0 - exp(-dt * turn))
	dir = nd.normalized() if nd.length() > 0.01 else dir.rotated(Vector3.UP, 0.5)
	speed = move_toward(speed, want_speed, dt * (6.0 if state == "charge" else 2.5))
	var step := dir * speed * dt
	# don't walk into rock
	var nxt := position + step
	var blocked := false
	for tr in world.trunks_near(nxt.x, nxt.z, 6.0):
		if Vector2(nxt.x - tr.x, nxt.z - tr.y).length() < float(tr.z) * 0.8 + 0.8:
			blocked = true
	if not blocked:
		position = nxt
	else:
		dir = dir.rotated(Vector3.UP, 1.5 * dt * 3.0)
	position.y = lerpf(position.y, world.height_at(position.x, position.z), 1.0 - exp(-dt * 12.0))
	var prev := gait
	gait += speed * dt * gait_rate
	_footfall(prev)
	_pose()


## Looks for everyone; locks on to the closest person it can see.
func _look(dt: float) -> void:
	sees = false
	player = session.nearest_player(position)
	if player == null:
		return
	var fwd := dir
	var eye := to_global(eye_off)
	var best := 1e9
	var reach := 40.0
	var d := 0.0
	var pp := Vector3.ZERO
	for p: Player in session.alive_players():
		if not _notices(p):
			continue
		var at: Vector3 = p.global_position + Vector3(0, 0.6 if p.crouching else 1.3, 0)
		var to := at - eye
		var dd := to.length()
		var r := lit_sight if p.light.visible else sight
		if p.crouching:
			r *= 0.6
		if dd < r and dd < best and (fwd.dot(to / dd) > cos(deg_to_rad(65.0)) or dd < 7.0) and world.clear_line(eye, at):
			best = dd
			sees = true
			player = p
			reach = r
			d = dd
			pp = at
	if sees:
		var rate := (0.2 + (1.0 - d / reach) * 1.3) * (1.4 if player.moving else 0.6)
		if player.light.visible:
			rate *= 1.4
		seen = minf(1.2, seen + dt * rate)
		last_seen = Vector3(pp.x, 0, pp.z)
		lost = 0.0
	else:
		seen = maxf(0.0, seen - dt * (0.06 if state == "charge" else 0.15))
		lost += dt


## A shovel to the head or a flash in the eyes.
func stun(secs: float) -> void:
	stunned = maxf(stunned, secs)
	state = "search"
	timer = 8.0
	growl.pitch_scale = 1.4
	growl.play()


## The kill (on the server) or the lunge (as everyone sees it).
func _bite() -> void:
	pass


## Whether it can pick this player out at all (the T. rex only sees movement).
func _notices(_p: Player) -> bool:
	return true


func _think(dt: float) -> void:
	var pp := player.global_position
	var d := Vector2(pp.x - position.x, pp.z - position.z).length()
	if player.alive and d < catch_range and not hear_off:
		caught.emit(player)
		_bite()
		feeding = 3.5
		_pick_prowl()
		return
	var arrive := Vector2(target.x - position.x, target.z - position.z).length() < 2.0
	match state:
		"prowl":
			want_speed = prowl_speed
			timer -= dt
			if arrive or timer <= 0.0:
				_pick_prowl()
			if seen > 0.3 and not hear_off:
				state = "stalk"
				growl.play()
		"stalk":
			want_speed = stalk_speed
			target = last_seen
			if seen >= 1.0:
				state = "charge"
				roar.play()
				alerted.emit()
			elif seen <= 0.05:
				_search()
		"charge":
			want_speed = hunt_speed
			target = pp if sees else last_seen
			if not sees and (arrive or lost > 4.0):
				_search()
		"search":
			want_speed = 1.1
			timer -= dt
			if arrive:
				target = last_seen + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
			if seen > 0.55:
				state = "charge"
				roar.play()
				alerted.emit()
			elif timer <= 0.0:
				_pick_prowl()


func _search() -> void:
	state = "search"
	timer = 10.0
	target = last_seen


func _pick_prowl() -> void:
	state = "prowl"
	timer = 25.0
	var a := rng.randf() * TAU
	var off := Vector3(cos(a), 0, sin(a))
	if rng.randf() < drift and player:
		target = player.global_position + off * rng.randf_range(20.0, 40.0)
	else:
		target = position + off * rng.randf_range(20.0, 45.0)
	var lim := World.BOUND - 10.0
	target.x = clampf(target.x, -lim, lim)
	target.z = clampf(target.z, -lim, lim)


func _pose() -> void:
	rotation.y = atan2(-dir.x, -dir.z)
	var amp := clampf(speed / 3.0, 0.0, 1.0)
	var run := clampf((speed - 3.0) / 3.0, 0.0, 1.0)
	for k in legs.size():
		# trot: diagonal pairs together; gallop: fronts and backs pair up
		var ph := gait + (0.0 if k in [0, 3] else PI)
		ph = lerpf(ph, gait + (0.0 if k < 2 else PI * 0.6), run)
		legs[k].rotation.x = sin(ph) * 0.55 * amp
	var low := 0.12 if state == "stalk" else 0.0
	rig.position.y = 0.42 - low + absf(sin(gait)) * 0.05 * amp
	rig.rotation.x = -low * 0.3 + sin(gait * 2.0) * 0.02 * run
