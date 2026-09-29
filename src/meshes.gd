class_name Meshes
extends RefCounted
## Procedural low-poly meshes: Carboniferous flora, the creatures, props.
## Colour lives in vertex colours; everything is flat-shaded.

static var _veg: StandardMaterial3D


static func veg() -> StandardMaterial3D:
	if _veg == null:
		_veg = StandardMaterial3D.new()
		_veg.vertex_color_use_as_albedo = true
		_veg.cull_mode = BaseMaterial3D.CULL_DISABLED
		_veg.roughness = 1.0
	return _veg


static func chitin() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.42
	m.metallic_specular = 0.9
	return m


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st


static func finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.generate_normals()
	st.set_material(mat)
	return st.commit()


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, c0: Color, c1: Color) -> void:
	# a,b share colour c0 (one ring); c,d share c1 (next ring)
	st.set_color(c0); st.add_vertex(a)
	st.set_color(c0); st.add_vertex(b)
	st.set_color(c1); st.add_vertex(c)
	st.set_color(c0); st.add_vertex(a)
	st.set_color(c1); st.add_vertex(c)
	st.set_color(c1); st.add_vertex(d)


static func box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, col)


## A tube through `pts`, one ring per point. `pattern` checkers the bark
## (the diamond leaf-scars of scale trees).
static func tube(st: SurfaceTool, pts: Array, radii: Array, cols: Array, sides: int, pattern := false, flat := 1.0) -> void:
	var rings := []
	for i in pts.size():
		var fwd: Vector3
		if i == 0:
			fwd = pts[1] - pts[0]
		elif i == pts.size() - 1:
			fwd = pts[i] - pts[i - 1]
		else:
			fwd = pts[i + 1] - pts[i - 1]
		fwd = fwd.normalized()
		var ref := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT
		var side := fwd.cross(ref).normalized()
		var up := side.cross(fwd).normalized()
		var ring := []
		for s in sides:
			var a := TAU * (s + (0.5 if pattern and i % 2 == 1 else 0.0)) / sides
			ring.append(pts[i] + (side * cos(a) + up * sin(a) * flat) * float(radii[i]))
		rings.append(ring)
	for i in pts.size() - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var c0: Color = cols[i]
			var c1: Color = cols[i + 1]
			if pattern and s % 2 == 0:
				c0 = c0.lightened(0.1)
				c1 = c1.lightened(0.1)
			quad(st, rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s], c0, c1)


static func octa(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var v := [c + Vector3(r, 0, 0), c + Vector3(0, 0, r), c + Vector3(-r, 0, 0), c + Vector3(0, 0, -r)]
	var top := c + Vector3(0, r, 0)
	var bot := c - Vector3(0, r, 0)
	for k in 4:
		tri(st, v[k], v[(k + 1) % 4], top, col)
		tri(st, v[(k + 1) % 4], v[k], bot, col.darkened(0.3))


## A fern frond: a drooping rachis with sawtooth leaflets either side.
static func frond(st: SurfaceTool, o: Vector3, d: Vector3, length: float, width: float, c: Color, droop := 0.2, segs := 7) -> void:
	var p := o
	var dir := d.normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.05:
		side = Vector3.RIGHT
	side = side.normalized()
	for i in segs:
		var t := float(i) / segs
		var q := p + dir * (length / segs)
		var w := width * sin(PI * (0.12 + t * 0.85))
		var m := p.lerp(q, 0.2)
		var sag := Vector3.DOWN * w * 0.35
		var cc := c.lerp(c.darkened(0.35), t)
		tri(st, p, q, m + side * w + sag, cc)
		tri(st, p, q, m - side * w + sag, cc)
		p = q
		dir = (dir + Vector3.DOWN * droop).normalized()


static func _blade(st: SurfaceTool, p: Vector3, dir: Vector3, length: float, width: float, droop: float, col: Color) -> void:
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.05:
		side = Vector3.RIGHT
	side = side.normalized() * width
	var mid := p + dir * length * 0.5
	var tip := p + dir * length + Vector3.DOWN * droop
	tri(st, p - side, p + side, mid, col)
	tri(st, mid - side * 0.6, mid + side * 0.6, tip, col.darkened(0.15))


# ---------------------------------------------------------------- flora

## Lepidodendron: the scale tree. A tall bare pole that forks at the very top
## into a crown of bottle-brush tufts.
static func lepidodendron(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(15.0, 19.0)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.9
	var pts := []
	var rad := []
	var col := []
	var rings := 18
	for i in rings + 1:
		var t := float(i) / rings
		pts.append(Vector3(0, t * h, 0) + lean * t * t)
		var r := lerpf(0.6, 0.3, pow(t, 0.8))
		if i == 0:
			r = 1.1
		elif i == 1:
			r = 0.75
		rad.append(r)
		col.append(Color(0.19, 0.2, 0.15).lerp(Color(0.26, 0.27, 0.19), t))
	tube(st, pts, rad, col, 8, true)
	_branch(st, rng, pts[rings], (Vector3.UP + lean * 0.15).normalized(), 2.4, 0.3, 4)
	return finish(st, veg())


static func _branch(st: SurfaceTool, rng: RandomNumberGenerator, o: Vector3, d: Vector3, length: float, r: float, depth: int) -> void:
	var e := o + d * length
	var c := Color(0.22, 0.23, 0.17)
	tube(st, [o, e], [r, r * 0.72], [c, c], 5)
	if depth == 0:
		_tuft(st, rng, e, d, 11, 1.3)
		return
	var axis := d.cross(Vector3.UP)
	if axis.length() < 0.05:
		axis = Vector3.RIGHT
	axis = axis.normalized().rotated(d, rng.randf_range(-0.9, 0.9))
	for sgn in [-1.0, 1.0]:
		var nd := d.rotated(axis, sgn * rng.randf_range(0.38, 0.62))
		nd = (nd + Vector3.DOWN * 0.1).normalized()
		_branch(st, rng, e, nd, length * 0.78, r * 0.72, depth - 1)


static func _tuft(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, d: Vector3, count: int, length: float) -> void:
	for k in count:
		var dir := (d * 0.5 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.8), rng.randf_range(-1, 1))).normalized()
		var c := Color(0.09, 0.16, 0.06).lerp(Color(0.17, 0.23, 0.09), rng.randf())
		_blade(st, p, dir, length * rng.randf_range(0.7, 1.2), 0.06, 0.35, c)
	# a hanging cone
	if rng.randf() < 0.5:
		var cc := Color(0.24, 0.18, 0.1)
		tube(st, [p, p + Vector3(0, -0.5, 0)], [0.07, 0.03], [cc, cc], 4)


## Sigillaria: a thick straight column ending in a skirt of grass-like leaves.
static func sigillaria(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(11.0, 14.0)
	var pts := []
	var rad := []
	var col := []
	for i in 13:
		var t := i / 12.0
		pts.append(Vector3(sin(t * 3.0) * 0.15, t * h, 0))
		rad.append(1.2 if i == 0 else lerpf(0.72, 0.5, t))
		col.append(Color(0.2, 0.19, 0.15).lerp(Color(0.24, 0.24, 0.18), t))
	tube(st, pts, rad, col, 10, true)
	var tops: Array = [pts[12]]
	if rng.randf() < 0.6:
		var top: Vector3 = pts[12]
		var c := Color(0.23, 0.23, 0.17)
		var a := top + Vector3(1.4, 2.0, 0.3)
		var b := top + Vector3(-1.2, 2.2, -0.4)
		tube(st, [top, a], [0.45, 0.35], [c, c], 6)
		tube(st, [top, b], [0.45, 0.35], [c, c], 6)
		tops = [a, b]
	for p in tops:
		for k in 34:
			var ang := TAU * k / 34.0 + rng.randf() * 0.2
			var dir := Vector3(cos(ang), rng.randf_range(0.2, 1.1), sin(ang)).normalized()
			var c := Color(0.1, 0.17, 0.06).lerp(Color(0.2, 0.25, 0.1), rng.randf())
			_blade(st, p, dir, rng.randf_range(1.8, 2.6), 0.07, 1.2, c)
		# rings of cones below the crown
		for k in 8:
			var ang := TAU * k / 8.0
			var q: Vector3 = p + Vector3(cos(ang) * 0.55, -1.0, sin(ang) * 0.55)
			var cc := Color(0.26, 0.19, 0.1)
			tube(st, [q, q + Vector3(0, -0.6, 0)], [0.08, 0.03], [cc, cc], 4)
	return finish(st, veg())


## Calamites: giant horsetails, a clump of jointed stems with whorled needles.
static func calamites(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	for stem in rng.randi_range(3, 5):
		var base := Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9))
		var h := rng.randf_range(5.0, 9.0)
		var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.6
		var nodes := int(h / 0.7)
		var prev := base
		for i in range(1, nodes + 1):
			var t := float(i) / nodes
			var p := base + Vector3(0, t * h, 0) + bend * t * t
			var r := lerpf(0.13, 0.05, t)
			var c := Color(0.21, 0.25, 0.13).lerp(Color(0.28, 0.3, 0.16), t)
			tube(st, [prev, p], [r * 1.1, r], [c.darkened(0.3), c], 5)
			if t > 0.25:
				for k in 8:
					var ang := TAU * k / 8.0 + i
					var dir := Vector3(cos(ang), 0.55, sin(ang)).normalized()
					_blade(st, p, dir, lerpf(0.8, 0.35, t), 0.025, 0.12, Color(0.13, 0.21, 0.08))
			prev = p
	return finish(st, veg())


