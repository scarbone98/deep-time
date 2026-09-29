class_name Player
extends CharacterBody3D
## First person, holding a camcorder. Every footstep is a vibration
## something else can feel.

signal noise(pos: Vector3, radius: float)

const WALK := 4.3
const RUN := 7.6
const SNEAK := 2.1
const JUMP := 6.2
const GRAVITY := 18.0

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
var id := 1
var view := true  # this machine looks through its camera
var input_mode := "local"  # local: keyboard/touch; net: from a client packet
var net_move := Vector2.ZERO
var net_sprint := false
var net_crouch := false
var net_light := false
var talk := 0.0  # microphone level, 0..1: talking is noise too
var talk_noise := 0.0
var seq := 0
var through := false
var last_move := Vector2.ZERO
var last_sprint := false
var last_input_t := 0.0
var bot := false  # dev: walk in circles
var slots: Array[int] = [-1, -1, -1, -1]  # loot index per slot, -1 empty
var held := 0  # the slot in your hands
var carry := 0.0  # total weight: slower, louder
var hand: Node3D  # first person: what you're holding
var hand_mi: MeshInstance3D
var hand_two := false
var hand_swap := 0.0
var battery_life := 300.0
var vy := 0.0
var grounded := true
var net_jump := false
var jump_queued := false
var last_jump := false
var land_dip := 0.0
var fov_kick := 0.0
var shake := 0.0  # big footsteps nearby
var cur_spd := 0.0  # eases toward walk/run speed: a sprint winds up
var jump_buf := 0.0  # a jump pressed just before landing still counts
var stam_delay := 0.0  # stamina waits a moment before it comes back
var bob_amp := 0.0
var tilt := 0.0


func setup(w: World, s: Dictionary, is_view := true) -> void:
	world = w
	sounds = s
	view = is_view
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
	cam.current = is_view
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
	hand = Node3D.new()
	cam.add_child(hand)
	hand_mi = MeshInstance3D.new()
	hand.add_child(hand_mi)
	step_sfx = _audio(null, -6.0)
	breath = _audio(sounds.breath, -80.0)
	heart = _audio(sounds.heart, -80.0)


# ------------------------------------------------ inventory

func items() -> Array[int]:
	var out: Array[int] = []
	for i in slots:
		if i >= 0:
			out.append(i)
	return out


func held_item() -> int:
	return slots[held]


func free_slot() -> int:
	if slots[held] < 0:
		return held
	for k in slots.size():
		if slots[k] < 0:
			return k
	return -1


func set_slot_count(n: int) -> void:
	while slots.size() < n:
		slots.append(-1)


## What you see in your hands. Big things are held low in both arms.
func set_hand(m: Mesh, two: bool) -> void:
	hand_mi.mesh = m
	hand_two = two
	hand_swap = 0.25
	hand_mi.scale = Vector3.ONE * (1.2 if two else 1.0)
	hand_mi.rotation = Vector3(0.2, -0.4, 0.0) if not two else Vector3(0.1, 0.0, 0.0)


