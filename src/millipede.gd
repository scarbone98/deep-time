class_name Millipede
extends Node3D
## Arthropleura, scaled up. Blind: it hunts by the vibration of footsteps.
## Stand still or crouch-walk and it loses you. Run and it knows exactly where you are.

signal caught(victim: Player)
signal alerted

const N := 22
const S := 1.4
const SP := 0.28 * S
const RIDE := 0.17 * S

var world: World
var session: Node
var player: Player
var puppet := false
var feeding := 0.0
var net_head := Vector3.ZERO
var pos: Array[Vector3] = []
var nodes: Array[Node3D] = []
var legs: Array = []
var dir := Vector3.FORWARD
var state := "roam"
var target := Vector3.ZERO
var home := Vector3.ZERO
var timer := 0.0
var t := 0.0
var speed := 0.0
var want_speed := 1.3
var wiggle := 0.5
var rear := 0.0
var gait := 0.0
var active := false
var drift := 0.45  # how often roaming heads your way
var hunt_speed := 5.2
var hear_off := false  # attract mode: it just passes by
var skitter: AudioStreamPlayer3D
var hiss: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()


func setup(w: World, sess: Node, s: Dictionary, start: Vector3, facing: Vector3) -> void:
	world = w
	session = sess
	rng.randomize()
	var mat := Meshes.chitin()
	var seg := Meshes.mill_segment(mat)
	var headm := Meshes.mill_segment(mat, true)
	var leg_r := Meshes.mill_leg(mat, 1.0)
	var leg_l := Meshes.mill_leg(mat, -1.0)
	dir = Vector3(facing.x, 0, facing.z).normalized()
	for i in N:
		var n := Node3D.new()
		add_child(n)
		var taper := 1.0
		if i >= N - 7:
			taper = lerpf(1.0, 0.4, float(i - (N - 7)) / 7.0)
		var mi := MeshInstance3D.new()
		mi.mesh = headm if i == 0 else seg
		mi.scale = Vector3(taper, lerpf(0.7, 1.0, taper), 1.0)
		n.add_child(mi)
		var ls := []
		if i > 0:
			for pair in 2:
				for side in [1.0, -1.0]:
					var pv := Node3D.new()
					pv.position = Vector3(0.28 * side * taper, 0.03, -0.08 + pair * 0.16)
					pv.scale = Vector3.ONE * lerpf(0.7, 1.0, taper)
					var lm := MeshInstance3D.new()
					lm.mesh = leg_r if side > 0.0 else leg_l
					pv.add_child(lm)
					n.add_child(pv)
					ls.append(pv)
		legs.append(ls)
		nodes.append(n)
		var q := start - dir * SP * i
		q.y = world.height_at(q.x, q.z) + RIDE
		pos.append(q)
	skitter = AudioStreamPlayer3D.new()
	skitter.stream = s.skitter
	skitter.unit_size = 5.0
	skitter.max_distance = 70.0
	nodes[0].add_child(skitter)
	hiss = AudioStreamPlayer3D.new()
	hiss.stream = s.hiss
	hiss.unit_size = 10.0
	hiss.max_distance = 90.0
	nodes[0].add_child(hiss)
	target = start + dir * 10.0
	net_head = pos[0]
	_pose()


func begin() -> void:
	active = true
	skitter.play()


func head_pos() -> Vector3:
	return pos[0]


func is_hunting() -> bool:
	return state == "hunt"


func film_points() -> Array:
	return [pos[0] + Vector3(0, 0.3, 0), pos[N / 2] + Vector3(0, 0.3, 0)]


const STATES := ["roam", "investigate", "search", "hunt"]


func net_get(out: PackedFloat32Array) -> void:
	out.append_array([pos[0].x, pos[0].y, pos[0].z, dir.x, dir.z, speed, STATES.find(state), rear])


func net_set(a: PackedFloat32Array, i: int) -> int:
	net_head = Vector3(a[i], a[i + 1], a[i + 2])
	var d := Vector3(a[i + 3], 0, a[i + 4])
	if d.length() > 0.01:
		dir = d.normalized()
	speed = a[i + 5]
	var st: String = STATES[clampi(int(a[i + 6]), 0, 3)]
	if st == "hunt" and state != "hunt":
		hiss.play()
	state = st
	rear = a[i + 7]
	return i + 8


func _puppet(dt: float) -> void:
	t += dt
	if net_head.distance_to(pos[0]) > 6.0:
		pos[0] = net_head
	pos[0] = pos[0].lerp(net_head, 1.0 - exp(-dt * 10.0))
	_follow()
	gait += speed * dt * 7.0
	skitter.volume_db = linear_to_db(clampf(speed / 5.0, 0.12, 1.0)) + 3.0
	skitter.pitch_scale = 0.75 + speed * 0.09
	_pose()


