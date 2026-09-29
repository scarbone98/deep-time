class_name Avatar
extends Node3D
## Another player, as seen by you: a researcher in a coloured raincoat,
## camcorder up at their eye, lamp beam, name tag. Driven by snapshots:
## position and look are smoothed, the walk cycle comes from how fast
## they're actually moving.

const EMOTE_TIME := 2.2

var id := 0
var pname := ""
var color := Color.WHITE
var parts: Dictionary
var target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var t_yaw := 0.0
var t_pitch := 0.0
var crouch := false
var alive := true
var through := false
var talk := 0.0
var speed := 0.0
var gait := 0.0
var emote_id := 0
var emote_t := 0.0
var fresh := true
var last := Vector3.ZERO
var rig: Node3D
var hips: Node3D
var chest: Node3D
var head: Node3D
var legs: Array[Node3D] = []
var arm_l: Node3D
var arm_r: Node3D
var lamp: SpotLight3D
var flash: OmniLight3D
var tag: Label3D
var talking: Label3D
var step: AudioStreamPlayer3D
var yell: AudioStreamPlayer3D
var sounds: Dictionary
var stride := 0.0


func setup(pid: int, n: String, c: Color, s: Dictionary) -> void:
	id = pid
	pname = n
	color = c
	sounds = s
	parts = Meshes.person(c)
	rig = Node3D.new()
	add_child(rig)
	hips = Node3D.new()
	hips.position.y = 0.92
	rig.add_child(hips)
	for sd in [-1.0, 1.0]:
		var lp := Node3D.new()
		lp.position = Vector3(0.1 * sd, 0, 0)
		hips.add_child(lp)
		_mesh(lp, parts.leg)
		legs.append(lp)
	chest = Node3D.new()
	hips.add_child(chest)
	_mesh(chest, parts.torso)
	head = Node3D.new()
	head.position.y = 0.62
	chest.add_child(head)
	_mesh(head, parts.head)
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.22, 0.52, 0)
	chest.add_child(arm_l)
	_mesh(arm_l, parts.arm)
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.22, 0.52, 0)
	chest.add_child(arm_r)
	_mesh(arm_r, parts.arm)
	var cam := Node3D.new()
	cam.position = Vector3(0, -0.62, 0)
	cam.rotation.x = PI * 0.5
	arm_r.add_child(cam)
	_mesh(cam, parts.cam)
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0, 0, -0.24)
	lamp.spot_range = 30.0
	lamp.spot_angle = 26.0
	lamp.light_energy = 2.6
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.visible = false
	cam.add_child(lamp)
	flash = OmniLight3D.new()
	flash.position = Vector3(0, 0, -0.3)
	flash.omni_range = 14.0
	flash.light_energy = 0.0
	cam.add_child(flash)
	tag = Label3D.new()
	tag.text = n
	tag.font_size = 40
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = c.lightened(0.3)
	tag.outline_size = 8
	tag.position.y = 2.05
	tag.fixed_size = false
	add_child(tag)
	talking = Label3D.new()
	talking.text = "((  ))"
	talking.font_size = 36
	talking.pixel_size = 0.004
	talking.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	talking.modulate = Color(1, 1, 1, 0.8)
	talking.position.y = 1.72
	talking.visible = false
	add_child(talking)
	step = AudioStreamPlayer3D.new()
	step.unit_size = 3.0
	step.max_distance = 40.0
	add_child(step)
	yell = AudioStreamPlayer3D.new()
	yell.unit_size = 12.0
	yell.max_distance = 120.0
	yell.position.y = 1.6
	add_child(yell)


func _mesh(parent: Node3D, m: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	parent.add_child(mi)


func eye() -> Vector3:
	return global_position + Vector3(0, 1.0 if crouch else 1.6, 0)


func look_dir() -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD


func net_set(pos: Vector3, y: float, p: float, cr: bool, lit: bool, al: bool, thr: bool, tk: float) -> void:
	target = pos
	t_yaw = y
	t_pitch = p
	crouch = cr
	lamp.visible = lit and al
	alive = al
	through = thr
	talk = tk
	visible = al and not thr
	if fresh:
		fresh = false
		position = pos
		last = pos
		yaw = y
		pitch = p


func emote(e: int) -> void:
	emote_id = e
	emote_t = EMOTE_TIME
	match e:
		3:
			yell.stream = sounds.scream
			yell.pitch_scale = randf_range(0.9, 1.15)
			yell.play()
		4:
			yell.stream = sounds.flash
			yell.play()
			flash.light_energy = 16.0


func _process(dt: float) -> void:
	position = position.lerp(target, 1.0 - exp(-dt * 12.0))
	yaw = lerp_angle(yaw, t_yaw, 1.0 - exp(-dt * 14.0))
	pitch = lerpf(pitch, t_pitch, 1.0 - exp(-dt * 14.0))
	var moved := Vector2(position.x - last.x, position.z - last.z).length()
	last = position
	speed = lerpf(speed, moved / maxf(dt, 0.001), 1.0 - exp(-dt * 8.0))
	gait += speed * dt * 3.2
	stride += moved
	if stride > (0.6 if crouch else 0.9) and alive:
		stride = 0.0
		step.stream = sounds.step
		step.pitch_scale = randf_range(0.85, 1.1)
		step.volume_db = -14.0 if crouch else -6.0
		step.play()
	rig.rotation.y = yaw
	var amp := clampf(speed / 3.0, 0.0, 1.0)
	var low := 0.35 if crouch else 0.0
	hips.position.y = 0.92 - low + absf(sin(gait)) * 0.04 * amp
	chest.rotation.x = -low * 0.8
	legs[0].rotation.x = sin(gait) * 0.6 * amp + low * 1.2
	legs[1].rotation.x = -sin(gait) * 0.6 * amp + low * 1.2
	head.rotation.x = pitch + low * 0.8
	# camcorder arm follows the look
	arm_r.rotation.x = -1.35 - pitch * 0.9 + low * 0.8
	arm_r.rotation.z = 0.35
	arm_l.rotation.x = sin(gait + PI) * 0.4 * amp
	arm_l.rotation.z = 0.0
	if emote_t > 0.0:
		emote_t -= dt
		match emote_id:
			1:  # wave
				arm_l.rotation.z = -2.6
				arm_l.rotation.x = sin(emote_t * 14.0) * 0.4
			2:  # point
				arm_l.rotation.x = -1.5 - pitch
			3:  # scream
				head.rotation.x = -0.5 + sin(emote_t * 30.0) * 0.08
				arm_l.rotation.z = -2.2
	flash.light_energy = maxf(0.0, flash.light_energy - dt * 60.0)
	talking.visible = alive and talk > 0.03
	talking.modulate = color.lightened(0.4)
	talking.scale = Vector3.ONE * (1.0 + talk * 4.0)
