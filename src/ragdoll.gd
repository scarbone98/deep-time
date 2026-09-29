class_name Ragdoll
extends Node3D
## What's left when a friend's signal is lost: a floppy chibi of rigid
## bodies pinned together, thrown the way whatever got them was going.

const LAYER := 1 << 8
const MASK := 1 | (1 << 7)  # trunks and rocks, and the ground


func setup(parts: Dictionary, at: Vector3, yaw: float, push: Vector3) -> void:
	position = at
	var b := Basis(Vector3.UP, yaw)
	var body := _body([parts.body], b * Vector3(0, 0.5, 0), Vector3(0.52, 0.56, 0.5), Vector3(0, 0.28, 0), b, 4.0)
	var head_meshes := [parts.head, parts.face]
	var head := _body(head_meshes, b * Vector3(0, 1.02, 0), Vector3(0.7, 0.68, 0.7), Vector3(0, 0.34, 0), b, 2.0)
	if parts.get("hat"):
		var hm := MeshInstance3D.new()
		hm.mesh = parts.hat
		hm.position.y = 0.66
		head.add_child(hm)
	if parts.get("gear"):
		var gm := MeshInstance3D.new()
		gm.mesh = parts.gear
		head.add_child(gm)
	_pin(body, head, b * Vector3(0, 1.02, 0) + at)
	for sd in [-1.0, 1.0]:
		var leg := _body([parts.leg], b * Vector3(0.13 * sd, 0.52, 0), Vector3(0.2, 0.5, 0.24), Vector3(0, -0.24, 0), b, 1.0)
		_pin(body, leg, b * Vector3(0.13 * sd, 0.52, 0) + at)
		var arm := _body([parts.arm], b * Vector3(0.3 * sd, 0.9, 0), Vector3(0.16, 0.4, 0.16), Vector3(0, -0.2, 0), b, 0.6)
		_pin(body, arm, b * Vector3(0.3 * sd, 0.9, 0) + at)
	for c in get_children():
		if c is RigidBody3D:
			c.linear_velocity = push + Vector3(randf_range(-1, 1), randf_range(2, 4), randf_range(-1, 1))
			c.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _body(meshes: Array, at: Vector3, size: Vector3, center: Vector3, b: Basis, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = LAYER
	rb.collision_mask = MASK
	rb.transform = Transform3D(b, at)
	rb.angular_damp = 1.5
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = center
	rb.add_child(cs)
	for m in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		rb.add_child(mi)
	add_child(rb)
	return rb


func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
