class_name Dicynodon
extends Node3D
## Sits beside its burrow mouth, chewing. Walk up on it, or shine a light
## at it, and it's gone underground for a while. Crouch.

const OUT_Y := 0.0
const IN_Y := -0.9

var world: World
var player: Player
var home := Vector3.ZERO
var hidden := false
var calm := 0.0
var t := 0.0
var active := false
var squeak: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()


func setup(w: World, p: Player, s: Dictionary, mesh: Mesh, burrow: Vector3) -> void:
	world = w
	player = p
	rng.randomize()
	home = burrow + Vector3(0, 0.08, 0)
	position = home
	rotation.y = rng.randf() * TAU
	scale = Vector3.ONE * 1.3
	t = rng.randf() * 10.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	squeak = AudioStreamPlayer3D.new()
	squeak.stream = s.chitter
	squeak.unit_size = 4.0
	squeak.max_distance = 40.0
	squeak.pitch_scale = 0.5
	add_child(squeak)


func begin() -> void:
	active = true


func out() -> bool:
	return not hidden and position.y > home.y - 0.1


func film_point() -> Vector3:
	return global_position + Vector3(0, 0.35, 0)


func _process(dt: float) -> void:
	if not active:
		return
	t += dt
	var d := Vector2(player.position.x - home.x, player.position.z - home.z).length()
	var spooked := false
	if player.alive:
		if player.moving and not player.crouching and d < 14.0:
			spooked = true
		if player.light.visible and d < 18.0:
			var to := (global_position - player.cam.global_position).normalized()
			if (-player.cam.global_transform.basis.z).dot(to) > 0.95:
				spooked = true
		if d < 4.0:
			spooked = true
	if spooked:
		if not hidden:
			squeak.play()
		hidden = true
		calm = rng.randf_range(5.0, 8.0)
	elif hidden:
		calm -= dt
		if calm <= 0.0:
			hidden = false
	var want := home.y + (IN_Y if hidden else OUT_Y)
	position.y = lerpf(position.y, want, 1.0 - exp(-dt * (6.0 if hidden else 1.5)))
	rotation.x = sin(t * 2.3) * 0.04
	if not hidden:
		rotation.y += sin(t * 0.4) * dt * 0.3
