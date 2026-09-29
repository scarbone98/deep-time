class_name Grazer
extends Node3D
## A Scutosaurus in a loose herd, drifting and grazing. Harmless. Loud.

var world: World
var puppet := false
var net_pos := Vector3.ZERO
var herd: Dictionary  # shared {"center": Vector3, "goal": Vector3}
var offset := Vector3.ZERO
var dir := Vector3.FORWARD
var speed := 0.0
var t := 0.0
var gait := 0.0
var active := false
var rig: Node3D
var head_bob := 0.0
var legs: Array[Node3D] = []
var model: DinoModel
var call_: AudioStreamPlayer3D
var next_call := 0.0
var rng := RandomNumberGenerator.new()


func setup(w: World, h: Dictionary, s: Dictionary, meshes: Dictionary) -> void:
	world = w
	herd = h
	rng.randomize()
	offset = Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
	var c: Vector3 = herd.center
	position = Vector3(c.x + offset.x, 0, c.z + offset.z)
	position.y = world.height_at(position.x, position.z)
	scale = Vector3.ONE * rng.randf_range(1.6, 1.95)
	t = rng.randf() * 20.0
	next_call = rng.randf_range(5.0, 25.0)
	rig = Node3D.new()
	rig.position.y = 0.5
	add_child(rig)
	if meshes.has("model"):
		scale = Vector3.ONE * rng.randf_range(0.9, 1.1)
		rig.position.y = 0.0
		model = DinoModel.new()
		rig.add_child(model)
		model.setup(meshes.model, meshes.size)
		_add_call(s)
		return
	var body := MeshInstance3D.new()
	body.mesh = meshes.body
	rig.add_child(body)
	for hip in [[0.45, -0.6], [-0.45, -0.6], [0.45, 0.65], [-0.45, 0.65]]:
		var pv := Node3D.new()
		pv.position = Vector3(hip[0], 0.3, hip[1])
		rig.add_child(pv)
		var lm := MeshInstance3D.new()
		lm.mesh = meshes.leg
		lm.scale = Vector3(signf(hip[0]), 1, 1)
		pv.add_child(lm)
		legs.append(pv)
	_add_call(s)


func _add_call(s: Dictionary) -> void:
	call_ = AudioStreamPlayer3D.new()
	call_.stream = s.croak
	call_.unit_size = 12.0
	call_.max_distance = 120.0
	add_child(call_)


func begin() -> void:
	active = true


func film_point() -> Vector3:
	return to_global(Vector3(0, 0.9, 0))


func net_get(out: PackedFloat32Array) -> void:
	out.append_array([position.x, position.y, position.z, dir.x, dir.z, speed])


func net_set(a: PackedFloat32Array, i: int) -> int:
	net_pos = Vector3(a[i], a[i + 1], a[i + 2])
	var d := Vector3(a[i + 3], 0, a[i + 4])
	if d.length() > 0.01:
		dir = d.normalized()
	speed = a[i + 5]
	return i + 6


func _physics_process(dt: float) -> void:
	if puppet:
		t += dt
		if net_pos.distance_to(position) > 8.0:
			position = net_pos
		position = position.lerp(net_pos, 1.0 - exp(-dt * 8.0))
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-dt * 6.0))
		gait += speed * dt * 3.0
		for k in legs.size():
			legs[k].rotation.x = sin(gait + (0.0 if k in [0, 3] else PI)) * 0.35 * clampf(speed, 0.0, 1.0)
		if model:
			model.move(speed, 1.0, 5.0)
		next_call -= dt
		if next_call <= 0.0:
			next_call = rng.randf_range(12.0, 30.0)
			call_.pitch_scale = rng.randf_range(0.45, 0.6)
			call_.play()
		return
	if not active:
		return
	t += dt
	var c: Vector3 = herd.center
	var goal := c + offset.rotated(Vector3.UP, sin(t * 0.05) * 0.5)
	var to := goal - position
	to.y = 0.0
	var want_speed := clampf(to.length() * 0.3, 0.0, 1.1)
	# a stampede: the whole herd charges one way, flattening whoever's there
	if float(herd.get("dash_t", 0.0)) > 0.0:
		to = herd.dash
		want_speed = 8.5
		var main: Node = herd.get("main")
		if main:
			for p: Player in main.alive_players():
				if Vector2(p.position.x - position.x, p.position.z - position.z).length() < 2.2 * scale.x:
					main._kill(p, position + Vector3(0, 1.0, 0))
	if to.length() > 0.5:
		var nd := dir.lerp(to.normalized(), 1.0 - exp(-dt * 0.8))
		if nd.length() > 0.01:
			dir = nd.normalized()
	speed = move_toward(speed, want_speed, dt * (6.0 if want_speed > 5.0 else 1.0))
	position += dir * speed * dt
	position.y = world.height_at(position.x, position.z)
	rotation.y = atan2(-dir.x, -dir.z)
	gait += speed * dt * 3.0
	for k in legs.size():
		legs[k].rotation.x = sin(gait + (0.0 if k in [0, 3] else PI)) * 0.35 * clampf(speed, 0.0, 1.0)
	if model:
		model.move(speed, 1.0, 5.0)
	# head down to graze when standing
	head_bob = lerpf(head_bob, 0.12 if speed < 0.2 else 0.0, dt)
	if model == null:
		rig.rotation.x = head_bob + sin(t * 0.9) * 0.02
	next_call -= dt
	if next_call <= 0.0:
		next_call = rng.randf_range(12.0, 30.0)
		call_.pitch_scale = rng.randf_range(0.45, 0.6)
		call_.play()
