extends Node2D

# Pista + cenários. Desenha o chão das laterais, o asfalto, as faixas e as
# decorações (prédios, árvores, cactos, mar, pinheiros, neon...) rolando
# na velocidade do jogo. O cenário muda com a distância e as cores se
# misturam suavemente na transição (ver GameManager.biome_state).

signal biome_changed(index: int)

const W := 480.0
const H := 720.0
const ROAD_L := 90.0
const ROAD_R := 390.0

var follow_game: bool = true # usa GameManager.distance_m como distância
var distance_scale: float = 1.0 # no menu os cenários passam mais rápido
var distance_m: float = 0.0
var scroll: float = 0.0
var time: float = 0.0
var decor: Array = []
var _gap_left: float = 0.0
var _gap_right: float = 0.0
var _last_biome: int = -1
var _bs: Array = [0, 1, 0.0]

func _ready() -> void:
	z_index = -10
	if follow_game:
		distance_m = GameManager.distance_m
	_bs =GameManager.biome_state(distance_m)
	_last_biome = _bs[0]
	# pré-popula a tela com decorações
	var y := -100.0
	while y < H + 100.0:
		_spawn_decor(true, y)
		_spawn_decor(false, y + randf_range(20, 60))
		y += randf_range(90, 150)

func _process(delta: float) -> void:
	time += delta
	if not GameManager.game_over:
		var px := GameManager.speed * delta
		scroll += px
		if follow_game:
			distance_m = GameManager.distance_m
		else:
			distance_m += px / GameManager.PX_PER_METER * distance_scale
		for d in decor:
			d["y"] += px * d.get("par", 1.0)
		decor = decor.filter(func(d): return d["y"] < H + 160.0)
		_gap_left -= px
		_gap_right -= px
		if _gap_left <= 0.0:
			_spawn_decor(true, -140.0)
		if _gap_right <= 0.0:
			_spawn_decor(false, -140.0)

	_bs = GameManager.biome_state(distance_m)
	var current: int = _bs[0] if _bs[2] < 0.5 else _bs[1]
	if current != _last_biome:
		_last_biome = current
		biome_changed.emit(current)
	queue_redraw()

func current_biome() -> int:
	return _last_biome

func _spawn_decor(left: bool, y: float) -> void:
	var bi: int = _bs[0] if _bs[2] < 0.5 else _bs[1]
	var biome: Dictionary = GameManager.biomes[bi]
	var kinds: Array = biome["decor_left"] if left else biome["decor_right"]
	var kind: String = kinds[randi() % kinds.size()]
	var x: float
	if left:
		x = randf_range(22, ROAD_L - 26)
	else:
		x = randf_range(ROAD_R + 26, W - 22)
	if kind in ["building", "neon_building"]:
		x = 44.0 if left else W - 44.0
	elif kind == "lamp" or kind == "neon_pole":
		x = ROAD_L - 14.0 if left else ROAD_R + 14.0
	var d := {"x": x, "y": y, "kind": kind, "seed": randi() % 1000, "left": left, "par": 1.0}
	if kind == "boat":
		d["par"] = 0.75
	decor.append(d)
	var gap := randf_range(70.0, 150.0)
	if kind in ["building", "neon_building"]:
		gap = randf_range(125.0, 150.0)
	if left:
		_gap_left = gap
	else:
		_gap_right = gap

# ---------- cores misturadas ----------

func _col(key: String) -> Color:
	var a: Color = GameManager.biomes[_bs[0]][key]
	var b: Color = GameManager.biomes[_bs[1]][key]
	return a.lerp(b, _bs[2])

func _weight(id: String) -> float:
	var w := 0.0
	if GameManager.biomes[_bs[0]]["id"] == id:
		w += 1.0 - _bs[2]
	if GameManager.biomes[_bs[1]]["id"] == id:
		w += _bs[2]
	return w

# ---------- desenho ----------

