class_name World
extends Node3D
## The Coal Forest: a heightfield swamp with black pools, scale trees,
## horsetail thickets and a carpet of ferns. New layout every run.

const HALF := 160.0
const STEP := 2.0
const N := 160
const BOUND := 146.0

var heights := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var trunks := {}  # Vector2i cell -> Array of Vector3(x, z, radius)
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var exit_pos := Vector3.ZERO
var exit_yaw := 0.0
var _colliders: StaticBody3D
var lite := false  # phones: shorter draw distances


func generate(seed_: int) -> void:
	rng.seed = seed_
	_heights(seed_)
	_pick_points()
	_terrain()
	_water()
	_colliders = StaticBody3D.new()
	add_child(_colliders)
	_flora()
	_logs()


func _heights(seed_: int) -> void:
	var a := FastNoiseLite.new()
	a.seed = seed_
	a.frequency = 0.005
	var b := FastNoiseLite.new()
	b.seed = seed_ + 1
	b.frequency = 0.018
	var c := FastNoiseLite.new()
	c.seed = seed_ + 2
	c.frequency = 0.07
	heights.resize((N + 1) * (N + 1))
	for j in N + 1:
		for i in N + 1:
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var h := a.get_noise_2d(x, z) * 5.0 + b.get_noise_2d(x, z) * 2.4 + c.get_noise_2d(x, z) * 0.5 + 0.8
			if h < 0.0:
				h = -1.2 * (1.0 - exp(h * 1.6))  # pools stay wadeable
			var rim := maxf(absf(x), absf(z)) - (BOUND - 4.0)
			if rim > 0.0:
				h += rim * 0.3
			heights[j * (N + 1) + i] = h


func height_at(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / STEP, 0.0, N - 0.001)
	var gz := clampf((z + HALF) / STEP, 0.0, N - 0.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := heights[j * (N + 1) + i]
	var h10 := heights[j * (N + 1) + i + 1]
	var h01 := heights[(j + 1) * (N + 1) + i]
	var h11 := heights[(j + 1) * (N + 1) + i + 1]
	# same diagonal split as the mesh
	if fx > fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h11 - h01) * fx + (h01 - h00) * fz


func _pick_points() -> void:
	for tries in 2000:
		var s := Vector3(rng.randf_range(-125, 125), 0, rng.randf_range(-125, 125))
		if height_at(s.x, s.z) < 0.25:
			continue
		var ang := rng.randf() * TAU
		var e := s + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(130.0, 165.0)
		if absf(e.x) > 128.0 or absf(e.z) > 128.0:
			continue
		if height_at(e.x, e.z) < 0.1 and tries < 1500:
			continue
		spawn = s
		exit_pos = e
		break
	spawn_yaw = rng.randf() * TAU
	exit_yaw = atan2(spawn.x - exit_pos.x, spawn.z - exit_pos.z)
	# level a pad under the doorway
	var pad := maxf(height_at(exit_pos.x, exit_pos.z), 0.25)
	for j in N + 1:
		for i in N + 1:
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var d := Vector2(x - exit_pos.x, z - exit_pos.z).length()
			if d < 9.0:
				var k := smoothstep(9.0, 5.0, d)
				heights[j * (N + 1) + i] = lerpf(heights[j * (N + 1) + i], pad, k)
	spawn.y = height_at(spawn.x, spawn.z)
	exit_pos.y = pad


func _terrain() -> void:
	var tint := FastNoiseLite.new()
	tint.seed = rng.seed + 5
	tint.frequency = 0.04
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in N + 1:
		for i in N + 1:
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var h := heights[j * (N + 1) + i]
			var n := tint.get_noise_2d(x, z) * 0.5 + 0.5
			var col := Color(0.14, 0.12, 0.07).lerp(Color(0.1, 0.15, 0.06), n)
			if h < 0.3:
				col = col.lerp(Color(0.06, 0.06, 0.04), clampf((0.3 - h) / 0.8, 0.0, 1.0))
			st.set_color(col)
			st.add_vertex(Vector3(x, h, z))
	for j in N:
		for i in N:
			var a := j * (N + 1) + i
			var b := a + 1
			var c := a + N + 2
			var d := a + N + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(a); st.add_index(d); st.add_index(c)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)


func _water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.2, HALF * 2.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.035, 0.03)
	m.roughness = 0.06
	m.metallic_specular = 1.0
	pm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	add_child(mi)


func _clear(x: float, z: float, r: float) -> bool:
	return Vector2(x - spawn.x, z - spawn.z).length() < r or Vector2(x - exit_pos.x, z - exit_pos.z).length() < r + 5.0


func _add_trunk(x: float, z: float, r: float, collide := true) -> void:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not trunks.has(k):
		trunks[k] = []
	trunks[k].append(Vector3(x, z, r))
	if collide:
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = 14.0
		cs.shape = cy
		cs.position = Vector3(x, height_at(x, z) + 6.0, z)
		_colliders.add_child(cs)


func trunks_near(x: float, z: float, rad: float) -> Array:
	var out := []
	for cx in range(floori((x - rad) / 8.0), floori((x + rad) / 8.0) + 1):
		for cz in range(floori((z - rad) / 8.0), floori((z + rad) / 8.0) + 1):
			var k := Vector2i(cx, cz)
			if trunks.has(k):
				out.append_array(trunks[k])
	return out