## Psaronius: tree fern. A fibrous trunk, a flared root mantle, arching fronds.
static func tree_fern(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(3.5, 5.5)
	var bark := Color(0.17, 0.12, 0.08)
	var top := Vector3(rng.randf_range(-0.3, 0.3), h, rng.randf_range(-0.3, 0.3))
	tube(st, [Vector3.ZERO, Vector3(0, 1.0, 0), Vector3(top.x * 0.3, h * 0.6, top.z * 0.3), top],
		[0.55, 0.32, 0.26, 0.24], [bark.darkened(0.3), bark, bark, bark.lightened(0.1)], 6, true)
	var n := rng.randi_range(11, 15)
	for k in n:
		var ang := TAU * k / n + rng.randf() * 0.3
		var dir := Vector3(cos(ang), rng.randf_range(0.3, 0.9), sin(ang))
		var c := Color(0.12, 0.2, 0.07).lerp(Color(0.19, 0.26, 0.1), rng.randf())
		frond(st, top, dir, rng.randf_range(2.4, 3.2), 0.42, c, 0.22, 8)
	return finish(st, veg())


static func ground_fern(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var n := rng.randi_range(6, 8)
	for k in n:
		var ang := TAU * k / n + rng.randf() * 0.4
		var dir := Vector3(cos(ang), rng.randf_range(0.8, 1.6), sin(ang))
		var c := Color(0.1, 0.18, 0.06).lerp(Color(0.18, 0.25, 0.09), rng.randf())
		frond(st, Vector3(0, 0.02, 0), dir, rng.randf_range(0.9, 1.4), 0.24, c, 0.28, 6)
	return finish(st, veg())


## A fallen, rotting scale-tree trunk lying along X.
static func log_mesh(rng: RandomNumberGenerator, length: float) -> ArrayMesh:
	var st := begin()
	var pts := []
	var rad := []
	var col := []
	var n := 10
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector3((t - 0.5) * length, sin(t * 5.0) * 0.08, sin(t * 3.0) * 0.2))
		rad.append(lerpf(0.62, 0.45, t) * rng.randf_range(0.9, 1.05))
		col.append(Color(0.17, 0.19, 0.11).lerp(Color(0.2, 0.17, 0.11), rng.randf()))
	tube(st, pts, rad, col, 7, true)
	# jagged broken end
	var end: Vector3 = pts[n]
	for k in 5:
		var ang := TAU * k / 5.0
		var c := Color(0.3, 0.24, 0.15)
		tri(st, end + Vector3(0, cos(ang), sin(ang)) * 0.45, end + Vector3(0, cos(ang + 1.2), sin(ang + 1.2)) * 0.45,
			end + Vector3(rng.randf_range(0.2, 0.6), cos(ang + 0.6) * 0.2, sin(ang + 0.6) * 0.2), c)
	return finish(st, veg())


# ---------------------------------------------------------------- Arthropleura

## One body ring. Forward is -Z. Wide flat tergite plates with a pale rear rim,
## so overlapping segments read as armour.
static func mill_segment(mat: Material, head := false) -> ArrayMesh:
	var st := begin()
	# wide flat paranota at the edges, a humped back in the middle
	var prof := [Vector2(-0.46, -0.02), Vector2(-0.4, 0.08), Vector2(-0.3, 0.12), Vector2(-0.2, 0.24), Vector2(0, 0.31),
		Vector2(0.2, 0.24), Vector2(0.3, 0.12), Vector2(0.4, 0.08), Vector2(0.46, -0.02)]
	var top := Color(0.055, 0.042, 0.035)
	var rim := Color(0.48, 0.29, 0.13)
	var zf := -0.18
	var zb := 0.18
	var fs := 0.86 if not head else 0.55
	for k in prof.size() - 1:
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		quad(st, Vector3(a.x * fs, a.y * fs, zf), Vector3(b.x * fs, b.y * fs, zf), Vector3(b.x, b.y, zb), Vector3(a.x, a.y, zb), top, rim)
		tri(st, Vector3(0, 0.02, zb), Vector3(b.x, b.y, zb), Vector3(a.x, a.y, zb), rim.darkened(0.3))
		tri(st, Vector3(0, 0.02, zf), Vector3(a.x * fs, a.y * fs, zf), Vector3(b.x * fs, b.y * fs, zf), top)
	var belly := Color(0.2, 0.13, 0.08)
	quad(st, Vector3(-0.42 * fs, 0, zf), Vector3(0.42 * fs, 0, zf), Vector3(0.42, 0, zb), Vector3(-0.42, 0, zb), belly, belly)
	if head:
		var ac := Color(0.3, 0.2, 0.1)
		for s in [-1.0, 1.0]:
			tube(st, [Vector3(0.1 * s, 0.08, zf), Vector3(0.28 * s, 0.24, -0.5), Vector3(0.45 * s, 0.18, -0.95)],
				[0.025, 0.02, 0.008], [ac, ac, ac], 4)
			tube(st, [Vector3(0.08 * s, 0.02, zf), Vector3(0.12 * s, -0.04, -0.3)], [0.04, 0.015], [rim, rim], 4)
		octa(st, Vector3(0, 0.1, zf - 0.02), 0.09, top)
	return finish(st, mat)


## A three-jointed leg sticking out along +X (side = 1) or -X (side = -1).
static func mill_leg(mat: Material, side: float) -> ArrayMesh:
	var st := begin()
	var c := Color(0.32, 0.19, 0.09)
	tube(st, [Vector3.ZERO, Vector3(0.2 * side, 0.06, 0), Vector3(0.34 * side, -0.14, 0), Vector3(0.38 * side, -0.19, -0.02)],
		[0.035, 0.03, 0.02, 0.008], [c, c, c.darkened(0.3), c.darkened(0.4)], 4)
	return finish(st, mat)


# ---------------------------------------------------------------- Meganeura

static func fly_body() -> ArrayMesh:
	var st := begin()
	var thorax := Color(0.12, 0.16, 0.14)
	tube(st, [Vector3(0, 0, 0.08), Vector3(0, 0.01, -0.02), Vector3(0, 0, -0.11)], [0.05, 0.07, 0.05], [thorax, thorax, thorax], 6)
	var eye := Color(0.16, 0.3, 0.27)
	Meshes.octa(st, Vector3(0.05, 0.02, -0.15), 0.05, eye)
	Meshes.octa(st, Vector3(-0.05, 0.02, -0.15), 0.05, eye)
	var pts := []
	var rad := []
	var col := []
	for i in 10:
		var t := i / 9.0
		pts.append(Vector3(0, -t * t * 0.05, 0.08 + t * 0.55))
		rad.append(lerpf(0.035, 0.018, t))
		col.append(Color(0.06, 0.17, 0.19) if i % 2 == 0 else Color(0.03, 0.06, 0.06))
	tube(st, pts, rad, col, 5)
	var leg := Color(0.05, 0.05, 0.05)
	for k in 3:
		for s in [-1.0, 1.0]:
			var o := Vector3(0.03 * s, -0.03, -0.06 + k * 0.05)
			tube(st, [o, o + Vector3(0.1 * s, -0.06, -0.04), o + Vector3(0.13 * s, -0.13, -0.08)], [0.008, 0.006, 0.004], [leg, leg, leg], 3)
	return finish(st, veg())


static func fly_wing() -> ArrayMesh:
	var st := begin()
	var c := Color(0.75, 0.8, 0.72, 0.3)
	var pts := [Vector3(0, 0, -0.02), Vector3(0.12, 0, -0.045), Vector3(0.3, 0, -0.04), Vector3(0.37, 0, 0.0),
		Vector3(0.3, 0, 0.035), Vector3(0.12, 0, 0.04), Vector3(0, 0, 0.02)]
	for k in range(1, pts.size() - 1):
		tri(st, pts[0], pts[k], pts[k + 1], c)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.2
	return finish(st, m)


# ---------------------------------------------------------------- Eryops

## A two-metre amphibian, flat as a log, forward is -Z. Returns [body, eyes];
## the eyes get their own unlit material so they catch in the dark.
static func eryops() -> Array:
	var st := begin()
	var skin := Color(0.13, 0.12, 0.07)
	var pts := [Vector3(0, 0, 1.35), Vector3(0, 0, 0.95), Vector3(0, 0, 0.55), Vector3(0, 0.02, 0.25), Vector3(0, 0.03, -0.1),
		Vector3(0, 0.02, -0.35), Vector3(0, 0.02, -0.45), Vector3(0, 0.02, -0.62), Vector3(0, 0.01, -0.8), Vector3(0, 0, -0.95)]
	var rad := [0.02, 0.08, 0.16, 0.3, 0.32, 0.27, 0.22, 0.27, 0.21, 0.08]
	var col := []
	for i in pts.size():
		col.append(skin.lerp(Color(0.2, 0.17, 0.09), 0.5 + 0.5 * sin(i * 2.3)))
	tube(st, pts, rad, col, 8, true, 0.42)
	var leg := Color(0.16, 0.14, 0.08)
	for z in [-0.3, 0.35]:
		for sd in [-1.0, 1.0]:
			var a := Vector3(0.22 * sd, 0, z)
			var b := Vector3(0.5 * sd, -0.04, z - 0.08)
			var c := Vector3(0.56 * sd, -0.2, z - 0.14)
			tube(st, [a, b, c], [0.07, 0.05, 0.035], [leg, leg, leg.darkened(0.2)], 5)
			for k in 3:
				tri(st, c + Vector3(0, 0, -0.03), c + Vector3(0, 0, 0.03), c + Vector3(0.1 * sd, -0.02, (k - 1) * 0.08 - 0.05), leg.darkened(0.3))
	var body := finish(st, chitin())
	var es := begin()
	for sd in [-1.0, 1.0]:
		octa(es, Vector3(0.11 * sd, 0.1, -0.6), 0.035, Color(0.75, 0.72, 0.35))
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return [body, finish(es, em)]


# ---------------------------------------------------------------- Pulmonoscorpius

## Body with legs and pincers; forward is -Z, tail attaches at (0, 0.03, 0.3).
static func scorpion_body() -> ArrayMesh:
	var st := begin()
	var shell := Color(0.08, 0.07, 0.05)
	tube(st, [Vector3(0, 0, 0.32), Vector3(0, 0.02, 0.1), Vector3(0, 0.03, -0.15), Vector3(0, 0.02, -0.3)],
		[0.14, 0.2, 0.18, 0.12], [shell, shell.lightened(0.08), shell, shell], 8, true, 0.45)
	var leg := Color(0.16, 0.12, 0.07)
	for i in 4:
		var z := -0.15 + i * 0.1
		var dz := (i - 1.5) * 0.12
		for sd in [-1.0, 1.0]:
			tube(st, [Vector3(0.15 * sd, 0, z), Vector3(0.38 * sd, 0.12, z + dz), Vector3(0.55 * sd, -0.1, z + dz * 1.4)],
				[0.03, 0.022, 0.008], [leg, leg, leg.darkened(0.3)], 4)
	for sd in [-1.0, 1.0]:
		tube(st, [Vector3(0.1 * sd, 0, -0.3), Vector3(0.25 * sd, 0.05, -0.5), Vector3(0.2 * sd, 0.04, -0.7)], [0.04, 0.035, 0.05], [shell, shell, shell], 5)
		tube(st, [Vector3(0.2 * sd, 0.04, -0.7), Vector3(0.14 * sd, 0.05, -0.95)], [0.055, 0.008], [shell, leg], 5)
		tube(st, [Vector3(0.24 * sd, 0.03, -0.72), Vector3(0.27 * sd, 0.03, -0.9)], [0.03, 0.005], [shell, leg], 4)
	return finish(st, chitin())


static func scorpion_tail(telson := false) -> ArrayMesh:
	var st := begin()
	var shell := Color(0.09, 0.075, 0.05)
	if telson:
		octa(st, Vector3(0, 0, 0.08), 0.075, Color(0.2, 0.13, 0.07))
		tube(st, [Vector3(0, 0, 0.12), Vector3(0, -0.05, 0.22), Vector3(0, -0.13, 0.24)], [0.025, 0.012, 0.002],
			[Color(0.3, 0.2, 0.1), Color(0.3, 0.2, 0.1), Color(0.1, 0.05, 0.03)], 4)
	else:
		tube(st, [Vector3.ZERO, Vector3(0, 0, 0.16)], [0.07, 0.06], [shell, shell.lightened(0.1)], 6, false, 0.9)
	return finish(st, chitin())


# ---------------------------------------------------------------- Permian

## A sandstone block with red and ochre strata. `base` is its bottom centre.
static func rock(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, size: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var bands := maxi(2, int(size.y / 0.7))
	var shrink := rng.randf_range(0.6, 0.9)
	var cols := [Color(0.45, 0.2, 0.12), Color(0.56, 0.31, 0.18), Color(0.4, 0.18, 0.11), Color(0.6, 0.38, 0.22)]
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var jit := []
	for k in 4:
		jit.append(Vector2(rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.1)))
	var ring := func(t: float) -> Array:
		var out := []
		var sc := lerpf(1.0, shrink, t) * (1.0 + sin(t * 17.0) * 0.04)
		for k in 4:
			var c: Vector2 = corners[k] * jit[k] * sc
			out.append(base + b * Vector3(c.x * size.x * 0.5, t * size.y, c.y * size.z * 0.5))
		return out
	var prev: Array = ring.call(0.0)
	for i in bands:
		var t := float(i + 1) / bands
		var cur: Array = ring.call(t)
		var col: Color = cols[(i + rng.randi() % 2) % cols.size()]
		for k in 4:
			quad(st, prev[k], prev[(k + 1) % 4], cur[(k + 1) % 4], cur[k], col, col.darkened(0.08))
		prev = cur
	var top := Color(0.62, 0.42, 0.26)
	quad(st, prev[0], prev[1], prev[2], prev[3], top, top)


## Glossopteris: a stocky tree with drooping tongue-shaped leaves.
static func glossopteris(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(4.5, 7.0)
	var bark := Color(0.24, 0.18, 0.13)
	var top := Vector3(rng.randf_range(-0.4, 0.4), h, rng.randf_range(-0.4, 0.4))
	tube(st, [Vector3.ZERO, Vector3(0, h * 0.5, 0), top], [0.4, 0.25, 0.18], [bark, bark, bark.lightened(0.1)], 6, true)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf() * 0.4
		var d := Vector3(cos(a), rng.randf_range(0.2, 0.8), sin(a)).normalized()
		var e := top + d * rng.randf_range(1.2, 2.2)
		tube(st, [top - Vector3(0, 0.6, 0), e], [0.12, 0.05], [bark, bark], 4)
		for l in 9:
			var ld := (d + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.2, -0.2), rng.randf_range(-0.8, 0.8))).normalized()
			var c := Color(0.22, 0.26, 0.1).lerp(Color(0.34, 0.33, 0.14), rng.randf())
			var side := ld.cross(Vector3.UP)
			if side.length() < 0.05:
				side = Vector3.RIGHT
			side = side.normalized() * 0.09
			var L := rng.randf_range(0.5, 0.8)
			var m := e + ld * L * 0.45
			tri(st, e, m + side, m - side, c)
			tri(st, m + side, e + ld * L, m - side, c.darkened(0.15))
	return finish(st, veg())


