extends Node2D

# Pista + cenários. Desenha o chão das laterais, o asfalto, as faixas e as
# decorações (prédios, árvores, cactos, mar, pinheiros, neon...) rolando
# na velocidade do jogo. O cenário muda com a distância e as cores se
# misturam suavemente na transição (ver GameManager.biome_state).
#
# Profundidade: prédios, postes e copas são desenhados em perspectiva
# (o topo se afasta do ponto de fuga VP), as sombras mudam com a hora do
# dia, o chão tem detalhes e sombras de nuvens passam mais devagar.
# Com day_night ligado, a camada "Glow" desenha o que brilha à noite
# (janelas, postes, neon) por cima da escuridão do Lighting.

signal biome_changed(index: int)

const W := 480.0
const H := 720.0
# bordas do asfalto: 90 e 390 com 3 faixas; a pista do versus (5) é mais larga
var ROAD_L := 90.0
var ROAD_R := 390.0
var _side_k := 1.0 # largura das laterais em relação às de 3 faixas
const VP := Vector2(240, 430) # ponto de fuga da perspectiva

var follow_game: bool = true # usa GameManager.distance_m como distância
var distance_scale: float = 1.0 # no menu os cenários passam mais rápido
var day_night: bool = false # usa o ciclo de dia e noite (corrida e menu)
var distance_m: float = 0.0
var scroll: float = 0.0
var time: float = 0.0
var decor: Array = []
var _gap_left: float = 0.0
var _gap_right: float = 0.0
var _last_biome: int = -1
var _bs: Array = [0, 1, 0.0]
var _sky: Vector2 = Vector2.ZERO
var _glow: Node2D

# Camada do que brilha à noite (fica acima da escuridão).
class Glow extends Node2D:
	var world: Node2D
	func _draw() -> void:
		world._draw_glow(self)

func _ready() -> void:
	z_index = -10
	var edges := GameManager.road_edges()
	ROAD_L = edges.x
	ROAD_R = edges.y
	_side_k = ROAD_L / 90.0
	if follow_game:
		distance_m = GameManager.distance_m
	_bs = GameManager.biome_state(distance_m)
	_last_biome = _bs[0]
	_glow = Glow.new()
	_glow.world = self
	_glow.z_index = 26 # -10 + 26 = 16, acima do Lighting (15)
	add_child(_glow)
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
	_sky = GameManager.sky(distance_m) if day_night else Vector2.ZERO
	var current: int = _bs[0] if _bs[2] < 0.5 else _bs[1]
	if current != _last_biome:
		_last_biome = current
		biome_changed.emit(current)
	queue_redraw()
	_glow.visible = _sky.x > 0.01
	if _glow.visible:
		_glow.queue_redraw()

func current_biome() -> int:
	return _last_biome

# Vector2(noite, pôr do sol); zero se o ciclo de dia e noite está desligado
func sky() -> Vector2:
	return _sky

func weight(id: String) -> float:
	return _weight(id)

func _spawn_decor(left: bool, y: float) -> void:
	var bi: int = _bs[0] if _bs[2] < 0.5 else _bs[1]
	var biome: Dictionary = GameManager.biomes[bi]
	var kinds: Array = biome["decor_left"] if left else biome["decor_right"]
	var kind: String = kinds[randi() % kinds.size()]
	var x: float
	if left:
		x = randf_range(22 * _side_k, ROAD_L - 26 * _side_k)
	else:
		x = randf_range(ROAD_R + 26 * _side_k, W - 22 * _side_k)
	if kind in ["building", "neon_building"]:
		x = 44.0 * _side_k if left else W - 44.0 * _side_k
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

