class_name Outpost
extends Node3D
## A lost Chrono Bureau outpost: an earlier crew built a scrap of the
## Backrooms here and never came home. A maze of yellow wallpaper under a
## drop ceiling, half its lights dead, the best loot in its dead ends. The
## first time anyone steps inside, something outside hears the door.

const C := 3.2  # cell size
const H := 2.9  # ceiling height

var n := 9
var cells := []  # cells[x][z] = {"n","e","s","w"} walls
var dead_ends: Array = []  # world positions
var lights: Array = []  # [OmniLight3D, panel material, base energy]
var body: StaticBody3D
var t := 0.0
var entered := false
var blackout := 0.0


## Lays out the maze and builds it. `pad` is the floor height, `yaw` points
## the entrance (local +Z) at the rift. Returns world points to avoid.
func build(rng: RandomNumberGenerator, at: Vector3, yaw: float, pad: float, look: Dictionary) -> Array:
	position = Vector3(at.x, pad, at.z)
	rotation.y = yaw
	_carve(rng)
	var half := n * C * 0.5
	var st := Meshes.begin()
	var wall_a: Color = look.wall
	var wall_b: Color = look.wall2
	var floor_c: Color = look.floor
	# floor and ceiling
	for x in n:
		for z in n:
			var x0 := -half + x * C
			var z0 := -half + z * C
			var fc := floor_c.lerp(floor_c.darkened(0.45), rng.randf() * rng.randf())
			Meshes.quad(st, Vector3(x0, 0.02, z0), Vector3(x0 + C, 0.02, z0), Vector3(x0 + C, 0.02, z0 + C), Vector3(x0, 0.02, z0 + C), fc, fc)
	var tile := Color(0.6, 0.58, 0.48)
	Meshes.box(st, Vector3(-half - 0.2, H, -half - 0.2), Vector3(half + 0.2, H + 0.08, half + 0.2), tile)
	# walls, as segments between cells
	var segs := []
	for x in n:
		for z in n:
			var c: Dictionary = cells[x][z]
			var x0 := -half + x * C
			var z0 := -half + z * C
			if c.n:
				segs.append([Vector3(x0, 0, z0), Vector3(x0 + C, 0, z0)])
			if c.w:
				segs.append([Vector3(x0, 0, z0), Vector3(x0, 0, z0 + C)])
			if z == n - 1 and c.s:
				segs.append([Vector3(x0, 0, z0 + C), Vector3(x0 + C, 0, z0 + C)])
			if x == n - 1 and c.e:
				segs.append([Vector3(x0 + C, 0, z0), Vector3(x0 + C, 0, z0 + C)])
	body = StaticBody3D.new()
	add_child(body)
	var avoid := []
	for sg in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		var stain := rng.randf() < 0.25
		var col := (wall_a if rng.randf() < 0.5 else wall_b)
		if stain:
			col = col.darkened(rng.randf_range(0.2, 0.45))
		var lo := Vector3(minf(a.x, b.x) - 0.08, 0, minf(a.z, b.z) - 0.08)
		var hi := Vector3(maxf(a.x, b.x) + 0.08, H, maxf(a.z, b.z) + 0.08)
		Meshes.box(st, lo, hi, col)
		Meshes.box(st, lo - Vector3(0.01, 0, 0.01), Vector3(hi.x + 0.01, 0.12, hi.z + 0.01), col.darkened(0.5))
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = hi - lo
		cs.shape = bx
		cs.position = (lo + hi) * 0.5
		body.add_child(cs)
		for k in 4:
			avoid.append(to_global_pre(a.lerp(b, (k + 0.5) / 4.0)))
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.finish(st, _flat_mat())
	add_child(mi)
	_lights(rng, half)
	# dead ends hold the good stuff (never the entrance cell)
	for x in n:
		for z in n:
			var c: Dictionary = cells[x][z]
			var w := int(c.n) + int(c.e) + int(c.s) + int(c.w)
			if w >= 3 and not (x == n / 2 and z == n - 1):
				dead_ends.append(to_global_pre(Vector3(-half + (x + 0.5) * C, 0, -half + (z + 0.5) * C)))
	return avoid


