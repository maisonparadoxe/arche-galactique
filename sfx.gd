extends Node
## Sons du jeu, entièrement générés par code (aucun fichier audio à fournir).
##
## - des effets courts (coup, tir, relève, coffre…) joués par un petit groupe de lecteurs ;
## - une musique « calme » pour les écrans de gestion ;
## - une musique « action » à couches pour l'abordage : basse, batterie, arpège.
##   Les couches se mettent en route selon l'intensité (ennemis éveillés, enchaînements).
## La touche M coupe ou rétablit tout le son sur le PC.

const RATE := 22050
const MUSIC_RATE := 16000
const POOL := 10
const BPM := 124.0

var muted := false
var _pool: Array = []
var _next := 0
var _sounds: Dictionary = {}
var _layers: Dictionary = {}           # nom -> AudioStreamPlayer (musique)
var _target: Dictionary = {}           # nom -> volume cible en dB
var _thread: Thread
var _mode := "off"
var _ready_music := false
var _rng := RandomNumberGenerator.new()

const SILENT := -60.0


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_pool.append(p)
	_build_sfx()
	for n in ["calme", "basse", "batterie", "arpege"]:
		var p := AudioStreamPlayer.new()
		p.volume_db = SILENT
		add_child(p)
		_layers[n] = p
		_target[n] = SILENT
	_thread = Thread.new()
	_thread.start(_build_music)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


# ---------------------------------------------------------------- effets

## Joue un effet. pitch > 1 = plus aigu ; vol en dB.
func play(name: String, pitch := 1.0, vol := 0.0) -> void:
	if muted or not _sounds.has(name):
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _sounds[name]
	p.pitch_scale = pitch
	p.volume_db = -4.0 + vol
	p.play()


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted


# ---------------------------------------------------------------- musique

## "calme" (gestion), "action" (abordage) ou "off".
func set_music(mode: String) -> void:
	_mode = mode
	_apply_targets(0.0, false)


## Intensité de l'abordage : 0 = tout dort, 1 = mêlée, +combo.
func set_action(awake: float, combo: int) -> void:
	if _mode != "action":
		return
	_apply_targets(awake, combo >= 2)


func _apply_targets(awake: float, arp: bool) -> void:
	_target["calme"] = -16.0 if _mode == "calme" else SILENT
	_target["basse"] = -11.0 if _mode == "action" else SILENT
	_target["batterie"] = (-12.0 if awake > 0.0 else SILENT) if _mode == "action" else SILENT
	_target["arpege"] = (-14.0 if arp or awake > 0.6 else SILENT) if _mode == "action" else SILENT


func _process(delta: float) -> void:
	if not _ready_music:
		return
	for n in _layers:
		var p: AudioStreamPlayer = _layers[n]
		var target := float(_target[n])
		if target > SILENT and not p.playing and p.stream != null:
			p.volume_db = SILENT
			p.play(_sync_pos())
		p.volume_db = move_toward(p.volume_db, target, 60.0 * delta)
		if p.playing and target <= SILENT and p.volume_db <= SILENT + 0.5:
			p.stop()


## Les couches d'action restent alignées : on les relance à la même position de boucle.
func _sync_pos() -> float:
	var base: AudioStreamPlayer = _layers["basse"]
	if base.playing:
		return base.get_playback_position()
	return 0.0


func _music_built(streams: Dictionary) -> void:
	_thread.wait_to_finish()
	for n in streams:
		(_layers[n] as AudioStreamPlayer).stream = streams[n]
	_ready_music = true


# ---------------------------------------------------------------- synthèse : effets

