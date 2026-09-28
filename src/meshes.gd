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
static func tube(st: SurfaceTool, pts: Array, radii: Array, cols: Array, sides: int, pattern := false) -> void:
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
			ring.append(pts[i] + (side * cos(a) + up * sin(a)) * float(radii[i]))
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