## A dead conifer, bleached and bare.
static func snag(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(6.0, 10.0)
	var c := Color(0.5, 0.45, 0.38)
	var lean := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	tube(st, [Vector3.ZERO, Vector3(0, h * 0.5, 0) + lean * 0.3, Vector3(0, h, 0) + lean], [0.3, 0.2, 0.04], [c.darkened(0.3), c, c], 6)
	for k in 6:
		var y := h * rng.randf_range(0.35, 0.85)
		var a := rng.randf() * TAU
		var o := Vector3(0, y, 0) + lean * (y / h)
		tube(st, [o, o + Vector3(cos(a), rng.randf_range(-0.4, 0.2), sin(a)) * rng.randf_range(0.6, 1.6)], [0.06, 0.01], [c, c], 3)
	return finish(st, veg())


static func scrub(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	for k in 14:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), rng.randf_range(0.5, 1.4), sin(a)).normalized()
		var c := Color(0.3, 0.26, 0.13).lerp(Color(0.42, 0.34, 0.18), rng.randf())
		_blade(st, Vector3.ZERO, dir, rng.randf_range(0.4, 0.8), 0.03, 0.08, c)
	return finish(st, veg())


## Something big died here: a spine, a rib cage, a skull.
static func skeleton(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var bone := Color(0.78, 0.72, 0.6)
	var spine := []
	var rad := []
	var cols := []
	for i in 12:
		spine.append(Vector3(sin(i * 0.4) * 0.3, 0.35 + sin(i * 0.35) * 0.2, i * 0.3 - 1.6))
		rad.append(0.06)
		cols.append(bone.darkened(0.1 * (i % 2)))
	tube(st, spine, rad, cols, 4)
	for i in range(2, 8):
		var p: Vector3 = spine[i]
		for sd in [-1.0, 1.0]:
			var w := 0.55 - absf(i - 4.5) * 0.06
			tube(st, [p, p + Vector3(w * sd, 0.1, 0.05), p + Vector3(w * 1.3 * sd, -0.35, 0.1)], [0.035, 0.03, 0.02], [bone, bone, bone.darkened(0.2)], 3)
	var skull: Vector3 = spine[0] + Vector3(0, 0.0, -0.3)
	tube(st, [skull, skull + Vector3(0, -0.05, -0.55)], [0.18, 0.07], [bone, bone.darkened(0.15)], 5, false, 0.7)
	octa(st, skull + Vector3(0.1, 0.08, -0.1), 0.05, Color(0.1, 0.08, 0.06))
	octa(st, skull + Vector3(-0.1, 0.08, -0.1), 0.05, Color(0.1, 0.08, 0.06))
	return finish(st, veg())


static func burrow() -> ArrayMesh:
	var st := begin()
	var dirt := Color(0.4, 0.22, 0.13)
	var n := 10
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0)) * 1.3
		var o1 := Vector3(cos(a1), 0, sin(a1)) * 1.3
		var i0 := Vector3(cos(a0), 0.35, sin(a0)) * Vector3(0.4, 1, 0.4)
		var i1 := Vector3(cos(a1), 0.35, sin(a1)) * Vector3(0.4, 1, 0.4)
		quad(st, o0, o1, i1, i0, dirt, dirt.lightened(0.1))
		tri(st, i0, i1, Vector3(0, 0.05, 0), Color(0.03, 0.02, 0.02))
	return finish(st, veg())


## Inostrancevia: a gorgonopsid the size of a bear, all skull and sabres.
## Forward is -Z; hips at z = +/-0.7. Returns {"body", "leg_f", "leg_b"}.
static func gorgon() -> Dictionary:
	var st := begin()
	var hide := Color(0.3, 0.24, 0.19)
	var belly := Color(0.46, 0.38, 0.3)
	var stripe := Color(0.16, 0.12, 0.1)
	var pts := [Vector3(0, 0.05, 1.9), Vector3(0, 0.12, 1.3), Vector3(0, 0.28, 0.7), Vector3(0, 0.36, 0.1),
		Vector3(0, 0.33, -0.5), Vector3(0, 0.3, -0.9), Vector3(0, 0.38, -1.25)]
	var rad := [0.04, 0.14, 0.38, 0.46, 0.42, 0.26, 0.24]
	var cols := []
	for i in pts.size():
		cols.append(stripe if i % 2 == 1 and i > 1 else hide)
	tube(st, pts, rad, cols, 8, true, 0.85)
	quad(st, Vector3(-0.3, 0.05, 0.6), Vector3(0.3, 0.05, 0.6), Vector3(0.3, 0.05, -0.4), Vector3(-0.3, 0.05, -0.4), belly, belly)
	# the skull: long, deep, with a gape of sabres
	var sk := [Vector3(0, 0.42, -1.3), Vector3(0, 0.42, -1.6), Vector3(0, 0.36, -1.95), Vector3(0, 0.3, -2.2)]
	tube(st, sk, [0.26, 0.26, 0.2, 0.12], [hide, hide.darkened(0.1), hide, hide.lightened(0.05)], 7, false, 1.2)
	var jaw := [Vector3(0, 0.2, -1.45), Vector3(0, 0.14, -1.9), Vector3(0, 0.16, -2.1)]
	tube(st, jaw, [0.14, 0.1, 0.06], [belly, belly, belly], 6, false, 0.8)
	var tooth := Color(0.92, 0.88, 0.76)
	for sd in [-1.0, 1.0]:
		tube(st, [Vector3(0.1 * sd, 0.24, -2.0), Vector3(0.11 * sd, -0.05, -2.02), Vector3(0.1 * sd, -0.12, -1.98)],
			[0.035, 0.02, 0.002], [tooth, tooth, tooth], 4)
		octa(st, Vector3(0.17 * sd, 0.55, -1.65), 0.045, Color(0.85, 0.6, 0.15))
	var body := finish(st, chitin())
	return {"body": body, "leg_f": _gorgon_leg(false), "leg_b": _gorgon_leg(true)}