func _build_sfx() -> void:
	_sounds["coup"] = _wave(0.17, func(t: float, k: float) -> float:
		return (_noise() * 0.55 + sin(TAU * lerpf(900.0, 260.0, k) * t) * 0.35) * pow(1.0 - k, 1.6) * sin(minf(k * 9.0, 1.57)))
	_sounds["tir"] = _wave(0.2, func(t: float, k: float) -> float:
		var f := lerpf(1100.0, 140.0, pow(k, 0.55))
		return (_square(f, t) * 0.4 + _noise() * 0.18 * (1.0 - k)) * pow(1.0 - k, 1.5))
	_sounds["roulade"] = _wave(0.24, func(t: float, k: float) -> float:
		return _noise() * 0.5 * sin(PI * k) * (0.4 + 0.6 * sin(TAU * 12.0 * t)))
	_sounds["mort"] = _wave(0.32, func(t: float, k: float) -> float:
		return (sin(TAU * lerpf(190.0, 45.0, k) * t) * 0.7 + _noise() * 0.5 * pow(1.0 - k, 3.0)) * pow(1.0 - k, 1.3))
	_sounds["touche"] = _wave(0.1, func(t: float, k: float) -> float:
		return (_noise() * 0.5 + _square(520.0, t) * 0.3) * (1.0 - k))
	_sounds["tombe"] = _wave(0.55, func(t: float, k: float) -> float:
		return (_tri(lerpf(480.0, 90.0, k), t) * 0.6 + _noise() * 0.25 * pow(1.0 - k, 4.0)) * pow(1.0 - k, 0.9))
	_sounds["releve"] = _notes([523.25, 659.25, 783.99, 1046.5], 0.085, 0.55)
	_sounds["coffre"] = _notes([1318.5, 1760.0], 0.11, 0.55)
	_sounds["gros_coffre"] = _notes([659.25, 830.6, 987.77, 1318.5, 1661.2], 0.09, 0.55)
	_sounds["verrou"] = _wave(0.22, func(t: float, k: float) -> float:
		return (sin(TAU * 110.0 * t) * 0.6 + _noise() * 0.4) * pow(1.0 - k, 4.0) + sin(TAU * 880.0 * t) * 0.18 * pow(1.0 - k, 2.0))
	_sounds["ouvre"] = _notes([392.0, 587.33], 0.09, 0.55)
	_sounds["alerte"] = _wave(0.16, func(t: float, k: float) -> float:
		return sin(TAU * (700.0 + 160.0 * sin(TAU * 18.0 * t)) * t) * 0.35 * (1.0 - k))
	_sounds["ennemi_tire"] = _wave(0.16, func(t: float, k: float) -> float:
		return (_square(lerpf(520.0, 200.0, k), t) * 0.3 + _noise() * 0.1) * pow(1.0 - k, 1.4))
	_sounds["enchainement"] = _notes([880.0], 0.14, 0.5)
	_sounds["victoire"] = _notes([392.0, 523.25, 659.25, 783.99, 1046.5], 0.14, 0.6)
	_sounds["defaite"] = _notes([392.0, 349.23, 311.13, 261.63], 0.2, 0.6)
	_sounds["repartie"] = _notes([1046.5, 1318.5], 0.07, 0.35)


