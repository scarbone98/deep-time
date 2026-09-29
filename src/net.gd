extends Node
## Online co-op, server authoritative.
##
## One headless Godot process (`-- server port=N`) hosts every room. Each room
## runs the real game (main.gd in "server" mode) inside its own SubViewport,
## so every room gets its own physics world. Browsers connect over WebSocket
## (wss on Fly), send only their inputs, predict their own movement, and draw
## everything else from 20 Hz snapshots.
##
## All RPCs live on this autoload (/root/Net on both ends), so node paths
## always match. Rooms are in memory only.

signal room_changed
signal status(text: String)
signal level_start
signal snapshot(data: PackedFloat32Array)
signal event(ev: Array)
signal left

const VERSION := 1
const MAX_PLAYERS := 4
const DEFAULT_URL := "wss://deep-time-coop.fly.dev"
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const LOAD_TIMEOUT := 20.0
const CARD_TIME := 7.0
const NAME_MAX := 12
const COLORS := [Color(0.95, 0.72, 0.12), Color(0.86, 0.26, 0.2), Color(0.28, 0.56, 0.92), Color(0.38, 0.8, 0.36)]
const SESSION := preload("res://src/main.gd")

var is_server := false
var dev := {}  # server: its command-line flags

# --- client state
var online := false
var code := ""
var my_id := 0
var host_id := 0
var members := {}  # peer id -> {"name": String, "color": int}
var phase := "lobby"
var level := 1
var seed_ := 0
var player_name := ""
var voice: Voice
var _pending := {}

# --- server state
var rooms := {}  # code -> room Dictionary
var peer_room := {}  # peer id -> code


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	voice = Voice.new()
	add_child(voice)
	status.connect(func(t: String) -> void: print("net: ", t))


static func clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges().to_upper():
		if ch.is_valid_identifier() or ch in "0123456789 -_.":
			out += ch
	return out.substr(0, NAME_MAX).strip_edges()


func server_url(flags: Dictionary) -> String:
	return str(flags.get("server", DEFAULT_URL))


# ============================================================ client side

## Host a new room (code "") or join one.
func join(url: String, pname: String, room_code: String, create: bool) -> void:
	leave(false)
	player_name = clean_name(pname)
	if player_name == "":
		player_name = "CAM %d" % (randi() % 90 + 10)
	_pending = {"code": room_code.to_upper().strip_edges(), "create": create}
	var p := WebSocketMultiplayerPeer.new()
	var err := p.create_client(url)
	if err != OK:
		status.emit("can't reach the server")
		return
	multiplayer.multiplayer_peer = p
	status.emit("connecting...")


func leave(emit := true) -> void:
	var was := online or multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and not is_server:
		multiplayer.multiplayer_peer.close()
	if not is_server:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	members = {}
	code = ""
	phase = "lobby"
	voice.drop_all()
	if was and emit:
		left.emit()


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	print("net: connected as ", my_id)
	c_hello.rpc_id(1, VERSION, player_name, _pending.get("code", ""), _pending.get("create", true))


func _on_failed() -> void:
	status.emit("couldn't connect")
	leave()


func _on_server_gone() -> void:
	status.emit("lost the server")
	leave()


func start_level(lvl: int) -> void:
	c_start.rpc_id(1, lvl)


func loaded() -> void:
	c_loaded.rpc_id(1)


func send_input(a: PackedFloat32Array) -> void:
	c_input.rpc_id(1, a)


func emote(id: int) -> void:
	c_emote.rpc_id(1, id)


func send_signal(to: int, msg: String) -> void:
	c_signal.rpc_id(1, to, msg)


@rpc("authority", "call_remote", "reliable")
func s_error(msg: String) -> void:
	status.emit(msg)
	leave()


@rpc("authority", "call_remote", "reliable")
func s_room(room_code: String, host: int, mem: Dictionary, ph: String, lvl: int) -> void:
	var fresh := not online
	online = true
	code = room_code
	host_id = host
	var before := members.keys()
	members = mem
	phase = ph
	level = lvl
	if fresh:
		voice.start(send_signal)
	# voice: the lower id calls, the other answers
	for id in members:
		if id != my_id and not before.has(id):
			voice.add_peer(int(id), my_id < int(id))
	for id in before:
		if not members.has(id):
			voice.drop(int(id))
	room_changed.emit()


@rpc("authority", "call_remote", "reliable")
func s_level(lvl: int, sd: int, mem: Dictionary) -> void:
	level = lvl
	seed_ = sd
	members = mem
	phase = "play"
	level_start.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func s_snap(a: PackedFloat32Array) -> void:
	snapshot.emit(a)


@rpc("authority", "call_remote", "reliable")
func s_event(ev: Array) -> void:
	event.emit(ev)


@rpc("authority", "call_remote", "reliable")
func s_signal(from: int, msg: String) -> void:
	voice.on_signal(from, msg)


# ============================================================ server side

