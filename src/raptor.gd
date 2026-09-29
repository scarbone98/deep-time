class_name Raptor
extends Gorgon
## Dakotaraptor. Hunts in pairs, by sight AND sound: a noise draws it in
## to look, and once it's seen you it comes faster than you can run. It
## stalks low before it charges, and its eyes shine in your lamp.

var legs2: Array[Node3D] = []
var body_node: Node3D
var tail_sway := 0.0


func _tune() -> void:
	size = 1.0
	catch_range = 1.9
	sight = 34.0
	lit_sight = 60.0
	stalk_speed = 3.0
	prowl_speed = 2.2
	hunt_speed = 8.3
	thud_pitch = 1.3
	gait_rate = 3.2


func _voice() -> void:
	growl.pitch_scale = 1.7
	roar.pitch_scale = 1.9
	roar.stream = session.sounds.shriek if session and session.sounds.has("shriek") else roar.stream


func _build_body() -> void:
	var m := Meshes.raptor()
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
		pv.position = Vector3(0.17 * sd, m.hip, 0.15)
		rig.add_child(pv)
		var lm := MeshInstance3D.new()
		lm.mesh = m.leg
		pv.add_child(lm)
		legs2.append(pv)
	head_off = m.head_at
	eye_off = m.head_at + Vector3(0, 0.1, 0.3)


## It hears too: a noise close enough brings it over to look.
func hear(at: Vector3, radius: float) -> void:
	if not active or feeding > 0.0 or hear_off:
		return
	var d := Vector2(at.x - position.x, at.z - position.z).length()
	if d > radius or d > 45.0:
		return
	last_seen = Vector3(at.x, 0, at.z)
	seen = minf(1.2, seen + clampf(radius / 40.0, 0.1, 0.4))
	if state == "prowl":
		state = "stalk"
		growl.play()


func _pose() -> void:
	rotation.y = atan2(-dir.x, -dir.z)
	var amp := clampf(speed / 3.0, 0.0, 1.0)
	for k in legs2.size():
		var ph := gait + (0.0 if k == 0 else PI)
		legs2[k].rotation.x = sin(ph) * 0.7 * amp
	var low := 0.25 if state == "stalk" else 0.0
	body_node.position.y = -low * 0.4 + absf(sin(gait)) * 0.06 * amp
	body_node.rotation.x = -low * 0.15 + (0.08 if state == "charge" else 0.0)
	tail_sway += (0.016 if speed < 1.0 else 0.0)
	body_node.rotation.y = sin(t * 1.4 + tail_sway) * 0.05
	if jaw:
		var open := 0.5 if state == "charge" else (0.15 + 0.1 * sin(t * 3.0) if state == "stalk" else 0.05)
		jaw.rotation.x = lerpf(jaw.rotation.x, open, 0.2)
