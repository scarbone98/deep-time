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
var shot_label: Label
var focus: Control
var focus_name := ""
var focus_prog := 0.0
var flash := 0.0
var stage_box: HBoxContainer
var menu_box: VBoxContainer
var menu_fields := {}
var status_label: Label
var roster_box: VBoxContainer
var mic_label: Label
var spec_label: Label


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
	roster_box = VBoxContainer.new()
	roster_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	roster_box.offset_left = -220
	roster_box.offset_right = -20
	roster_box.offset_top = 40
	roster_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roster_box.add_theme_constant_override("separation", 0)
	osd.add_child(roster_box)
	mic_label = _label(osd, "", 11, Vector2.ZERO)
	mic_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mic_label.offset_left = 20
	mic_label.offset_top = -54
	spec_label = _label(osd, "", 13, Vector2.ZERO)
	spec_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spec_label.offset_left = -250
	spec_label.offset_right = 250
	spec_label.offset_top = 40
	shot_label = _label(osd, "", 11, Vector2(20, 40))
	shot_label.modulate = Color(1, 1, 1, 0.85)
	focus = Control.new()
	focus.set_anchors_preset(Control.PRESET_FULL_RECT)
	focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus.draw.connect(_draw_focus)
	osd.add_child(focus)
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
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	card.add_child(box)
	card_title = _label(box, "", 34, Vector2.ZERO)
	card_sub = _label(box, "", 16, Vector2.ZERO)
	card_body = _label(box, "", 13, Vector2.ZERO)
	card_foot = _label(box, "", 14, Vector2.ZERO)
	stage_box = HBoxContainer.new()
	stage_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_theme_constant_override("separation", 14)
	box.add_child(stage_box)
	menu_box = VBoxContainer.new()
	menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_box.add_theme_constant_override("separation", 4)
	box.add_child(menu_box)
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


## The level list on the title card. Locked levels show but can't be picked.
func show_stages(stages: Array, pick: Callable) -> void:
	for c in stage_box.get_children():
		c.queue_free()
	if stages.is_empty():
		return
	var head := _label(stage_box, "layers:", 12, Vector2.ZERO)
	head.modulate = Color(1, 1, 1, 0.5)
	for st in stages:
		var b := Button.new()
		b.text = st.label
		b.flat = true
		b.disabled = st.locked
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", Color(1, 0.85, 0.45) if st.current else Color(0.8, 0.8, 0.75))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.38))
		b.pressed.connect(pick.bind(int(st.n)))
		stage_box.add_child(b)


## A little form under the card: buttons, text fields, labels, rows of them.
## Items: {"type": "button"|"edit"|"label"|"status"|"row", ...}.
func show_menu(items: Array) -> void:
	for c in menu_box.get_children():
		c.queue_free()
	menu_fields = {}
	status_label = null
	for it in items:
		menu_box.add_child(_menu_item(it))


func _menu_item(it: Dictionary) -> Control:
	match str(it.type):
		"button":
			var b := Button.new()
			b.text = it.text
			b.add_theme_font_size_override("font_size", 13)
			b.custom_minimum_size = Vector2(170, 0)
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(it.cb)
			return b
		"edit":
			var e := LineEdit.new()
			e.text = it.get("text", "")
			e.placeholder_text = it.get("hint", "")
			e.max_length = 12
			e.alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.add_theme_font_size_override("font_size", 13)
			e.custom_minimum_size = Vector2(it.get("width", 170), 0)
			e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			menu_fields[it.id] = e
			return e
		"row":
			var r := HBoxContainer.new()
			r.alignment = BoxContainer.ALIGNMENT_CENTER
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for sub in it.items:
				r.add_child(_menu_item(sub))
			return r
		"status":
			status_label = Label.new()
			status_label.add_theme_font_size_override("font_size", 12)
			status_label.modulate = Color(1, 0.8, 0.5)
			status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			return status_label
	var l := Label.new()
	l.text = str(it.get("text", ""))
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(0.8, 0.8, 0.75)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func menu_value(id: String) -> String:
	var e: LineEdit = menu_fields.get(id)
	return e.text if e else ""


func status(t: String) -> void:
	if status_label:
		status_label.text = t


func set_roster(lines: Array, mic: String) -> void:
	while roster_box.get_child_count() < lines.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
		roster_box.add_child(l)
	for k in roster_box.get_child_count():
		var l: Label = roster_box.get_child(k)
		l.visible = k < lines.size()
		if l.visible:
			l.text = lines[k][0]
			l.modulate = (lines[k][1] as Color).lightened(0.25)
	mic_label.text = mic


func spec(who: String, touch: bool) -> void:
	spec_label.text = "" if who == "" else "WATCHING %s'S TAPE   -   %s to switch" % [who, "tap" if touch else "click"]


func set_shots(shots: Array) -> void:
	var lines := ["SHOT LIST"]
	for s in shots:
		lines.append(("[x] " if s.done else "[  ] ") + String(s.name))
	shot_label.text = "\n".join(lines)


## Viewfinder brackets while something worth filming is framed.
func _draw_focus() -> void:
	var c := focus.get_rect().size * 0.5
	var col := Color(1, 1, 1, 0.8)
	if flash > 0.0:
		col = Color(0.5, 1.0, 0.5, flash)
	elif focus_name == "":
		return
	var h := 46.0
	var k := 14.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * h, sy * h * 0.75)
			focus.draw_line(p, p - Vector2(sx * k, 0), col, 2.0)
			focus.draw_line(p, p - Vector2(0, sy * k), col, 2.0)
	var font := ThemeDB.fallback_font
	var txt := "GOT IT" if flash > 0.0 else focus_name
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	focus.draw_string(font, c + Vector2(-w * 0.5, h * 0.75 + 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	if flash <= 0.0:
		var bw := 70.0
		focus.draw_rect(Rect2(c + Vector2(-bw * 0.5, h * 0.75 + 24), Vector2(bw, 4)), Color(1, 1, 1, 0.25))
		focus.draw_rect(Rect2(c + Vector2(-bw * 0.5, h * 0.75 + 24), Vector2(bw * focus_prog, 4)), Color(0.9, 0.2, 0.15, 0.9))


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
		tip.offset_top = -290.0 if vs.y > vs.x else -130.0
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
	flash = maxf(0.0, flash - dt)
	focus.queue_redraw()
	mat.set_shader_parameter("glitch", glitch)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("static_amt", static_amt)
	mat.set_shader_parameter("white", white)
