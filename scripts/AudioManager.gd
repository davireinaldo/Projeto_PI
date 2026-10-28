extends Node

# Som do ZERO-IMPACT (autoload): música com troca suave entre faixas,
# efeitos sonoros, ronco do motor que acompanha a velocidade e as
# opções de ligar/desligar música e efeitos (salvas no SaveManager).
# Os .wav são gerados por tools/gerar_sons.py. O loop de menu, race e engine
# fica na importação (.import, loop_mode=2): ligado por código ele não chega
# no navegador (modo Sample da web) e a música parava no fim.

const MUSIC := {
	"menu": preload("res://assets/audio/music/menu.wav"),
	"race": preload("res://assets/audio/music/race.wav"),
	"race_cyber": preload("res://assets/audio/music/race_cyber.wav"),
	"race_chill": preload("res://assets/audio/music/race_chill.wav"),
	"gameover": preload("res://assets/audio/music/gameover.wav"),
}
const LOOPING := ["menu", "race", "race_cyber", "race_chill"]
const RADIO_STATIONS := [
	{"name": "SYNTH WAVE", "track": "race"},
	{"name": "CYBER RUSH", "track": "race_cyber"},
	{"name": "CHILL DRIVE", "track": "race_chill"},
]
# Rádio do Gol do Narcelio: só esse carro toca estas músicas (SHIFT direito
# troca). Carregadas só quando o Gol corre, para não pesar no resto do jogo.
const GOL_RADIO := [
	{"name": "SONHO DE AMOR", "path": "res://assets/audio/music/gol/sonho_de_amor.mp3"},
	{"name": "TE ESPERANDO", "path": "res://assets/audio/music/gol/te_esperando.mp3"},
]
const SFX := {
	"coin": preload("res://assets/audio/sfx/coin.wav"),
	"power_shield": preload("res://assets/audio/sfx/power_shield.wav"),
	"power_slow": preload("res://assets/audio/sfx/power_slow.wav"),
	"power_points": preload("res://assets/audio/sfx/power_points.wav"),
	"crash": preload("res://assets/audio/sfx/crash.wav"),
	"shield_block": preload("res://assets/audio/sfx/shield_block.wav"),
	"life_lost": preload("res://assets/audio/sfx/life_lost.wav"),
	"shield_end": preload("res://assets/audio/sfx/shield_end.wav"),
	"whoosh": preload("res://assets/audio/sfx/whoosh.wav"),
	"biome": preload("res://assets/audio/sfx/biome.wav"),
	"ui_move": preload("res://assets/audio/sfx/ui_move.wav"),
	"ui_click": preload("res://assets/audio/sfx/ui_click.wav"),
	"ui_buy": preload("res://assets/audio/sfx/ui_buy.wav"),
	"ui_error": preload("res://assets/audio/sfx/ui_error.wav"),
	"horn": preload("res://assets/audio/sfx/horn.wav"),
	"near_miss": preload("res://assets/audio/sfx/near_miss.wav"),
	"power_nitro": preload("res://assets/audio/sfx/power_nitro.wav"),
	"power_magnet": preload("res://assets/audio/sfx/power_magnet.wav"),
	"power_x2": preload("res://assets/audio/sfx/power_x2.wav"),
	"mission": preload("res://assets/audio/sfx/mission.wav"),
	"bump": preload("res://assets/audio/sfx/bump.wav"),
	"splash": preload("res://assets/audio/sfx/splash.wav"),
	"ice": preload("res://assets/audio/sfx/ice.wav"),
	"storm": preload("res://assets/audio/sfx/storm.wav"),
	"siren": preload("res://assets/audio/sfx/siren.wav"),
	"jump": preload("res://assets/audio/sfx/jump.wav"),
}
const ENGINE := preload("res://assets/audio/sfx/engine.wav")

const MUSIC_DB := -8.0
const POOL_SIZE := 12

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current_music: String = ""
var _gol_streams: Dictionary = {} # caminho -> AudioStream
var _pool: Array = []
var _next: int = 0
var _engine: AudioStreamPlayer
var _engine_on: bool = false
var _ui_quiet_until: float = 0.0
var _duck: float = 0.0 # abaixa a música na pausa
var _unlocked := not OS.has_feature("web") # navegador libera o som no 1º toque

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("Music")
	_make_bus("SFX")

	_music_a = _player("Music")
	_music_b = _player("Music")
	for p in [_music_a, _music_b]:
		p.finished.connect(_on_music_finished.bind(p))
	for i in range(POOL_SIZE):
		_pool.append(_player("SFX"))
	_engine = _player("SFX")
	_engine.stream = ENGINE
	_engine.volume_db = -80.0

	apply_settings()

func _make_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# Na web o som só é liberado no primeiro toque/clique. No celular (iPhone)
# a música que começou antes disso pode ficar muda, então ela recomeça
# do mesmo ponto quando o jogador solta o dedo pela primeira vez.
func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	var released: bool = (event is InputEventScreenTouch or event is InputEventMouseButton) and not event.pressed
	if not (released or (event is InputEventKey and event.pressed)):
		return
	_unlocked = true
	if _music_a.playing:
		_music_a.play(_music_a.get_playback_position())

# ---------- opções ----------

func music_on() -> bool:
	return bool(SaveManager.data.get("music_on", true))

func sfx_on() -> bool:
	return bool(SaveManager.data.get("sfx_on", true))

func toggle_music() -> void:
	SaveManager.data["music_on"] = not music_on()
	SaveManager.save()
	apply_settings()

