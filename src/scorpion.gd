class_name Scorpion
extends Node3D
## Pulmonoscorpius, bigger than it should be. It sits dead still by the
## fallen logs. Come too close and it rattles and raises its tail. Still close
## when the rattle ends? It strikes.

signal struck

const WARN_AT := 4.5
const STRIKE_AT := 3.6

var player: Player
var state := "idle"
var timer := 0.0
var t := 0.0
var curl := 0.45
var lunge := 0.0
var hit := false
var active := false
var body: Node3D
var tail: Array[Node3D] = []
var rattle: AudioStreamPlayer3D
var home := Vector3.ZERO


func setup(p: Player, s: Dictionary, at: Vector3, yaw: float) -> void:
	player = p
	position = at
	home = at
	rotation.y = yaw
	scale = Vector3.ONE * 2.0
	t = randf() * 10.0
	body = Node3D.new()
	body.position.y = 0.12
	add_child(body)
	var bm := MeshInstance3D.new()
	bm.mesh = Meshes.scorpion_body()
	body.add_child(bm)
	var seg := Meshes.scorpion_tail()
	var parent: Node3D = body
	var at_ := Vector3(0, 0.03, 0.3)
	for i in 6:
		var pv := Node3D.new()
		pv.position = at_
		parent.add_child(pv)
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.scorpion_tail(true) if i == 5 else seg
		pv.add_child(mi)
		tail.append(pv)
		parent = pv
		at_ = Vector3(0, 0, 0.16)
	rattle = AudioStreamPlayer3D.new()
	rattle.stream = s.chitter
	rattle.unit_size = 5.0
	rattle.max_distance = 40.0
	add_child(rattle)


func begin() -> void:
	active = true


func film_point() -> Vector3:
	return global_position + Vector3(0, 0.45, 0)


func _process(dt: float) -> void:
	if not active:
		return
	t += dt
	var to := player.global_position - global_position
	var d := Vector2(to.x, to.z).length()
	var want_curl := 0.45
	match state:
		"idle":
			if player.alive and d < WARN_AT:
				state = "warn"
				timer = 1.3
				rattle.play()
		"warn":
			want_curl = 0.62
			timer -= dt
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-dt * 6.0))
			if timer <= 0.0:
				if player.alive and d < STRIKE_AT:
					state = "strike"
					timer = 0.4
				else:
					state = "idle"
		"strike":
			want_curl = 0.3
			timer -= dt
			lunge = minf(1.0, lunge + dt * 6.0)
			if timer <= 0.2 and not hit:
				hit = true
				struck.emit()
	curl = lerpf(curl, want_curl, 1.0 - exp(-dt * 8.0))
	var sway := sin(t * (9.0 if state == "warn" else 0.7)) * (0.1 if state == "warn" else 0.02)
	for i in tail.size():
		tail[i].rotation = Vector3(-curl, sway, 0)
	# the lunge: the whole body throws forward, tail whips over
	body.position.z = -lunge * 0.6
	if state == "strike":
		tail[tail.size() - 1].rotation.x = -curl - lunge * 1.2
	body.position.y = 0.12 + (sin(t * 22.0) * 0.004 if state == "warn" else 0.0)
