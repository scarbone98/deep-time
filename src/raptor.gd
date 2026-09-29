class_name Raptor
extends Gorgon
## Dakotaraptor. Hunts in pairs, by sight AND sound: a noise draws it in
## to look, and once it's seen you it comes faster than you can run. It
## stalks low before it charges, and its eyes shine in your lamp.

var model: DinoModel


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
	rig.position.y = 0.0
	model = DinoModel.new()
	rig.add_child(model)
	model.setup("Velociraptor", 0.34)
	head_off = Vector3(0, 1.55, -1.3)
	eye_off = Vector3(0, 1.6, -1.2)


func _bite() -> void:
	if model:
		model.attack()


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
	if model == null:
		return
	if feeding > 0.0 or stunned > 0.0:
		model.play("Idle", 0.4 if stunned > 0.0 else 1.0)
		return
	model.move(speed, 1.8, 7.0)
	# it crouches as it stalks
	model.position.y = lerpf(model.position.y, -0.25 if state == "stalk" else 0.0, 0.1)
