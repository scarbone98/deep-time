class_name Ragdoll
extends Node3D
## What's left when a friend's signal is lost: six rigid bodies pinned
## together, thrown the way whatever got them was going.

const LAYER := 1 << 8
const MASK := 1 | (1 << 7)  # trunks and rocks, and the ground


func setup(parts: Dictionary, at: Vector3, yaw: float, push: Vector3) -> void:
	position = at
	var b := Basis(Vector3.UP, yaw)
	var torso := _body(parts.torso, b * Vector3(0, 0.92, 0), Vector3(0.36, 0.6, 0.26), Vector3(0, 0.3, 0), b, 4.0)
	var head := _body(parts.head, b * Vector3(0, 1.54, 0), Vector3(0.26, 0.3, 0.26), Vector3(0, 0.15, 0), b, 1.0)
	_pin(torso, head, b * Vector3(0, 1.52, 0) + at)
	for sd in [-1.0, 1.0]:
		var leg := _body(parts.leg, b * Vector3(0.1 * sd, 0.92, 0), Vector3(0.16, 0.9, 0.18), Vector3(0, -0.45, 0), b, 1.5)
		_pin(torso, leg, b * Vector3(0.1 * sd, 0.92, 0) + at)
		var arm := _body(parts.arm, b * Vector3(0.22 * sd, 1.44, 0), Vector3(0.12, 0.64, 0.12), Vector3(0, -0.32, 0), b, 0.8)
		_pin(torso, arm, b * Vector3(0.22 * sd, 1.44, 0) + at)
	for c in get_children():
		if c is RigidBody3D:
			c.linear_velocity = push + Vector3(randf_range(-1, 1), randf_range(1, 3), randf_range(-1, 1))
			c.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _body(mesh: Mesh, at: Vector3, size: Vector3, center: Vector3, b: Basis, mass: float) -> RigidBody3D:
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
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rb.add_child(mi)
	add_child(rb)
	return rb


func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