func _physics_process(dt: float) -> void:
	if puppet:
		_puppet(dt)
		return
	if not active:
		return
	t += dt
	player = session.nearest_player(pos[0])
	if feeding > 0.0:
		feeding -= dt
		want_speed = 0.0
	if player == null:
		want_speed = 0.0
	else:
		_think(dt)
	var p0 := pos[0]
	var to := target - p0
	to.y = 0.0
	var want := dir
	if to.length() > 0.3:
		want = to.normalized()
	want = want.rotated(Vector3.UP, sin(t * 2.1) * 0.5 * wiggle)
	# feel around trunks and logs
	var ahead := p0 + dir * 1.6
	for tr in world.trunks_near(ahead.x, ahead.z, 4.0):
		var away := Vector3(ahead.x - tr.x, 0, ahead.z - tr.y)
		var dd := away.length()
		var lim: float = tr.z + 1.3
		if dd < lim and dd > 0.01:
			want += away / dd * (lim - dd) / lim * 2.5
	var lim_b := World.BOUND - 6.0
	if absf(p0.x) > lim_b:
		want.x -= signf(p0.x) * 2.0
	if absf(p0.z) > lim_b:
		want.z -= signf(p0.z) * 2.0
	want.y = 0.0
	want = want.normalized()
	var turn := 3.2 if state == "hunt" else 1.8
	var nd := dir.lerp(want, 1.0 - exp(-dt * turn))
	dir = nd.normalized() if nd.length() > 0.01 else dir.rotated(Vector3.UP, 0.5)
	speed = move_toward(speed, want_speed, dt * 4.0)
	p0 += dir * speed * dt
	p0.y = world.height_at(p0.x, p0.z) + RIDE
	pos[0] = p0
	_follow()
	gait += speed * dt * 7.0
	rear = lerpf(rear, 0.55 if state == "search" else 0.0, 1.0 - exp(-dt * 2.0))
	skitter.volume_db = linear_to_db(clampf(speed / 5.0, 0.12, 1.0)) + 3.0
	skitter.pitch_scale = 0.75 + speed * 0.09
	_pose()


func _follow() -> void:
	for i in range(1, N):
		var d: Vector3 = pos[i] - pos[i - 1]
		d.y = 0.0
		if d.length() < 0.001:
			d = -dir
		var q: Vector3 = pos[i - 1] + d.normalized() * SP
		q.y = world.height_at(q.x, q.z) + RIDE
		pos[i] = q


func _pose() -> void:
	var shown := []
	for i in N:
		var q: Vector3 = pos[i]
		if i < 5:
			q.y += rear * S * (1.0 - i / 5.0) * (1.0 + 0.15 * sin(t * 3.0))
		shown.append(q)
	for i in N:
		var f: Vector3 = dir if i == 0 else (shown[i - 1] - shown[i])
		if i == 0:
			f = (dir + Vector3(0, (shown[0].y - shown[1].y) / SP, 0))
		if f.length() < 0.001:
			f = dir
		nodes[i].global_transform = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP).scaled(Vector3.ONE * S), shown[i])
		var ls: Array = legs[i]
		for k in ls.size():
			var side := 1.0 if k % 2 == 0 else -1.0
			var ph := gait - i * 0.7 - (k / 2) * 0.35 + (0.0 if side > 0.0 else PI)
			var sw := sin(ph) * 0.5
			var lift := maxf(0.0, cos(ph)) * 0.45
			(ls[k] as Node3D).rotation = Vector3(0, sw * side, lift * side)


func _dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _think(dt: float) -> void:
	var pp := player.global_position
	var d := _dist2(pp, pos[0])
	if player.alive and not hear_off and feeding <= 0.0:
		var feel := 3.2 if player.moving else 1.7
		if d < feel:
			_hunt(pp)
		if d < 1.3 and feeding <= 0.0:
			caught.emit(player)
			feeding = 3.0
			_pick_roam()
			return
	var arrive := _dist2(target, pos[0]) < 1.5
	match state:
		"roam":
			want_speed = 1.3
			wiggle = 0.5
			timer -= dt
			if arrive or timer <= 0.0:
				_pick_roam()
		"investigate":
			want_speed = 1.6 if hear_off else 2.7
			wiggle = 0.25
			if arrive:
				_search(target)
		"search":
			want_speed = 0.8
			wiggle = 1.3
			timer -= dt
			if arrive:
				target = home + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			if timer <= 0.0:
				_pick_roam()
		"hunt":
			want_speed = hunt_speed
			wiggle = 0.08
			timer -= dt
			if arrive or timer <= 0.0:
				_search(target)


func _hunt(at: Vector3) -> void:
	if state != "hunt":
		alerted.emit()
		hiss.play()
	state = "hunt"
	target = at
	timer = 4.0


func _search(at: Vector3) -> void:
	state = "search"
	home = at
	timer = 8.0
	target = home + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))


func _pick_roam() -> void:
	state = "roam"
	timer = 22.0
	var a := rng.randf() * TAU
	var off := Vector3(cos(a), 0, sin(a))
	# it drifts your way more often than chance would say
	if rng.randf() < drift and player:
		target = player.global_position + off * rng.randf_range(15.0, 32.0)
	else:
		target = pos[0] + off * rng.randf_range(15.0, 40.0)
	var lim := World.BOUND - 8.0
	target.x = clampf(target.x, -lim, lim)
	target.z = clampf(target.z, -lim, lim)


## Its nest was robbed: it knows exactly where.
func alarm(at: Vector3) -> void:
	if active and feeding <= 0.0 and not hear_off:
		_hunt(at)
		timer = 8.0


func hear(at: Vector3, radius: float) -> void:
	if not active or hear_off or feeding > 0.0:
		return
	var d := _dist2(at, pos[0])
	if d > radius:
		return
	var err := d * 0.18
	var guess := at + Vector3(rng.randf_range(-err, err), 0, rng.randf_range(-err, err))
	if state == "hunt" or d < 16.0:
		_hunt(guess)
	else:
		state = "investigate"
		target = guess