func _draw() -> void:
	var band := 60.0
	var off := fmod(scroll, band * 2.0)
	# laterais com faixas horizontais rolando
	draw_rect(Rect2(0, 0, ROAD_L, H), _col("left"))
	draw_rect(Rect2(ROAD_R, 0, W - ROAD_R, H), _col("right"))
	var y := -band * 2.0 + off
	while y < H:
		draw_rect(Rect2(0, y, ROAD_L, band), _col("left2"))
		draw_rect(Rect2(ROAD_R, y, W - ROAD_R, band), _col("right2"))
		y += band * 2.0

	_draw_sea(_weight("mar"))

	# calçada / acostamento
	var curb := _col("left").darkened(0.15)
	draw_rect(Rect2(ROAD_L - 10, 0, 10, H), curb)
	draw_rect(Rect2(ROAD_R, 0, 10, H), curb)

	# asfalto
	draw_rect(Rect2(ROAD_L, 0, ROAD_R - ROAD_L, H), _col("road"))

	# decorações
	for d in decor:
		_draw_decor(d)

	# linhas laterais (com brilho no cenário neon)
	var edge := _col("edge")
	var neon := _weight("neon")
	if neon > 0.0:
		var glow := Color(edge.r, edge.g, edge.b, 0.25 * neon)
		draw_rect(Rect2(ROAD_L - 8, 0, 14, H), glow)
		draw_rect(Rect2(ROAD_R - 6, 0, 14, H), glow)
	draw_rect(Rect2(ROAD_L - 2, 0, 5, H), edge)
	draw_rect(Rect2(ROAD_R - 3, 0, 5, H), edge)

	# faixas tracejadas
	var dash := _col("dash")
	var dash_off := fmod(scroll, 50.0)
	for dx in [190.0, 290.0]:
		var dy := -50.0 + dash_off
		while dy < H:
			if neon > 0.0:
				draw_rect(Rect2(dx - 6, dy - 3, 12, 34), Color(dash.r, dash.g, dash.b, 0.2 * neon))
			draw_rect(Rect2(dx - 3, dy, 6, 28), dash)
			dy += 50.0

	_draw_snowfall(_weight("neve"))

func _draw_sea(w: float) -> void:
	if w <= 0.01:
		return
	# espuma na beira e ondinhas
	var foam := Color(1, 1, 1, 0.75 * w)
	var pts := PackedVector2Array()
	var y := -20.0
	while y <= H + 20.0:
		pts.append(Vector2(ROAD_R + 22 + sin((y + scroll) * 0.04 + time * 2.0) * 4.0, y))
		y += 12.0
	draw_polyline(pts, foam, 4.0, true)
	draw_rect(Rect2(ROAD_R + 10, 0, 12, H), Color(0.93, 0.84, 0.62, w))
	var wave := Color(1, 1, 1, 0.35 * w)
	for i in range(9):
		var wy := fmod(i * 97.0 + scroll * 0.75, H + 60.0) - 30.0
		var wx := ROAD_R + 40.0 + fmod(i * 37.0, 45.0)
		draw_arc(Vector2(wx, wy), 8, PI * 1.1, PI * 1.9, 8, wave, 2.0, true)

func _draw_snowfall(w: float) -> void:
	if w <= 0.01:
		return
	for i in range(70):
		var sx := fmod(i * 73.3 + sin(time * 0.8 + i) * 12.0, W)
		var sy := fmod(i * 131.7 + time * (50.0 + (i % 5) * 18.0) + scroll * 0.35, H)
		draw_circle(Vector2(sx, sy), 1.5 + (i % 3) * 0.7, Color(1, 1, 1, 0.85 * w))

