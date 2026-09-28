class_name Exit
extends Node3D
## The way out: a scrap of the Backrooms standing in the swamp. A yellow
## wallpapered wall with a doorway, a patch of damp carpet, a floating piece
## of drop ceiling and one humming fluorescent tube.

const WALL := Color(0.74, 0.66, 0.36)
const WALL2 := Color(0.68, 0.6, 0.31)

var player: Player
var light: OmniLight3D
var panel_mat: StandardMaterial3D
var door_mat: StandardMaterial3D
var glow_mat: StandardMaterial3D
var hum: AudioStreamPlayer3D
var t := 0.0
var flicker := 0.0
var next_flicker := 4.0
var on := false  # dark until the shot list is done


func setup(w: World, s: Dictionary, p: Player) -> void:
	player = p
	position = w.exit_pos
	rotation.y = w.exit_yaw
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var st := Meshes.begin()
	# wall in vertical wallpaper strips, with the doorway cut out
	var x := -2.4
	var k := 0
	while x < 2.39:
		var x1 := x + 0.2
		var c := WALL if k % 2 == 0 else WALL2
		if x1 <= -0.55 or x >= 0.55:
			Meshes.box(st, Vector3(x, 0.12, -0.08), Vector3(x1, 2.9, 0.08), c)
		else:
			Meshes.box(st, Vector3(x, 2.2, -0.08), Vector3(x1, 2.9, 0.08), c)
		x = x1
		k += 1
	var base := Color(0.4, 0.33, 0.18)
	Meshes.box(st, Vector3(-2.4, 0.0, -0.09), Vector3(-0.55, 0.12, 0.09), base)
	Meshes.box(st, Vector3(0.55, 0.0, -0.09), Vector3(2.4, 0.12, 0.09), base)
	# door frame
	var fr := Color(0.55, 0.47, 0.28)
	Meshes.box(st, Vector3(-0.62, 0.0, -0.1), Vector3(-0.55, 2.25, 0.1), fr)
	Meshes.box(st, Vector3(0.55, 0.0, -0.1), Vector3(0.62, 2.25, 0.1), fr)
	Meshes.box(st, Vector3(-0.62, 2.2, -0.1), Vector3(0.62, 2.27, 0.1), fr)
	# carpet, stained
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for gz in 8:
		for gx in 10:
			var c := Color(0.52, 0.46, 0.28).lerp(Color(0.33, 0.29, 0.17), rng.randf() * rng.randf())
			var x0 := -2.5 + gx * 0.5
			var z0 := 0.1 + gz * 0.5
			Meshes.quad(st, Vector3(x0, 0.03, z0), Vector3(x0 + 0.5, 0.03, z0), Vector3(x0 + 0.5, 0.03, z0 + 0.5), Vector3(x0, 0.03, z0 + 0.5), c, c)
	# floating drop ceiling with its T-bar grid
	var tile := Color(0.66, 0.64, 0.52)
	var bar := Color(0.5, 0.48, 0.4)
	Meshes.box(st, Vector3(-2.4, 2.95, 0.1), Vector3(2.4, 3.0, 4.1), tile)
	for i in 9:
		var bx := -2.4 + i * 0.6
		Meshes.box(st, Vector3(bx - 0.02, 2.92, 0.1), Vector3(bx + 0.02, 2.95, 4.1), bar)
	for i in 7:
		var bz := 0.1 + i * 0.6667
		Meshes.box(st, Vector3(-2.4, 2.92, bz - 0.02), Vector3(2.4, 2.95, bz + 0.02), bar)
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.finish(st, mat)
	add_child(mi)

	# the fluorescent tube
	panel_mat = StandardMaterial3D.new()
	panel_mat.albedo_color = Color(1, 0.98, 0.88)
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(1, 0.96, 0.8)
	panel_mat.emission_energy_multiplier = 2.5
	var pm := BoxMesh.new()
	pm.size = Vector3(1.2, 0.04, 0.6)
	pm.material = panel_mat
	var panel := MeshInstance3D.new()
	panel.mesh = pm
	panel.position = Vector3(0, 2.9, 1.9)
	add_child(panel)
	light = OmniLight3D.new()
	light.position = Vector3(0, 2.6, 1.9)
	light.omni_range = 13.0
	light.light_energy = 1.5
	light.light_color = Color(1.0, 0.95, 0.75)
	add_child(light)

	# the doorway: flat yellow light, the next level
	door_mat = StandardMaterial3D.new()
	door_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	door_mat.albedo_color = Color(0.04, 0.035, 0.02)
	var dm := BoxMesh.new()
	dm.size = Vector3(1.1, 2.2, 0.02)
	dm.material = door_mat
	var door := MeshInstance3D.new()
	door.mesh = dm
	door.position = Vector3(0, 1.1, 0)
	add_child(door)

	# a far-off smudge of light in the fog, to be found
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_mat.disable_fog = true
	glow_mat.albedo_texture = gt
	glow_mat.albedo_color = Color(1.0, 0.9, 0.6, 0.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(18, 18)
	qm.material = glow_mat
	var glow := MeshInstance3D.new()
	glow.mesh = qm
	glow.position = Vector3(0, 3.0, 1.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)

	var body := StaticBody3D.new()
	add_child(body)
	for side in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.85, 3.0, 0.2)
		cs.shape = bs
		cs.position = Vector3(side * 1.475, 1.5, 0)
		body.add_child(cs)

	hum = AudioStreamPlayer3D.new()
	hum.stream = s.hum
	hum.unit_size = 4.0
	hum.max_distance = 130.0
	hum.position = panel.position
	add_child(hum)


func begin() -> void:
	if on:
		hum.play()


func activate() -> void:
	on = true
	door_mat.albedo_color = Color(1.0, 0.9, 0.55)
	door_mat.disable_fog = true
	hum.play()


func inside() -> bool:
	var l := to_local(player.global_position)
	return absf(l.x) < 0.5 and absf(l.z) < 0.3


func near_door() -> bool:
	return to_local(player.global_position).length() < 3.0


func _process(dt: float) -> void:
	t += dt
	if not on:
		light.light_energy = 0.0
		panel_mat.emission_energy_multiplier = 0.0
		glow_mat.albedo_color.a = 0.0
		return
	next_flicker -= dt
	if next_flicker <= 0.0:
		flicker = randf_range(0.2, 0.9)
		next_flicker = randf_range(3.0, 11.0)
	var on := 1.0
	if flicker > 0.0:
		flicker -= dt
		on = 1.0 if randf() > 0.45 else randf_range(0.0, 0.25)
	light.light_energy = 1.5 * on
	panel_mat.emission_energy_multiplier = 2.5 * on
	hum.volume_db = 0.0 if on > 0.5 else -8.0
	var d := global_position.distance_to(player.global_position)
	glow_mat.albedo_color.a = clampf((d - 10.0) / 40.0, 0.0, 1.0) * 0.28 * on