# Luzes para o Lighting: [posição, raio, cor, intensidade]
func light_sources() -> Array:
	var out: Array = []
	for d in decor:
		var p := Vector2(d["x"], d["y"])
		if d["kind"] == "lamp":
			out.append([_top(p, 0.12), 85.0, Color(1, 0.85, 0.55), 0.8])
		elif d["kind"] == "neon_pole":
			var c := Color(0.2, 0.95, 1) if d["seed"] % 2 == 0 else Color(1, 0.2, 0.8)
			out.append([_top(p, 0.12), 75.0, c, 0.7])
	# na Cidade Neon as linhas da pista iluminam o asfalto
	var neon := _weight("neon")
	if neon > 0.2:
		var edge := _col("edge")
		for i in range(4):
			var y := fmod(i * 190.0 + scroll, 760.0) - 20.0
			out.append([Vector2(ROAD_L, y), 95.0, edge, 0.45 * neon])
			out.append([Vector2(ROAD_R, y + 95.0), 95.0, edge, 0.45 * neon])
	return out

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

# ---------- perspectiva e sombras ----------

# topo de algo com "altura" h, visto de cima: se afasta do ponto de fuga
func _top(p: Vector2, h: float) -> Vector2:
	return p + (p - VP) * h

# direção/tamanho da sombra: curta de dia, comprida no pôr do sol
func _shadow_vec() -> Vector2:
	return Vector2(7, 11).lerp(Vector2(24, 14), _sky.y)

# força da sombra (some à noite)
func _shadow_a() -> float:
	return 1.0 - 0.75 * _sky.x

func _rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

func _hull(a: Rect2, off: Vector2) -> PackedVector2Array:
	var pts := _rect_pts(a)
	pts.append_array(_rect_pts(Rect2(a.position + off, a.size)))
	return Geometry2D.convex_hull(pts)

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

	_draw_ground_details()
	_draw_sea(_weight("mar"))

	# calçada / acostamento
	var curb := _col("left").darkened(0.15)
	draw_rect(Rect2(ROAD_L - 10, 0, 10, H), curb)
	draw_rect(Rect2(ROAD_R, 0, 10, H), curb)

	# asfalto
	draw_rect(Rect2(ROAD_L, 0, ROAD_R - ROAD_L, H), _col("road"))
	_draw_asphalt_texture()

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
	for i in range(GameManager.lane_count - 1):
		var dx: float = (GameManager.LANES[i] + GameManager.LANES[i + 1]) * 0.5
		var dy := -50.0 + dash_off
		while dy < H:
			if neon > 0.0:
				draw_rect(Rect2(dx - 6, dy - 3, 12, 34), Color(dash.r, dash.g, dash.b, 0.2 * neon))
			draw_rect(Rect2(dx - 3, dy, 6, 28), dash)
			dy += 50.0

	_draw_wet_road(_weight("cidade"))

	# decorações: primeiro as sombras, depois as coisas (sombra não cobre vizinho)
	for d in decor:
		_draw_decor_shadow(d)
	for d in decor:
		_draw_decor(d)

	_draw_cloud_shadows()

# textura leve no asfalto (manchas e remendos rolando junto)
func _draw_asphalt_texture() -> void:
	var step := 70.0
	var k0 := int(floor(-scroll / step)) - 1
	var k1 := int(floor((H - scroll) / step)) + 1
	for k in range(k0, k1 + 1):
		var h := _hash(k)
		var y := k * step + scroll
		var x := ROAD_L + 14.0 + h * (ROAD_R - ROAD_L - 28.0)
		if int(h * 100.0) % 3 == 0:
			draw_rect(Rect2(x - 12, y, 24, 14), Color(0, 0, 0, 0.08))
		else:
			draw_circle(Vector2(x, y), 3.0 + h * 4.0, Color(1, 1, 1, 0.025))