## to_global before we're in the tree.
func to_global_pre(p: Vector3) -> Vector3:
	return Transform3D(Basis(Vector3.UP, rotation.y), position) * p


func _flat_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Recursive backtracker, then a few extra openings so there are loops to
## lose something in, and a door in the middle of the +Z side.
func _carve(rng: RandomNumberGenerator) -> void:
	cells = []
	for x in n:
		var col := []
		for z in n:
			col.append({"n": true, "e": true, "s": true, "w": true, "seen": false})
		cells.append(col)
	var stack := [Vector2i(n / 2, n - 1)]
	cells[n / 2][n - 1].seen = true
	while not stack.is_empty():
		var c: Vector2i = stack[-1]
		var opts := []
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var q: Vector2i = c + d
			if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and not cells[q.x][q.y].seen:
				opts.append(d)
		if opts.is_empty():
			stack.pop_back()
			continue
		var d: Vector2i = opts[rng.randi() % opts.size()]
		_open(c, d)
		var q := c + d
		cells[q.x][q.y].seen = true
		stack.append(q)
	for k in 10:
		var c := Vector2i(rng.randi_range(1, n - 2), rng.randi_range(1, n - 2))
		_open(c, [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][rng.randi() % 4])
	cells[n / 2][n - 1].s = false  # the door


func _open(c: Vector2i, d: Vector2i) -> void:
	var q := c + d
	if d == Vector2i(0, -1):
		cells[c.x][c.y].n = false
		cells[q.x][q.y].s = false
	elif d == Vector2i(0, 1):
		cells[c.x][c.y].s = false
		cells[q.x][q.y].n = false
	elif d == Vector2i(1, 0):
		cells[c.x][c.y].e = false
		cells[q.x][q.y].w = false
	else:
		cells[c.x][c.y].w = false
		cells[q.x][q.y].e = false


## Fluorescent panels in some cells; a few actually light. Most flicker.
func _lights(rng: RandomNumberGenerator, half: float) -> void:
	var lit := 0
	for x in n:
		for z in n:
			if rng.randf() > 0.4:
				continue
			var p := Vector3(-half + (x + 0.5) * C, H - 0.03, -half + (z + 0.5) * C)
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.9, 0.9, 0.8)
			pm.emission_enabled = true
			pm.emission = Color(1.0, 0.95, 0.8)
			var dead := rng.randf() < 0.35
			pm.emission_energy_multiplier = 0.0 if dead else 2.0
			var bm := BoxMesh.new()
			bm.size = Vector3(1.1, 0.04, 0.5)
			bm.material = pm
			var panel := MeshInstance3D.new()
			panel.mesh = bm
			panel.position = p
			add_child(panel)
			if dead:
				continue
			var ol: OmniLight3D = null
			if lit < 7 and rng.randf() < 0.6:
				ol = OmniLight3D.new()
				ol.position = p - Vector3(0, 0.3, 0)
				ol.omni_range = 5.5
				ol.light_energy = 1.1
				ol.light_color = Color(1.0, 0.95, 0.78)
				add_child(ol)
				lit += 1
			lights.append([ol, pm, rng.randf() * 10.0])


func contains(p: Vector3) -> bool:
	var l := Transform3D(Basis(Vector3.UP, rotation.y), position).affine_inverse() * p
	var half := n * C * 0.5
	return absf(l.x) < half and absf(l.z) < half


## Someone opened the door: the lights stutter and die for a while.
func trip() -> void:
	blackout = 6.0


func _process(dt: float) -> void:
	t += dt
	blackout = maxf(0.0, blackout - dt)
	for L in lights:
		var ph: float = L[2]
		var on := 1.0
		var f := sin(t * 1.7 + ph) + sin(t * 23.0 + ph * 3.0) * 0.4
		if f > 1.15:
			on = 0.2
		if blackout > 0.0:
			on = 0.0 if fmod(t * 7.0 + ph, 1.0) > 0.12 or blackout > 4.0 else 1.0
		(L[1] as StandardMaterial3D).emission_energy_multiplier = 2.0 * on
		if L[0]:
			(L[0] as OmniLight3D).light_energy = 1.1 * on
