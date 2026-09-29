class_name World
extends Node3D
## The level's ground and everything rooted in it. New layout every run.
## Carboniferous: a swamp with black pools, scale trees, horsetails, ferns.
## Permian: red dunes and dry washes, sandstone outcrops, Glossopteris, bones.

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
var log_spots: Array = []  # [position, yaw] per fallen log
var burrows: Array = []  # Permian burrow mouths
var era := "carboniferous"
var bone_spots: Array = []
var hub_radius := 0.0  # the hub: walkable disc instead of a square
var spots := {}  # hub: named interaction points
var ring: Node3D


func generate(seed_: int, era_id: String) -> void:
	era = era_id
	rng.seed = seed_
	_colliders = StaticBody3D.new()
	add_child(_colliders)
	if era == "hub":
		_hub()
		return
	if era == "permian":
		_heights_permian(seed_)
		_pick_points()
		_terrain()
		_rocks()
		_flora_permian()
		return
	_heights(seed_)
	_pick_points()
	_terrain()
	_water()
	_flora()
	_logs()


func _heights_permian(seed_: int) -> void:
	var dune := FastNoiseLite.new()
	dune.seed = seed_
	dune.frequency = 0.006
	var ripple := FastNoiseLite.new()
	ripple.seed = seed_ + 1
	ripple.frequency = 0.03
	var wash := FastNoiseLite.new()
	wash.seed = seed_ + 2
	wash.frequency = 0.008
	wash.fractal_octaves = 2
	heights.resize((N + 1) * (N + 1))
	for j in N + 1:
		for i in N + 1:
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var h := 4.0 + dune.get_noise_2d(x, z) * 7.0 + absf(ripple.get_noise_2d(x, z)) * 1.2
			var w := absf(wash.get_noise_2d(x, z))
			h -= smoothstep(0.08, 0.0, w) * 2.2  # dry riverbeds
			var rim := maxf(absf(x), absf(z)) - (BOUND - 4.0)
			if rim > 0.0:
				h += rim * 0.4
			heights[j * (N + 1) + i] = maxf(h, 0.3)


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
		if height_at(s.x, s.z) < 0.25 or _in_rim(s):
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
			if era == "permian":
				col = Color(0.46, 0.22, 0.12).lerp(Color(0.56, 0.36, 0.2), n)
				col = col.lerp(Color(0.3, 0.2, 0.16), clampf((2.0 - h) / 2.0, 0.0, 1.0))
			elif h < 0.3:
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
		log_spots.append([mi.position, yaw])
		placed += 1


## Spread-out spots in the deeper pools, away from the start.
func pools(count: int) -> Array:
	var out := []
	for depth in [-0.8, -0.65, -0.5]:
		for tries in 3000:
			if out.size() >= count:
				return out
			var p := Vector3(rng.randf_range(-BOUND + 10, BOUND - 10), 0, rng.randf_range(-BOUND + 10, BOUND - 10))
			if height_at(p.x, p.z) > depth or Vector2(p.x - spawn.x, p.z - spawn.z).length() < 30.0:
				continue
			var ok := true
			for q in out:
				if (q as Vector3).distance_to(p) < 45.0:
					ok = false
			if ok:
				out.append(p)
	return out


func _in_rim(p: Vector3) -> bool:
	return absf(p.x) > BOUND - 12.0 or absf(p.z) > BOUND - 12.0


## Sandstone outcrops: the only cover in the Red Waste.
func _rocks() -> void:
	var placed := 0
	for tries in 3000:
		if placed >= 130:
			break
		var c := Vector3(rng.randf_range(-BOUND + 6, BOUND - 6), 0, rng.randf_range(-BOUND + 6, BOUND - 6))
		if _clear(c.x, c.z, 10.0):
			continue
		var st := Meshes.begin()
		var blocks := rng.randi_range(2, 5)
		for b in blocks:
			var off := Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			var p := c + off
			var size := Vector3(rng.randf_range(2.0, 5.0), rng.randf_range(2.0, 7.5), rng.randf_range(2.0, 4.5))
			if b == 0:
				size.y = rng.randf_range(4.0, 9.0)
			var yaw := rng.randf() * TAU
			var base := height_at(p.x, p.z) - 0.6
			Meshes.rock(st, rng, Vector3(off.x, base, off.z), size, yaw)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = size
			cs.shape = bx
			cs.position = Vector3(p.x, base + size.y * 0.5, p.z)
			cs.rotation.y = yaw
			_colliders.add_child(cs)
			_add_trunk(p.x, p.z, maxf(size.x, size.z) * 0.5, false)
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.finish(st, Meshes.veg())
		mi.position = Vector3(c.x, 0, c.z)
		mi.visibility_range_end = 140.0
		add_child(mi)
		placed += 1