static func _gorgon_leg(back: bool) -> ArrayMesh:
	var st := begin()
	var c := Color(0.28, 0.22, 0.18)
	var knee := Vector3(0.12, -0.35, 0.18 if back else -0.12)
	var foot := Vector3(0.08, -0.72, 0.0)
	tube(st, [Vector3.ZERO, knee, foot, foot + Vector3(0, 0, -0.18)], [0.15, 0.09, 0.07, 0.04], [c, c, c.darkened(0.2), c.darkened(0.3)], 5)
	return finish(st, chitin())


## Scutosaurus: a squat armoured grazer, knobbly and slow.
static func scutosaurus() -> Dictionary:
	var st := begin()
	var hide := Color(0.4, 0.33, 0.24)
	var pts := [Vector3(0, 0.15, 1.3), Vector3(0, 0.35, 0.9), Vector3(0, 0.55, 0.3), Vector3(0, 0.6, -0.3),
		Vector3(0, 0.5, -0.8), Vector3(0, 0.45, -1.05), Vector3(0, 0.4, -1.35)]
	var rad := [0.05, 0.3, 0.62, 0.66, 0.5, 0.25, 0.22]
	var cols := []
	for i in pts.size():
		cols.append(hide.lerp(Color(0.3, 0.25, 0.18), float(i % 2)))
	tube(st, pts, rad, cols, 9, true, 0.8)
	var knob := Color(0.5, 0.42, 0.3)
	var r := RandomNumberGenerator.new()
	r.seed = 4
	for k in 26:
		var z := r.randf_range(-0.7, 0.8)
		var a := r.randf_range(0.3, PI - 0.3)
		octa(st, Vector3(cos(a) * 0.6, 0.55 + sin(a) * 0.45, z), r.randf_range(0.05, 0.1), knob)
	for sd in [-1.0, 1.0]:
		octa(st, Vector3(0.22 * sd, 0.45, -1.3), 0.08, knob)
	return {"body": finish(st, chitin()), "leg": _stumpy_leg(Color(0.34, 0.28, 0.2), 0.8, 0.13)}


static func _stumpy_leg(c: Color, h: float, r: float) -> ArrayMesh:
	var st := begin()
	tube(st, [Vector3.ZERO, Vector3(0.1, -h * 0.5, 0), Vector3(0.05, -h, 0), Vector3(0.05, -h, -r)], [r, r * 0.8, r * 0.75, r * 0.4], [c, c, c.darkened(0.2), c.darkened(0.3)], 5)
	return finish(st, chitin())


## Dicynodon: a tusked, beaked burrower.
static func dicynodon() -> ArrayMesh:
	var st := begin()
	var hide := Color(0.48, 0.36, 0.26)
	var pts := [Vector3(0, 0.12, 0.55), Vector3(0, 0.25, 0.3), Vector3(0, 0.3, -0.05), Vector3(0, 0.26, -0.35), Vector3(0, 0.26, -0.55), Vector3(0, 0.2, -0.72)]
	tube(st, pts, [0.05, 0.22, 0.27, 0.2, 0.17, 0.08], [hide, hide, hide.darkened(0.1), hide, hide, Color(0.3, 0.25, 0.2)], 7, true, 0.85)
	var tusk := Color(0.9, 0.86, 0.74)
	for sd in [-1.0, 1.0]:
		tube(st, [Vector3(0.07 * sd, 0.16, -0.6), Vector3(0.08 * sd, 0.02, -0.64)], [0.025, 0.004], [tusk, tusk], 4)
		octa(st, Vector3(0.1 * sd, 0.33, -0.5), 0.03, Color(0.1, 0.07, 0.05))
		for z in [-0.25, 0.25]:
			tube(st, [Vector3(0.18 * sd, 0.12, z), Vector3(0.28 * sd, 0.0, z - 0.05), Vector3(0.3 * sd, -0.05, z - 0.1)], [0.06, 0.05, 0.03], [hide, hide, hide.darkened(0.2)], 4)
	return finish(st, chitin())


# ---------------------------------------------------------------- people

## A ball, as a stack of rings. sy squashes or stretches it vertically.
static func ball(st: SurfaceTool, c: Vector3, r: float, col: Color, sy := 1.0, sides := 12, rings := 7, col2 := Color(-1, 0, 0)) -> void:
	var pts := []
	var rad := []
	var cols := []
	for i in rings + 1:
		var a := PI * i / rings
		pts.append(c + Vector3(0, -cos(a) * r * sy, 0))
		rad.append(maxf(sin(a) * r, 0.001))
		cols.append(col if col2.r < 0.0 else col.lerp(col2, float(i) / rings))
	tube(st, pts, rad, cols, sides)


static func _smooth_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	return m


static func _smooth() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	return st


## A chibi time-traveller: big round head, soft suit, stubby limbs, a time
## pack on the back. Parts sit on their joints (see Avatar and Ragdoll):
## legs hang from the hips, the body rises from the hips, the head sits on
## the neck, arms hang from the shoulders. Sized for a 1.6 m eye line.
static func chibi(suit: Color) -> Dictionary:
	var skin := Color(0.98, 0.8, 0.66)
	var boot := suit.darkened(0.55)
	var mat := _smooth_mat()
	var st := _smooth()
	# body: a soft bean
	tube(st, [Vector3(0, 0, 0), Vector3(0, 0.12, 0), Vector3(0, 0.3, 0), Vector3(0, 0.46, 0), Vector3(0, 0.56, 0)],
		[0.2, 0.28, 0.29, 0.24, 0.12], [suit.darkened(0.15), suit, suit, suit.lightened(0.08), suit.lightened(0.1)], 14)
	# belt and buckle
	tube(st, [Vector3(0, 0.1, 0), Vector3(0, 0.15, 0)], [0.285, 0.29], [suit.darkened(0.45), suit.darkened(0.45)], 14)
	ball(st, Vector3(0, 0.125, -0.29), 0.04, Color(1.0, 0.85, 0.3), 1.0, 8, 4)
	# the time pack
	var pack := Color(0.32, 0.34, 0.4)
	box(st, Vector3(-0.17, 0.12, 0.2), Vector3(0.17, 0.46, 0.36), pack)
	ball(st, Vector3(0, 0.3, 0.37), 0.07, Color(0.35, 0.95, 1.0), 1.0, 10, 5)
	var body := finish(st, mat)
	st = _smooth()
	ball(st, Vector3(0, 0.34, 0), 0.38, skin, 0.94, 16, 10)
	var head := finish(st, mat)
	# the face: big shiny eyes, blush, a little smile
	st = _smooth()
	for sd in [-1.0, 1.0]:
		ball(st, Vector3(0.13 * sd, 0.36, -0.335), 0.065, Color(0.06, 0.05, 0.08), 1.25, 10, 6)
		ball(st, Vector3(0.105 * sd, 0.4, -0.385), 0.02, Color(1, 1, 1), 1.0, 6, 3)
		ball(st, Vector3(0.22 * sd, 0.26, -0.29), 0.05, Color(1.0, 0.55, 0.6), 0.55, 8, 4)
	tube(st, [Vector3(-0.05, 0.25, -0.365), Vector3(0, 0.235, -0.37), Vector3(0.05, 0.25, -0.365)], [0.012, 0.012, 0.012],
		[Color(0.35, 0.15, 0.15), Color(0.35, 0.15, 0.15), Color(0.35, 0.15, 0.15)], 5)
	var face := finish(st, _unshaded())
	st = _smooth()
	tube(st, [Vector3(0, 0, 0), Vector3(0, -0.22, 0), Vector3(0, -0.36, 0)], [0.1, 0.09, 0.09], [suit, suit, suit.darkened(0.1)], 10)
	ball(st, Vector3(0, -0.42, -0.04), 0.12, boot, 0.6, 10, 5)
	var leg := finish(st, mat)
	st = _smooth()
	tube(st, [Vector3(0, 0, 0), Vector3(0, -0.18, 0), Vector3(0, -0.3, 0)], [0.08, 0.075, 0.07], [suit, suit, suit], 10)
	ball(st, Vector3(0, -0.34, 0), 0.08, Color(1, 1, 1), 1.0, 10, 5)
	var arm := finish(st, mat)
	st = _smooth()
	var cb := Color(0.25, 0.25, 0.3)
	box(st, Vector3(-0.06, -0.06, -0.12), Vector3(0.06, 0.06, 0.08), cb)
	tube(st, [Vector3(0, 0, -0.12), Vector3(0, 0, -0.18)], [0.045, 0.05], [cb, Color(0.5, 0.8, 1.0)], 10)
	ball(st, Vector3(0.03, 0.07, 0.0), 0.018, Color(1, 0.2, 0.2), 1.0, 6, 3)
	var cam := finish(st, mat)
	return {"body": body, "head": head, "face": face, "leg": leg, "arm": arm, "cam": cam}


