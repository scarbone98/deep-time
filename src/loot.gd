class_name Loot
extends Node3D
## Something worth taking home: an egg, a lump of amber, a fossil. The
## authority (solo or server) owns where it is; clients just show it.

enum { GROUND, CARRIED, GONE }

var idx := 0
var item_id := ""
var item_name := ""
var value := 0
var weight := 0.5
var nest := false  # taking it enrages the hunter
var state := GROUND
var holder := 0
var mesh: ArrayMesh
var mi: MeshInstance3D
var t := 0.0


func setup(i: int, info: Dictionary, at: Vector3) -> void:
	idx = i
	item_id = info.id
	item_name = info.name
	value = int(info.value)
	weight = float(info.weight)
	nest = info.where == "nest"
	position = at
	t = randf() * 10.0
	mesh = Meshes.loot(item_id)
	mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation.y = randf() * TAU
	add_child(mi)


func on_ground() -> bool:
	return state == GROUND


func set_state(s: int, who := 0, at := Vector3.ZERO) -> void:
	state = s
	holder = who
	if s == GROUND:
		position = at
	visible = s == GROUND


func _process(dt: float) -> void:
	if state != GROUND:
		return
	t += dt
	# a slow shimmer so it can be spotted in the lamp
	mi.position.y = 0.03 + sin(t * 1.7) * 0.02
