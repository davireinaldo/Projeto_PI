extends Node2D

# Clima de cada cenário, desenhado por cima dos carros (z 14):
#   cidade  -> chuva com respingos (os reflexos no asfalto molhado ficam no World)
#   deserto -> areia voando e, de vez em quando, TEMPESTADE DE AREIA:
#              a parte de cima da tela some na poeira por alguns segundos
#   neve    -> neve caindo
# As tempestades só acontecem na corrida (storms = true).

signal storm_started
signal storm_survived

const W := 480.0
const H := 720.0
const STORM_TIME := 7.0
const SAND := Color(0.82, 0.62, 0.36)

var world: Node2D
var storms: bool = false
var storm: float = 0.0 # força da tempestade agora (0..1)
var _storm_left: float = 0.0
var _storm_cd: float = 5.0

func _ready() -> void:
	z_index = 14

func _process(delta: float) -> void:
	var desert: float = world.weight("deserto")
	if storms and GameManager.running and not GameManager.game_over:
		if _storm_left > 0.0:
			_storm_left -= delta
			if _storm_left <= 0.0:
				storm_survived.emit()
		elif desert > 0.9:
			_storm_cd -= delta
			if _storm_cd <= 0.0:
				_storm_left = STORM_TIME
				_storm_cd = randf_range(14.0, 22.0)
				storm_started.emit()
		else:
			_storm_cd = 5.0 # a primeira vem logo depois de entrar no deserto
	var target := 1.0 if _storm_left > 1.0 else 0.0
	storm = move_toward(storm, target, delta * (0.7 if target > storm else 1.0))
	queue_redraw()

func _draw() -> void:
	var t: float = world.time
	_draw_rain(world.weight("cidade"), t)
	_draw_sand(world.weight("deserto"), t)
	_draw_snow(world.weight("neve"), t)
	_draw_storm(storm, t)

func _draw_rain(w: float, t: float) -> void:
	if w <= 0.01:
		return
	draw_rect(Rect2(0, 0, W, H), Color(0.12, 0.14, 0.25, 0.12 * w))
	for i in range(110):
		var sp := 900.0 + (i % 4) * 140.0
		var y := fmod(i * 137.3 + t * sp, H + 60.0) - 30.0
		var x := fposmod(i * 71.9 - y * 0.22, W + 40.0) - 20.0
		var a := (0.22 + (i % 3) * 0.08) * w
		draw_line(Vector2(x, y), Vector2(x - 5.0, y + 22.0), Color(0.78, 0.85, 1.0, a), 1.2)
	# respingos no chão
	for i in range(22):
		var ph := fmod(t * 2.3 + i * 0.371, 1.0)
		var x := 20.0 + fmod(i * 97.7, W - 40.0)
		var y := fmod(i * 211.3 + floor(t * 2.3 + i * 0.371) * 53.0, H)
		draw_arc(Vector2(x, y), 2.0 + ph * 7.0, PI, TAU, 8, Color(0.85, 0.9, 1.0, 0.4 * (1.0 - ph) * w), 1.2)

func _draw_sand(w: float, t: float) -> void:
	if w <= 0.01:
		return
	draw_rect(Rect2(0, 0, W, H), Color(SAND.r, SAND.g, SAND.b, 0.06 * w))
	for i in range(45):
		var sp := 260.0 + (i % 5) * 70.0
		var x := fmod(i * 83.1 + t * sp, W + 80.0) - 40.0
		var y := fmod(i * 157.9 + t * (60.0 + (i % 3) * 30.0) + world.scroll * 0.3, H)
		draw_line(Vector2(x, y), Vector2(x + 12.0 + (i % 4) * 4.0, y + 2.0), Color(0.95, 0.8, 0.55, 0.35 * w), 1.5)

func _draw_snow(w: float, t: float) -> void:
	if w <= 0.01:
		return
	for i in range(80):
		var sx := fposmod(i * 73.3 + sin(t * 0.8 + i) * 12.0, W)
		var sy := fmod(i * 131.7 + t * (50.0 + (i % 5) * 18.0) + world.scroll * 0.35, H)
		draw_circle(Vector2(sx, sy), 1.5 + (i % 3) * 0.7, Color(1, 1, 1, 0.85 * w))

func _draw_storm(s: float, t: float) -> void:
	if s <= 0.01:
		return
	# poeira mais grossa em cima: dá para ver só o que está perto do carro
	# (degradê com cor por vértice)
	var dust := Color(0.66, 0.44, 0.22)
	var stops := [[0.0, 0.97], [0.35, 0.88], [0.62, 0.45], [1.0, 0.22]]
	for i in range(stops.size() - 1):
		var y0: float = stops[i][0] * H
		var y1: float = stops[i + 1][0] * H
		var c0 := Color(dust.r, dust.g, dust.b, s * float(stops[i][1]))
		var c1 := Color(dust.r, dust.g, dust.b, s * float(stops[i + 1][1]))
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(W, y0), Vector2(W, y1), Vector2(0, y1)]),
			PackedColorArray([c0, c0, c1, c1]))
	# nuvens de poeira rolando (claras e escuras)
	for i in range(8):
		var x := fmod(i * 131.0 + t * (120.0 + i * 25.0), W + 300.0) - 150.0
		var y := 40.0 + fmod(i * 97.0, 460.0) + sin(t * 1.3 + i) * 20.0
		var c := Color(0.9, 0.72, 0.45) if i % 2 == 0 else Color(0.45, 0.28, 0.12)
		world.draw_soft(self, Vector2(x, y), 90.0 + (i % 3) * 30.0, Color(c.r, c.g, c.b, 0.4 * s))
	for i in range(110):
		var x := fmod(i * 59.3 + t * (500.0 + (i % 6) * 90.0), W + 60.0) - 30.0
		var y := fmod(i * 113.7 + t * 40.0, H)
		var c := Color(0.95, 0.8, 0.55) if i % 3 == 0 else Color(0.42, 0.28, 0.14)
		draw_line(Vector2(x, y), Vector2(x + 22.0, y + 3.0), Color(c.r, c.g, c.b, 0.6 * s), 2.0)
