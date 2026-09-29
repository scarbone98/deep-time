class_name Synth
extends RefCounted
## Every sound in the game is synthesized here at load time. No audio files.

const RATE := 22050


static func all() -> Dictionary:
	return {
		"hum": hum(),
		"skitter": skitter(),
		"wings": wings(),
		"step": step(),
		"splash": splash(),
		"heart": heart(),
		"breath": breath(),
		"hiss": hiss(),
		"death": death(),
		"crack": crack(),
		"call": distant_call(),
		"beep": beep(),
		"growl": growl(),
		"roar": roar(),
		"croak": croak(),
		"chitter": chitter(),
	}


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


static func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


## Crossfades the tail into the head so the buffer loops without a click.
## Periodic parts with whole-number Hz stay in phase if the buffer was made
## `fade` samples longer than the loop.
static func _loop(s: PackedFloat32Array, fade: int) -> AudioStreamWAV:
	var n := s.size() - fade
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n + i] * (1.0 - k)
	s.resize(n)
	return _wav(s, true)


static func hum() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var fade := 2205
	var s := _buf(1.0 + 0.1)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = 0.24 * sin(TAU * 120.0 * t) + 0.1 * sin(TAU * 240.0 * t) \
			+ 0.07 * clampf(sin(TAU * 60.0 * t) * 5.0, -1.0, 1.0) \
			+ 0.04 * sin(TAU * 360.0 * t) + r.randf_range(-0.015, 0.015)
	return _loop(s, fade)


static func skitter() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var s := _buf(1.0)
	var n := s.size()
	var brown := 0.0
	for i in n:
		brown = brown * 0.99 + r.randf_range(-1.0, 1.0) * 0.03
		s[i] = brown * 0.25
	for c in 55:
		var at := r.randi_range(0, n - 1)
		var f := r.randf_range(1500.0, 3200.0)
		var amp := r.randf_range(0.2, 0.55)
		for k in 300:
			var tt := float(k) / RATE
			s[(at + k) % n] += amp * (r.randf_range(-1.0, 1.0) * exp(-k / 35.0) + sin(TAU * f * tt) * exp(-k / 70.0))
	return _wav(s, true)


static func wings() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var fade := 2205
	var s := _buf(1.0 + 0.1)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var w := sin(TAU * 24.0 * t)
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.25
		s[i] = (w * w * w) * 0.45 + lp * 0.55 * (0.3 + 0.7 * absf(w)) + 0.12 * sin(TAU * 48.0 * t)
	return _loop(s, fade)


static func step() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(0.16)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.35
		s[i] = lp * exp(-t * 28.0) * 0.9 + sin(TAU * 70.0 * t) * exp(-t * 40.0) * 0.4
	return _wav(s)


static func splash() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(0.5)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var w := r.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.08
		var env := minf(t / 0.03, 1.0) * exp(-t * 7.0)
		s[i] = (w - lp) * env * 0.5 + sin(TAU * (500.0 + 300.0 * sin(t * 40.0)) * t) * exp(-t * 14.0) * 0.12
	return _wav(s)


static func heart() -> AudioStreamWAV:
	var s := _buf(1.0)
	for i in s.size():
		var t := float(i) / RATE
		var a := sin(TAU * 46.0 * t) * exp(-t * 16.0)
		var t2 := maxf(0.0, t - 0.28)
		var b := sin(TAU * 42.0 * t2) * exp(-t2 * 18.0) * 0.7 if t > 0.28 else 0.0
		s[i] = (a + b) * 0.95
	return _wav(s, true)


static func breath() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(1.6)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var w := r.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.3
		lp2 += (lp - lp2) * 0.3
		var inhale := sin(PI * clampf(t / 0.55, 0.0, 1.0)) * 0.5
		var exhale := sin(PI * clampf((t - 0.7) / 0.7, 0.0, 1.0)) * 0.9
		s[i] = (lp - lp2 * 0.6) * (inhale + exhale) * 0.7
	return _wav(s, true)


