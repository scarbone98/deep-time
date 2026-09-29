class_name Voice
extends Node
## Proximity voice, web only. The browser does the hard parts (Opus, echo
## cancellation, WebRTC); Godot relays the signalling through the game
## server and, every frame, tells the page where everyone's head is so each
## voice comes from its speaker. Voices get a camcorder-ish band-pass.
##
## The living can't hear the dead. The dead hear everyone.

const JS := """
window.dtVoice = (() => {
  const ICE = [{urls: 'stun:stun.l.google.com:19302'}, {urls: 'stun:stun1.l.google.com:19302'}];
  const V = {ctx: null, stream: null, peers: {}, send: null, muted: false, analyser: null, buf: null, ok: false, err: ''};
  V.start = async (send) => {
    V.send = send;
    try {
      V.ctx = V.ctx || new (window.AudioContext || window.webkitAudioContext)();
      if (V.ctx.state !== 'running') await V.ctx.resume();
    } catch (e) { V.err = String(e); }
    try {
      V.stream = await navigator.mediaDevices.getUserMedia({audio: {echoCancellation: true, noiseSuppression: true, autoGainControl: true}});
      const src = V.ctx.createMediaStreamSource(V.stream);
      V.analyser = V.ctx.createAnalyser();
      V.analyser.fftSize = 512;
      V.buf = new Float32Array(512);
      src.connect(V.analyser);
      V.ok = true;
    } catch (e) { V.ok = false; V.err = String(e); }
    for (const id in V.peers) V._attach(V.peers[id]);
    return V.ok;
  };
  V.prime = () => {
    try { V.ctx = V.ctx || new (window.AudioContext || window.webkitAudioContext)(); V.ctx.resume(); } catch (e) {}
  };
  V.level = () => {
    if (!V.analyser || V.muted) return 0;
    V.analyser.getFloatTimeDomainData(V.buf);
    let s = 0; for (let i = 0; i < V.buf.length; i++) s += V.buf[i] * V.buf[i];
    return Math.sqrt(s / V.buf.length);
  };
  V.setMuted = (m) => { V.muted = !!m; if (V.stream) V.stream.getAudioTracks().forEach(t => t.enabled = !V.muted); };
  V._attach = (P) => {
    if (!V.stream || P.attached) return;
    V.stream.getAudioTracks().forEach(t => P.pc.addTrack(t, V.stream));
    P.attached = true;
  };
  V._msg = (id, obj) => { if (V.send) V.send(Number(id), JSON.stringify(obj)); };
  V.add = (id, caller) => {
    if (V.peers[id]) return;
    const pc = new RTCPeerConnection({iceServers: ICE});
    const P = {pc, caller, queue: [], attached: false, gain: null, panner: null};
    V.peers[id] = P;
    pc.onicecandidate = (e) => { if (e.candidate) V._msg(id, {c: e.candidate}); };
    pc.ontrack = (e) => {
      if (P.gain || !V.ctx) return;
      const st = e.streams[0] || new MediaStream([e.track]);
      const el = new Audio(); el.srcObject = st; el.muted = true; el.play().catch(() => {});
      P.el = el;
      const src = V.ctx.createMediaStreamSource(st);
      const hp = V.ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 220;
      const lp = V.ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 4200;
      const pan = V.ctx.createPanner();
      pan.panningModel = 'HRTF'; pan.distanceModel = 'linear';
      pan.refDistance = 2; pan.maxDistance = 32; pan.rolloffFactor = 1;
      const g = V.ctx.createGain(); g.gain.value = 0;
      src.connect(hp).connect(lp).connect(pan).connect(g).connect(V.ctx.destination);
      P.panner = pan; P.gain = g;
    };
    pc.onnegotiationneeded = async () => {
      if (!P.caller) return;
      try { await pc.setLocalDescription(await pc.createOffer()); V._msg(id, {sdp: pc.localDescription}); } catch (e) {}
    };
    if (caller) {
      if (V.stream) V._attach(P); else pc.addTransceiver('audio', {direction: 'recvonly'});
    }
  };
  V.onSig = async (id, text) => {
    let m; try { m = JSON.parse(text); } catch (e) { return; }
    if (!V.peers[id]) V.add(id, false);
    const P = V.peers[id], pc = P.pc;
    try {
      if (m.sdp) {
        await pc.setRemoteDescription(m.sdp);
        for (const c of P.queue) await pc.addIceCandidate(c);
        P.queue = [];
        if (m.sdp.type === 'offer') {
          V._attach(P);
          await pc.setLocalDescription(await pc.createAnswer());
          V._msg(id, {sdp: pc.localDescription});
        }
      } else if (m.c) {
        if (pc.remoteDescription) await pc.addIceCandidate(m.c); else P.queue.push(m.c);
      }
    } catch (e) {}
  };
  V.drop = (id) => { const P = V.peers[id]; if (!P) return; try { P.pc.close(); } catch (e) {} if (P.el) P.el.srcObject = null; delete V.peers[id]; };
  V.dropAll = () => { for (const id in V.peers) V.drop(id); };
  V.listener = (x, y, z, fx, fy, fz) => {
    if (!V.ctx) return;
    const L = V.ctx.listener, t = V.ctx.currentTime;
    if (L.positionX) {
      L.positionX.setTargetAtTime(x, t, 0.05); L.positionY.setTargetAtTime(y, t, 0.05); L.positionZ.setTargetAtTime(z, t, 0.05);
      L.forwardX.setTargetAtTime(fx, t, 0.05); L.forwardY.setTargetAtTime(fy, t, 0.05); L.forwardZ.setTargetAtTime(fz, t, 0.05);
      L.upX.value = 0; L.upY.value = 1; L.upZ.value = 0;
    } else { L.setPosition(x, y, z); L.setOrientation(fx, fy, fz, 0, 1, 0); }
  };
  V.peer = (id, x, y, z, gain, flat) => {
    const P = V.peers[id]; if (!P || !P.panner) return;
    const t = V.ctx.currentTime;
    P.panner.distanceModel = flat ? 'inverse' : 'linear';
    P.panner.maxDistance = flat ? 10000 : 32;
    if (P.panner.positionX) { P.panner.positionX.setTargetAtTime(x, t, 0.05); P.panner.positionY.setTargetAtTime(y, t, 0.05); P.panner.positionZ.setTargetAtTime(z, t, 0.05); }
    else P.panner.setPosition(x, y, z);
    P.gain.gain.setTargetAtTime(gain, t, 0.08);
  };
  V.connected = (id) => { const P = V.peers[id]; return !!(P && P.gain); };
  return V;
})();
"""