func _draw_decor(d: Dictionary) -> void:
	var p := Vector2(d["x"], d["y"])
	var s: int = d["seed"]
	match d["kind"]:
		"building":
			var cols := [Color(0.55, 0.38, 0.32), Color(0.32, 0.38, 0.5), Color(0.6, 0.58, 0.52), Color(0.38, 0.45, 0.4)]
			var c: Color = cols[s % cols.size()]
			var size := Vector2(70, 100 + s % 20)
			var r := Rect2(p - size * 0.5, size)
			draw_rect(Rect2(r.position + Vector2(5, 8), r.size), Color(0, 0, 0, 0.3))
			draw_rect(r, c)
			draw_rect(r.grow(-6), c.lightened(0.12))
			for i in range(3):
				draw_rect(Rect2(r.position + Vector2(12 + i * 17, 14), Vector2(10, 10)), c.darkened(0.25))
			if s % 2 == 0:
				draw_circle(r.get_center() + Vector2(0, 20), 9, Color(0.75, 0.75, 0.78))
		"lamp":
			draw_circle(p + Vector2(2, 3), 5, Color(0, 0, 0, 0.3))
			draw_circle(p, 4, Color(0.3, 0.3, 0.32))
			draw_circle(p, 2, Color(1, 0.95, 0.7))
		"tree":
			var g := Color(0.1, 0.35 + (s % 10) * 0.012, 0.12)
			draw_circle(p + Vector2(4, 6), 18, Color(0, 0, 0, 0.25))
			draw_circle(p, 18, g)
			draw_circle(p + Vector2(-4, -4), 12, g.lightened(0.12))
			draw_circle(p + Vector2(-6, -7), 5, g.lightened(0.25))
		"bush":
			draw_circle(p, 9, Color(0.14, 0.4, 0.15))
			draw_circle(p + Vector2(8, 3), 7, Color(0.16, 0.45, 0.17))
			if s % 3 == 0:
				draw_circle(p + Vector2(2, -2), 2, Color(1, 0.4, 0.5))
		"hay":
			draw_circle(p + Vector2(3, 4), 12, Color(0, 0, 0, 0.2))
			draw_circle(p, 12, Color(0.9, 0.75, 0.35))
			draw_arc(p, 7, 0, TAU, 16, Color(0.75, 0.6, 0.25), 2.0)
		"cactus":
			var g := Color(0.25, 0.55, 0.25)
			draw_rect(Rect2(p + Vector2(-2, 10), Vector2(16, 6)), Color(0, 0, 0, 0.2))
			draw_rect(Rect2(p + Vector2(-5, -22), Vector2(10, 36)), g)
			draw_circle(p + Vector2(0, -22), 5, g)
			draw_rect(Rect2(p + Vector2(-15, -8), Vector2(10, 6)), g)
			draw_rect(Rect2(p + Vector2(-15, -18), Vector2(6, 12)), g)
			draw_rect(Rect2(p + Vector2(5, -4), Vector2(9, 6)), g)
			draw_rect(Rect2(p + Vector2(9, -14), Vector2(5, 12)), g)
			draw_line(p + Vector2(0, -24), p + Vector2(0, 12), g.lightened(0.2), 1.5)
		"rock":
			draw_circle(p + Vector2(3, 4), 10, Color(0, 0, 0, 0.2))
			draw_circle(p, 10, Color(0.55, 0.42, 0.3))
			draw_circle(p + Vector2(-3, -3), 5, Color(0.65, 0.52, 0.38))
		"tumbleweed":
			var spin := time * 3.0 + s
			draw_arc(p, 8, spin, spin + TAU, 10, Color(0.6, 0.45, 0.25), 2.0)
			draw_arc(p, 5, -spin, -spin + PI * 1.5, 8, Color(0.55, 0.4, 0.2), 1.5)
		"palm":
			draw_circle(p + Vector2(5, 7), 16, Color(0, 0, 0, 0.2))
			for i in range(6):
				var a := i * TAU / 6.0 + s
				var tip := p + Vector2(cos(a), sin(a)) * 20.0
				var side := Vector2(-sin(a), cos(a)) * 5.0
				draw_colored_polygon(PackedVector2Array([p, p + Vector2(cos(a), sin(a)) * 10.0 + side, tip]), Color(0.15, 0.55, 0.2))
			draw_circle(p, 4, Color(0.45, 0.3, 0.15))
		"umbrella":
			var cols := [Color(0.95, 0.25, 0.25), Color(0.2, 0.6, 0.95), Color(1, 0.75, 0.1)]
			var c: Color = cols[s % 3]
			draw_circle(p + Vector2(4, 5), 14, Color(0, 0, 0, 0.2))
			draw_circle(p, 14, c)
			for i in range(4):
				var a := i * TAU / 4.0 + 0.4
				draw_line(p, p + Vector2(cos(a), sin(a)) * 14.0, Color(1, 1, 1, 0.9), 2.0)
			draw_rect(Rect2(p + Vector2(10, 10), Vector2(16, 8)), Color(1, 1, 1, 0.8))
		"boat":
			var hull := PackedVector2Array([p + Vector2(0, -18), p + Vector2(8, -6), p + Vector2(7, 14), p + Vector2(-7, 14), p + Vector2(-8, -6)])
			draw_colored_polygon(hull, Color(0.95, 0.95, 0.95))
			draw_rect(Rect2(p + Vector2(-4, -2), Vector2(8, 10)), Color(0.6, 0.35, 0.2))
			draw_line(p + Vector2(-6, 18), p + Vector2(0, 30), Color(1, 1, 1, 0.5), 2.0)
			draw_line(p + Vector2(6, 18), p + Vector2(0, 30), Color(1, 1, 1, 0.5), 2.0)
		"buoy":
			var bob := sin(time * 3.0 + s) * 1.5
			draw_circle(p, 6 + bob, Color(1, 1, 1, 0.3))
			draw_circle(p, 5, Color(1, 0.35, 0.1))
			draw_circle(p, 2, Color(1, 1, 1))
		"wave":
			draw_arc(p, 10, PI * 1.1, PI * 1.9, 10, Color(1, 1, 1, 0.6), 2.5, true)
		"pine":
			draw_circle(p + Vector2(5, 7), 16, Color(0.2, 0.25, 0.35, 0.25))
			for i in range(3):
				var r := 18.0 - i * 5.0
				var pts := PackedVector2Array()
				for k in range(16):
					var a := k * TAU / 16.0
					var rr := r if k % 2 == 0 else r * 0.65
					pts.append(p + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(pts, Color(0.1, 0.32 + i * 0.06, 0.2))
			draw_circle(p + Vector2(-3, -3), 4, Color(1, 1, 1, 0.9))
			draw_circle(p + Vector2(6, 4), 3, Color(1, 1, 1, 0.8))
		"snowrock":
			draw_circle(p, 10, Color(0.5, 0.52, 0.58))
			draw_circle(p + Vector2(-2, -3), 7, Color(0.97, 0.98, 1))
		"neon_building":
			var neon_cols := [Color(1, 0.2, 0.8), Color(0.2, 0.95, 1), Color(0.6, 0.3, 1), Color(1, 0.85, 0.2)]
			var c: Color = neon_cols[s % neon_cols.size()]
			var size := Vector2(68, 100 + s % 25)
			var r := Rect2(p - size * 0.5, size)
			draw_rect(r, Color(0.09, 0.07, 0.15))
			var pulse := 0.6 + 0.4 * sin(time * 3.0 + s)
			draw_rect(r.grow(3), Color(c.r, c.g, c.b, 0.18 * pulse), false, 6.0)
			draw_rect(r, c, false, 2.0)
			for i in range(4):
				for k in range(3):
					if (s + i * 3 + k) % 3 != 0:
						draw_rect(Rect2(r.position + Vector2(10 + k * 18, 12 + i * 22), Vector2(10, 8)), Color(c.r, c.g, c.b, 0.55))
		"neon_pole":
			var c := Color(0.2, 0.95, 1) if s % 2 == 0 else Color(1, 0.2, 0.8)
			draw_circle(p, 12, Color(c.r, c.g, c.b, 0.15 + 0.1 * sin(time * 5.0 + s)))
			draw_circle(p, 4, c)