func toggle_sfx() -> void:
	SaveManager.data["sfx_on"] = not sfx_on()
	SaveManager.save()
	apply_settings()

func apply_settings() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_on())
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not sfx_on())

# ---------- música ----------

func play_music(key: String, fade: float = 0.8) -> void:
	if key == _current_music and _music_a.playing:
		return
	_current_music = key
	_crossfade(MUSIC[key], fade)

# troca A <-> B com fade cruzado
func _crossfade(stream: AudioStream, fade: float) -> void:
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	_music_a.stream = stream
	_music_a.pitch_scale = 1.0
	_music_a.volume_db = -40.0
	_music_a.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(_music_a, "volume_db", MUSIC_DB, fade)
	if _music_b.playing:
		tw.tween_property(_music_b, "volume_db", -60.0, fade)
		tw.chain().tween_callback(_music_b.stop)

func stop_music(fade: float = 0.5) -> void:
	_current_music = ""
	var p := _music_a
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.stop)

# ---------- rádio ----------

func current_radio_track() -> String:
	var idx: int = int(SaveManager.data.get("radio_track", 0)) % RADIO_STATIONS.size()
	return String(RADIO_STATIONS[idx]["track"])

func current_radio_name() -> String:
	var idx: int = int(SaveManager.data.get("radio_track", 0)) % RADIO_STATIONS.size()
	return String(RADIO_STATIONS[idx]["name"])

func next_radio() -> String:
	var idx: int = (int(SaveManager.data.get("radio_track", 0)) + 1) % RADIO_STATIONS.size()
	SaveManager.data["radio_track"] = idx
	SaveManager.save()
	var station_name: String = RADIO_STATIONS[idx]["name"]
	var track: String = RADIO_STATIONS[idx]["track"]
	play_music(track, 0.5)
	return station_name

func play_race_music() -> void:
	if GameManager.selected_car().get("radio", false):
		play_gol_radio(int(SaveManager.data.get("gol_track", 0)), 0.8)
		return
	play_music(current_radio_track(), 0.8)

# ---------- rádio do Gol ----------

func play_gol_radio(idx: int, fade: float = 0.5) -> String:
	idx = posmod(idx, GOL_RADIO.size())
	SaveManager.data["gol_track"] = idx
	var path: String = GOL_RADIO[idx]["path"]
	if not _gol_streams.has(path):
		_gol_streams[path] = load(path)
	_current_music = "gol_%d" % idx
	_crossfade(_gol_streams[path], fade)
	return String(GOL_RADIO[idx]["name"])

func next_gol_track() -> String:
	var song := play_gol_radio(int(SaveManager.data.get("gol_track", 0)) + 1)
	SaveManager.save()
	return song

# música do Gol acabou: entra a próxima
func _on_music_finished(p: AudioStreamPlayer) -> void:
	if p == _music_a and _current_music.begins_with("gol_"):
		play_gol_radio(int(SaveManager.data.get("gol_track", 0)) + 1, 0.05)

# ---------- efeitos ----------

func play(key: String, volume_db: float = 0.0, pitch_var: float = 0.05, pitch: float = 1.0) -> void:
	if key.begins_with("ui_") and Time.get_ticks_msec() / 1000.0 < _ui_quiet_until:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = SFX[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
	p.play()

# Toca o efeito de buzina do jogador sem alterar os outros carros
func play_horn() -> void:
	play("horn", 1.0, 0.08)

# Efeito Doppler: som com queda de frequência simulando passagem rápida
func play_doppler(key: String = "whoosh", start_pitch: float = 1.35, end_pitch: float = 0.82, duration: float = 0.38) -> void:
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = SFX[key]
	p.volume_db = -2.0
	p.pitch_scale = start_pitch
	p.play()
	var tw := create_tween()
	tw.tween_property(p, "pitch_scale", end_pitch, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# evita o "tique" de foco que acontece sozinho ao abrir uma tela
func quiet_ui(seconds: float = 0.25) -> void:
	_ui_quiet_until = Time.get_ticks_msec() / 1000.0 + seconds

# ---------- motor ----------

func engine_start() -> void:
	_engine_on = true
	if not _engine.playing:
		_engine.play()

func engine_stop() -> void:
	_engine_on = false

func _process(delta: float) -> void:
	var paused := get_tree().paused
	_duck = move_toward(_duck, 1.0 if paused else 0.0, delta * 4.0)

	# música: abaixa na pausa e fica mais lenta/grave na câmera lenta
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -10.0 * _duck)
	if _music_a.playing and _current_music in LOOPING:
		var slow: float = 1.0 - GameManager.slow_factor if GameManager.running else 0.0
		_music_a.pitch_scale = lerp(_music_a.pitch_scale, 1.0 - slow * 0.35, 0.1)

	# motor: tom acompanha a velocidade
	var want: bool = _engine_on and GameManager.running and not GameManager.game_over and not paused
	var target_db := -14.0 if want else -80.0
	_engine.volume_db = move_toward(_engine.volume_db, target_db, delta * (60.0 if want else 120.0))
	if want:
		var frac: float = clamp((GameManager.speed - 150.0) / (GameManager.max_speed - 150.0), 0.0, 1.0)
		_engine.pitch_scale = 0.8 + frac * 1.1
	if _engine.playing and _engine.volume_db <= -79.0 and not _engine_on:
		_engine.stop()

func _exit_tree() -> void:
	# para tudo antes de fechar (evita aviso de recurso preso ao sair)
	for p in [_music_a, _music_b, _engine] + _pool:
		p.stop()
		p.stream = null
