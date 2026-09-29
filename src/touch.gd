class_name TouchPad
extends Control
## Phone controls. Left thumb: a floating stick (drag past the ring to run).
## Right thumb: drag to look. Two toggles: LAMP and CROUCH.

const R := 46.0
const LOOK := 0.006

signal emote(e: int)
signal mic

var player: Player
var coop := false
var emotes_open := false
var move := Vector2.ZERO
var run := false
var crouch := false
var stick_idx := -1
var look_idx := -1
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _buttons() -> Dictionary:
	var s := get_viewport_rect().size
	var b := {
		"lamp": Vector2(s.x - 62, s.y - 190),
		"crouch": Vector2(s.x - 62, s.y - 110),
	}
	if coop:
		b["mic"] = Vector2(s.x - 136, s.y - 110)
		b["emote"] = Vector2(s.x - 136, s.y - 190)
		if emotes_open:
			for k in 4:
				b["e%d" % (k + 1)] = Vector2(s.x - 136, s.y - 190 - 62 * (k + 1))
	return b


func _input(e: InputEvent) -> void:
	if not visible or player == null or not player.control:
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position
		if e.pressed:
			var b := _buttons()
			var hit := ""
			for k in b:
				if p.distance_to(b[k]) < 30.0:
					hit = k
			if hit == "lamp":
				player.toggle_light()
			elif hit == "crouch":
				crouch = not crouch
			elif hit == "mic":
				mic.emit()
			elif hit == "emote":
				emotes_open = not emotes_open
			elif hit.begins_with("e") and hit.length() == 2:
				emote.emit(int(hit.substr(1)))
				emotes_open = false
			elif p.x < get_viewport_rect().size.x * 0.45 and stick_idx == -1:
				stick_idx = e.index
				origin = p
				knob = p
			elif look_idx == -1:
				look_idx = e.index
		else:
			if e.index == stick_idx:
				stick_idx = -1
				move = Vector2.ZERO
				run = false
			elif e.index == look_idx:
				look_idx = -1
		queue_redraw()
	elif e is InputEventScreenDrag:
		if e.index == stick_idx:
			knob = e.position
			var v: Vector2 = knob - origin
			run = v.length() > R * 1.35
			move = v.limit_length(R) / R
			queue_redraw()
		elif e.index == look_idx:
			player.look(e.relative * LOOK)


func _draw() -> void:
	if player == null or not player.control:
		return
	var s := get_viewport_rect().size
	var faint := Color(1, 1, 1, 0.14)
	var mid := Color(1, 1, 1, 0.35)
	if stick_idx == -1:
		draw_arc(Vector2(90, s.y - 110), R, 0, TAU, 32, faint, 2.0)
	else:
		draw_arc(origin, R, 0, TAU, 32, Color(0.9, 0.3, 0.2, 0.5) if run else mid, 2.0)
		draw_arc(origin, R * 1.35, 0, TAU, 32, faint, 1.0)
		draw_circle(origin + (knob - origin).limit_length(R * 1.35), 16.0, mid)
	var b := _buttons()
	_button(b.lamp, "LAMP", player.light.visible)
	_button(b.crouch, "CROUCH", crouch)
	if coop:
		_button(b.mic, "MIC", not Net.voice.muted)
		_button(b.emote, "EMOTE", emotes_open)
		var names := ["WAVE", "POINT", "SCREAM", "FLASH"]
		for k in 4:
			if b.has("e%d" % (k + 1)):
				_button(b["e%d" % (k + 1)], names[k], false)


func _button(at: Vector2, label: String, on: bool) -> void:
	draw_circle(at, 30.0, Color(1, 0.9, 0.55, 0.35) if on else Color(0, 0, 0, 0.3))
	draw_arc(at, 30.0, 0, TAU, 32, Color(1, 1, 1, 0.4), 1.5)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, at + Vector2(-w * 0.5, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