func _flora() -> void:
	var dens := FastNoiseLite.new()
	dens.seed = rng.seed + 7
	dens.frequency = 0.02
	var kinds := {
		"tree": {"meshes": [lepi(), lepi(), lepi(), Meshes.sigillaria(rng), Meshes.sigillaria(rng)], "chunk": 40.0, "vis": 90.0 if lite else 115.0},
		"cala": {"meshes": [Meshes.calamites(rng), Meshes.calamites(rng), Meshes.calamites(rng)], "chunk": 40.0, "vis": 60.0 if lite else 80.0},
		"tfern": {"meshes": [Meshes.tree_fern(rng), Meshes.tree_fern(rng), Meshes.tree_fern(rng)], "chunk": 40.0, "vis": 80.0},
		"fern": {"meshes": [Meshes.ground_fern(rng), Meshes.ground_fern(rng), Meshes.ground_fern(rng), Meshes.ground_fern(rng)], "chunk": 20.0, "vis": 40.0 if lite else 58.0},
	}
	var buckets := {}
	var put := func(kind: String, x: float, z: float, y: float, s: float) -> void:
		var info: Dictionary = kinds[kind]
		var v := rng.randi() % (info.meshes as Array).size()
		var cs: float = info.chunk
		var key := "%s|%d|%d|%d" % [kind, v, floori(x / cs), floori(z / cs)]
		if not buckets.has(key):
			buckets[key] = []
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		buckets[key].append(Transform3D(b, Vector3(x, y, z)))

	# scale trees
	for gz in range(-int(HALF), int(HALF), 7):
		for gx in range(-int(HALF), int(HALF), 7):
			var x := gx + rng.randf() * 7.0
			var z := gz + rng.randf() * 7.0
			var d := dens.get_noise_2d(x, z)
			if rng.randf() > 0.32 + d * 0.7:
				continue
			var h := height_at(x, z)
			if h < -0.5 or _clear(x, z, 4.0):
				continue
			var s := rng.randf_range(0.8, 1.3)
			put.call("tree", x, z, h - 0.3, s)
			_add_trunk(x, z, 0.62 * s)
	# horsetail thickets hug the water
	for gz in range(-int(HALF), int(HALF), 5):
		for gx in range(-int(HALF), int(HALF), 5):
			var x := gx + rng.randf() * 5.0
			var z := gz + rng.randf() * 5.0
			var h := height_at(x, z)
			var wet := 1.0 - clampf(absf(h - 0.0) / 0.9, 0.0, 1.0)
			if rng.randf() > wet * 0.7 or _clear(x, z, 3.0):
				continue
			put.call("cala", x, z, h - 0.1, rng.randf_range(0.8, 1.2))
			_add_trunk(x, z, 0.9, false)
	# tree ferns
	for gz in range(-int(HALF), int(HALF), 8):
		for gx in range(-int(HALF), int(HALF), 8):
			var x := gx + rng.randf() * 8.0
			var z := gz + rng.randf() * 8.0
			var h := height_at(x, z)
			if h < 0.1 or rng.randf() > 0.45 or _clear(x, z, 3.0):
				continue
			put.call("tfern", x, z, h - 0.1, rng.randf_range(0.8, 1.25))
			_add_trunk(x, z, 0.3)
	# ground ferns everywhere dry
	for gz in range(-int(HALF), int(HALF), 3):
		for gx in range(-int(HALF), int(HALF), 3):
			var x := gx + rng.randf() * 3.0
			var z := gz + rng.randf() * 3.0
			var h := height_at(x, z)
			if h < -0.05 or rng.randf() > 0.62 or _clear(x, z, 1.5):
				continue
			put.call("fern", x, z, h, rng.randf_range(0.7, 1.4))

	for key in buckets:
		var parts: PackedStringArray = (key as String).split("|")
		var info: Dictionary = kinds[parts[0]]
		var cs: float = info.chunk
		var center := Vector3((int(parts[2]) + 0.5) * cs, 0, (int(parts[3]) + 0.5) * cs)
		var arr: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = info.meshes[int(parts[1])]
		mm.instance_count = arr.size()
		for k in arr.size():
			var tr: Transform3D = arr[k]
			tr.origin -= center
			mm.set_instance_transform(k, tr)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.position = center
		mi.visibility_range_end = info.vis
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func lepi() -> ArrayMesh:
	return Meshes.lepidodendron(rng)


func _logs() -> void:
	var meshes := [Meshes.log_mesh(rng, 9.0), Meshes.log_mesh(rng, 12.0), Meshes.log_mesh(rng, 7.0)]
	var lens := [9.0, 12.0, 7.0]
	var placed := 0
	for tries in 400:
		if placed >= 36:
			break
		var x := rng.randf_range(-BOUND + 8, BOUND - 8)
		var z := rng.randf_range(-BOUND + 8, BOUND - 8)
		var h := height_at(x, z)
		if h < -0.4 or _clear(x, z, 6.0):
			continue
		var v := rng.randi() % 3
		var yaw := rng.randf() * TAU
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[v]
		mi.position = Vector3(x, h + 0.25, z)
		mi.rotation.y = yaw
		mi.visibility_range_end = 90.0
		add_child(mi)
		var len_: float = lens[v]
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(len_, 1.2, 1.0)
		cs.shape = bx
		cs.position = mi.position
		cs.rotation.y = yaw
		_colliders.add_child(cs)
		var along := Vector3(cos(yaw), 0, -sin(yaw))
		for k in int(len_) + 1:
			var p := mi.position + along * (k - len_ * 0.5)
			_add_trunk(p.x, p.z, 0.6, false)
		placed += 1
