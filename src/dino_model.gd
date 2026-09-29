class_name DinoModel
extends Node3D
## A rigged, animated dinosaur from Quaternius's public-domain pack
## (assets/dinos, see CREDITS.md), recoloured for the fog and given eyes
## that catch your lamp. Plays Idle / Walk / Run / Attack / Death; the
## creature scripts just say how fast they're going and what they're doing.

const LOOKS := {
	# material name -> colour. "Black" is the eyes: they glow.
	"Velociraptor": {"LightBrown": Color(0.52, 0.42, 0.3), "Brown": Color(0.16, 0.12, 0.1), "eyes": Color(1.0, 0.78, 0.15)},
	"TRex": {"LightYellow": Color(0.45, 0.38, 0.28), "LightGreen": Color(0.26, 0.24, 0.18), "Green": Color(0.12, 0.11, 0.09),
		"Red": Color(0.35, 0.08, 0.08), "eyes": Color(1.0, 0.45, 0.1)},
	"Triceratops": {"LightBrown": Color(0.62, 0.55, 0.42), "Purple": Color(0.3, 0.26, 0.3), "Brown": Color(0.36, 0.28, 0.2)},
}

var kind := ""
var ap: AnimationPlayer
var cur := ""
var locked := 0.0  # a one-shot (attack) is playing
static var probe := false
static var no_recolour := false


func setup(k: String, size: float) -> void:
	kind = k
	var scene: PackedScene = load("res://assets/dinos/%s.glb" % k)
	var inst: Node3D = scene.instantiate()
	inst.rotation.y = PI  # the models face +Z; ours face -Z
	inst.scale = Vector3.ONE * size
	add_child(inst)
	ap = inst.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["Idle", "Walk", "Run"]:
		var anim := ap.get_animation(_full(a))
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
	if not no_recolour:
		_recolour(inst)
	_eyes(inst)
	play("Idle", 1.0)


## Head-bone space: +Y runs down the skull, +X is sideways, +Z is up.
const EYES := {
	"Velociraptor": {"at": Vector3(0.0038, 0.0085, 0.0028), "r": 0.0009},
	"TRex": {"at": Vector3(0.0048, 0.0075, 0.0042), "r": 0.0011},
}


## Two glowing eyes riding the skull: what your lamp catches first.
func _eyes(inst: Node) -> void:
	var look: Dictionary = LOOKS.get(kind, {})
	if not EYES.has(kind) or not look.has("eyes"):
		return
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Head"
	sk.add_child(ba)
	var e: Dictionary = EYES[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = look.eyes
	m.disable_fog = true
	var sm := SphereMesh.new()
	sm.radius = e.r
	sm.height = e.r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = m
	for sd in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		var p: Vector3 = e.at
		mi.position = Vector3(p.x * sd, p.y, p.z)
		ba.add_child(mi)


func _full(a: String) -> String:
	return "Armature|%s_%s" % [kind, a]


func _recolour(inst: Node) -> void:
	var look: Dictionary = LOOKS.get(kind, {})
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
			var n := String(src.resource_name)
			if n == "Black":  # claws and teeth
				m.albedo_color = Color(0.55, 0.5, 0.42)
				m.roughness = 0.4
			elif look.has(n):
				m.albedo_color = look[n]
				m.roughness = 0.6
				m.metallic_specular = 0.55
			mi.set_surface_override_material(s, m)


## Walk or run to match `speed` (m/s); `stride` is the ground covered by
## one loop of the walk at speed 1.
func move(speed: float, walk_at: float, run_at: float) -> void:
	if locked > 0.0:
		return
	if speed < 0.25:
		play("Idle", 1.0)
	elif speed < run_at * 0.75:
		play("Walk", clampf(speed / walk_at, 0.4, 2.2))
	else:
		play("Run", clampf(speed / run_at, 0.6, 2.0))


func attack() -> void:
	play("Attack", 1.3)
	locked = 1.0


func play(a: String, speed: float) -> void:
	var name := _full(a)
	if not ap.has_animation(name):
		return
	if cur != name:
		ap.play(name, 0.2)
		cur = name
	ap.speed_scale = speed


func _process(dt: float) -> void:
	locked = maxf(0.0, locked - dt)