func _audio(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func begin() -> void:
	control = true
	if view:
		breath.play()
		heart.play()


func _unhandled_input(e: InputEvent) -> void:
	if not control or input_mode != "local":
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Chrome's pointer lock sometimes reports one huge bogus jump: skip those
		if e.relative.length() < 250.0:
			look(e.relative * 0.0022 * Run.sens)
	if e.is_action_pressed("light"):
		toggle_light()
	if e.is_action_pressed("jump"):
		jump_queued = true


func look(d: Vector2) -> void:
	if not control:
		return
	yaw -= d.x
	pitch = clampf(pitch - d.y, -1.35, 1.35)
	_look_now()


func toggle_light() -> void:
	if battery > 0.0:
		light.visible = not light.visible


## The player you're looking through moves every rendered frame, so the
## camera stays smooth on any refresh rate; everyone the server simulates
## moves on the physics tick.
func _process(dt: float) -> void:
	if view and input_mode == "local":
		_tick(dt)
	elif view:
		_look_now()


func _physics_process(dt: float) -> void:
	if not (view and input_mode == "local"):
		_tick(dt)


func _look_now() -> void:
	rotation.y = yaw
	head.rotation.x = pitch


func _tick(dt: float) -> void:
	t += dt
	if dying > 0.0:
		_death_cam(dt)
		return
	var inp := Vector2.ZERO
	var sprint := false
	if control:
		if input_mode == "net":
			inp = net_move.limit_length(1.0)
			crouching = net_crouch
			sprint = net_sprint
			if net_jump:
				jump_queued = true
				net_jump = false
			if net_light != light.visible and (battery > 0.0 or not net_light):
				light.visible = net_light
		else:
			inp = Input.get_vector("left", "right", "fwd", "back")
			crouching = Input.is_action_pressed("crouch")
			sprint = Input.is_action_pressed("sprint")
			if bot:
				inp = Vector2(0, -1)
				yaw += dt * 0.35
			if touch:
				inp = (inp + touch.move).limit_length(1.0)
				crouching = crouching or touch.crouch
				sprint = sprint or touch.run
				if touch.jump:
					touch.jump = false
					jump_queued = true
		last_move = inp
		last_sprint = sprint
	var depth := maxf(0.0, -world.height_at(position.x, position.z))
	var running := sprint and inp.length() > 0.2 and not crouching and not exhausted
	var spd := WALK
	if crouching:
		spd = SNEAK
	elif running:
		spd = RUN
	spd *= lerpf(1.0, 0.55, clampf(depth / 0.9, 0.0, 1.0))
	spd *= clampf(1.0 - carry * 0.07, 0.6, 1.0)
	# a sprint winds up over a third of a second; slowing down is quicker
	cur_spd = move_toward(cur_spd, spd, dt * (10.0 if spd > cur_spd else 20.0))
	if running:
		stamina -= dt / 7.0
		stam_delay = 0.8
	elif stam_delay > 0.0:
		stam_delay -= dt
	else:
		stamina += dt / (6.0 if inp.length() > 0.1 else 4.0)
	stamina = clampf(stamina, 0.0, 1.0)
	if stamina <= 0.0:
		exhausted = true
	elif exhausted and stamina > 0.45:
		exhausted = false

	# Quake-style: reach full speed in about a tenth of a second, stop almost
	# as fast, and keep your momentum in the air
	var wish := Basis(Vector3.UP, yaw) * Vector3(inp.x, 0, inp.y)
	var want := wish * cur_spd
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var accel := 45.0 if inp.length() > 0.05 else 32.0
	if not grounded:
		accel = 9.0
	hv = hv.move_toward(want, accel * dt)
	velocity = hv
	# move_and_slide steps by the physics delta; scale so a frame of any
	# length moves exactly its own share
	var pdt := get_physics_process_delta_time()
	var keep := velocity
	if dt > 0.0:
		velocity = keep * (dt / pdt)
		move_and_slide()
		velocity = Vector3(velocity.x, 0.0, velocity.z) * (pdt / dt)
	if world.hub_radius > 0.0:
		var flat := Vector2(position.x, position.z).limit_length(world.hub_radius)
		position.x = flat.x
		position.z = flat.y
	else:
		position.x = clampf(position.x, -World.BOUND, World.BOUND)
		position.z = clampf(position.z, -World.BOUND, World.BOUND)
	# jumping and landing
	last_jump = false
	var ground := world.height_at(position.x, position.z)
	if jump_queued:
		jump_buf = 0.14
	jump_buf = maxf(0.0, jump_buf - dt)
	if jump_buf > 0.0 and grounded and control and not crouching and stamina > 0.08:
		jump_buf = 0.0
		vy = JUMP * clampf(1.0 - carry * 0.06, 0.7, 1.0)
		grounded = false
		last_jump = true
		stamina = maxf(0.0, stamina - 0.06)
	jump_queued = false
	if grounded:
		position.y = lerpf(position.y, ground, 1.0 - exp(-dt * 22.0))
	else:
		vy -= GRAVITY * dt
		position.y += vy * dt
		if position.y <= ground:
			position.y = ground
			if vy < -3.0:
				land_dip = clampf(-vy * 0.02, 0.0, 0.18)
				_step(maxf(0.0, -ground), true)
			vy = 0.0
			grounded = true

	var hs := Vector2(velocity.x, velocity.z).length()
	moving = hs > 0.4
	# one footstep per half bob cycle, landing at the bottom of each dip
	var stride_len := 0.65 if crouching else (1.45 if running else 0.95)
	var was := bob
	if grounded:
		bob += hs * dt / stride_len * PI
	if int(floor(bob / PI)) != int(floor(was / PI)) and hs > 0.5:
		_step(depth, running)

	# breathing: loud when winded, and loud enough to be felt nearby
	var winded := 1.0 - stamina
	breath.volume_db = linear_to_db(clampf(winded * 1.4 - 0.25, 0.0, 1.0) * 0.8 + 0.0001)
	if exhausted:
		breath_noise -= dt
		if breath_noise <= 0.0:
			breath_noise = 1.6
			noise.emit(global_position, 4.5)

	# talking carries: a quiet mutter a few metres, a shout much further
	if talk > 0.04 and alive:
		talk_noise -= dt
		if talk_noise <= 0.0:
			talk_noise = 0.5
			noise.emit(global_position, lerpf(6.0, 18.0, clampf((talk - 0.04) * 8.0, 0.0, 1.0)))

	heart.volume_db = linear_to_db(fear * 0.9 + 0.0001)
	heart.pitch_scale = 0.85 + fear * 0.6

	# lamp battery
	if light.visible:
		battery = maxf(0.0, battery - dt / battery_life)
		light.light_energy = 3.2 if battery > 0.12 else (3.2 if randf() > 0.25 else randf() * 0.8)
		if battery <= 0.0:
			light.visible = false

	# camera: crouch height, walk bob, handheld drift
	eye = lerpf(eye, 1.0 if crouching else 1.6, 1.0 - exp(-dt * 8.0))
	# separate bob for each gait, eased in and out so starting and stopping
	# never snaps; a little side-to-side sway on top
	var want_amp := 0.0
	if grounded and hs > 0.5:
		want_amp = 0.014 if crouching else (0.05 if running else 0.028)
	bob_amp = lerpf(bob_amp, want_amp, 1.0 - exp(-dt * 8.0))
	land_dip = lerpf(land_dip, 0.0, 1.0 - exp(-dt * 8.0))
	head.position.y = eye - absf(sin(bob)) * bob_amp * 1.4 + bob_amp * 0.7 - land_dip
	head.position.x = sin(bob) * bob_amp * 0.45
	rotation.y = yaw
	head.rotation.x = pitch
	# portrait phones: hold the horizontal view instead of the vertical one
	var vs := get_viewport().get_visible_rect().size
	fov_kick = lerpf(fov_kick, 8.0 * clampf((hs - WALK) / (RUN - WALK), 0.0, 1.0), 1.0 - exp(-dt * 5.0))
	if vs.y > vs.x:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = 84.0 + fov_kick
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 80.0 + fov_kick
	# lean a touch into strafes
	tilt = lerpf(tilt, -inp.x * 0.022 * clampf(hs / WALK, 0.0, 1.0), 1.0 - exp(-dt * 7.0))
	cam.rotation.z = tilt + sin(bob) * bob_amp * 0.06 + sin(t * 0.7) * 0.0015
	cam.rotation.x = sin(t * 0.53) * 0.002 * (1.0 + winded * 3.0)
	cam.rotation.y = 0.0
	if shake > 0.01:
		cam.rotation.x += randf_range(-1.0, 1.0) * shake * 0.03
		cam.rotation.z += randf_range(-1.0, 1.0) * shake * 0.03
		cam.v_offset = randf_range(-1.0, 1.0) * shake * 0.05
	else:
		cam.v_offset = 0.0
	shake = lerpf(shake, 0.0, 1.0 - exp(-dt * 6.0))
	# the held item: bobs with your step, dips when you swap or land
	hand_swap = maxf(0.0, hand_swap - dt)
	var base := Vector3(0.0, -0.52, -0.62) if hand_two else Vector3(0.3, -0.32, -0.52)
	hand.position = base + Vector3(sin(bob) * bob_amp * 0.5 - tilt * 0.4, -absf(sin(bob)) * bob_amp * 0.5 - hand_swap * 1.2 - land_dip * 0.5, 0.0)


func _step(depth: float, running: bool) -> void:
	var r := 7.0
	if crouching:
		r = 2.2
	elif running:
		r = 20.0
	var wet := depth > 0.05
	if wet:
		r *= 1.5
	r *= 1.0 + carry * 0.12
	noise.emit(global_position, r)
	if not view:
		return
	step_sfx.stream = sounds.splash if wet else sounds.steps[randi() % sounds.steps.size()]
	step_sfx.pitch_scale = randf_range(0.9, 1.1)
	step_sfx.volume_db = -26.0 if crouching else (-14.0 if running else -19.0)
	if wet:
		step_sfx.volume_db -= 4.0
	step_sfx.play()


## Gone from the world for this level (dead or through the door): no
## collisions, no noise, nothing for anything to find.
func vanish() -> void:
	control = false
	moving = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	light.visible = false
	breath.stop()


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
