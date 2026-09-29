class_name Loot
extends Node3D
## Something worth taking home: an egg, a lump of amber, a fossil. The
## authority (solo or server) owns where it is; clients show it and fly
## thrown loot the same way, so a throw looks right before the server says
## where it landed. It glints through the fog so you can find it.

enum { GROUND, CARRIED, GONE, FLYING }

const GRAVITY := 16.0

var idx := 0
var world: World
var item_id := ""
var item_name := ""
var value := 0
var weight := 0.5
var nest := false  # taking it enrages the hunter
var fragile := false  # eggs crack if they hit the ground
var cracked := false
var state := GROUND
var holder := 0
var thrower := 0
var vel := Vector3.ZERO
var air := 0.0
var landed := false
var mesh: ArrayMesh
var mi: MeshInstance3D
var glint: MeshInstance3D
var glint_mat: StandardMaterial3D
var tag: Label3D
var t := 0.0
var targeted := false

static var _glint_tex: GradientTexture2D


func setup(i: int, info: Dictionary, at: Vector3, w: World) -> void:
	idx = i
	world = w
	item_id = info.id
	item_name = info.name
	value = int(info.value)
	weight = float(info.weight)
	nest = info.where == "nest"
	fragile = item_id.ends_with("egg") or item_id.ends_with("spawn")
	position = at
	t = randf() * 10.0
	mesh = Meshes.loot(item_id)
	mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * 1.35
	mi.rotation.y = randf() * TAU
	add_child(mi)
	if _glint_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_glint_tex = GradientTexture2D.new()
		_glint_tex.gradient = g
		_glint_tex.fill = GradientTexture2D.FILL_RADIAL
		_glint_tex.fill_from = Vector2(0.5, 0.5)
		_glint_tex.fill_to = Vector2(1.0, 0.5)
		_glint_tex.width = 32
		_glint_tex.height = 32
	glint_mat = StandardMaterial3D.new()
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glint_mat.disable_fog = true
	glint_mat.albedo_texture = _glint_tex
	glint_mat.albedo_color = Color(1.0, 0.9, 0.55, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	q.material = glint_mat
	glint = MeshInstance3D.new()
	glint.mesh = q
	glint.position.y = 0.4
	add_child(glint)
	tag = Label3D.new()
	tag.font_size = 32
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 8
	tag.no_depth_test = true
	tag.position.y = 0.75
	tag.visible = false
	add_child(tag)
	_retag()


func _retag() -> void:
	tag.text = "%s  %s" % [item_name, Run.cash(value)]
	tag.modulate = Color(1.0, 0.6, 0.5) if cracked else Color(1.0, 0.95, 0.6)


func on_ground() -> bool:
	return state == GROUND


func set_state(s: int, who := 0, at := Vector3.ZERO) -> void:
	state = s
	holder = who
	if s == GROUND:
		position = at
		landed = false
	visible = s == GROUND or s == FLYING


func throw_from(at: Vector3, v: Vector3, who: int) -> void:
	state = FLYING
	holder = 0
	thrower = who
	position = at
	vel = v
	air = 0.0
	landed = false
	visible = true


## Half the value, and it says so.
func crack() -> void:
	if cracked or not fragile:
		return
	cracked = true
	value = int(value / 2)
	item_name = "CRACKED " + item_name
	_retag()


func _physics_process(dt: float) -> void:
	if state != FLYING or landed:
		return
	air += dt
	vel.y -= GRAVITY * dt
	position += vel * dt
	mi.rotation.x += dt * 9.0
	var g := world.height_at(position.x, position.z)
	if position.y <= g:
		position.y = g
		vel = Vector3.ZERO
		mi.rotation.x = 0.0
		landed = true


func _process(dt: float) -> void:
	t += dt
	tag.visible = targeted and state == GROUND
	if state != GROUND:
		glint_mat.albedo_color.a = 0.0
		return
	mi.position.y = 0.03 + sin(t * 1.7) * 0.02
	mi.rotation.y += dt * (1.5 if targeted else 0.2)
	# a twinkle every couple of seconds, so it can be found in the fog
	var ph := fmod(t + idx * 0.37, 2.6)
	var tw := maxf(0.0, 1.0 - absf(ph - 0.25) / 0.25)
	glint_mat.albedo_color.a = 0.15 + tw * 0.6 + (0.3 if targeted else 0.0)
	glint.scale = Vector3.ONE * (0.6 + tw * 0.8)
