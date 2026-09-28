class_name Eryops
extends Node3D
## A big amphibian lying in a pool with just its back and eyes above the
## water. Any noise nearby and it sinks out of sight. It only comes back up
## once the swamp has been quiet for a while.

const SURFACE := -0.03
const SUNK := -0.95

var world: World
var player: Player
var home := Vector3.ZERO
var under := false
var quiet := 0.0
var t := 0.0
var heading := 0.0
var turn := 0.0
var next_croak := 6.0
var active := false
var croak: AudioStreamPlayer3D
var splash: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()


func setup(w: World, p: Player, s: Dictionary, at: Vector3) -> void:
	world = w
	player = p
	rng.randomize()
	home = Vector3(at.x, 0, at.z)
	position = Vector3(at.x, SURFACE, at.z)
	heading = rng.randf() * TAU
	t = rng.randf() * 20.0
	var parts := Meshes.eryops()
	for m in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.scale = Vector3.ONE * 1.15
		add_child(mi)
	croak = AudioStreamPlayer3D.new()
	croak.stream = s.croak
	croak.unit_size = 8.0
	croak.max_distance = 80.0
	add_child(croak)
	splash = AudioStreamPlayer3D.new()
	splash.stream = s.splash
	splash.unit_size = 10.0
	splash.max_distance = 60.0
	add_child(splash)


func begin() -> void:
	active = true


func surfaced() -> bool:
	return not under and position.y > SURFACE - 0.08


func film_point() -> Vector3:
	return global_position + Vector3(0, 0.08, 0)


func hear(at: Vector3, radius: float) -> void:
	if not active:
		return
	if Vector2(at.x - position.x, at.z - position.z).length() < radius + 8.0:
		if not under:
			splash.pitch_scale = 0.6
			splash.play()
		under = true
		quiet = rng.randf_range(6.0, 9.0)


func _process(dt: float) -> void:
	if not active:
		return
	t += dt
	quiet -= dt
	if under and quiet <= 0.0:
		under = false
	var want_y := SUNK if under else SURFACE + sin(t * 0.8) * 0.015
	position.y = lerpf(position.y, want_y, 1.0 - exp(-dt * (3.0 if under else 0.7)))
	# drift lazily around its pool, never onto dry ground
	turn = lerpf(turn, sin(t * 0.13) * 0.25, dt)
	heading += turn * dt
	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	var next := position + fwd * 0.12 * dt
	var back_home := Vector2(next.x - home.x, next.z - home.z).length() > 3.0
	if back_home or world.height_at(next.x, next.z) > -0.55:
		heading += PI * 0.5 * dt * 4.0
	else:
		position.x = next.x
		position.z = next.z
	rotation.y = heading
	rotation.z = sin(t * 0.6) * 0.03
	if surfaced():
		next_croak -= dt
		if next_croak <= 0.0:
			next_croak = rng.randf_range(9.0, 18.0)
			croak.pitch_scale = rng.randf_range(0.85, 1.1)
			croak.play()
