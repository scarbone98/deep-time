class_name TRex
extends Gorgon
## Tyrannosaurus. Enormous, and it only sees movement: freeze (or creep
## slower than a crouch-walk) and it looks right through you. You feel its
## footsteps long before you see it.

var model: DinoModel


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
	rig.position.y = 0.0
	model = DinoModel.new()
	rig.add_child(model)
	model.setup("TRex", 0.42)
	head_off = Vector3(0, 5.0, -4.0)
	eye_off = Vector3(0, 5.3, -3.6)


func _bite() -> void:
	if model:
		model.attack()


## Stand still and it can't see you.
func _notices(p: Player) -> bool:
	return p.moving and Vector2(p.velocity.x, p.velocity.z).length() > 1.8


func _footfall(prev: float) -> void:
	if speed > 0.4 and int(prev / PI) != int(gait / PI):
		thud.pitch_scale = thud_pitch * rng.randf_range(0.9, 1.1)
		thud.play()


func _pose() -> void:
	rotation.y = atan2(-dir.x, -dir.z)
	if model == null:
		return
	if feeding > 0.0 or stunned > 0.0:
		model.play("Idle", 0.4 if stunned > 0.0 else 1.0)
		return
	model.move(speed, 2.0, 6.5)


## Everyone near it feels each step.
func quake_at(p: Vector3) -> float:
	if speed < 0.4:
		return 0.0
	var d := p.distance_to(position)
	return clampf(1.0 - d / 45.0, 0.0, 1.0) * absf(cos(gait))
