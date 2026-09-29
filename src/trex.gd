class_name TRex
extends Gorgon
## Tyrannosaurus. Enormous, and it only sees movement: freeze (or creep
## slower than a crouch-walk) and it looks right through you. You feel its
## footsteps long before you see it.

var legs2: Array[Node3D] = []
var body_node: Node3D


func _tune() -> void:
	size = 1.0
	catch_range = 4.2
	sight = 55.0
	lit_sight = 70.0
	stalk_speed = 2.4
	prowl_speed = 2.0
	hunt_speed = 6.9
	thud_pitch = 0.3
	gait_rate = 1.1
	drift = 0.3


func _voice() -> void:
	growl.pitch_scale = 0.45
	growl.unit_size = 20.0
	growl.max_distance = 160.0
	roar.pitch_scale = 0.42
	roar.unit_size = 40.0
	roar.max_distance = 250.0
	thud.unit_size = 30.0
	thud.max_distance = 120.0
	thud.volume_db = 6.0


func _build_body() -> void:
	var m := Meshes.rex()
	rig.position.y = 0.0
	body_node = Node3D.new()
	rig.add_child(body_node)
	for part in [m.body, m.eyes]:
		var mi := MeshInstance3D.new()
		mi.mesh = part
		body_node.add_child(mi)
	jaw = Node3D.new()
	jaw.position = m.jaw_at
	body_node.add_child(jaw)
	var jm := MeshInstance3D.new()
	jm.mesh = m.jaw
	jaw.add_child(jm)
	for sd in [-1.0, 1.0]:
		var pv := Node3D.new()
		pv.position = Vector3(0.95 * sd, m.hip * 0.95, 0.6)
		rig.add_child(pv)
		var lm := MeshInstance3D.new()
		lm.mesh = m.leg
		pv.add_child(lm)
		legs2.append(pv)
	head_off = m.head_at
	eye_off = m.head_at + Vector3(0, 0.3, 0.8)


## Stand still and it can't see you.
func _notices(p: Player) -> bool:
	return p.moving and Vector2(p.velocity.x, p.velocity.z).length() > 1.8


func _footfall(prev: float) -> void:
	if speed > 0.4 and int(prev / PI) != int(gait / PI):
		thud.pitch_scale = thud_pitch * rng.randf_range(0.9, 1.1)
		thud.play()


func _pose() -> void:
	rotation.y = atan2(-dir.x, -dir.z)
	var amp := clampf(speed / 2.5, 0.0, 1.0)
	for k in legs2.size():
		var ph := gait + (0.0 if k == 0 else PI)
		legs2[k].rotation.x = sin(ph) * 0.45 * amp
	body_node.position.y = absf(sin(gait)) * 0.18 * amp
	body_node.rotation.z = sin(gait) * 0.03 * amp
	body_node.rotation.y = sin(t * 0.6) * 0.04
	if jaw:
		var open := 0.55 if state == "charge" else (0.2 if state == "search" else 0.06)
		jaw.rotation.x = lerpf(jaw.rotation.x, open, 0.1)


## Everyone near it feels each step.
func quake_at(p: Vector3) -> float:
	if speed < 0.4:
		return 0.0
	var d := p.distance_to(position)
	return clampf(1.0 - d / 45.0, 0.0, 1.0) * absf(cos(gait))