# detalhes no chão das laterais, por cenário
func _draw_ground_details() -> void:
	var step := 46.0
	var k0 := int(floor((-60.0 - scroll) / step))
	var k1 := int(floor((H + 60.0 - scroll) / step))
	var wc := _weight("cidade")
	var wf := _weight("campo")
	var wd := _weight("deserto")
	var wm := _weight("mar")
	var wn := _weight("neve")
	var wneon := _weight("neon")
	for k in range(k0, k1 + 1):
		var y := k * step + scroll
		for side in [0, 1]:
			var h := _hash(k * 2 + side)
			var x0 := 6.0 if side == 0 else ROAD_R + 16.0
			var x1 := ROAD_L - 16.0 if side == 0 else W - 6.0
			var x := lerpf(x0, x1, h)
			if wc > 0.01:
				# placas da calçada
				draw_line(Vector2(x0 - 6, y), Vector2(x1 + 6, y), Color(0, 0, 0, 0.1 * wc), 1.0)
				if h > 0.8:
					draw_polyline(PackedVector2Array([Vector2(x, y + 6), Vector2(x + 5, y + 14), Vector2(x + 2, y + 22)]),
						Color(0, 0, 0, 0.18 * wc), 1.0)
			if wf > 0.01:
				var g := Color(0.08, 0.3, 0.1, 0.6 * wf)
				for j in range(3):
					var bx := x + j * 4.0 - 4.0
					draw_line(Vector2(bx, y + 8), Vector2(bx + (j - 1) * 2.0, y), g, 1.5)
				if h > 0.6:
					draw_circle(Vector2(lerpf(x0, x1, fmod(h * 7.3, 1.0)), y + 24), 2.0,
						Color(1, 0.9, 0.3, 0.8 * wf) if h > 0.8 else Color(1, 1, 1, 0.8 * wf))
			if wd > 0.01:
				var c := Color(0.7, 0.55, 0.32, 0.45 * wd)
				draw_arc(Vector2(x, y), 9, PI * 1.15, PI * 1.85, 6, c, 1.5)
				draw_arc(Vector2(x + 6, y + 6), 9, PI * 1.15, PI * 1.85, 6, c, 1.5)
				if h > 0.7:
					draw_circle(Vector2(x - 8, y + 18), 2.5, Color(0.55, 0.42, 0.3, 0.8 * wd))
			if wm > 0.01 and side == 0:
				if h > 0.55:
					draw_circle(Vector2(x, y + 10), 2.5, Color(1, 0.92, 0.85, 0.9 * wm))
					draw_arc(Vector2(x, y + 10), 2.5, PI, TAU, 6, Color(0.85, 0.6, 0.5, 0.9 * wm), 1.0)
				draw_circle(Vector2(x0 + 30 + sin(k * 1.7) * 6.0, y), 2.0, Color(0.7, 0.6, 0.4, 0.4 * wm))
			if wn > 0.01:
				draw_circle(Vector2(x, y + 10), 10 + h * 6.0, Color(1, 1, 1, 0.55 * wn))
				draw_circle(Vector2(x + 6, y + 6), 6 + h * 3.0, Color(0.8, 0.86, 0.95, 0.5 * wn))
			if wneon > 0.01:
				draw_line(Vector2(x0 - 6, y), Vector2(x1 + 6, y), Color(0.6, 0.3, 1, 0.12 * wneon), 1.0)
				draw_line(Vector2(x, y), Vector2(x, y + step), Color(0.2, 0.9, 1, 0.08 * wneon), 1.0)

# sombras de nuvens altas, passando mais devagar que o chão
func _draw_cloud_shadows() -> void:
	var a := 0.09 * (1.0 - _sky.x) * (1.0 - _weight("neon")) * (1.0 - 0.6 * _weight("cidade"))
	if a <= 0.005:
		return
	for i in range(3):
		var cy := fmod(i * 420.0 + scroll * 0.55, H + 600.0) - 300.0
		var cx := fmod(i * 170.0 + time * 10.0, W + 360.0) - 180.0
		for j in range(4):
			var o := Vector2(cos(i * 2.1 + j * 1.6) * 60.0, sin(i * 1.7 + j * 2.2) * 45.0)
			draw_soft(self, Vector2(cx, cy) + o, 80.0 + j * 12.0, Color(0, 0, 0.05, a))

