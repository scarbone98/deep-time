class_name Avatar
extends Node3D
## Another player, as seen by you (or yourself, in the shop preview): a
## chibi time-traveller in their suit colour, hat and face gear, camcorder
## in hand, loot stacked on the time pack. Driven by snapshots: position and
## look are smoothed, the waddle comes from how fast they actually move.

const EMOTE_TIME := 2.2

var id := 0
var pname := ""
var look := {}
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
var t := 0.0
var emote_id := 0
var emote_t := 0.0
var fresh := true
var last := Vector3.ZERO
var preview := false  # shop mirror: no tag, no sounds, idles
var rig: Node3D
var hips: Node3D
var body: Node3D
var head: Node3D
var hat_mi: MeshInstance3D
var face_mi: MeshInstance3D
var legs: Array[Node3D] = []
var arm_l: Node3D
var arm_r: Node3D
var pack: Node3D
var body_mi: MeshInstance3D
var parts_mis := []
var lamp: SpotLight3D
var flash: OmniLight3D
var tag: Label3D
var talking: Label3D
var step: AudioStreamPlayer3D
var yell: AudioStreamPlayer3D
var sounds: Dictionary
var stride := 0.0
var held := 0
var hand_mi: MeshInstance3D


func setup(pid: int, n: String, lk: Dictionary, s: Dictionary, is_preview := false) -> void:
	id = pid
	pname = n
	sounds = s
	preview = is_preview
	rig = Node3D.new()
	add_child(rig)
	hips = Node3D.new()
	hips.position.y = 0.5
	rig.add_child(hips)
	for sd in [-1.0, 1.0]:
		var lp := Node3D.new()
		lp.position = Vector3(0.13 * sd, 0.02, 0)
		hips.add_child(lp)
		legs.append(lp)
	body = Node3D.new()
	hips.add_child(body)
	head = Node3D.new()
	head.position.y = 0.52
	body.add_child(head)
	hat_mi = MeshInstance3D.new()
	hat_mi.position.y = 0.66
	head.add_child(hat_mi)
	face_mi = MeshInstance3D.new()
	head.add_child(face_mi)
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.3, 0.4, 0)
	body.add_child(arm_l)
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.3, 0.4, 0)
	body.add_child(arm_r)
	pack = Node3D.new()
	pack.position = Vector3(0, 0.5, 0.3)
	body.add_child(pack)
	var cam := Node3D.new()
	cam.position = Vector3(0, -0.36, -0.05)
	cam.rotation.x = PI * 0.5
	arm_r.add_child(cam)
	cam.name = "Cam"
	hand_mi = MeshInstance3D.new()
	hand_mi.position = Vector3(0, -0.32, -0.25)
	hand_mi.scale = Vector3.ONE * 0.8
	arm_l.add_child(hand_mi)
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0, 0, -0.2)
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
	tag.outline_size = 8
	tag.position.y = 2.25
	tag.visible = not preview
	add_child(tag)
	talking = Label3D.new()
	talking.text = "((  ))"
	talking.font_size = 36
	talking.pixel_size = 0.004
	talking.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	talking.position.y = 2.02
	talking.visible = false
	add_child(talking)
	if not preview:
		step = AudioStreamPlayer3D.new()
		step.unit_size = 3.0
		step.max_distance = 40.0
		add_child(step)
		yell = AudioStreamPlayer3D.new()
		yell.unit_size = 12.0
		yell.max_distance = 120.0
		yell.position.y = 1.5
		add_child(yell)
	set_look(lk)


## Rebuild the meshes for a new suit, hat or face.
func set_look(lk: Dictionary) -> void:
	look = Shop.clean_look(lk)
	color = Shop.suit_color(look.suit)
	parts = Meshes.chibi(color)
	parts["hat"] = Meshes.hat(look.hat)
	parts["gear"] = Meshes.face_gear(look.face)
	for m in parts_mis:
		m.queue_free()
	parts_mis = []
	_put(body, parts.body)
	_put(head, parts.head)
	_put(head, parts.face)
	for lp in legs:
		_put(lp, parts.leg)
	_put(arm_l, parts.arm)
	_put(arm_r, parts.arm)
	_put(arm_r.get_node("Cam"), parts.cam)
	hat_mi.mesh = parts.hat
	face_mi.mesh = parts.gear
	tag.modulate = color.lightened(0.35)