static func _unshaded() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Hats sit on top of the head: origin is the crown, +Y up, forward -Z.
static func hat(id: String) -> ArrayMesh:
	if id == "" or id == "none":
		return null
	var st := _smooth()
	match id:
		"party":
			var n := 6
			for i in n:
				var t0 := float(i) / n
				var t1 := float(i + 1) / n
				var c := Color(1.0, 0.35, 0.55) if i % 2 == 0 else Color(1.0, 0.85, 0.3)
				tube(st, [Vector3(0, t0 * 0.42, 0), Vector3(0, t1 * 0.42, 0)], [lerpf(0.17, 0.01, t0), lerpf(0.17, 0.01, t1)], [c, c], 12)
			ball(st, Vector3(0, 0.44, 0), 0.05, Color(0.4, 0.9, 1.0), 1.0, 8, 4)
		"propeller":
			ball(st, Vector3(0, -0.02, 0), 0.26, Color(0.3, 0.55, 1.0), 0.55, 14, 7)
			box(st, Vector3(-0.2, -0.07, -0.34), Vector3(0.2, -0.04, -0.16), Color(1.0, 0.8, 0.2))
			tube(st, [Vector3(0, 0.12, 0), Vector3(0, 0.2, 0)], [0.015, 0.015], [Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8)], 6)
			box(st, Vector3(-0.28, 0.19, -0.03), Vector3(0.28, 0.21, 0.03), Color(1.0, 0.3, 0.3))
			box(st, Vector3(-0.03, 0.19, -0.28), Vector3(0.03, 0.21, 0.28), Color(0.3, 0.9, 0.4))
		"cowboy":
			var c := Color(0.6, 0.4, 0.22)
			tube(st, [Vector3(0, -0.05, 0), Vector3(0, -0.03, 0)], [0.42, 0.44], [c, c], 18)
			tube(st, [Vector3(0, -0.04, 0), Vector3(0, 0.12, 0), Vector3(0, 0.2, 0)], [0.21, 0.2, 0.15], [c.darkened(0.1), c, c.lightened(0.1)], 14)
			tube(st, [Vector3(0, 0.0, 0), Vector3(0, 0.04, 0)], [0.215, 0.215], [Color(0.3, 0.15, 0.1), Color(0.3, 0.15, 0.1)], 14)
		"tophat":
			var c := Color(0.12, 0.1, 0.14)
			tube(st, [Vector3(0, -0.05, 0), Vector3(0, -0.03, 0)], [0.3, 0.31], [c, c], 18)
			tube(st, [Vector3(0, -0.04, 0), Vector3(0, 0.36, 0)], [0.19, 0.2], [c, c], 16)
			tube(st, [Vector3(0, 0.0, 0), Vector3(0, 0.06, 0)], [0.195, 0.197], [Color(0.8, 0.15, 0.2), Color(0.8, 0.15, 0.2)], 16)
			ball(st, Vector3(0, 0.36, 0), 0.19, c, 0.02, 16, 3)
		"dino":
			var g := Color(0.35, 0.78, 0.35)
			ball(st, Vector3(0, -0.06, 0.02), 0.34, g, 0.8, 16, 8)
			for k in 5:
				var z := -0.22 + k * 0.12
				var y := 0.2 - absf(z) * 0.4
				tube(st, [Vector3(0, y, z), Vector3(0, y + 0.14, z + 0.03)], [0.06, 0.005], [Color(1.0, 0.75, 0.2), Color(1.0, 0.9, 0.4)], 6)
			for sd in [-1.0, 1.0]:
				ball(st, Vector3(0.14 * sd, 0.1, -0.28), 0.06, Color(1, 1, 1), 1.0, 8, 4)
				ball(st, Vector3(0.14 * sd, 0.1, -0.33), 0.03, Color(0.05, 0.05, 0.05), 1.0, 6, 3)
		"crown":
			var gold := Color(1.0, 0.8, 0.2)
			tube(st, [Vector3(0, -0.02, 0), Vector3(0, 0.1, 0)], [0.2, 0.22], [gold.darkened(0.2), gold], 16)
			for k in 6:
				var a := TAU * k / 6.0
				var o := Vector3(cos(a), 0, sin(a)) * 0.21
				tube(st, [o + Vector3(0, 0.09, 0), o + Vector3(0, 0.24, 0)], [0.05, 0.005], [gold, gold.lightened(0.3)], 6)
				ball(st, o + Vector3(0, 0.05, 0), 0.03, [Color(1, 0.2, 0.3), Color(0.3, 0.5, 1)][k % 2], 1.0, 6, 3)
		"halo":
			var y := Color(1.0, 0.95, 0.6)
			for k in 20:
				var a0 := TAU * k / 20.0
				var a1 := TAU * (k + 1) / 20.0
				tube(st, [Vector3(cos(a0) * 0.22, 0.2, sin(a0) * 0.22), Vector3(cos(a1) * 0.22, 0.2, sin(a1) * 0.22)], [0.025, 0.025], [y, y], 6)
			return finish(st, _unshaded())
		"beanie":
			var c := Color(0.95, 0.45, 0.2)
			ball(st, Vector3(0, -0.04, 0), 0.3, c, 0.75, 14, 7)
			tube(st, [Vector3(0, -0.1, 0), Vector3(0, -0.02, 0)], [0.31, 0.3], [c.lightened(0.3), c.lightened(0.3)], 14)
			ball(st, Vector3(0, 0.22, 0), 0.08, Color(1, 1, 1), 1.0, 8, 4)
		_:
			return null
	return finish(st, _smooth_mat())


## Face accessories, in head space (head centre at y 0.34).
static func face_gear(id: String) -> ArrayMesh:
	if id == "" or id == "none":
		return null
	var st := _smooth()
	match id:
		"glasses":
			var c := Color(0.2, 0.15, 0.1)
			for sd in [-1.0, 1.0]:
				for k in 12:
					var a0 := TAU * k / 12.0
					var a1 := TAU * (k + 1) / 12.0
					var o := Vector3(0.13 * sd, 0.36, -0.37)
					tube(st, [o + Vector3(cos(a0), sin(a0), 0) * 0.085, o + Vector3(cos(a1), sin(a1), 0) * 0.085], [0.012, 0.012], [c, c], 4)
			tube(st, [Vector3(-0.045, 0.37, -0.38), Vector3(0.045, 0.37, -0.38)], [0.01, 0.01], [c, c], 4)
		"shades":
			var c := Color(0.05, 0.05, 0.07)
			box(st, Vector3(-0.24, 0.32, -0.4), Vector3(0.24, 0.42, -0.36), c)
			box(st, Vector3(-0.25, 0.39, -0.37), Vector3(0.25, 0.42, 0.05), c)
		"mustache":
			var c := Color(0.3, 0.18, 0.1)
			for sd in [-1.0, 1.0]:
				tube(st, [Vector3(0, 0.28, -0.37), Vector3(0.07 * sd, 0.275, -0.37), Vector3(0.13 * sd, 0.3, -0.34)], [0.03, 0.03, 0.01], [c, c, c], 6)
		"mask":
			var c := Color(0.95, 0.95, 0.95)
			ball(st, Vector3(0, 0.24, -0.3), 0.14, c, 0.7, 12, 6)
		_:
			return null
	return finish(st, _smooth_mat())


# ---------------------------------------------------------------- loot

static func _glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(1, 0.95, 0.8)
	m.emission_energy_multiplier = 0.12
	return m


static func loot(id: String) -> ArrayMesh:
	var st := _smooth()
	match id:
		"arthro_egg", "scuto_egg", "dicy_egg", "trike_egg":
			var base := {"arthro_egg": Color(0.75, 0.68, 0.5), "scuto_egg": Color(0.92, 0.88, 0.78), "dicy_egg": Color(0.8, 0.72, 0.62),
				"trike_egg": Color(0.55, 0.62, 0.66)}[id] as Color
			var size := {"arthro_egg": 0.16, "scuto_egg": 0.2, "dicy_egg": 0.13, "trike_egg": 0.21}[id] as float
			ball(st, Vector3(0, size * 1.3, 0), size, base, 1.3, 12, 8, base.lightened(0.15))
			var r := RandomNumberGenerator.new()
			r.seed = id.hash()
			for k in 10:
				var a := r.randf() * TAU
				var y := r.randf_range(0.4, 2.0) * size
				var rr := sqrt(maxf(0.0, 1.0 - pow((y - size * 1.3) / (size * 1.3), 2.0))) * size
				ball(st, Vector3(cos(a) * rr, y, sin(a) * rr), size * 0.12, base.darkened(0.45), 0.6, 6, 3)
		"eryops_spawn":
			var r := RandomNumberGenerator.new()
			r.seed = 7
			for k in 14:
				var p := Vector3(r.randf_range(-0.14, 0.14), r.randf_range(0.04, 0.16), r.randf_range(-0.14, 0.14))
				ball(st, p, 0.05, Color(0.55, 0.8, 0.45), 1.0, 8, 4)
				ball(st, p + Vector3(0, 0, -0.02), 0.015, Color(0.05, 0.08, 0.05), 1.0, 5, 3)
		"amber":
			octa(st, Vector3(0, 0.12, 0), 0.12, Color(1.0, 0.6, 0.12))
			octa(st, Vector3(0.05, 0.1, 0.02), 0.07, Color(0.95, 0.5, 0.1))
			octa(st, Vector3(0, 0.12, -0.02), 0.025, Color(0.1, 0.07, 0.03))
		"wing":
			var c := Color(0.8, 0.85, 0.9)
			var pts := [Vector3(0, 0.03, -0.02), Vector3(0.12, 0.03, -0.05), Vector3(0.34, 0.03, -0.04), Vector3(0.42, 0.03, 0.0),
				Vector3(0.34, 0.03, 0.04), Vector3(0.12, 0.03, 0.05), Vector3(0, 0.03, 0.02)]
			for k in range(1, pts.size() - 1):
				tri(st, pts[0], pts[k], pts[k + 1], c)
			tube(st, [Vector3(0, 0.035, 0), Vector3(0.4, 0.035, 0)], [0.006, 0.003], [Color(0.2, 0.2, 0.2), Color(0.2, 0.2, 0.2)], 3)
		"cone":
			var c := Color(0.45, 0.32, 0.18)
			tube(st, [Vector3(0, 0.02, 0), Vector3(0, 0.12, 0), Vector3(0, 0.28, 0)], [0.07, 0.08, 0.02], [c.darkened(0.2), c, c.lightened(0.1)], 8, true)
		"rex_tooth":
			var c := Color(0.92, 0.86, 0.7)
			tube(st, [Vector3(0, 0.02, 0), Vector3(0.03, 0.2, 0), Vector3(0.12, 0.42, 0)], [0.07, 0.05, 0.004], [Color(0.55, 0.4, 0.3), c, c.lightened(0.1)], 9)
		"feather":
			var c := Color(0.75, 0.32, 0.12)
			tube(st, [Vector3(0, 0.02, 0.18), Vector3(0, 0.03, -0.2)], [0.008, 0.003], [Color(0.9, 0.85, 0.7), Color(0.9, 0.85, 0.7)], 4)
			for k in 8:
				var z := 0.14 - k * 0.045
				for sd in [-1.0, 1.0]:
					tri(st, Vector3(0, 0.03, z), Vector3(0, 0.03, z - 0.05), Vector3(0.07 * sd * (1.0 - absf(k - 3.5) / 5.0), 0.035, z - 0.01), c if k % 2 == 0 else Color(0.2, 0.15, 0.12))
		"ammonite":
			var c := Color(0.75, 0.65, 0.5)
			for k in 26:
				var a0 := k * 0.45
				var a1 := (k + 1) * 0.45
				var r0 := 0.03 + a0 * 0.012
				var r1 := 0.03 + a1 * 0.012
				tube(st, [Vector3(cos(a0) * r0, 0.08, sin(a0) * r0), Vector3(cos(a1) * r1, 0.08, sin(a1) * r1)], [r0 * 0.45, r1 * 0.45],
					[c.lerp(Color(0.95, 0.8, 0.6), float(k % 2)), c.lerp(Color(0.95, 0.8, 0.6), float((k + 1) % 2))], 6)
		"flower":
			tube(st, [Vector3(0, 0, 0), Vector3(0, 0.25, 0)], [0.012, 0.01], [Color(0.25, 0.45, 0.2), Color(0.25, 0.45, 0.2)], 4)
			for k in 6:
				var a := TAU * k / 6.0
				ball(st, Vector3(cos(a) * 0.06, 0.27, sin(a) * 0.06), 0.05, Color(1.0, 0.78, 0.88), 0.4, 6, 3)
			ball(st, Vector3(0, 0.28, 0), 0.03, Color(1.0, 0.9, 0.4), 1.0, 6, 3)
		"chrono_core":
			var brass := Color(0.85, 0.66, 0.3)
			tube(st, [Vector3(0, 0.0, 0), Vector3(0, 0.06, 0)], [0.2, 0.2], [brass.darkened(0.3), brass], 12)
			tube(st, [Vector3(0, 0.42, 0), Vector3(0, 0.48, 0)], [0.2, 0.2], [brass, brass.lightened(0.1)], 12)
			for k in 4:
				var a := TAU * k / 4.0
				tube(st, [Vector3(cos(a) * 0.17, 0.05, sin(a) * 0.17), Vector3(cos(a) * 0.17, 0.43, sin(a) * 0.17)], [0.02, 0.02], [brass, brass], 5)
			ball(st, Vector3(0, 0.25, 0), 0.13, Color(0.4, 0.95, 1.0), 1.3, 12, 6, Color(0.8, 0.5, 1.0))
		"lost_tape":
			box(st, Vector3(-0.16, 0.0, -0.1), Vector3(0.16, 0.05, 0.1), Color(0.08, 0.08, 0.09))
			box(st, Vector3(-0.12, 0.051, -0.06), Vector3(0.12, 0.055, 0.03), Color(0.95, 0.92, 0.8))
			for sd in [-1.0, 1.0]:
				tube(st, [Vector3(0.06 * sd, 0.05, 0.05), Vector3(0.06 * sd, 0.056, 0.05)], [0.03, 0.03], [Color(0.3, 0.25, 0.2), Color(0.3, 0.25, 0.2)], 8)
		"badge":
			tube(st, [Vector3(0, 0.0, 0), Vector3(0, 0.03, 0)], [0.1, 0.1], [Color(0.75, 0.6, 0.25), Color(0.95, 0.8, 0.35)], 12)
			ball(st, Vector3(0, 0.035, 0), 0.05, Color(0.3, 0.8, 0.95), 0.2, 8, 3)
		"tooth":
			var c := Color(0.95, 0.92, 0.82)
			tube(st, [Vector3(0, 0.02, 0), Vector3(0.02, 0.14, 0), Vector3(0.07, 0.3, 0)], [0.05, 0.035, 0.004], [c.darkened(0.2), c, c], 8)
		"leaf":
			box(st, Vector3(-0.14, 0.0, -0.1), Vector3(0.14, 0.05, 0.1), Color(0.55, 0.5, 0.45))
			var g := Color(0.3, 0.3, 0.2)
			for k in 3:
				tri(st, Vector3(-0.08 + k * 0.06, 0.055, 0.07), Vector3(-0.1 + k * 0.06, 0.055, -0.06), Vector3(-0.05 + k * 0.06, 0.055, -0.07), g)
		_:
			ball(st, Vector3(0, 0.1, 0), 0.1, Color(1, 0, 1))
	return finish(st, _glow_mat())