func host_server(port: int, flags := {}) -> void:
	is_server = true
	dev = flags
	var p := WebSocketMultiplayerPeer.new()
	p.inbound_buffer_size = 1 << 17
	p.outbound_buffer_size = 1 << 18
	var err := p.create_server(port)
	if err != OK:
		push_error("couldn't listen on %d (%d)" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = p
	print("DEEP TIME server listening on ", port)


func _new_code() -> String:
	for tries in 100:
		var c := ""
		for k in 4:
			c += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
		if not rooms.has(c):
			return c
	return ""


func _roster(room: Dictionary) -> Dictionary:
	return room.members.duplicate(true)


func _push_room(room: Dictionary) -> void:
	for id in room.members:
		s_room.rpc_id(id, room.code, room.host, _roster(room), room.phase, room.level)


@rpc("any_peer", "call_remote", "reliable")
func c_hello(version: int, pname: String, room_code: String, create: bool) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION:
		s_error.rpc_id(id, "the game updated - reload the page")
		return
	var room: Dictionary
	room_code = room_code.to_upper().strip_edges()
	if create:
		var c := room_code if room_code.length() == 4 and not rooms.has(room_code) else _new_code()
		room = {"code": c, "host": id, "members": {}, "level": 1, "seed": 0, "phase": "lobby",
			"session": null, "vp": null, "loaded": {}, "t": 0.0}
		rooms[c] = room
	else:
		if not rooms.has(room_code):
			s_error.rpc_id(id, "no room called %s" % room_code)
			return
		room = rooms[room_code]
		if room.members.size() >= MAX_PLAYERS:
			s_error.rpc_id(id, "that room is full")
			return
	var used := []
	for m in room.members.values():
		used.append(m.color)
	var color := 0
	while color in used:
		color += 1
	var n := clean_name(pname)
	room.members[id] = {"name": n if n != "" else "CAM %d" % (id % 90 + 10), "color": color}
	peer_room[id] = room.code
	print("room %s: %s joined (%d)" % [room.code, room.members[id].name, room.members.size()])
	_push_room(room)
	if room.phase != "lobby":
		# drop in on the level already running
		s_level.rpc_id(id, room.level, room.seed, _roster(room))


@rpc("any_peer", "call_remote", "reliable")
func c_start(lvl: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var room: Dictionary = rooms.get(peer_room.get(id, ""), {})
	if room.is_empty() or room.host != id or room.phase != "lobby":
		return
	_begin_level(room, clampi(lvl, 1, Eras.COUNT))


func _begin_level(room: Dictionary, lvl: int) -> void:
	_end_session(room)
	room.level = lvl
	room.seed = randi() % 1000000
	room.phase = "loading"
	room.loaded = {}
	room.t = 0.0
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(2, 2)
	add_child(vp)
	var s: Node3D = SESSION.new()
	s.mode = "server"
	s.net_room = room
	s.level = lvl
	s.seed_ = room.seed
	vp.add_child(s)
	room.vp = vp
	room.session = s
	for id in room.members:
		s_level.rpc_id(id, lvl, room.seed, _roster(room))
	_push_room(room)
	print("room %s: level %d seed %d" % [room.code, lvl, room.seed])


func _end_session(room: Dictionary) -> void:
	if room.vp:
		room.vp.queue_free()
	room.vp = null
	room.session = null


@rpc("any_peer", "call_remote", "reliable")
func c_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	var room: Dictionary = rooms.get(peer_room.get(id, ""), {})
	if room.is_empty() or room.session == null:
		return
	room.loaded[id] = true
	room.session.add_net_player(id, room.members[id])
	if room.phase == "play":
		s_event.rpc_id(id, ["go"])
	elif room.loaded.size() >= room.members.size():
		_go(room)


func _go(room: Dictionary) -> void:
	room.phase = "play"
	room.session.go()
	for id in room.loaded:
		s_event.rpc_id(id, ["go"])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_input(a: PackedFloat32Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	var room: Dictionary = rooms.get(peer_room.get(id, ""), {})
	if room.is_empty() or room.session == null or a.size() < 7:
		return
	room.session.net_input(id, a)


@rpc("any_peer", "call_remote", "reliable")
func c_emote(e: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var room: Dictionary = rooms.get(peer_room.get(id, ""), {})
	if room.is_empty() or room.session == null:
		return
	room.session.emote(id, clampi(e, 1, 4))


@rpc("any_peer", "call_remote", "reliable")
func c_signal(to: int, msg: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if peer_room.get(id, "") == "" or peer_room.get(id) != peer_room.get(to, "-") or msg.length() > 20000:
		return
	s_signal.rpc_id(to, id, msg)


## Called by a server session.
func room_snapshot(room: Dictionary, a: PackedFloat32Array) -> void:
	for id in room.loaded:
		s_snap.rpc_id(id, a)


func room_event(room: Dictionary, ev: Array) -> void:
	for id in room.loaded:
		s_event.rpc_id(id, ev)


func room_over(room: Dictionary, cleared: bool) -> void:
	room.phase = "card"
	room.t = 0.0
	room.next = (room.level + 1 if cleared else room.level)


func _on_peer_gone(id: int) -> void:
	if not is_server:
		return
	var c: String = peer_room.get(id, "")
	peer_room.erase(id)
	if not rooms.has(c):
		return
	var room: Dictionary = rooms[c]
	print("room %s: %s left" % [c, room.members.get(id, {}).get("name", "?")])
	room.members.erase(id)
	room.loaded.erase(id)
	if room.session:
		room.session.remove_net_player(id)
	if room.members.is_empty():
		_end_session(room)
		rooms.erase(c)
		return
	if room.host == id:
		room.host = room.members.keys()[0]
	_push_room(room)


func _process(dt: float) -> void:
	if not is_server:
		return
	for c in rooms.keys():
		var room: Dictionary = rooms[c]
		room.t += dt
		if room.phase == "loading" and room.t > LOAD_TIMEOUT and not room.loaded.is_empty():
			_go(room)
		elif room.phase == "card" and room.t > CARD_TIME:
			if room.next > Eras.COUNT:
				# the bottom of the tape: back to the lobby
				_end_session(room)
				room.phase = "lobby"
				room.level = 1
				_push_room(room)
			else:
				_begin_level(room, room.next)