var js: JavaScriptObject
var _cb: JavaScriptObject
var _send: Callable
var muted := false
var level := 0.0
var available := false


func _ready() -> void:
	available = OS.has_feature("web")
	if available:
		JavaScriptBridge.eval(JS, true)
		js = JavaScriptBridge.get_interface("dtVoice")


## Asks for the microphone. Call from a click so the browser allows audio.
func start(send: Callable) -> void:
	_send = send
	if not available:
		return
	_cb = JavaScriptBridge.create_callback(_on_js_send)
	js.start(_cb)


func _on_js_send(args: Array) -> void:
	if _send.is_valid():
		_send.call(int(args[0]), str(args[1]))


## Wake the page's audio inside a click, before anything async happens.
func prime() -> void:
	if available:
		js.prime()


func add_peer(id: int, caller: bool) -> void:
	if available:
		js.add(id, caller)


func on_signal(from: int, msg: String) -> void:
	if available:
		js.onSig(from, msg)


func drop(id: int) -> void:
	if available:
		js.drop(id)


func drop_all() -> void:
	if available:
		js.dropAll()


func set_muted(m: bool) -> void:
	muted = m
	if available:
		js.setMuted(m)


func mic_ok() -> bool:
	return available and bool(js.ok)


func listener(pos: Vector3, fwd: Vector3) -> void:
	if available:
		js.listener(pos.x, pos.y, pos.z, fwd.x, fwd.y, fwd.z)


func peer(id: int, pos: Vector3, gain: float, flat: bool) -> void:
	if available:
		js.peer(id, pos.x, pos.y, pos.z, gain, flat)


func _process(_dt: float) -> void:
	level = float(js.level()) if available and js.ok else 0.0