# ---------------------------------------------------------------- the Chrono Hub

## The station deck: a disc of tiles with glowing seams and a rail.
static func hub_deck(radius: float) -> ArrayMesh:
	var st := _smooth()
	var rings := 6
	var seg := 48
	for r in rings:
		var r0 := radius * r / rings
		var r1 := radius * (r + 1) / rings
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var c := Color(0.42, 0.45, 0.66) if (r + k / 6) % 2 == 0 else Color(0.5, 0.53, 0.76)
			if r == 1:
				c = Color(0.6, 0.45, 0.8)
			quad(st, Vector3(cos(a0) * r1, 0, sin(a0) * r1), Vector3(cos(a1) * r1, 0, sin(a1) * r1),
				Vector3(cos(a1) * r0, 0, sin(a1) * r0), Vector3(cos(a0) * r0, 0, sin(a0) * r0), c, c)
	# underside and the rim
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var c := Color(0.12, 0.12, 0.2)
		quad(st, Vector3(cos(a0), 0, sin(a0)) * radius, Vector3(cos(a1), 0, sin(a1)) * radius,
			Vector3(cos(a1) * radius * 0.6, -3.0, sin(a1) * radius * 0.6), Vector3(cos(a0) * radius * 0.6, -3.0, sin(a0) * radius * 0.6), c, c.darkened(0.5))
		# rail posts
		if k % 3 == 0:
			var p := Vector3(cos(a0), 0, sin(a0)) * (radius - 0.2)
			tube(st, [p, p + Vector3(0, 1.0, 0)], [0.04, 0.04], [Color(0.7, 0.72, 0.85), Color(0.7, 0.72, 0.85)], 6)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var c := Color(0.75, 0.78, 0.95)
		tube(st, [Vector3(cos(a0), 0, sin(a0)) * (radius - 0.2) + Vector3(0, 1.0, 0), Vector3(cos(a1), 0, sin(a1)) * (radius - 0.2) + Vector3(0, 1.0, 0)], [0.05, 0.05], [c, c], 6)
	return finish(st, _smooth_mat())


## Glowing seams on the deck, unshaded so they read as light.
static func hub_lines(radius: float) -> ArrayMesh:
	var st := _smooth()
	var seg := 64
	for rr in [radius * 2.0 / 6.0, radius * 4.0 / 6.0, radius - 0.5]:
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var c := Color(0.4, 0.95, 1.0)
			var w := 0.05
			quad(st, Vector3(cos(a0) * (rr - w), 0.01, sin(a0) * (rr - w)), Vector3(cos(a1) * (rr - w), 0.01, sin(a1) * (rr - w)),
				Vector3(cos(a1) * (rr + w), 0.01, sin(a1) * (rr + w)), Vector3(cos(a0) * (rr + w), 0.01, sin(a0) * (rr + w)), c, c)
	return finish(st, _unshaded())


## The time ring: a big upright torus of alternating segments.
static func time_ring(radius: float, thick: float) -> ArrayMesh:
	var st := _smooth()
	var seg := 36
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var c := Color(0.85, 0.75, 0.35) if k % 3 == 0 else Color(0.55, 0.58, 0.72)
		tube(st, [Vector3(cos(a0) * radius, sin(a0) * radius, 0), Vector3(cos(a1) * radius, sin(a1) * radius, 0)], [thick, thick], [c, c], 8)
	# clock marks
	for k in 12:
		var a := TAU * k / 12.0
		ball(st, Vector3(cos(a), sin(a), 0) * radius + Vector3(0, 0, -thick), thick * 0.5, Color(0.4, 0.95, 1.0), 1.0, 8, 4)
	return finish(st, _smooth_mat())


static func console_mesh() -> ArrayMesh:
	var st := _smooth()
	var c := Color(0.35, 0.38, 0.55)
	tube(st, [Vector3(0, 0, 0), Vector3(0, 0.9, 0)], [0.45, 0.3], [c.darkened(0.2), c], 12)
	box(st, Vector3(-0.6, 0.9, -0.35), Vector3(0.6, 1.0, 0.35), c.lightened(0.1))
	for k in 5:
		ball(st, Vector3(-0.4 + k * 0.2, 1.02, 0.2), 0.04, [Color(1, 0.3, 0.3), Color(1, 0.8, 0.2), Color(0.3, 1, 0.4), Color(0.3, 0.7, 1), Color(0.9, 0.4, 1)][k], 1.0, 8, 4)
	return finish(st, _smooth_mat())


static func kiosk_mesh() -> ArrayMesh:
	var st := _smooth()
	var wood := Color(0.55, 0.38, 0.28)
	box(st, Vector3(-1.2, 0, -0.5), Vector3(1.2, 1.0, 0.5), wood)
	box(st, Vector3(-1.25, 1.0, -0.55), Vector3(1.25, 1.08, 0.55), wood.lightened(0.2))
	for sd in [-1.0, 1.0]:
		tube(st, [Vector3(1.15 * sd, 1.0, 0.4), Vector3(1.15 * sd, 2.6, 0.4)], [0.05, 0.05], [Color(0.8, 0.8, 0.85), Color(0.8, 0.8, 0.85)], 6)
	# striped awning
	for k in 8:
		var x0 := -1.35 + k * 0.3375
		var c := Color(1.0, 0.45, 0.6) if k % 2 == 0 else Color(1, 1, 1)
		quad(st, Vector3(x0, 2.6, 0.5), Vector3(x0 + 0.3375, 2.6, 0.5), Vector3(x0 + 0.3375, 2.3, -0.7), Vector3(x0, 2.3, -0.7), c, c)
	return finish(st, _smooth_mat())


# ---------------------------------------------------------------- hub dressing

static func bench() -> ArrayMesh:
	var st := _smooth()
	var wood := Color(0.72, 0.5, 0.36)
	var iron := Color(0.35, 0.36, 0.5)
	for k in 4:
		box(st, Vector3(-1.0, 0.42 + 0.0, -0.25 + k * 0.13), Vector3(1.0, 0.47, -0.15 + k * 0.13), wood.lightened(0.05 * (k % 2)))
	for k in 3:
		box(st, Vector3(-1.0, 0.6 + k * 0.13, 0.26), Vector3(1.0, 0.7 + k * 0.13, 0.3), wood)
	for sd in [-1.0, 1.0]:
		box(st, Vector3(0.85 * sd - 0.04, 0.0, -0.25), Vector3(0.85 * sd + 0.04, 0.45, -0.18), iron)
		box(st, Vector3(0.85 * sd - 0.04, 0.0, 0.2), Vector3(0.85 * sd + 0.04, 1.0, 0.27), iron)
	return finish(st, _smooth_mat())


