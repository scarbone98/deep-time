class_name Meganeura
extends Node3D
## Giant griffinfly. Mostly just there, darting through the canopy.
## They're drawn to the camcorder lamp, and their droning gives you away.

var world: World
var session: Node
var player: Player
var puppet := false
var net_pos := Vector3.ZERO
var vel := Vector3.ZERO
var goal := Vector3.ZERO
var home := Vector3.ZERO
var rest := 0.0
var t := 0.0
var pester := 0.0
var active := false
var body: Node3D
var wings: Array[Node3D] = []
var buzz: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()
var on_noise: Callable


func setup(w: World, sess: Node, s: Dictionary, start: Vector3, noise_cb: Callable) -> void:
	world = w
	session = sess
	on_noise = noise_cb
	rng.randomize()
	t = rng.randf() * 10.0
	home = start
	position = start + Vector3(0, 6, 0)
	goal = position
	body = Node3D.new()
	add_child(body)
	var bm := MeshInstance3D.new()
	bm.mesh = Meshes.fly_body()
	body.add_child(bm)
	var wm := Meshes.fly_wing()
	for z in [-0.03, 0.05]:
		for side in [1.0, -1.0]:
			var pv := Node3D.new()
			pv.position = Vector3(0.04 * side, 0.05, z)
			body.add_child(pv)
			var mi := MeshInstance3D.new()
			mi.mesh = wm
			mi.scale = Vector3(side, 1, 1)
			pv.add_child(mi)
			wings.append(pv)
	buzz = AudioStreamPlayer3D.new()
	buzz.stream = s.wings
	buzz.unit_size = 2.5
	buzz.max_distance = 45.0
	buzz.pitch_scale = rng.randf_range(0.85, 1.15)
	add_child(buzz)


func begin() -> void:
	active = true
	buzz.play()


func net_get(out: PackedFloat32Array) -> void:
	out.append_array([position.x, position.y, position.z, vel.x, vel.y, vel.z])


func net_set(a: PackedFloat32Array, i: int) -> int:
	net_pos = Vector3(a[i], a[i + 1], a[i + 2])
	vel = Vector3(a[i + 3], a[i + 4], a[i + 5])
	return i + 6


func _process(dt: float) -> void:
	if puppet:
		t += dt
		if net_pos.distance_to(position) > 10.0:
			position = net_pos
		position = position.lerp(net_pos + vel * 0.05, 1.0 - exp(-dt * 10.0))
		_animate(dt)
		return
	if not active:
		return
	t += dt
	rest -= dt
	player = session.lit_player(position)
	if player == null:
		return
	var pp := player.global_position
	var lit := player.light.visible
	var d := global_position.distance_to(pp)
	if rest <= 0.0:
		if lit and d < 45.0 and player.alive:
			var fwd := -player.cam.global_transform.basis.z
			goal = player.cam.global_position + fwd * rng.randf_range(2.0, 5.0) \
				+ Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.5, 1.5))
			rest = rng.randf_range(0.3, 1.0)
		else:
			if Vector2(home.x - pp.x, home.z - pp.z).length() > 55.0:
				var a := rng.randf() * TAU
				home = pp + Vector3(cos(a), 0, sin(a)) * 30.0
			goal = home + Vector3(rng.randf_range(-18, 18), 0, rng.randf_range(-18, 18))
			goal.y = world.height_at(goal.x, goal.z) + rng.randf_range(2.5, 11.0)
			rest = rng.randf_range(1.0, 3.5)
		goal.y = maxf(goal.y, world.height_at(goal.x, goal.z) + 1.0)
	var desired := (goal - global_position) * 2.2
	if desired.length() > 10.0:
		desired = desired.normalized() * 10.0
	vel = vel.lerp(desired, 1.0 - exp(-dt * 4.0))
	vel += Vector3(sin(t * 7.1), sin(t * 5.3) * 0.6, cos(t * 6.7)) * dt * 3.0
	global_position += vel * dt
	global_position.y = maxf(global_position.y, world.height_at(global_position.x, global_position.z) + 0.8)
	_animate(dt)
	if lit and d < 6.0 and player.alive:
		pester += dt
		if pester > 2.0:
			pester = 0.0
			on_noise.call(pp, 15.0)
	else:
		pester = maxf(0.0, pester - dt)


func _animate(dt: float) -> void:
	var hv := Vector3(vel.x, 0, vel.z)
	if hv.length() > 0.4:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-hv.x, -hv.z), 1.0 - exp(-dt * 8.0))
	body.rotation.x = lerpf(body.rotation.x, clampf(-vel.y * 0.08, -0.4, 0.4), 1.0 - exp(-dt * 5.0))
	for k in wings.size():
		var side := 1.0 if k % 2 == 0 else -1.0
		wings[k].rotation.z = sin(t * 95.0 + (k / 2) * 1.6) * 0.6 * side
	buzz.pitch_scale = 0.9 + minf(vel.length(), 10.0) * 0.03