## Une suite de notes douces (chaque note : triangle + harmonique).
func _notes(freqs: Array, dur: float, amp: float) -> AudioStreamWAV:
	var total := dur * freqs.size() + 0.2
	return _wave(total, func(t: float, _k: float) -> float:
		var i := mini(int(t / dur), freqs.size() - 1)
		var lt := t - i * dur
		var env := exp(-lt * 11.0) * minf(lt * 400.0, 1.0)
		var f: float = freqs[i]
		return (_tri(f, t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.2) * env * amp)


## Fabrique un son mono de « seconds » secondes à partir d'une fonction (temps, progression 0..1).
func _wave(seconds: float, fn: Callable, rate := RATE) -> AudioStreamWAV:
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := clampf(float(fn.call(t, float(i) / n)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


func _square(f: float, t: float, duty := 0.5) -> float:
	return 1.0 if fmod(f * t, 1.0) < duty else -1.0


func _tri(f: float, t: float) -> float:
	return absf(fmod(f * t, 1.0) * 4.0 - 2.0) - 1.0


func _saw(f: float, t: float) -> float:
	return fmod(f * t, 1.0) * 2.0 - 1.0


# ---------------------------------------------------------------- synthèse : musique (dans un thread)

const ROOTS := [55.0, 43.65, 65.41, 49.0]            # La, Fa, Do, Sol (octave grave) : la mineur
const CHORDS := [[0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]]   # intervalles en demi-tons au-dessus de la fondamentale


func _build_music() -> void:
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var bars := 4
	var length := bar * bars
	var streams := {}
	# Basse : croches sur la fondamentale, avec l'octave de temps en temps
	streams["basse"] = _loop(length, func(t: float, _k: float) -> float:
		var b := int(t / bar) % bars
		var step := int(t / (beat / 2.0))
		var lt := fmod(t, beat / 2.0)
		var f: float = ROOTS[b] * (2.0 if step % 8 in [2, 5, 7] else 1.0)
		var env := exp(-lt * 6.0) * minf(lt * 500.0, 1.0)
		return (_saw(f, t) * 0.5 + _square(f * 0.5, t) * 0.3) * env * 0.8)
	# Batterie : grosse caisse sur les temps, caisse claire sur 2 et 4, charleston sur les contretemps
	streams["batterie"] = _loop(length, func(t: float, _k: float) -> float:
		var lt := fmod(t, beat)
		var beat_i := int(t / beat) % 4
		var v := 0.0
		v += sin(TAU * lerpf(150.0, 48.0, minf(lt * 14.0, 1.0)) * lt) * exp(-lt * 9.0) * 0.9
		if beat_i == 1 or beat_i == 3:
			v += _noise() * exp(-lt * 14.0) * 0.55
		var hh := fmod(t + beat / 2.0, beat)
		v += _noise() * exp(-hh * 40.0) * 0.18
		return v)
	# Arpège : doubles croches sur les notes de l'accord, une octave plus haut
	streams["arpege"] = _loop(length, func(t: float, _k: float) -> float:
		var b := int(t / bar) % bars
		var step := int(t / (beat / 4.0))
		var lt := fmod(t, beat / 4.0)
		var chord: Array = CHORDS[b]
		var semis: int = int(chord[[0, 1, 2, 1][step % 4]]) + (12 if step % 8 >= 4 else 0)
		var f: float = float(ROOTS[b]) * 4.0 * pow(2.0, semis / 12.0)
		var env := exp(-lt * 14.0) * minf(lt * 600.0, 1.0)
		return _square(f, t, 0.25) * env * 0.32)
	# Calme : nappe lente et cloches éparses, plus de temps
	var slow := 60.0 / 66.0
	var clength := slow * 4.0 * 4.0
	streams["calme"] = _loop(clength, func(t: float, _k: float) -> float:
		var b := int(t / (slow * 4.0)) % 4
		var root: float = float(ROOTS[b]) * 2.0
		var pad := 0.0
		for semi in [0, 7, 12, 16 if b != 0 else 15]:
			var f := root * pow(2.0, semi / 12.0)
			pad += sin(TAU * f * t) * 0.16 + sin(TAU * f * 1.003 * t) * 0.1
		var lt := fmod(t, slow * 2.0)
		var bell_i := int(t / (slow * 2.0)) % 8
		var bf: float = root * 4.0 * pow(2.0, [0, 7, 12, 10, 12, 7, 15, 12][bell_i] / 12.0)
		var bell := (sin(TAU * bf * t) * 0.5 + sin(TAU * bf * 2.76 * t) * 0.18) * exp(-lt * 3.2) * 0.35
		var swell := 0.7 + 0.3 * sin(TAU * t / (slow * 8.0))
		return pad * swell * 0.7 + bell)
	call_deferred("_music_built", streams)


## Boucle de musique (même fabrication qu'un effet, mais répétée).
func _loop(seconds: float, fn: Callable, rate := MUSIC_RATE) -> AudioStreamWAV:
	var w := _wave(seconds, fn, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(seconds * rate)
	return w