static func lamp_post() -> ArrayMesh:
	var st := _smooth()
	var iron := Color(0.3, 0.3, 0.45)
	tube(st, [Vector3(0, 0, 0), Vector3(0, 0.15, 0)], [0.18, 0.14], [iron, iron], 10)
	tube(st, [Vector3(0, 0.15, 0), Vector3(0, 2.6, 0)], [0.06, 0.05], [iron, iron.lightened(0.1)], 8)
	tube(st, [Vector3(0, 2.6, 0), Vector3(0, 2.75, 0)], [0.14, 0.1], [iron, iron], 8)
	tube(st, [Vector3(0, 3.1, 0), Vector3(0, 3.2, 0)], [0.16, 0.02], [iron, iron], 8)
	return finish(st, _smooth_mat())


static func lamp_globe() -> ArrayMesh:
	var st := _smooth()
	ball(st, Vector3(0, 2.93, 0), 0.2, Color(1.0, 0.85, 0.55), 1.0, 12, 6)
	return finish(st, _unshaded())


## A round raised bed with a little prehistoric garden in it.
static func planter(rng: RandomNumberGenerator, r: float) -> ArrayMesh:
	var st := _smooth()
	var stone := Color(0.62, 0.58, 0.78)
	var n := 24
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		quad(st, o0 * r, o1 * r, o1 * r + Vector3(0, 0.5, 0), o0 * r + Vector3(0, 0.5, 0), stone.darkened(0.1), stone)
		quad(st, o0 * r + Vector3(0, 0.5, 0), o1 * r + Vector3(0, 0.5, 0), o1 * (r - 0.25) + Vector3(0, 0.5, 0), o0 * (r - 0.25) + Vector3(0, 0.5, 0), stone.lightened(0.1), stone.lightened(0.1))
		var soil := Color(0.3, 0.22, 0.2)
		tri(st, Vector3(0, 0.45, 0), o0 * (r - 0.25) + Vector3(0, 0.45, 0), o1 * (r - 0.25) + Vector3(0, 0.45, 0), soil)
	var veg := finish(st, _smooth_mat())
	return veg


static func flowers(rng: RandomNumberGenerator, r: float, count: int) -> ArrayMesh:
	var st := _smooth()
	var cols := [Color(1.0, 0.5, 0.8), Color(0.5, 0.9, 1.0), Color(1.0, 0.9, 0.4), Color(0.8, 0.6, 1.0)]
	for k in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * (r - 0.4)
		var p := Vector3(cos(a) * d, 0.45, sin(a) * d)
		var h := rng.randf_range(0.2, 0.5)
		tube(st, [p, p + Vector3(0, h, 0)], [0.015, 0.012], [Color(0.3, 0.6, 0.3), Color(0.3, 0.6, 0.3)], 4)
		ball(st, p + Vector3(0, h, 0), rng.randf_range(0.05, 0.09), cols[k % cols.size()], 0.7, 8, 4)
	return finish(st, _unshaded())


static func pedestal() -> ArrayMesh:
	var st := _smooth()
	var c := Color(0.85, 0.83, 0.95)
	tube(st, [Vector3(0, 0, 0), Vector3(0, 0.1, 0)], [0.45, 0.42], [c.darkened(0.2), c], 12)
	tube(st, [Vector3(0, 0.1, 0), Vector3(0, 0.95, 0)], [0.3, 0.3], [c, c], 12)
	tube(st, [Vector3(0, 0.95, 0), Vector3(0, 1.05, 0)], [0.42, 0.42], [c.lightened(0.1), c.lightened(0.1)], 12)
	ball(st, Vector3(0, 1.05, 0), 0.42, c.lightened(0.1), 0.001, 12, 2)
	box(st, Vector3(-0.2, 0.55, -0.32), Vector3(0.2, 0.75, -0.3), Color(1.0, 0.85, 0.4))
	return finish(st, _smooth_mat())


static func glass_dome() -> ArrayMesh:
	var st := _smooth()
	var pts := []
	var rad := []
	var cols := []
	for i in 7:
		var t := i / 6.0
		pts.append(Vector3(0, 1.05 + t * 0.55, 0))
		rad.append(0.36 * sqrt(maxf(0.0, 1.0 - pow(t, 3.0))) + 0.001)
		cols.append(Color(0.8, 0.95, 1.0, 0.22))
	tube(st, pts, rad, cols, 14)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return finish(st, m)


## A giant hourglass: a brass frame, glass bulbs, glowing sand.
static func hourglass() -> Dictionary:
	var st := _smooth()
	var brass := Color(0.9, 0.7, 0.35)
	for y in [0.0, 3.6]:
		tube(st, [Vector3(0, y, 0), Vector3(0, y + 0.25, 0)], [1.1, 1.1], [brass.darkened(0.2), brass], 16)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var o := Vector3(cos(a), 0, sin(a)) * 0.95
		tube(st, [o + Vector3(0, 0.25, 0), o + Vector3(0, 3.6, 0)], [0.07, 0.07], [brass, brass], 8)
	var frame := finish(st, _smooth_mat())
	st = _smooth()
	var pts := []
	var rad := []
	var cols := []
	for i in 13:
		var t := i / 12.0
		pts.append(Vector3(0, 0.25 + t * 3.35, 0))
		rad.append(0.08 + 0.72 * pow(absf(t - 0.5) * 2.0, 0.7))
		cols.append(Color(0.85, 0.95, 1.0, 0.18))
	tube(st, pts, rad, cols, 16)
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.05
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := finish(st, gm)
	st = _smooth()
	var sand := Color(0.55, 0.9, 1.0)
	ball(st, Vector3(0, 0.55, 0), 0.62, sand, 0.45, 14, 6)
	ball(st, Vector3(0, 2.75, 0), 0.5, sand, 0.5, 14, 6)
	tube(st, [Vector3(0, 1.0, 0), Vector3(0, 2.3, 0)], [0.03, 0.03], [sand, sand], 6)
	return {"frame": frame, "glass": glass, "sand": finish(st, _unshaded())}


## A ringed planet for the sky.
static func planet() -> ArrayMesh:
	var st := _smooth()
	ball(st, Vector3.ZERO, 1.0, Color(1.0, 0.62, 0.55), 1.0, 20, 12, Color(0.75, 0.45, 0.85))
	var n := 48
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var c := Color(1.0, 0.9, 0.7, 1.0) if k % 2 == 0 else Color(0.95, 0.8, 0.95)
		quad(st, Vector3(cos(a0), 0, sin(a0)) * 1.4, Vector3(cos(a1), 0, sin(a1)) * 1.4,
			Vector3(cos(a1), 0, sin(a1)) * 2.0, Vector3(cos(a0), 0, sin(a0)) * 2.0, c, c)
	var m := _unshaded()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return finish(st, m)


# ---------------------------------------------------------------- the Cretaceous

## Eyes that catch your lamp and read through fog: the thing you see first.
static func eye_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.disable_fog = true
	return m


