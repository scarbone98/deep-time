class_name Decoy
extends Node3D
## A squeaky rubber dinosaur. Thrown in an arc; where it lands it squeaks
## for a while with a blinking light. The authority turns each squeak into
## noise the millipede hears, and a gorgon comes to look.

const GRAVITY := 16.0
const LIFE := 9.0

var world: World
var vel := Vector3.ZERO
var landed := false
var life := LIFE
var next := 0.0
var squeak: AudioStreamPlayer3D
var blink: OmniLight3D
var body: MeshInstance3D
var on_squeak: Callable  # authority only


func setup(w: World, s: Dictionary, at: Vector3, v: Vector3) -> void:
	world = w
	position = at
	vel = v
	var st := Meshes._smooth()
	var y := Color(1.0, 0.85, 0.15)
	Meshes.ball(st, Vector3(0, 0.12, 0), 0.13, y, 0.9, 10, 6)
	Meshes.ball(st, Vector3(0, 0.3, -0.08), 0.09, y, 1.0, 10, 6)
	Meshes.ball(st, Vector3(0.04, 0.33, -0.16), 0.02, Color(0.05, 0.05, 0.05), 1.0, 6, 3)
	Meshes.ball(st, Vector3(-0.04, 0.33, -0.16), 0.02, Color(0.05, 0.05, 0.05), 1.0, 6, 3)
	Meshes.tube(st, [Vector3(0, 0.28, -0.14), Vector3(0, 0.27, -0.22)], [0.04, 0.01], [Color(1, 0.5, 0.1), Color(1, 0.5, 0.1)], 6)
	body = MeshInstance3D.new()
	body.mesh = Meshes.finish(st, Meshes._unshaded())
	add_child(body)
	blink = OmniLight3D.new()
	blink.position.y = 0.4
	blink.omni_range = 5.0
	blink.light_color = Color(1.0, 0.3, 0.2)
	blink.light_energy = 0.0
	add_child(blink)
	squeak = AudioStreamPlayer3D.new()
	squeak.stream = s.squeak
	squeak.unit_size = 10.0
	squeak.max_distance = 90.0
	add_child(squeak)


func _physics_process(dt: float) -> void:
	if not landed:
		vel.y -= GRAVITY * dt
		position += vel * dt
		body.rotation.x += dt * 8.0
		var g := world.height_at(position.x, position.z)
		if position.y <= g:
			position.y = g
			landed = true
			body.rotation = Vector3.ZERO
		return
	life -= dt
	next -= dt
	if next <= 0.0 and life > 0.0:
		next = 1.0
		squeak.pitch_scale = randf_range(0.9, 1.2)
		squeak.play()
		blink.light_energy = 3.0
		body.scale = Vector3(1.2, 0.75, 1.2)
		if on_squeak.is_valid():
			on_squeak.call(position)
	blink.light_energy = maxf(0.0, blink.light_energy - dt * 8.0)
	body.scale = body.scale.lerp(Vector3.ONE, 1.0 - exp(-dt * 10.0))
	if life < -2.0:
		queue_free()
