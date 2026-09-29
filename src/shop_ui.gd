class_name ShopUI
extends Control
## The hub kiosk: your little time-traveller turning on a pedestal, three
## tabs of things to buy with haul money, click to buy, click again to wear.

signal closed
signal looked

var tab := "suit"
var preview: Avatar
var vp: SubViewport
var grid: GridContainer
var money_label: Label
var msg: Label
var tabs := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	# the mirror
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	root.add_child(left)
	var title := _label("THE KIOSK", 22, Color(1.0, 0.7, 0.85))
	left.add_child(title)
	money_label = _label("", 16, Color(0.6, 1.0, 1.0))
	left.add_child(money_label)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.15, 2.9)
	cam.rotation.x = -0.12
	cam.fov = 40.0
	vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	light.light_energy = 1.2
	vp.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.8, 1.0)
	env.ambient_light_energy = 0.8
	we.environment = env
	vp.add_child(we)
	preview = Avatar.new()
	vp.add_child(preview)
	preview.setup(0, "", Run.look, {}, true)
	msg = _label("", 12, Color(1, 0.85, 0.5))
	left.add_child(msg)
	# the shelves
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	var tabrow := HBoxContainer.new()
	right.add_child(tabrow)
	for k in [["suit", "SUITS"], ["hat", "HATS"], ["face", "FACES"]]:
		var b := Button.new()
		b.text = k[1]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_show_tab.bind(k[0]))
		tabrow.add_child(b)
		tabs[k[0]] = b
	var close := Button.new()
	close.text = "DONE"
	close.add_theme_font_size_override("font_size", 13)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: closed.emit())
	tabrow.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)


func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.modulate = c
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func open() -> void:
	visible = true
	position = Vector2.ZERO
	size = get_viewport_rect().size
	msg.text = ""
	preview.t_yaw = PI
	preview.set_look(Run.look)
	_show_tab(tab)


func _show_tab(k: String) -> void:
	tab = k
	for t in tabs:
		tabs[t].button_pressed = t == k
	money_label.text = Run.cash(Run.money)
	for c in grid.get_children():
		c.queue_free()
	for it in Shop.tab(k):
		var b := Button.new()
		var wearing: bool = Run.look[k] == it.id
		var owned := Run.owns(k, it.id)
		var price := "WEARING" if wearing else ("OWNED" if owned else Run.cash(int(it.cost)))
		b.text = "%s\n%s" % [it.name, price]
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if k == "suit":
			b.add_theme_color_override("font_color", (it.color as Color).lightened(0.2))
		if not owned and Run.money < int(it.cost):
			b.modulate = Color(1, 1, 1, 0.5)
		b.pressed.connect(_pick.bind(k, it.id))
		b.mouse_entered.connect(_try_on.bind(k, it.id))
		b.mouse_exited.connect(func() -> void: preview.set_look(Run.look))
		grid.add_child(b)


## Hovering tries it on in the mirror.
func _try_on(k: String, id: String) -> void:
	var l := Run.look.duplicate()
	l[k] = id
	preview.set_look(l)


func _pick(k: String, id: String) -> void:
	var it := Shop.find(k, id)
	if not Run.owns(k, id):
		if not Run.buy(k, id):
			msg.text = "need %s more" % Run.cash(int(it.cost) - Run.money)
			return
		msg.text = "bought the %s!" % String(it.name).to_lower()
	Run.look[k] = id
	Run.save()
	preview.set_look(Run.look)
	preview.emote(1)
	looked.emit()
	_show_tab(k)


func _process(dt: float) -> void:
	if visible and size != get_viewport_rect().size:
		size = get_viewport_rect().size
	if visible and preview:
		preview.t_yaw += dt * 0.7
		preview.yaw = preview.t_yaw