# círculo com borda esfumaçada (centro na cor, borda transparente)
static func draw_soft(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var edge := Color(col.r, col.g, col.b, 0.0)
	var colors := PackedColorArray([col, edge, edge])
	var seg := 18
	for k in range(seg):
		var a0 := k * TAU / seg
		var a1 := (k + 1) * TAU / seg
		ci.draw_primitive(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
			colors, PackedVector2Array())

# asfalto molhado: brilho em faixas e reflexo dos carros e postes
func _draw_wet_road(w: float) -> void:
	if w <= 0.01:
		return
	for i in range(6):
		var x := ROAD_L + 18.0 + i * 50.0
		draw_rect(Rect2(x, 0, 10, H), Color(0.8, 0.85, 1, 0.03 * w))
	var bodies: Array = get_tree().get_nodes_in_group("traffic") + get_tree().get_nodes_in_group("player")
	for t in bodies:
		if t.is_in_group("obstacles") or not t.visible:
			continue
		var len: float = t.length if "length" in t else 64.0
		var c: Color = t.visual.body_color
		var p: Vector2 = t.position
		for i in range(4):
			var f := i / 4.0
			draw_rect(Rect2(p.x - 15 + i * 2, p.y + len * 0.5 + i * len * 0.22, 30 - i * 4, len * 0.22),
				Color(c.r, c.g, c.b, 0.16 * w * (1.0 - f)))
		for sx in [-10.0, 10.0]:
			draw_rect(Rect2(p.x + sx - 2, p.y + len * 0.5, 4, 46), Color(1, 0.15, 0.1, 0.28 * w))
	for d in decor:
		if d["kind"] == "lamp":
			var x := ROAD_L + 6.0 if d["left"] else ROAD_R - 14.0
			draw_rect(Rect2(x, d["y"] - 6, 8, 70), Color(1, 0.85, 0.5, 0.12 * w * (0.4 + _sky.x)))

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

# ---------- prédios em perspectiva ----------

func _building_geom(d: Dictionary) -> Dictionary:
	var p := Vector2(d["x"], d["y"])
	var s: int = d["seed"]
	var size := Vector2((68 if d["kind"] == "neon_building" else 70) * _side_k, 100 + s % (25 if d["kind"] == "neon_building" else 20))
	var h := 0.1 + (s % 4) * 0.035
	var base := Rect2(p - size * 0.5, size)
	return {"base": base, "off": (p - VP) * h, "h": h}

func _draw_building_shadow(d: Dictionary) -> void:
	var g := _building_geom(d)
	var sv: Vector2 = _shadow_vec() * (1.0 + float(g["h"]) * 9.0)
	draw_colored_polygon(_hull(g["base"], sv), Color(0, 0, 0, 0.28 * _shadow_a()))

func _draw_building(d: Dictionary) -> void:
	var g := _building_geom(d)
	var base: Rect2 = g["base"]
	var off: Vector2 = g["off"]
	var s: int = d["seed"]
	var cols := [Color(0.55, 0.38, 0.32), Color(0.32, 0.38, 0.5), Color(0.6, 0.58, 0.52), Color(0.38, 0.45, 0.4)]
	var c: Color = cols[s % cols.size()]
	# paredes (o que aparece entre a base e o telhado)
	draw_colored_polygon(_hull(base, off), c.darkened(0.38))
	# andares e janelas na parede virada para a pista
	for k in range(1, 4):
		var t := k / 4.0
		draw_rect(Rect2(base.position + off * t, base.size), c.darkened(0.5), false, 1.0)
	for wp in _window_points(base, off, s):
		draw_rect(Rect2(wp[0] - Vector2(1.5, 3), Vector2(3, 6)), Color(0.35, 0.5, 0.65, 0.9))
	# telhado
	var roof := Rect2(base.position + off, base.size)
	draw_rect(roof, c)
	draw_rect(roof.grow(-5), c.lightened(0.12))
	draw_rect(roof.grow(-5), c.darkened(0.2), false, 1.0)
	var rp := roof.position
	# casinhas de máquinas / ar-condicionado
	draw_rect(Rect2(rp + Vector2(10, 12), Vector2(16, 12)), c.darkened(0.15))
	draw_rect(Rect2(rp + Vector2(10, 12), Vector2(16, 12)), c.darkened(0.35), false, 1.0)
	if s % 3 != 0:
		draw_rect(Rect2(rp + Vector2(42, 16 + s % 30), Vector2(12, 10)), Color(0.7, 0.72, 0.75))
		draw_line(rp + Vector2(44, 21 + s % 30), rp + Vector2(52, 21 + s % 30), Color(0.4, 0.42, 0.45), 1.0)
	if s % 2 == 0:
		draw_circle(roof.get_center() + Vector2(0, 26), 9, Color(0.75, 0.75, 0.78))
		draw_arc(roof.get_center() + Vector2(0, 26), 9, 0, TAU, 16, Color(0.5, 0.5, 0.55), 1.5)
	elif s % 5 == 1:
		# heliponto
		var hc := roof.get_center() + Vector2(0, 20)
		draw_arc(hc, 14, 0, TAU, 20, Color(1, 0.85, 0.2), 2.0)
		draw_string(preload("res://scripts/UIKit.gd").font(), hc + Vector2(-5, 6), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

# Janelas na parede virada para a pista: [posição, acesa à noite?]
func _window_points(base: Rect2, off: Vector2, s: int) -> Array:
	var out: Array = []
	if abs(off.x) < 6.0:
		return out
	var wall_x := base.end.x if off.x < 0.0 else base.position.x
	for k in range(3):
		var t := 0.2 + k * 0.27
		for j in range(4):
			var p := Vector2(wall_x + off.x * t, base.position.y + off.y * t + (j + 0.5) * base.size.y / 4.0)
			out.append([p, (s + k * 7 + j * 3) % 5 < 3])
	return out

func _draw_neon_building(d: Dictionary) -> void:
	var g := _building_geom(d)
	var base: Rect2 = g["base"]
	var off: Vector2 = g["off"]
	var s: int = d["seed"]
	var c := _neon_color(s)
	draw_colored_polygon(_hull(base, off), Color(0.05, 0.04, 0.09))
	for wp in _window_points(base, off, s):
		if wp[1]:
			draw_rect(Rect2(wp[0] - Vector2(1.5, 3), Vector2(3, 6)), Color(c.r, c.g, c.b, 0.5))
	var r := Rect2(base.position + off, base.size)
	draw_rect(r, Color(0.09, 0.07, 0.15))
	var pulse := 0.6 + 0.4 * sin(time * 3.0 + s)
	draw_rect(r.grow(3), Color(c.r, c.g, c.b, 0.18 * pulse), false, 6.0)
	draw_rect(r, c, false, 2.0)
	# arestas verticais visíveis
	for corner in _rect_pts(base):
		draw_line(corner, corner + off, Color(c.r, c.g, c.b, 0.35), 1.0)
	for i in range(4):
		for k in range(3):
			if (s + i * 3 + k) % 3 != 0:
				draw_rect(Rect2(r.position + Vector2(10 + k * 18, 12 + i * 22), Vector2(10, 8)), Color(c.r, c.g, c.b, 0.55))

func _neon_color(s: int) -> Color:
	var neon_cols := [Color(1, 0.2, 0.8), Color(0.2, 0.95, 1), Color(0.6, 0.3, 1), Color(1, 0.85, 0.2)]
	return neon_cols[s % neon_cols.size()]

# ---------- decorações ----------

func _draw_decor_shadow(d: Dictionary) -> void:
	var p := Vector2(d["x"], d["y"])
	var sv := _shadow_vec()
	var sa := _shadow_a()
	match d["kind"]:
		"building", "neon_building":
			_draw_building_shadow(d)
		"tree":
			draw_circle(p + sv * 1.3, 18, Color(0, 0, 0, 0.25 * sa))
		"pine":
			draw_circle(p + sv * 1.6, 16, Color(0.2, 0.25, 0.35, 0.28 * sa))
		"palm":
			draw_line(p, p + sv * 2.2, Color(0, 0, 0, 0.2 * sa), 3.0)
			draw_circle(p + sv * 2.2, 15, Color(0, 0, 0, 0.18 * sa))
		"lamp", "neon_pole":
			draw_line(p, p + sv * 2.4, Color(0, 0, 0, 0.25 * sa), 2.0)
		"cactus":
			draw_line(p + Vector2(0, 10), p + Vector2(0, 10) + sv * 2.4, Color(0, 0, 0, 0.22 * sa), 8.0)
		"hay", "rock", "snowrock", "umbrella":
			draw_circle(p + sv * 0.6, 12, Color(0, 0, 0, 0.2 * sa))

func _draw_decor(d: Dictionary) -> void:
	var p := Vector2(d["x"], d["y"])
	var s: int = d["seed"]
	match d["kind"]:
		"building":
			_draw_building(d)
		"lamp":
			var top := _top(p, 0.12)
			draw_circle(p, 3, Color(0.25, 0.25, 0.28))
			draw_line(p, top, Color(0.35, 0.35, 0.38), 2.5)
			draw_circle(top, 4, Color(0.3, 0.3, 0.32))
			draw_circle(top, 2, Color(1, 0.95, 0.7))
		"tree":
			var g := Color(0.1, 0.35 + (s % 10) * 0.012, 0.12)
			var top := _top(p, 0.04)
			draw_circle(p, 5, Color(0.3, 0.2, 0.1))
			draw_circle(top, 18, g)
			draw_circle(top + Vector2(-4, -4), 12, g.lightened(0.12))
			draw_circle(_top(p, 0.07) + Vector2(-6, -7), 5, g.lightened(0.25))
		"bush":
			draw_circle(p, 9, Color(0.14, 0.4, 0.15))
			draw_circle(p + Vector2(8, 3), 7, Color(0.16, 0.45, 0.17))
			if s % 3 == 0:
				draw_circle(p + Vector2(2, -2), 2, Color(1, 0.4, 0.5))
		"hay":
			draw_circle(p, 12, Color(0.9, 0.75, 0.35))
			draw_arc(p, 7, 0, TAU, 16, Color(0.75, 0.6, 0.25), 2.0)
		"cactus":
			var g := Color(0.25, 0.55, 0.25)
			var t := _top(p, 0.03) - p
			draw_rect(Rect2(p + t + Vector2(-5, -22), Vector2(10, 36)), g)
			draw_circle(p + t + Vector2(0, -22), 5, g)
			draw_rect(Rect2(p + t + Vector2(-15, -8), Vector2(10, 6)), g)
			draw_rect(Rect2(p + t + Vector2(-15, -18), Vector2(6, 12)), g)
			draw_rect(Rect2(p + t + Vector2(5, -4), Vector2(9, 6)), g)
			draw_rect(Rect2(p + t + Vector2(9, -14), Vector2(5, 12)), g)
			draw_line(p + t + Vector2(0, -24), p + t + Vector2(0, 12), g.lightened(0.2), 1.5)
		"rock":
			draw_circle(p, 10, Color(0.55, 0.42, 0.3))
			draw_circle(p + Vector2(-3, -3), 5, Color(0.65, 0.52, 0.38))
		"tumbleweed":
			var spin := time * 3.0 + s
			draw_circle(p + _shadow_vec() * 0.5, 7, Color(0, 0, 0, 0.15 * _shadow_a()))
			draw_arc(p, 8, spin, spin + TAU, 10, Color(0.6, 0.45, 0.25), 2.0)
			draw_arc(p, 5, -spin, -spin + PI * 1.5, 8, Color(0.55, 0.4, 0.2), 1.5)
		"palm":
			var top := _top(p, 0.08)
			draw_line(p, top, Color(0.45, 0.3, 0.15), 4.0)
			for i in range(6):
				var a := i * TAU / 6.0 + s
				var tip := top + Vector2(cos(a), sin(a)) * 20.0
				var side := Vector2(-sin(a), cos(a)) * 5.0
				draw_colored_polygon(PackedVector2Array([top, top + Vector2(cos(a), sin(a)) * 10.0 + side, tip]), Color(0.15, 0.55, 0.2))
			draw_circle(top, 4, Color(0.45, 0.3, 0.15))
		"umbrella":
			var cols := [Color(0.95, 0.25, 0.25), Color(0.2, 0.6, 0.95), Color(1, 0.75, 0.1)]
			var c: Color = cols[s % 3]
			draw_rect(Rect2(p + Vector2(10, 10), Vector2(16, 8)), Color(1, 1, 1, 0.8))
			var top := _top(p, 0.04)
			draw_circle(top, 14, c)
			for i in range(4):
				var a := i * TAU / 4.0 + 0.4
				draw_line(top, top + Vector2(cos(a), sin(a)) * 14.0, Color(1, 1, 1, 0.9), 2.0)
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
			# andares da copa cada vez mais "altos" (deslocados) = cone em 3D
			for i in range(3):
				var r := 18.0 - i * 5.0
				var c := _top(p, 0.025 * (i + 1))
				var pts := PackedVector2Array()
				for k in range(16):
					var a := k * TAU / 16.0
					var rr := r if k % 2 == 0 else r * 0.65
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(pts, Color(0.1, 0.32 + i * 0.06, 0.2))
			var tip := _top(p, 0.09)
			draw_circle(tip + Vector2(-3, -3), 4, Color(1, 1, 1, 0.9))
			draw_circle(_top(p, 0.05) + Vector2(6, 4), 3, Color(1, 1, 1, 0.8))
		"snowrock":
			draw_circle(p, 10, Color(0.5, 0.52, 0.58))
			draw_circle(p + Vector2(-2, -3), 7, Color(0.97, 0.98, 1))
		"neon_building":
			_draw_neon_building(d)
		"neon_pole":
			var c := Color(0.2, 0.95, 1) if s % 2 == 0 else Color(1, 0.2, 0.8)
			var top := _top(p, 0.12)
			draw_line(p, top, Color(0.2, 0.18, 0.28), 2.5)
			draw_circle(top, 12, Color(c.r, c.g, c.b, 0.15 + 0.1 * sin(time * 5.0 + s)))
			draw_circle(top, 4, c)

# ---------- o que brilha à noite (camada Glow) ----------

func _draw_glow(ci: CanvasItem) -> void:
	var night := _sky.x
	for d in decor:
		var p := Vector2(d["x"], d["y"])
		var s: int = d["seed"]
		match d["kind"]:
			"building":
				var g := _building_geom(d)
				for wp in _window_points(g["base"], g["off"], s):
					if wp[1]:
						ci.draw_rect(Rect2(wp[0] - Vector2(1.5, 3), Vector2(3, 6)), Color(1, 0.82, 0.45, 0.9 * night))
				# luz das janelas do último andar no telhado
				var roof := Rect2(g["base"].position + g["off"], g["base"].size)
				if s % 3 == 0:
					ci.draw_rect(Rect2(roof.position + Vector2(10, 12), Vector2(16, 12)), Color(1, 0.8, 0.4, 0.55 * night))
			"lamp":
				var top := _top(p, 0.12)
				ci.draw_circle(top, 10, Color(1, 0.85, 0.5, 0.3 * night))
				ci.draw_circle(top, 3, Color(1, 0.97, 0.8, night))
			"neon_building":
				var g := _building_geom(d)
				var c := _neon_color(s)
				var r := Rect2(g["base"].position + g["off"], g["base"].size)
				var pulse := 0.6 + 0.4 * sin(time * 3.0 + s)
				ci.draw_rect(r.grow(3), Color(c.r, c.g, c.b, 0.25 * pulse * night), false, 6.0)
				ci.draw_rect(r, Color(c.r, c.g, c.b, night), false, 2.0)
				for wp in _window_points(g["base"], g["off"], s):
					if wp[1]:
						ci.draw_rect(Rect2(wp[0] - Vector2(1.5, 3), Vector2(3, 6)), Color(c.r, c.g, c.b, 0.8 * night))
				for i in range(4):
					for k in range(3):
						if (s + i * 3 + k) % 3 != 0:
							ci.draw_rect(Rect2(r.position + Vector2(10 + k * 18, 12 + i * 22), Vector2(10, 8)), Color(c.r, c.g, c.b, 0.6 * night))
			"neon_pole":
				var c := Color(0.2, 0.95, 1) if s % 2 == 0 else Color(1, 0.2, 0.8)
				var top := _top(p, 0.12)
				ci.draw_circle(top, 12, Color(c.r, c.g, c.b, 0.3 * night))
				ci.draw_circle(top, 4, Color(c.r, c.g, c.b, night))

static func _hash(k: int) -> float:
	var x := sin(k * 127.1 + 311.7) * 43758.5453
	return x - floor(x)
