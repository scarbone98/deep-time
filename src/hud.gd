class_name Hud
extends CanvasLayer
## Camcorder viewfinder OSD, title/death/win cards, and the tape shader over
## everything (so the text gets chewed up too).

var mat: ShaderMaterial
var rec: ColorRect
var rec_label: Label
var tc: Label
var batt: Label
var date: Label
var tip: Label
var paused_label: Label
var card: ColorRect
var card_title: Label
var card_sub: Label
var card_body: Label
var card_foot: Label
var glitch := 0.0
var dark := 0.0
var static_amt := 0.0
var white := 0.0
var clock := 0.0
var tip_time := 0.0
var tips: Array = []
var touch_mode := false


func _ready() -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	var osd := Control.new()
	osd.set_anchors_preset(Control.PRESET_FULL_RECT)
	osd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(osd)
	rec = ColorRect.new()
	rec.color = Color(0.9, 0.1, 0.08)
	rec.size = Vector2(9, 9)
	rec.position = Vector2(22, 22)
	osd.add_child(rec)
	rec_label = _label(osd, "REC", 14, Vector2(36, 16))
	batt = _label(osd, "", 14, Vector2(0, 16))
	batt.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	batt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	batt.offset_left = -200
	batt.offset_right = -20
	tc = _label(osd, "", 14, Vector2(0, 0))
	tc.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tc.offset_left = 20
	tc.offset_top = -36
	date = _label(osd, "CARBONIFEROUS  -307,000,000", 14, Vector2(0, 0))
	date.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.offset_left = -320
	date.offset_right = -20
	date.offset_top = -36
	tip = _label(osd, "", 14, Vector2.ZERO)
	tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.offset_left = -300
	tip.offset_right = 300
	tip.offset_top = -80
	paused_label = _label(osd, "PAUSE  -  click to keep recording", 16, Vector2.ZERO)
	paused_label.set_anchors_preset(Control.PRESET_CENTER)
	paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_label.offset_left = -300
	paused_label.offset_right = 300
	paused_label.visible = false

	card = ColorRect.new()
	card.color = Color(0.0, 0.0, 0.0, 1.0)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	card_title = _label(box, "", 40, Vector2.ZERO)
	card_sub = _label(box, "", 16, Vector2.ZERO)
	card_body = _label(box, "", 13, Vector2.ZERO)
	card_foot = _label(box, "", 14, Vector2.ZERO)
	for l in [card_title, card_sub, card_body, card_foot]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_sub.modulate = Color(0.9, 0.8, 0.5)
	card_body.modulate = Color(0.7, 0.72, 0.68)

	var vhs := ColorRect.new()
	vhs.set_anchors_preset(Control.PRESET_FULL_RECT)
	vhs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://src/vhs.gdshader")
	vhs.material = mat
	add_child(vhs)


## Phone controls sit under the tape shader, like the rest of the OSD.
func add_touch(pad: Control) -> void:
	add_child(pad)
	move_child(pad, 1)
	touch_mode = true


func _label(parent: Control, text: String, size: int, at: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func show_card(title: String, sub: String, body: String, foot: String, alpha := 1.0) -> void:
	card.visible = true
	card.color.a = alpha
	card_title.text = title
	card_sub.text = sub
	card_body.text = body
	card_foot.text = foot


func hide_card() -> void:
	card.visible = false


func say(lines: Array) -> void:
	tips = lines.duplicate()
	tip_time = 0.0
	tip.text = ""


func set_battery(b: float, on: bool) -> void:
	var bars := int(ceil(b * 4.0))
	batt.text = ("LAMP  " if on else "") + "BATT " + "|".repeat(bars) + ".".repeat(4 - bars)


func _process(dt: float) -> void:
	rec.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	var s := int(clock)
	tc.text = "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] + ":%02d" % (int(clock * 30.0) % 30)
	if touch_mode:  # keep hints clear of the thumbstick
		var vs := get_viewport().get_visible_rect().size
		tip.offset_top = -200.0 if vs.y > vs.x else -130.0
	# tips roll through one by one
	if not tips.is_empty():
		tip_time += dt
		var cur: Array = tips[0]
		tip.text = cur[0]
		tip.modulate.a = clampf(minf(tip_time / 0.5, (float(cur[1]) - tip_time) / 0.8), 0.0, 1.0)
		if tip_time > float(cur[1]):
			tips.pop_front()
			tip_time = 0.0
			tip.text = ""
	mat.set_shader_parameter("glitch", glitch)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("static_amt", static_amt)
	mat.set_shader_parameter("white", white)