func _flora_permian() -> void:
	var trees := [Meshes.glossopteris(rng), Meshes.glossopteris(rng), Meshes.snag(rng)]
	var scrub := [Meshes.scrub(rng), Meshes.scrub(rng), Meshes.scrub(rng)]
	var bones := Meshes.skeleton(rng)
	var mound := Meshes.burrow()
	var buckets := {}
	var put := func(kind: String, mesh: Mesh, x: float, z: float, y: float, s: float) -> void:
		var cs := 40.0
		var key := [kind, mesh, floori(x / cs), floori(z / cs)]
		var k := str(key[0]) + str(mesh.get_instance_id()) + "|" + str(key[2]) + "|" + str(key[3])
		if not buckets.has(k):
			buckets[k] = {"mesh": mesh, "cx": key[2], "cz": key[3], "xf": [], "vis": 70.0 if kind == "scrub" else 130.0}
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		buckets[k].xf.append(Transform3D(b, Vector3(x, y, z)))
	# trees, mostly along the washes where there was water once
	for tries in 900:
		var x := rng.randf_range(-HALF, HALF)
		var z := rng.randf_range(-HALF, HALF)
		var h := height_at(x, z)
		if (h > 2.6 and rng.randf() < 0.85) or _clear(x, z, 4.0):
			continue
		var v := rng.randi() % trees.size()
		var s := rng.randf_range(0.8, 1.3)
		put.call("tree", trees[v], x, z, h - 0.2, s)
		_add_trunk(x, z, 0.35 * s)
	for gz in range(-int(HALF), int(HALF), 3):
		for gx in range(-int(HALF), int(HALF), 3):
			if rng.randf() > 0.4:
				continue
			var x := gx + rng.randf() * 3.0
			var z := gz + rng.randf() * 3.0
			if _clear(x, z, 1.5):
				continue
			put.call("scrub", scrub[rng.randi() % scrub.size()], x, z, height_at(x, z), rng.randf_range(0.6, 1.4))
	for k in 26:
		var x := rng.randf_range(-BOUND + 10, BOUND - 10)
		var z := rng.randf_range(-BOUND + 10, BOUND - 10)
		put.call("bones", bones, x, z, height_at(x, z) - 0.1, rng.randf_range(0.8, 1.6))
		bone_spots.append(Vector3(x, height_at(x, z), z))
	# burrow colonies
	for c in 7:
		var cx := rng.randf_range(-BOUND + 20, BOUND - 20)
		var cz := rng.randf_range(-BOUND + 20, BOUND - 20)
		if Vector2(cx - spawn.x, cz - spawn.z).length() < 30.0:
			continue
		for k in rng.randi_range(3, 5):
			var p := Vector3(cx + rng.randf_range(-7, 7), 0, cz + rng.randf_range(-7, 7))
			p.y = height_at(p.x, p.z)
			burrows.append(p)
			put.call("mound", mound, p.x, p.z, p.y - 0.05, 1.0)
	for k in buckets:
		var bk: Dictionary = buckets[k]
		var center := Vector3((int(bk.cx) + 0.5) * 40.0, 0, (int(bk.cz) + 0.5) * 40.0)
		var arr: Array = bk.xf
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bk.mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			var tr: Transform3D = arr[i]
			tr.origin -= center
			mm.set_instance_transform(i, tr)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.position = center
		mi.visibility_range_end = (float(bk.vis) * (0.75 if lite else 1.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Line of sight between two points, blocked by rocks and trunks.
func clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or not (hit.collider == _colliders)


## Just the ground, for ragdolls to land on. Its own layer, so the player
## (who walks on height_at, not physics) never touches it.
func ground_collider() -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = N + 1
	hm.map_depth = N + 1
	hm.map_data = heights
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 7
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(STEP, 1.0, STEP)
	body.add_child(cs)
	add_child(body)


## A random dry spot, away from the start.
func dry_point(r: RandomNumberGenerator, min_h := 0.1, away := 25.0) -> Vector3:
	var p := Vector3.ZERO
	for tries in 400:
		p = Vector3(r.randf_range(-BOUND + 10, BOUND - 10), 0, r.randf_range(-BOUND + 10, BOUND - 10))
		if height_at(p.x, p.z) > min_h and Vector2(p.x - spawn.x, p.z - spawn.z).length() > away and not _near_trunk(p, 1.0):
			break
	p.y = height_at(p.x, p.z)
	return p


func _near_trunk(p: Vector3, pad: float) -> bool:
	for tr in trunks_near(p.x, p.z, 6.0):
		if Vector2(p.x - tr.x, p.z - tr.y).length() < float(tr.z) + pad:
			return true
	return false


## The shore nearest a point, walking outwards until it's dry.
func shore_near(p: Vector3, r: RandomNumberGenerator) -> Vector3:
	var a := r.randf() * TAU
	for k in 60:
		var q := p + Vector3(cos(a), 0, sin(a)) * (1.0 + k * 0.5)
		if height_at(q.x, q.z) > 0.05:
			q.y = height_at(q.x, q.z)
			return q
	return dry_point(r)


# ---------------------------------------------------------------- the Chrono Hub

func _hub() -> void:
	hub_radius = 15.0
	heights.resize((N + 1) * (N + 1))
	heights.fill(0.0)
	spawn = Vector3(0, 0, 6)
	spawn_yaw = 0.0
	exit_pos = Vector3(0, -100, 0)
	var deck := MeshInstance3D.new()
	deck.mesh = Meshes.hub_deck(16.0)
	add_child(deck)
	var lines := MeshInstance3D.new()
	lines.mesh = Meshes.hub_lines(16.0)
	add_child(lines)
	# the time ring, and the swirl inside it
	ring = Node3D.new()
	ring.position = Vector3(0, 5.2, -11)
	add_child(ring)
	var rm := MeshInstance3D.new()
	rm.mesh = Meshes.time_ring(4.6, 0.32)
	ring.add_child(rm)
	var swirl := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(9.0, 9.0)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float a = atan(p.y, p.x);
	float s = sin(a * 5.0 + r * 22.0 - TIME * 2.5) * 0.5 + 0.5;
	float m = smoothstep(0.5, 0.2, r);
	ALBEDO = mix(vec3(0.2, 0.5, 1.0), vec3(0.9, 0.5, 1.0), s) * m;
	ALPHA = m * (0.55 + 0.3 * s);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	qm.material = sm
	swirl.mesh = qm
	ring.add_child(swirl)
	var console := MeshInstance3D.new()
	console.mesh = Meshes.console_mesh()
	console.position = Vector3(0, 0, -5.0)
	add_child(console)
	spots["console"] = console.position
	var kiosk := MeshInstance3D.new()
	kiosk.mesh = Meshes.kiosk_mesh()
	kiosk.position = Vector3(9.0, 0, 2.0)
	kiosk.rotation.y = deg_to_rad(-70)
	add_child(kiosk)
	spots["shop"] = kiosk.position
	var hat := MeshInstance3D.new()
	hat.mesh = Meshes.hat("tophat")
	hat.position = kiosk.position + Vector3(0, 1.4, 0)
	hat.name = "ShopHat"
	add_child(hat)
	# signs
	for info in [["TIME CONSOLE", console.position + Vector3(0, 2.0, 0)], ["SHOP", kiosk.position + Vector3(0, 3.0, 0)]]:
		var l := Label3D.new()
		l.text = info[0]
		l.font_size = 64
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color(0.6, 1.0, 1.0)
		l.outline_size = 12
		l.position = info[1]
		add_child(l)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 4, -9)
	lamp.omni_range = 16.0
	lamp.light_energy = 1.4
	lamp.light_color = Color(0.6, 0.7, 1.0)
	add_child(lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.position = kiosk.position + Vector3(0, 3, 0)
	lamp2.omni_range = 8.0
	lamp2.light_energy = 1.2
	lamp2.light_color = Color(1.0, 0.75, 0.85)
	add_child(lamp2)
	# stars, far out, untouched by fog
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	var sq := QuadMesh.new()
	sq.size = Vector2(0.8, 0.8)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.disable_fog = true
	smat.albedo_color = Color(0.9, 0.9, 1.0)
	sq.material = smat
	stars.mesh = sq
	stars.instance_count = 500
	for k in 500:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		stars.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), d * 110.0))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = stars
	add_child(smi)
	# drifting clock-rings in the sky
	for k in 5:
		var g := MeshInstance3D.new()
		g.mesh = Meshes.time_ring(rng.randf_range(3.0, 8.0), 0.15)
		g.position = Vector3(rng.randf_range(-50, 50), rng.randf_range(10, 35), rng.randf_range(-60, -20))
		g.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		g.name = "Drift%d" % k
		add_child(g)
	# the console and kiosk are solid
	for p in [console.position, kiosk.position]:
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.8 if p == console.position else 1.3
		cy.height = 3.0
		cs.shape = cy
		cs.position = p + Vector3(0, 1.5, 0)
		_colliders.add_child(cs)


func _process(dt: float) -> void:
	if ring:
		ring.rotation.z += dt * 0.15
		for c in get_children():
			if c.name.begins_with("Drift"):
				c.rotation.x += dt * 0.05
				c.rotation.y += dt * 0.03
			elif c.name == "ShopHat":
				c.rotation.y += dt * 1.2
				c.position.y = 1.4 + sin(Time.get_ticks_msec() / 500.0) * 0.08