static func _skin() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A theropod, forward -Z, hips at the origin. Returns meshes for the body,
## the lower jaw (hinged at `jaw_at`), one leg (hanging from the hip), and
## the eyes, plus where the parts go. `o` holds the look:
##   len (tail tip to snout), head (skull size), feathers (bool),
##   back, belly, stripe (colours), eye (colour)
static func theropod(o: Dictionary) -> Dictionary:
	var L: float = o.len
	var hs: float = o.head
	var back: Color = o.back
	var belly: Color = o.belly
	var stripe: Color = o.stripe
	var h := L * 0.26  # hip height
	var st := _smooth()
	# spine: tail tip -> hips -> chest -> neck -> skull
	var spine := [
		Vector3(0, h * 0.9, L * 0.55), Vector3(0, h * 1.0, L * 0.4), Vector3(0, h * 1.05, L * 0.22),
		Vector3(0, h * 1.05, L * 0.05), Vector3(0, h * 1.02, -L * 0.1), Vector3(0, h * 1.05, -L * 0.2),
		Vector3(0, h * 1.25, -L * 0.28), Vector3(0, h * 1.45, -L * 0.32)]
	var bulk: float = o.get("bulk", 1.0)
	var rad := [0.01, L * 0.03 * bulk, L * 0.05 * bulk, L * 0.075 * bulk, L * 0.08 * bulk, L * 0.07 * bulk, L * 0.045 * (1.0 + hs) * bulk, L * 0.05 * (1.0 + hs)]
	var cols := []
	for i in spine.size():
		cols.append(stripe if i < 4 and i % 2 == 1 else back)
	tube(st, spine, rad, cols, 12, false, 0.95)
	# belly, lighter, slung under the ribcage
	tube(st, [Vector3(0, h * 0.9, L * 0.08), Vector3(0, h * 0.82, -L * 0.08), Vector3(0, h * 0.95, -L * 0.2)],
		[L * 0.055 * bulk, L * 0.065 * bulk, L * 0.04 * bulk], [belly, belly, belly], 10)
	# skull and upper jaw
	var sk: Vector3 = spine[spine.size() - 1]
	var snout := sk + Vector3(0, -L * 0.01, -L * 0.13 * (0.8 + hs))
	tube(st, [sk + Vector3(0, 0, L * 0.02), sk + Vector3(0, L * 0.01, -L * 0.04), snout],
		[L * 0.055 * (1.0 + hs), L * 0.05 * (1.0 + hs), L * 0.02 * (1.0 + hs)], [back, back.lightened(0.05), back.darkened(0.1)], 10, false, 1.1)
	var tooth := Color(0.95, 0.92, 0.82)
	for k in 6:
		var z := lerpf(-L * 0.05, -L * 0.12, k / 5.0) * (0.8 + hs)
		for sd in [-1.0, 1.0]:
			tube(st, [sk + Vector3(L * 0.03 * sd * (1.0 + hs) * 0.8, -L * 0.03 * (1.0 + hs), z), sk + Vector3(L * 0.03 * sd * (1.0 + hs) * 0.8, -L * 0.055 * (1.0 + hs), z)],
				[L * 0.006, 0.0005], [tooth, tooth], 4)
	# arms, folded; feathered on the raptor
	for sd in [-1.0, 1.0]:
		var sh := Vector3(L * 0.05 * sd, h * 1.0, -L * 0.17)
		var el := sh + Vector3(L * 0.03 * sd, -L * 0.06, L * 0.02)
		var wr := el + Vector3(0, -L * 0.01, -L * 0.07 * (0.35 if not o.feathers else 1.0))
		tube(st, [sh, el, wr], [L * 0.018, L * 0.012, L * 0.008], [back, back, back.darkened(0.2)], 6)
		if o.feathers:
			for k in 7:
				var at: Vector3 = el.lerp(wr, k / 6.0)
				_blade(st, at, Vector3(0.3 * sd, -1.0, 0.25).normalized(), L * 0.07, L * 0.012, 0.0, stripe if k % 2 == 0 else back.darkened(0.2))
	# feathers down the neck and back, a fan at the tail
	if o.feathers:
		for i in range(1, spine.size() - 1):
			var p: Vector3 = spine[i]
			for k in 3:
				var d := Vector3(randf_range(-0.4, 0.4), 1.0, 0.6).normalized()
				_blade(st, p + Vector3(0, float(rad[i]) * 0.8, 0), d, L * 0.05, L * 0.01, L * 0.01, back.lightened(0.1) if k == 1 else stripe)
		var tip: Vector3 = spine[0]
		for k in 9:
			var a := (k - 4) * 0.22
			_blade(st, tip + Vector3(0, 0, -L * 0.08), Vector3(sin(a), 0.1, 1.0).normalized(), L * 0.12, L * 0.015, 0.0, stripe if k % 2 == 0 else back)
	var body := finish(st, _skin())
	# lower jaw, hinged under the skull
	st = _smooth()
	var jaw_at := sk + Vector3(0, -L * 0.035 * (1.0 + hs), L * 0.01)
	tube(st, [Vector3.ZERO, Vector3(0, -L * 0.005, -L * 0.07 * (0.8 + hs)), Vector3(0, L * 0.005, -L * 0.12 * (0.8 + hs))],
		[L * 0.035 * (1.0 + hs), L * 0.03 * (1.0 + hs), L * 0.012 * (1.0 + hs)], [belly, belly, belly.darkened(0.1)], 8, false, 0.6)
	for k in 5:
		var z := lerpf(-L * 0.03, -L * 0.1, k / 4.0) * (0.8 + hs)
		for sd in [-1.0, 1.0]:
			tube(st, [Vector3(L * 0.022 * sd * (1.0 + hs), L * 0.005, z), Vector3(L * 0.022 * sd * (1.0 + hs), L * 0.03 * (1.0 + hs), z)], [L * 0.005, 0.0005], [tooth, tooth], 4)
	var jaw := finish(st, _skin())
	# one leg: thigh, shin, foot; the raptor's killing claw held up
	st = _smooth()
	var knee := Vector3(0, -h * 0.45, -L * 0.04)
	var ankle := Vector3(0, -h * 0.8, L * 0.05)
	var foot := Vector3(0, -h, -L * 0.02)
	tube(st, [Vector3(0, 0.02, 0), knee, ankle, foot], [L * 0.05 * bulk, L * 0.03 * bulk, L * 0.018 * bulk, L * 0.015 * bulk], [back, back.darkened(0.1), back.darkened(0.2), back.darkened(0.3)], 9)
	for k in 3:
		tube(st, [foot, foot + Vector3((k - 1) * L * 0.02, 0, -L * 0.06)], [L * 0.012, L * 0.003], [back.darkened(0.3), Color(0.15, 0.12, 0.1)], 5)
	if o.feathers:
		var claw := foot + Vector3(L * 0.012, L * 0.02, -L * 0.01)
		tube(st, [claw, claw + Vector3(0, L * 0.04, -L * 0.03), claw + Vector3(0, L * 0.02, -L * 0.055)], [L * 0.008, L * 0.005, 0.0005],
			[Color(0.2, 0.18, 0.15), Color(0.2, 0.18, 0.15), Color(0.85, 0.82, 0.75)], 5)
	var leg := finish(st, _skin())
	# eyes, glowing
	st = _smooth()
	for sd in [-1.0, 1.0]:
		ball(st, sk + Vector3(L * 0.04 * sd * (1.0 + hs), L * 0.02 * (1.0 + hs), -L * 0.02), L * 0.011 * (1.0 + hs * 0.5), Color.WHITE, 1.0, 8, 5)
	var eyes := finish(st, eye_mat(o.eye))
	return {"body": body, "jaw": jaw, "jaw_at": jaw_at, "leg": leg, "eyes": eyes, "hip": h, "head_at": snout}


static func raptor() -> Dictionary:
	return theropod({"len": 4.2, "head": 0.3, "feathers": true, "back": Color(0.18, 0.15, 0.13),
		"belly": Color(0.62, 0.5, 0.36), "stripe": Color(0.75, 0.32, 0.12), "eye": Color(1.0, 0.8, 0.2)})


static func rex() -> Dictionary:
	return theropod({"len": 12.0, "head": 0.55, "feathers": false, "bulk": 1.45, "back": Color(0.3, 0.27, 0.2),
		"belly": Color(0.55, 0.48, 0.38), "stripe": Color(0.22, 0.2, 0.15), "eye": Color(1.0, 0.45, 0.15)})


## Triceratops, sized to share the Grazer rig: three horns, a big frill.
static func triceratops() -> Dictionary:
	var st := _smooth()
	var hide := Color(0.42, 0.38, 0.28)
	var dark := Color(0.28, 0.25, 0.18)
	var pts := [Vector3(0, 0.3, 1.5), Vector3(0, 0.45, 1.05), Vector3(0, 0.62, 0.5), Vector3(0, 0.66, -0.1),
		Vector3(0, 0.58, -0.6), Vector3(0, 0.5, -0.9)]
	tube(st, pts, [0.05, 0.28, 0.55, 0.6, 0.48, 0.3], [dark, hide, hide, hide.lightened(0.05), hide, hide], 12, false, 0.85)
	var hd := Vector3(0, 0.55, -1.05)
	tube(st, [hd, hd + Vector3(0, -0.05, -0.35), hd + Vector3(0, -0.18, -0.6)], [0.28, 0.22, 0.08], [hide, hide, dark], 10, false, 1.1)
	# the frill: a fan of quads behind the head, with a darker rim
	var n := 14
	for k in n:
		var a0 := PI * (0.05 + 0.9 * k / n)
		var a1 := PI * (0.05 + 0.9 * (k + 1) / n)
		var c := hd + Vector3(0, 0.1, 0.1)
		var r := 0.75
		var p0 := c + Vector3(cos(a0) * r, sin(a0) * r, 0.25)
		var p1 := c + Vector3(cos(a1) * r, sin(a1) * r, 0.25)
		tri(st, c, p0, p1, Color(0.62, 0.35, 0.22) if k % 2 == 0 else Color(0.55, 0.3, 0.2))
		ball(st, p0, 0.05, dark, 1.0, 6, 3)
	var horn := Color(0.85, 0.8, 0.68)
	for sd in [-1.0, 1.0]:
		tube(st, [hd + Vector3(0.14 * sd, 0.2, -0.05), hd + Vector3(0.2 * sd, 0.45, -0.55), hd + Vector3(0.18 * sd, 0.5, -0.85)], [0.07, 0.04, 0.005], [horn, horn, horn], 7)
		ball(st, hd + Vector3(0.16 * sd, 0.12, -0.2), 0.035, Color(0.05, 0.04, 0.03), 1.0, 6, 3)
	tube(st, [hd + Vector3(0, -0.05, -0.45), hd + Vector3(0, 0.1, -0.6)], [0.05, 0.005], [horn, horn], 6)
	return {"body": finish(st, _skin()), "leg": _stumpy_leg(dark, 0.82, 0.14)}


## A dawn redwood: a straight trunk under tiers of drooping green.
static func conifer(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(12.0, 20.0)
	var bark := Color(0.35, 0.22, 0.15)
	tube(st, [Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h, 0)], [0.55, 0.35, 0.08], [bark.darkened(0.2), bark, bark], 8, true)
	var tiers := 7
	for k in tiers:
		var t := float(k) / tiers
		var y := lerpf(h * 0.35, h * 0.98, t)
		var r := lerpf(3.2, 0.7, t)
		var n := 9
		for j in n:
			var a := TAU * j / n + k * 0.4
			var c := Color(0.12, 0.26, 0.12).lerp(Color(0.2, 0.34, 0.14), rng.randf())
			frond(st, Vector3(0, y, 0), Vector3(cos(a), 0.15, sin(a)), r, 0.3, c, 0.12, 5)
	return finish(st, veg())


## A cycad: a stubby, scaly trunk with a crown of stiff fronds.
static func cycad(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	var h := rng.randf_range(0.8, 2.2)
	var bark := Color(0.4, 0.3, 0.18)
	tube(st, [Vector3.ZERO, Vector3(0, h, 0)], [0.4, 0.3], [bark.darkened(0.2), bark], 8, true)
	for k in 14:
		var a := TAU * k / 14.0 + rng.randf() * 0.2
		frond(st, Vector3(0, h, 0), Vector3(cos(a), rng.randf_range(0.5, 1.2), sin(a)), rng.randf_range(1.4, 2.0), 0.25, Color(0.2, 0.36, 0.12), 0.1, 6)
	ball(st, Vector3(0, h + 0.1, 0), 0.22, Color(0.8, 0.55, 0.2), 1.3, 8, 4)
	return finish(st, veg())


## The first flowers: a magnolia bush, pink and white.
static func magnolia(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := begin()
	for k in 18:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * rng.randf_range(0.0, 0.9), rng.randf_range(0.4, 1.6), sin(a) * rng.randf_range(0.0, 0.9))
		octa(st, p, rng.randf_range(0.3, 0.5), Color(0.14, 0.3, 0.14).lerp(Color(0.2, 0.38, 0.16), rng.randf()))
	for k in 10:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.9, rng.randf_range(0.8, 1.9), sin(a) * 0.9)
		octa(st, p, 0.14, Color(1.0, 0.8, 0.88) if k % 2 == 0 else Color(0.98, 0.95, 0.9))
	return finish(st, veg())


static func shovel() -> ArrayMesh:
	var st := _smooth()
	var wood := Color(0.55, 0.38, 0.22)
	var steel := Color(0.55, 0.57, 0.6)
	tube(st, [Vector3(0, -0.45, 0), Vector3(0, 0.35, 0)], [0.022, 0.022], [wood, wood.lightened(0.1)], 6)
	box(st, Vector3(-0.07, 0.35, -0.015), Vector3(0.07, 0.38, 0.015), Color(0.2, 0.2, 0.22))
	box(st, Vector3(-0.1, -0.72, -0.012), Vector3(0.1, -0.45, 0.012), steel)
	return finish(st, _smooth_mat())