func _put(parent: Node3D, m: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	parent.add_child(mi)
	parts_mis.append(mi)


## What's in their hands (held out in the free arm).
func set_hand(m: Mesh) -> void:
	hand_mi.mesh = m


## Stack whatever they're carrying on their time pack.
func set_carry(meshes: Array) -> void:
	for c in pack.get_children():
		c.queue_free()
	var y := 0.0
	for m in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = Vector3(0, y, 0)
		pack.add_child(mi)
		y += 0.22


func eye() -> Vector3:
	return global_position + Vector3(0, 1.0 if crouch else 1.55, 0)


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
	if preview:
		return
	match e:
		3:
			yell.stream = sounds.scream
			yell.pitch_scale = randf_range(1.15, 1.4)
			yell.play()
		4:
			yell.stream = sounds.flash
			yell.play()
			flash.light_energy = 16.0


func _process(dt: float) -> void:
	t += dt
	if preview:
		target = position
	position = position.lerp(target, 1.0 - exp(-dt * 12.0))
	yaw = lerp_angle(yaw, t_yaw, 1.0 - exp(-dt * 14.0))
	pitch = lerpf(pitch, t_pitch, 1.0 - exp(-dt * 14.0))
	var moved := Vector2(position.x - last.x, position.z - last.z).length()
	last = position
	speed = lerpf(speed, moved / maxf(dt, 0.001), 1.0 - exp(-dt * 8.0))
	gait += speed * dt * 4.0
	stride += moved
	if step and stride > (0.5 if crouch else 0.7) and alive:
		stride = 0.0
		step.stream = sounds.step
		step.pitch_scale = randf_range(1.1, 1.3)
		step.volume_db = -14.0 if crouch else -7.0
		step.play()
	rig.rotation.y = yaw
	var amp := clampf(speed / 3.0, 0.0, 1.0)
	var low := 0.22 if crouch else 0.0
	# a waddle: bounce and side-to-side rock
	hips.position.y = 0.5 - low + absf(sin(gait)) * 0.07 * amp + sin(t * 2.0) * 0.008
	rig.rotation.z = sin(gait) * 0.08 * amp
	body.rotation.x = -low * 0.6
	legs[0].rotation.x = sin(gait) * 0.7 * amp + low * 1.3
	legs[1].rotation.x = -sin(gait) * 0.7 * amp + low * 1.3
	head.rotation.x = pitch * 0.6 + low * 0.5
	head.rotation.z = sin(t * 1.3) * 0.03
	arm_r.rotation.x = -1.3 - pitch * 0.8
	arm_r.rotation.z = 0.25
	arm_l.rotation.x = sin(gait + PI) * 0.6 * amp
	arm_l.rotation.z = -0.15
	if hand_mi.mesh:
		arm_l.rotation.x = -1.1
		arm_l.rotation.z = 0.25
	if emote_t > 0.0:
		emote_t -= dt
		match emote_id:
			1:  # wave
				arm_l.rotation.z = -2.7
				arm_l.rotation.x = sin(emote_t * 14.0) * 0.4
			2:  # point
				arm_l.rotation.x = -1.5 - pitch
			3:  # scream
				head.rotation.x = -0.4 + sin(emote_t * 30.0) * 0.1
				arm_l.rotation.z = -2.4
			4:
				pass
	if look.get("hat", "") == "propeller" and hat_mi:
		hat_mi.rotation.y += dt * (6.0 + speed * 6.0)
	flash.light_energy = maxf(0.0, flash.light_energy - dt * 60.0)
	talking.visible = alive and talk > 0.03 and not preview
	talking.modulate = color.lightened(0.4)
	talking.scale = Vector3.ONE * (1.0 + talk * 4.0)
