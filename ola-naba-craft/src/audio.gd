# Original sound effects synthesised at startup (no audio files, no external sources).
extends Node

const RATE := 22050

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var pool3d: Array[AudioStreamPlayer3D] = []
var world_root: Node3D
var next := 0
var next3d := 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	_build()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		pool.append(p)

func attach_world(root: Node3D) -> void:
	world_root = root
	pool3d.clear()
	for i in 8:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 28.0
		p.unit_size = 4.0
		root.add_child(p)
		pool3d.append(p)

func detach_world() -> void:
	world_root = null
	pool3d.clear()

func play(name: String, volume := 1.0) -> void:
	if not streams.has(name) or pool.is_empty():
		return
	var p := pool[next]
	next = (next + 1) % pool.size()
	p.stream = streams[name]
	p.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
	p.pitch_scale = rng.randf_range(0.94, 1.06)
	p.play()

func play_at(name: String, pos: Vector3, volume := 1.0) -> void:
	if pool3d.is_empty() or not is_instance_valid(world_root):
		play(name, volume * 0.6)
		return
	if not streams.has(name):
		return
	var p := pool3d[next3d]
	next3d = (next3d + 1) % pool3d.size()
	p.stream = streams[name]
	p.global_position = pos
	p.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
	p.pitch_scale = rng.randf_range(0.92, 1.08)
	p.play()

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

# Filtered noise burst: soft for soil, bright for stone, hollow for wood.
func _noise(seconds: float, cutoff: float, decay: float, tone := 0.0, tone_mix := 0.0) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := clampf(cutoff / RATE * TAU, 0.0, 1.0)
	for i in n:
		var t := float(i) / RATE
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		var env := exp(-t * decay) * minf(1.0, t * 400.0)
		var s := lp * (1.0 - tone_mix)
		if tone > 0.0:
			s += sin(TAU * tone * t) * tone_mix
		out[i] = s * env * 0.9
	return out

func _tone(seconds: float, f0: float, f1: float, decay: float, harmonics := 1, vol := 0.5) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / seconds)
		phase += TAU * f / RATE
		var s := 0.0
		for h in harmonics:
			s += sin(phase * (h + 1)) / (h + 1)
		out[i] = s * exp(-t * decay) * minf(1.0, t * 300.0) * vol
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p[0] as PackedFloat32Array).size() + int(p[1] * RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var src: PackedFloat32Array = p[0]
		var off := int(p[1] * RATE)
		for i in src.size():
			out[off + i] += src[i]
	return out

func _build() -> void:
	rng.seed = 2207
	streams["dig_soft"] = _wav(_noise(0.12, 900.0, 30.0))
	streams["dig_sand"] = _wav(_noise(0.12, 2600.0, 34.0))
	streams["dig_stone"] = _wav(_noise(0.1, 4200.0, 40.0, 210.0, 0.25))
	streams["dig_wood"] = _wav(_noise(0.13, 1500.0, 26.0, 140.0, 0.45))
	streams["dig_leaf"] = _wav(_noise(0.1, 5200.0, 36.0))
	streams["dig_glass"] = _wav(_mix([[_noise(0.08, 6000.0, 50.0), 0.0], [_tone(0.18, 1800.0, 1700.0, 18.0, 1, 0.25), 0.0]]))
	streams["dig_"] = streams["dig_soft"]
	streams["place"] = _wav(_mix([[_noise(0.08, 1200.0, 45.0), 0.0], [_tone(0.09, 180.0, 120.0, 40.0, 2, 0.5), 0.0]]))
	streams["break"] = _wav(_mix([[_noise(0.22, 2200.0, 16.0), 0.0], [_tone(0.12, 140.0, 80.0, 25.0, 2, 0.4), 0.0]]))
	streams["pickup"] = _wav(_mix([[_tone(0.07, 740.0, 980.0, 30.0, 1, 0.35), 0.0], [_tone(0.08, 990.0, 1320.0, 30.0, 1, 0.3), 0.05]]))
	streams["craft"] = _wav(_mix([[_tone(0.3, 523.0, 523.0, 9.0, 3, 0.3), 0.0], [_tone(0.3, 659.0, 659.0, 9.0, 3, 0.25), 0.07], [_tone(0.4, 784.0, 784.0, 7.0, 3, 0.25), 0.14]]))
	streams["hurt"] = _wav(_mix([[_tone(0.25, 420.0, 180.0, 12.0, 2, 0.5), 0.0], [_noise(0.1, 1600.0, 30.0), 0.0]]))
	streams["eat"] = _wav(_mix([[_noise(0.07, 1800.0, 40.0), 0.0], [_noise(0.07, 1800.0, 40.0), 0.12], [_noise(0.07, 1800.0, 40.0), 0.24]]))
	streams["gloom"] = _wav(_tone(0.45, 110.0, 70.0, 5.0, 4, 0.45))
	streams["puff"] = _wav(_mix([[_noise(0.35, 3000.0, 10.0), 0.0], [_tone(0.3, 600.0, 1200.0, 8.0, 1, 0.2), 0.0]]))
	streams["break_tool"] = _wav(_mix([[_noise(0.2, 5000.0, 18.0), 0.0], [_tone(0.2, 900.0, 300.0, 14.0, 2, 0.3), 0.0]]))
	streams["ui_move"] = _wav(_tone(0.04, 880.0, 880.0, 60.0, 1, 0.2))
	streams["ui_ok"] = _wav(_mix([[_tone(0.06, 660.0, 660.0, 40.0, 1, 0.25), 0.0], [_tone(0.08, 990.0, 990.0, 35.0, 1, 0.25), 0.05]]))
	streams["ui_back"] = _wav(_tone(0.08, 520.0, 380.0, 35.0, 1, 0.25))
	streams["dusk"] = _wav(_mix([[_tone(1.2, 392.0, 392.0, 2.5, 3, 0.25), 0.0], [_tone(1.2, 311.0, 311.0, 2.5, 3, 0.2), 0.3]]))
	streams["dawn"] = _wav(_mix([[_tone(1.0, 523.0, 523.0, 3.0, 2, 0.22), 0.0], [_tone(1.0, 659.0, 659.0, 3.0, 2, 0.22), 0.2], [_tone(1.2, 784.0, 784.0, 2.5, 2, 0.22), 0.4]]))
