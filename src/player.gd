class_name Player
extends CharacterBody3D
## First person, holding a camcorder. Every footstep is a vibration
## something else can feel.

signal noise(pos: Vector3, radius: float)

const WALK := 3.2
const RUN := 6.4
const SNEAK := 1.5

var world: World
var sounds: Dictionary
var head: Node3D
var cam: Camera3D
var light: SpotLight3D
var yaw := 0.0
var pitch := 0.0
var stamina := 1.0
var exhausted := false
var crouching := false
var moving := false
var eye := 1.6
var stride := 0.0
var bob := 0.0
var t := 0.0
var alive := true
var control := false
var battery := 1.0
var fear := 0.0
var breath_noise := 0.0
var step_sfx: AudioStreamPlayer
var breath: AudioStreamPlayer
var heart: AudioStreamPlayer
var dying := 0.0
var death_at := Vector3.ZERO
var touch: TouchPad


func setup(w: World, s: Dictionary) -> void:
	world = w
	sounds = s
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	head = Node3D.new()
	head.position.y = eye
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 160.0
	cam.current = true
	head.add_child(cam)
	light = SpotLight3D.new()
	light.spot_range = 34.0
	light.spot_angle = 27.0
	light.light_energy = 3.2
	light.light_color = Color(1.0, 0.95, 0.82)
	light.spot_attenuation = 0.7
	light.position = Vector3(0.1, -0.08, 0.0)
	light.visible = false
	cam.add_child(light)
	step_sfx = _audio(null, -6.0)
	breath = _audio(sounds.breath, -80.0)
	heart = _audio(sounds.heart, -80.0)


func _audio(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func begin() -> void:
	control = true
	breath.play()
	heart.play()


func _unhandled_input(e: InputEvent) -> void:
	if not control:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(e.relative * 0.0022)
	if e.is_action_pressed("light"):
		toggle_light()


func look(d: Vector2) -> void:
	if not control:
		return
	yaw -= d.x
	pitch = clampf(pitch - d.y, -1.35, 1.35)


func toggle_light() -> void:
	if battery > 0.0:
		light.visible = not light.visible


func _physics_process(dt: float) -> void:
	t += dt
	if dying > 0.0:
		_death_cam(dt)
		return
	var inp := Vector2.ZERO
	var sprint := false
	if control:
		inp = Input.get_vector("left", "right", "fwd", "back")
		crouching = Input.is_action_pressed("crouch")
		sprint = Input.is_action_pressed("sprint")
		if touch:
			inp = (inp + touch.move).limit_length(1.0)
			crouching = crouching or touch.crouch
			sprint = sprint or touch.run
	var depth := maxf(0.0, -world.height_at(position.x, position.z))
	var running := sprint and inp.length() > 0.2 and not crouching and not exhausted
	var spd := WALK
	if crouching:
		spd = SNEAK
	elif running:
		spd = RUN
	spd *= lerpf(1.0, 0.55, clampf(depth / 0.9, 0.0, 1.0))
	if running:
		stamina -= dt / 5.5
	else:
		stamina += dt / (9.0 if inp.length() > 0.1 else 6.0)
	stamina = clampf(stamina, 0.0, 1.0)
	if stamina <= 0.0:
		exhausted = true
	elif exhausted and stamina > 0.45:
		exhausted = false

	var wish := Basis(Vector3.UP, yaw) * Vector3(inp.x, 0, inp.y)
	velocity = velocity.lerp(wish * spd, 1.0 - exp(-dt * 9.0))
	velocity.y = 0.0
	move_and_slide()
	position.x = clampf(position.x, -World.BOUND, World.BOUND)
	position.z = clampf(position.z, -World.BOUND, World.BOUND)
	position.y = lerpf(position.y, world.height_at(position.x, position.z), 1.0 - exp(-dt * 18.0))

	var hs := Vector2(velocity.x, velocity.z).length()
	moving = hs > 0.4
	var stride_len := 0.6 if crouching else (1.3 if running else 0.85)
	stride += hs * dt
	bob += hs * dt / stride_len * PI
	if stride >= stride_len:
		stride -= stride_len
		_step(depth, running)

	# breathing: loud when winded, and loud enough to be felt nearby
	var winded := 1.0 - stamina
	breath.volume_db = linear_to_db(clampf(winded * 1.4 - 0.25, 0.0, 1.0) * 0.8 + 0.0001)
	if exhausted:
		breath_noise -= dt
		if breath_noise <= 0.0:
			breath_noise = 1.6
			noise.emit(global_position, 4.5)

	heart.volume_db = linear_to_db(fear * 0.9 + 0.0001)
	heart.pitch_scale = 0.85 + fear * 0.6

	# lamp battery
	if light.visible:
		battery = maxf(0.0, battery - dt / 300.0)
		light.light_energy = 3.2 if battery > 0.12 else (3.2 if randf() > 0.25 else randf() * 0.8)
		if battery <= 0.0:
			light.visible = false

	# camera: crouch height, walk bob, handheld drift
	eye = lerpf(eye, 1.0 if crouching else 1.6, 1.0 - exp(-dt * 8.0))
	var amp := 0.035 if not running else 0.07
	head.position.y = eye + absf(sin(bob)) * amp * minf(hs, 1.0)
	rotation.y = yaw
	head.rotation.x = pitch
	# portrait phones: hold the horizontal view instead of the vertical one
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = 78.0
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 72.0
	cam.rotation.z = sin(bob) * 0.008 + sin(t * 0.7) * 0.006 + sin(t * 1.9) * 0.003
	cam.rotation.x = sin(t * 0.53) * 0.006 + sin(t * 1.3) * 0.003 * (1.0 + winded * 3.0)
	cam.rotation.y = sin(t * 0.41) * 0.006


func _step(depth: float, running: bool) -> void:
	var r := 7.0
	if crouching:
		r = 2.2
	elif running:
		r = 20.0
	var wet := depth > 0.05
	if wet:
		r *= 1.5
	step_sfx.stream = sounds.splash if wet else sounds.step
	step_sfx.pitch_scale = randf_range(0.85, 1.15)
	step_sfx.volume_db = -16.0 if crouching else (-2.0 if running else -8.0)
	step_sfx.play()
	noise.emit(global_position, r)


func die(at: Vector3) -> void:
	alive = false
	control = false
	death_at = at
	dying = 0.001
	breath.stop()


## The grab: whip round to face it, then the camera hits the ground.
func _death_cam(dt: float) -> void:
	dying += dt
	var to := death_at - cam.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var k := 1.0 - exp(-dt * 14.0)
	yaw = lerp_angle(yaw, want_yaw, k)
	pitch = lerpf(pitch, want_pitch, k)
	rotation.y = yaw
	head.rotation.x = pitch
	if dying > 0.45:
		head.position.y = lerpf(head.position.y, 0.15, 1.0 - exp(-dt * 10.0))
		cam.rotation.z = lerpf(cam.rotation.z, 1.3, 1.0 - exp(-dt * 8.0))
	cam.rotation.x = randf_range(-0.03, 0.03)
