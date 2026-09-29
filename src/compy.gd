class_name Compy
extends Node3D
## Compsognathus: chicken-sized, in a little pack, and thieves. They pick
## up loot left lying around (including what you set down on the way back)
## and run it to their hoard. Close to you they chirp, and raptors listen
## for that. A shovel makes them drop it.

var world: World
var session: Node
var idx := 0  # its place in the creature list
var home := Vector3.ZERO
var dir := Vector3.FORWARD
var speed := 0.0
var state := "roam"
var target := Vector3.ZERO
var goal: Loot
var holding := -1
var scared := 0.0
var think := 0.0
var chirp_t := 0.0
var t := 0.0
var active := false
var puppet := false
var net_pos := Vector3.ZERO
var model: DinoModel
var mouth: MeshInstance3D
var chirp: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()


func setup(w: World, sess: Node, s: Dictionary, at: Vector3, i: int, hoard: Vector3) -> void:
	world = w
	session = sess
	idx = i
	home = hoard
	rng.seed = hash([at.x, at.z, i])
	position = at
	net_pos = at
	target = at
	model = DinoModel.new()
	add_child(model)
	model.setup("Velociraptor", 0.11, "Compy")
	mouth = MeshInstance3D.new()
	mouth.position = Vector3(0, 0.45, -0.45)
	mouth.scale = Vector3.ONE * 0.8
	add_child(mouth)
	chirp = AudioStreamPlayer3D.new()
	chirp.stream = s.squeak
	chirp.unit_size = 5.0
	chirp.max_distance = 50.0
	add_child(chirp)


func begin() -> void:
	active = true


func net_get(out: PackedFloat32Array) -> void:
	out.append_array([position.x, position.y, position.z, dir.x, dir.z, speed, holding])


func net_set(a: PackedFloat32Array, i: int) -> int:
	net_pos = Vector3(a[i], a[i + 1], a[i + 2])
	var d := Vector3(a[i + 3], 0, a[i + 4])
	if d.length() > 0.01:
		dir = d.normalized()
	speed = a[i + 5]
	var h := int(a[i + 6])
	if h != holding:
		holding = h
		mouth.mesh = session.loot[h].mesh if h >= 0 and h < session.loot.size() else null
	return i + 7


## Hit with a shovel: drop it and scatter.
func whack(from: Vector3) -> void:
	scared = 6.0
	var away := position - from
	away.y = 0.0
	dir = away.normalized() if away.length() > 0.01 else dir
	_drop_it()
	state = "roam"
	target = position + dir * 20.0


func _drop_it() -> void:
	if holding < 0:
		return
	var at := position + dir * 0.4
	at.y = world.height_at(at.x, at.z)
	session.compy_drop(self, holding, at)
	holding = -1
	mouth.mesh = null


func _physics_process(dt: float) -> void:
	t += dt
	if puppet:
		if net_pos.distance_to(position) > 6.0:
			position = net_pos
		position = position.lerp(net_pos, 1.0 - exp(-dt * 10.0))
		_pose()
		return
	if not active:
		return
	scared = maxf(0.0, scared - dt)
	think -= dt
	var near: Player = session.nearest_player(position)
	var pd := 999.0
	if near:
		pd = Vector2(near.position.x - position.x, near.position.z - position.z).length()
	# chirping at people: raptors come to see what the fuss is
	chirp_t -= dt
	if pd < 6.0 and chirp_t <= 0.0:
		chirp_t = 1.6
		session.compy_chirp(self)
	var want := 0.0
	match state:
		"roam":
			want = 2.0 if scared <= 0.0 else 7.0
			if position.distance_to(target) < 1.0 or think < -6.0:
				var a := rng.randf() * TAU
				target = home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.0, 18.0)
				think = 0.0
			if think <= 0.0 and scared <= 0.0:
				think = 1.5
				goal = session.compy_find(self)
				if goal:
					state = "fetch"
		"fetch":
			want = 5.5
			if goal == null or not goal.on_ground():
				state = "roam"
			else:
				target = goal.position
				if Vector2(goal.position.x - position.x, goal.position.z - position.z).length() < 0.9:
					if session.compy_take(self, goal):
						holding = goal.idx
						mouth.mesh = goal.mesh
						state = "carry"
					else:
						state = "roam"
		"carry":
			want = 5.0
			target = home
			if pd < 3.0:  # someone's coming for it: run
				var away := position - near.position
				away.y = 0.0
				target = position + away.normalized() * 8.0
				want = 6.5
			if Vector2(home.x - position.x, home.z - position.z).length() < 1.5:
				_drop_it()
				state = "roam"
	var to := target - position
	to.y = 0.0
	if to.length() > 0.2:
		var nd := dir.lerp(to.normalized(), 1.0 - exp(-dt * 6.0))
		if nd.length() > 0.01:
			dir = nd.normalized()
	else:
		want = 0.0
	speed = move_toward(speed, want, dt * 12.0)
	position += dir * speed * dt
	position.y = world.height_at(position.x, position.z)
	_pose()


func _pose() -> void:
	rotation.y = atan2(-dir.x, -dir.z)
	model.move(speed, 1.2, 5.0)
