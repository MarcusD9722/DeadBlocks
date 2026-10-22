extends Node
## Every sound effect is synthesized at startup — no audio files needed.

const RATE := 22050

var streams := {}
var pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	streams["dig"] = _noise(0.07, 0.55, 1600.0)
	streams["break"] = _noise(0.2, 0.7, 900.0)
	streams["place"] = _thump(0.12, 160.0, 70.0, 0.8)
	streams["thud"] = _thump(0.18, 110.0, 50.0, 0.9)
	streams["hit"] = _hit()
	streams["hurt"] = _hurt()
	streams["zhurt"] = _thump(0.25, 220.0, 90.0, 0.6)
	streams["squeal"] = _squeal()
	streams["groan"] = _groan()
	streams["eat"] = _eat()
	streams["click"] = _noise(0.03, 0.4, 4000.0)
	streams["craft"] = _craft()
	streams["siren"] = _siren()
	streams["scream"] = _scream()
	streams["spit"] = _noise(0.16, 0.6, 2200.0)
	streams["splash"] = _sizzle()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)


func play(name: String, vol := 0.0, pitch := 1.0) -> void:
	for p in pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = vol
			p.pitch_scale = pitch * randf_range(0.94, 1.06)
			p.play()
			return


func play_at(name: String, pos: Vector3, vol := 0.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[name]
	p.volume_db = vol
	p.max_distance = 40.0
	p.unit_size = 5.0
	p.pitch_scale = randf_range(0.92, 1.08)
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------ synthesis

func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	w.data = b
	return w


func _lp(cut: float) -> float:
	return exp(-TAU * cut / RATE)


func _noise(dur: float, vol: float, cut: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var a := _lp(cut)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y = (1.0 - a) * randf_range(-1, 1) + a * y
		s[i] = y * vol * 2.5 * pow(1.0 - t, 2.0)
	return _wav(s)


func _thump(dur: float, f0: float, f1: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var y := 0.0
	var a := _lp(700.0)
	for i in n:
		var t := float(i) / n
		ph += lerpf(f0, f1, t) / RATE
		y = (1.0 - a) * randf_range(-1, 1) + a * y
		s[i] = (sin(ph * TAU) * 0.8 + y * 0.9) * vol * exp(-t * 5.0)
	return _wav(s)


func _hit() -> AudioStreamWAV:
	var n := int(0.12 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var a := _lp(1200.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += 180.0 / RATE
		y = (1.0 - a) * randf_range(-1, 1) + a * y
		s[i] = (y * 1.6 + sin(ph * TAU) * 0.5) * 0.7 * exp(-t * 6.0)
	return _wav(s)


func _hurt() -> AudioStreamWAV:
	var n := int(0.24 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var y := 0.0
	var a := _lp(1400.0)
	for i in n:
		var t := float(i) / n
		ph += lerpf(380.0, 150.0, t) / RATE
		var sq := 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		y = (1.0 - a) * sq + a * y
		s[i] = y * 0.45 * (1.0 - t)
	return _wav(s)


func _squeal() -> AudioStreamWAV:
	var n := int(0.3 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += (700.0 + sin(t * 40.0) * 120.0 - t * 250.0) / RATE
		s[i] = sin(ph * TAU) * 0.35 * sin(t * PI)
	return _wav(s)


func _groan() -> AudioStreamWAV:
	var dur := 1.2
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var y := 0.0
	var a := _lp(600.0)
	for i in n:
		var t := float(i) / n
		var f := 78.0 + 12.0 * sin(TAU * 4.5 * t * dur) + 22.0 * (1.0 - t)
		ph += f / RATE
		var saw := 2.0 * (ph - floorf(ph + 0.5))
		var x := saw * 0.8 + randf_range(-1, 1) * 0.35
		y = (1.0 - a) * x + a * y
		s[i] = y * 1.1 * pow(sin(PI * t), 0.6)
	return _wav(s)


## A Screamer: a shrill, wavering shriek that rises and breaks.
func _scream() -> AudioStreamWAV:
	var dur := 1.4
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / n
		var f := 620.0 + 900.0 * t + 60.0 * sin(TAU * 11.0 * t * dur)
		ph += f / RATE
		ph2 += f * 1.51 / RATE
		var x := sin(ph * TAU) * 0.5 + sin(ph2 * TAU) * 0.2 + randf_range(-1, 1) * 0.18
		s[i] = x * 0.6 * pow(sin(PI * minf(1.0, t * 1.15)), 0.5)
	return _wav(s)


## Acid landing: a short hiss that fades.
func _sizzle() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var a := _lp(5000.0)
	for i in n:
		var t := float(i) / n
		y = (1.0 - a) * randf_range(-1, 1) + a * y
		s[i] = y * 0.45 * pow(1.0 - t, 2.0)
	return _wav(s)


func _eat() -> AudioStreamWAV:
	var n := int(0.32 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var a := _lp(2200.0)
	for i in n:
		var t := float(i) / RATE
		var local := fmod(t, 0.1) / 0.05
		var env := 0.0 if local > 1.0 else (1.0 - local)
		y = (1.0 - a) * randf_range(-1, 1) + a * y
		s[i] = y * env * 0.9
	return _wav(s)


func _craft() -> AudioStreamWAV:
	var n := int(0.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 660.0 if t < 0.08 else 990.0
		ph += f / RATE
		var local := fmod(t, 0.08) / 0.08
		s[i] = sin(ph * TAU) * 0.25 * (1.0 - local)
	return _wav(s)


func _siren() -> AudioStreamWAV:
	var dur := 3.2
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / n
		ph += (70.0 + 50.0 * t) / RATE
		ph2 += (105.0 + 75.0 * t) / RATE
		var env := minf(1.0, t * 5.0) * minf(1.0, (1.0 - t) * 4.0)
		var trem := 0.75 + 0.25 * sin(t * dur * TAU * 3.0)
		s[i] = (sin(ph * TAU) * 0.5 + sin(ph2 * TAU) * 0.3) * env * trem * 0.8
	return _wav(s)