static func hiss() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(1.4)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(t / 0.02, 1.0) * exp(-t * 2.4)
		var f := lerpf(700.0, 180.0, t / 1.4)
		ph += TAU * f / RATE
		var rasp := clampf(sin(ph) * 3.0 + r.randf_range(-1.0, 1.0) * 1.5, -1.0, 1.0)
		s[i] = rasp * env * 0.6 + r.randf_range(-1.0, 1.0) * env * 0.35
	return _wav(s)


static func death() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(2.2)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(90.0, 30.0, t / 2.2) / RATE
		var crunch := clampf(sin(ph) * 4.0, -1.0, 1.0) * exp(-t * 1.2) * 0.5
		s[i] = r.randf_range(-1.0, 1.0) * 0.5 + crunch
	return _wav(s)


static func crack() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(1.2)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.12
		var pops := 1.0 if r.randf() < 0.02 * exp(-t * 3.0) else 0.0
		s[i] = lp * exp(-t * 3.0) * 0.8 + pops * r.randf_range(-0.8, 0.8)
	return _wav(s)


## Something big, far off. Nobody knows what made it.
static func distant_call() -> AudioStreamWAV:
	var s := _buf(3.0)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 110.0 + 40.0 * sin(PI * t / 3.0) - t * 12.0
		ph += TAU * f / RATE
		var env := sin(PI * t / 3.0)
		s[i] = (sin(ph) + 0.4 * sin(ph * 2.01) + 0.2 * sin(ph * 3.03)) * env * 0.35
	return _wav(s)


## The camcorder's "got it" double beep.
static func beep() -> AudioStreamWAV:
	var s := _buf(0.3)
	for i in s.size():
		var t := float(i) / RATE
		var on := 1.0 if t < 0.09 or (t > 0.15 and t < 0.24) else 0.0
		s[i] = sin(TAU * 1760.0 * t) * on * 0.3
	return _wav(s)


## Eryops: a low wet bellow with a pulsing throat.
static func croak() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(1.3)
	var ph := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (62.0 + 10.0 * sin(t * 3.0)) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.05
		var pulse := 0.6 + 0.4 * sin(TAU * 9.0 * t)
		var env := sin(PI * minf(t / 1.3, 1.0))
		s[i] = clampf((sin(ph) + 0.5 * sin(ph * 2.0)) * 1.6, -1.0, 1.0) * pulse * env * 0.45 + lp * env * 0.6
	return _wav(s)


## A scorpion's warning: dry, fast rattling.
static func chitter() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(1.2)
	for c in 70:
		var at := r.randi_range(0, s.size() - 400)
		var amp := r.randf_range(0.3, 0.7)
		var f := r.randf_range(2500.0, 4200.0)
		for k in 180:
			s[at + k] += amp * exp(-k / 25.0) * (r.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * f * k / RATE))
	return _wav(s)


## A low, wet, rolling growl from deep in a big chest.
static func growl() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(2.2)
	var lp := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.04
		ph += TAU * (48.0 + 6.0 * sin(t * 5.0)) / RATE
		var flutter := 0.55 + 0.45 * sin(TAU * 17.0 * t + sin(t * 3.0))
		var env := sin(PI * t / 2.2)
		s[i] = (lp * 4.0 + sin(ph) * 0.5) * flutter * env * 0.6
	return _wav(s)


## The charge: a ragged bellowing roar.
static func roar() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	var s := _buf(1.8)
	var ph := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 140.0 + 90.0 * sin(PI * minf(t / 0.6, 1.0)) - t * 40.0
		ph += TAU * f / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.2
		var env := minf(t / 0.08, 1.0) * exp(-t * 1.4)
		var v := sin(ph) + 0.6 * sin(ph * 2.03) + 0.4 * sin(ph * 3.1) + lp * 2.0
		s[i] = clampf(v * 1.8, -1.0, 1.0) * env * 0.7
	return _wav(s)
