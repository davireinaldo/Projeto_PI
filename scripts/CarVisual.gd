extends Node2D

# Desenho vetorial (visto de cima, frente para cima) de todos os veículos:
# carros jogáveis, tráfego, caminhões e ônibus.
# O modelo "texture" usa a imagem original assets/images/player_car.png;
# os outros seguem o mesmo estilo cartoon dela: contorno escuro grosso,
# laterais sombreadas, reflexo na lataria, vidros azul-claros com brilho,
# faróis amarelos, lanternas vermelhas e retrovisores.

const TEX := preload("res://assets/images/player_car.png")
const OUTLINE := Color(0.05, 0.06, 0.09)
const WHEEL := Color(0.08, 0.08, 0.1)
const TREAD := Color(0.24, 0.24, 0.27)
const GLASS := Color(0.56, 0.86, 0.96)
const DARK := Color(0.1, 0.1, 0.12)
const METAL := Color(0.62, 0.64, 0.68)
const HEAD := Color(1.0, 0.86, 0.22)
const TAIL := Color(0.92, 0.1, 0.12)
const BLINK := Color(1, 0.65, 0.05)

var model: String = "sedan"
var body_color: Color = Color(0.2, 0.6, 1.0)
var accent: Color = Color.WHITE
var blink: int = 0 # -1 seta esquerda, 1 seta direita
var dim: float = 0.0 # escurece o desenho (carro bloqueado na garagem)
var _t: float = 0.0

static func model_size(m: String) -> Vector2:
	match m:
		"truck":
			return Vector2(42, 124)
		"bus":
			return Vector2(42, 136)
		"pickup", "van":
			return Vector2(38, 70)
		"f1":
			return Vector2(36, 70)
	return Vector2(36, 64)

func setup(m: String, c: Color, a: Color = Color.WHITE) -> void:
	model = m
	body_color = c
	accent = a
	queue_redraw()

func set_color(c: Color) -> void:
	body_color = c
	queue_redraw()

func _process(delta: float) -> void:
	if blink != 0 or model == "legend":
		_t += delta
		queue_redraw()

# ---------- helpers de geometria ----------

func _c(c: Color) -> Color:
	return c.darkened(dim) if dim > 0.0 else c

# Monta um polígono simétrico a partir do lado direito (de cima para baixo).
func _sym(right: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in right:
		pts.append(p)
	for i in range(right.size() - 1, -1, -1):
		var p: Vector2 = right[i]
		if p.x != 0.0:
			pts.append(Vector2(-p.x, p.y))
	return pts

# Espelha um polígono no eixo X (para peças dos dois lados).
func _mx(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(-p.x, p.y))
	return out

# Arredonda os cantos (Chaikin) para o visual "desenhado".
# radius limita o corte em cada canto, para retas longas não virarem chanfro.
func _smooth(pts: PackedVector2Array, iters: int = 2, radius: float = 6.0) -> PackedVector2Array:
	var out := pts
	for _i in iters:
		var n := PackedVector2Array()
		var count := out.size()
		for i in count:
			var a: Vector2 = out[i]
			var b: Vector2 = out[(i + 1) % count]
			var t := minf(0.25, radius / maxf(a.distance_to(b), 0.001))
			n.append(a.lerp(b, t))
			n.append(a.lerp(b, 1.0 - t))
		out = n
		radius *= 0.5
	return out

func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

func _scaled(pts: PackedVector2Array, sx: float, sy: float, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var c := _bounds(pts).get_center()
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2((p.x - c.x) * sx, (p.y - c.y) * sy) + off)
	return out

# ---------- helpers de desenho ----------

func _line(pts: PackedVector2Array, c: Color, w: float = 2.2) -> void:
	draw_polyline(pts + PackedVector2Array([pts[0]]), _c(c), w, true)

func _shadow(pts: PackedVector2Array) -> void:
	var s := PackedVector2Array()
	for p in pts:
		s.append(p + Vector2(3, 6))
	draw_colored_polygon(s, Color(0, 0, 0, 0.3))

# Lataria: borda lateral mais escura, miolo na cor, faixa de reflexo e contorno.
func _body(pts: PackedVector2Array, c: Color) -> void:
	draw_colored_polygon(pts, _c(c.darkened(0.3)))
	draw_colored_polygon(_scaled(pts, 0.78, 0.96), _c(c))
	var hw := _bounds(pts).size.x * 0.5
	var hl := c.lightened(0.5)
	hl.a = 0.4
	draw_colored_polygon(_scaled(pts, 0.14, 0.84, Vector2(-hw * 0.42, 0)), _c(hl))
	_line(pts, OUTLINE, 2.2)

# Painel (teto, capô, caçamba...) com contorno fino.
func _panel(pts: PackedVector2Array, c: Color, smooth: bool = true) -> void:
	var p := _smooth(pts, 2, 3.0) if smooth else pts
	draw_colored_polygon(p, _c(c))
	_line(p, OUTLINE, 1.4)

func _glass(pts: PackedVector2Array, shine: bool = true) -> void:
	var g := _smooth(pts, 2, 3.0)
	draw_colored_polygon(g, _c(GLASS))
	var b := _bounds(g)
	if shine and b.size.x > 8.0:
		var w := Color(1, 1, 1, 0.8)
		draw_line(b.position + Vector2(b.size.x * 0.2, b.size.y * 0.8),
			b.position + Vector2(b.size.x * 0.36, b.size.y * 0.2), _c(w), 2.0, true)
		draw_line(b.position + Vector2(b.size.x * 0.34, b.size.y * 0.8),
			b.position + Vector2(b.size.x * 0.44, b.size.y * 0.4), _c(w), 1.0, true)
	_line(g, OUTLINE, 1.6)

func _seam(a: Vector2, b: Vector2, mirror: bool = true) -> void:
	var c := body_color.darkened(0.45)
	draw_line(a, b, _c(c), 1.0, true)
	if mirror:
		draw_line(Vector2(-a.x, a.y), Vector2(-b.x, b.y), _c(c), 1.0, true)

func _box(r: Rect2, c: Color, w: float = 1.2) -> void:
	draw_rect(r, _c(c))
	draw_rect(r, _c(OUTLINE), false, w)

func _wheels(rects: Array) -> void:
	for r: Rect2 in rects:
		draw_rect(r, _c(WHEEL))
		var y := r.position.y + 2.0
		while y < r.end.y - 1.0:
			draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), _c(TREAD), 1.0)
			y += 3.0
		draw_rect(r, _c(OUTLINE), false, 1.0)

# Lâmpada retangular em par (x0..x1 do lado direito, espelhada no esquerdo).
func _lamps(x0: float, x1: float, y: float, h: float, c: Color) -> void:
	for s in [-1.0, 1.0]:
		var r := Rect2(Vector2(x0 if s > 0 else -x1, y), Vector2(x1 - x0, h))
		if c == HEAD:
			var glow := HEAD
			glow.a = 0.22
			draw_circle(r.get_center(), 5.0, _c(glow))
		_box(r, c, 1.0)
		draw_rect(Rect2(r.position + Vector2(1, 0.8), Vector2(1.6, 1.2)), _c(Color(1, 1, 1, 0.85)))

# Lâmpada em formato livre (lado direito), espelhada.
func _lamp_poly(right: PackedVector2Array, c: Color) -> void:
	for p in [right, _mx(right)]:
		draw_colored_polygon(p, _c(c))
		_line(p, OUTLINE, 1.0)

func _mirrors(y: float, hw: float, c: Color) -> void:
	_box(Rect2(hw - 1, y, 4, 3), c, 1.0)
	_box(Rect2(-hw - 3, y, 4, 3), c, 1.0)

func _blinkers(front_y: float, rear_y: float, half_w: float) -> void:
	if blink == 0 or fmod(_t, 0.5) > 0.28:
		return
	var x := half_w * blink
	for y in [front_y + 3, rear_y - 3]:
		draw_circle(Vector2(x, y), 7, Color(1, 0.6, 0.0, 0.35))
		draw_circle(Vector2(x, y), 3.5, BLINK)

func _draw() -> void:
	match model:
		"texture": _draw_texture()
		"sport": _draw_sport()
		"armored": _draw_armored()
		"pickup": _draw_pickup()
		"muscle": _draw_muscle()
		"coupe": _draw_coupe()
		"f1": _draw_f1()
		"legend": _draw_legend()
		"van": _draw_van()
		"taxi": _draw_sedan(true)
		"truck": _draw_truck()
		"bus": _draw_bus()
		_: _draw_sedan(false)

# ---------- modelos ----------

func _draw_texture() -> void:
	var tex_size: Vector2 = TEX.get_size()
	var s: float = 38.0 / tex_size.x
	var size: Vector2 = tex_size * s
	draw_rect(Rect2(-size * 0.5 + Vector2(3, 6), size).grow(-3), Color(0, 0, 0, 0.25))
	draw_texture_rect(TEX, Rect2(-size * 0.5, size), false, Color(1, 1, 1).darkened(dim))

func _draw_sedan(taxi: bool) -> void:
	var body := _smooth(_sym([Vector2(12, -32), Vector2(16, -28), Vector2(18, -14),
		Vector2(18, 22), Vector2(16, 30), Vector2(12, 32)]))
	_shadow(body)
	_wheels([Rect2(-20, -21, 5, 12), Rect2(15, -21, 5, 12), Rect2(-20, 9, 5, 12), Rect2(15, 9, 5, 12)])
	_body(body, body_color)
	_seam(Vector2(6, -29), Vector2(8, -17))
	_mirrors(-12, 18, body_color)
	_glass(_sym([Vector2(11, -16), Vector2(14, -5)]))
	_panel(_sym([Vector2(12, -5), Vector2(12, 13)]), body_color.lightened(0.1))
	_glass(PackedVector2Array([Vector2(13, -3), Vector2(16, -2), Vector2(16, 12), Vector2(13, 12)]), false)
	_glass(_mx(PackedVector2Array([Vector2(13, -3), Vector2(16, -2), Vector2(16, 12), Vector2(13, 12)])), false)
	_glass(_sym([Vector2(12, 14), Vector2(10, 21)]))
	_seam(Vector2(-10, 25), Vector2(10, 25), false)
	if taxi:
		_box(Rect2(-7, 0, 14, 7), DARK)
		_box(Rect2(-6, 1, 12, 5), Color(1, 0.95, 0.5), 0.8)
		for x in [-4, 0, 4]:
			draw_rect(Rect2(x - 1, 2.5, 2, 2), _c(DARK))
	_lamps(7, 13, -30, 4, HEAD)
	_lamps(8, 14, 27, 3.5, TAIL)
	_blinkers(-30, 30, 17)

func _draw_sport() -> void:
	var body := _smooth(_sym([Vector2(9, -32), Vector2(14, -29), Vector2(17, -18),
		Vector2(18, 0), Vector2(18, 24), Vector2(16, 31), Vector2(11, 32)]))
	_shadow(body)
	_wheels([Rect2(-20, -22, 5, 12), Rect2(15, -22, 5, 12), Rect2(-21, 8, 6, 14), Rect2(15, 8, 6, 14)])
	_body(body, body_color)
	_panel(_sym([Vector2(12, -1), Vector2(11, 10)]), body_color.lightened(0.08))
	# faixas de corrida
	for x in [-6, 2]:
		draw_rect(Rect2(x, -31, 4, 16), _c(accent))
		draw_rect(Rect2(x, -1, 4, 11), _c(accent))
		draw_rect(Rect2(x, 18, 4, 6), _c(accent))
	_seam(Vector2(9, -27), Vector2(12, -17))
	_mirrors(-11, 17, body_color)
	_glass(_sym([Vector2(11, -15), Vector2(14, -1)]))
	_glass(_sym([Vector2(11, 10), Vector2(9, 17)]))
	# entradas de ar laterais
	var intake := PackedVector2Array([Vector2(14, 2), Vector2(16.5, 4), Vector2(16.5, 13), Vector2(14, 11)])
	_panel(intake, DARK, false)
	_panel(_mx(intake), DARK, false)
	_lamp_poly(PackedVector2Array([Vector2(8, -30), Vector2(13, -28), Vector2(14, -25), Vector2(9, -27)]), HEAD)
	_lamps(6, 13, 29, 2.5, TAIL)
	# aerofólio
	_box(Rect2(-18, 22, 3, 8), DARK)
	_box(Rect2(15, 22, 3, 8), DARK)
	_box(Rect2(-17, 24, 34, 4.5), DARK)
	draw_rect(Rect2(-16, 24.5, 32, 1.5), _c(accent))
	for x in [-4, 4]:
		draw_circle(Vector2(x, 32), 2.0, _c(OUTLINE))
		draw_circle(Vector2(x, 32), 1.2, _c(METAL))
	_blinkers(-30, 30, 17)

func _draw_armored() -> void:
	var body := _smooth(_sym([Vector2(16, -30), Vector2(19, -27), Vector2(19, 28), Vector2(17, 32)]), 2, 4.0)
	_shadow(body)
	_wheels([Rect2(-21, -22, 5, 14), Rect2(16, -22, 5, 14), Rect2(-21, 10, 5, 14), Rect2(16, 10, 5, 14)])
	_body(body, body_color)
	# para-choque de impulsão
	_box(Rect2(-17, -35, 34, 5), Color(0.32, 0.34, 0.36))
	for x in [-11.0, -1.5, 8.0]:
		_box(Rect2(x, -36, 3, 7), Color(0.5, 0.52, 0.55), 1.0)
	_lamps(10, 16, -29, 3, HEAD)
	_panel(_sym([Vector2(15, -25), Vector2(15, -21)]), body_color.darkened(0.2), false)
	_glass(_sym([Vector2(12, -19), Vector2(13, -11)]))
	for x in [-4, 4]:
		draw_line(Vector2(x, -19), Vector2(x, -11), _c(OUTLINE), 1.5)
	_mirrors(-15, 19, body_color.darkened(0.2))
	var roof := _sym([Vector2(15, -9), Vector2(15, 27)])
	_panel(roof, body_color.darkened(0.12), false)
	for y in [-1, 13]:
		_seam(Vector2(-15, y), Vector2(15, y), false)
	# escotilha
	draw_circle(Vector2(0, 6), 7.5, _c(OUTLINE))
	draw_circle(Vector2(0, 6), 6.3, _c(body_color.darkened(0.35)))
	draw_circle(Vector2(0, 6), 4, _c(accent.darkened(0.2)))
	draw_arc(Vector2(0, 6), 4, 0, TAU, 16, _c(OUTLINE), 1.0, true)
	draw_rect(Rect2(-3, 5, 6, 2), _c(OUTLINE))
	for p in [Vector2(-12, -6), Vector2(12, -6), Vector2(-12, 24), Vector2(12, 24)]:
		draw_circle(p, 2.0, _c(OUTLINE))
		draw_circle(p, 1.3, _c(accent))
	_lamps(11, 16, 28, 3, TAIL)
	_blinkers(-28, 30, 18)

func _draw_pickup() -> void:
	var body := _smooth(_sym([Vector2(14, -34), Vector2(18, -30), Vector2(19, -20),
		Vector2(19, 33), Vector2(17, 35)]))
	_shadow(body)
	_wheels([Rect2(-21, -26, 5, 14), Rect2(16, -26, 5, 14), Rect2(-21, 14, 5, 14), Rect2(16, 14, 5, 14)])
	_body(body, body_color)
	_box(Rect2(-8, -33.5, 16, 3), DARK, 1.0)
	_lamps(10, 15, -32, 4, HEAD)
	_seam(Vector2(5, -29), Vector2(6, -18))
	_mirrors(-15, 19, body_color)
	_glass(_sym([Vector2(13, -17), Vector2(15, -6)]))
	_panel(_sym([Vector2(14, -6), Vector2(14, 6)]), body_color.lightened(0.1))
	_glass(_sym([Vector2(13, 6), Vector2(13, 9)]), false)
	# caçamba
	_box(Rect2(-16, 12, 32, 20), body_color.darkened(0.55), 1.4)
	for y in [17, 22, 27]:
		draw_rect(Rect2(-14, y, 28, 1.5), _c(body_color.darkened(0.72)))
	_box(Rect2(-17, 11, 3, 22), accent, 1.0)
	_box(Rect2(14, 11, 3, 22), accent, 1.0)
	_box(Rect2(-16, 10.5, 32, 2), accent, 1.0)
	_box(Rect2(-15, 31.5, 30, 3), body_color, 1.0)
	_lamps(13, 17, 30, 4, TAIL)
	_blinkers(-32, 33, 18)

func _draw_muscle() -> void:
	var body := _smooth(_sym([Vector2(14, -33), Vector2(17, -28), Vector2(18, -18),
		Vector2(18, 24), Vector2(17, 31), Vector2(14, 33)]))
	_shadow(body)
	_wheels([Rect2(-20, -23, 5, 13), Rect2(15, -23, 5, 13), Rect2(-21, 9, 6, 15), Rect2(15, 9, 6, 15)])
	_body(body, body_color)
	_panel(_sym([Vector2(13, 1), Vector2(12, 13)]), body_color.lightened(0.08))
	for x in [-7, 2]:
		draw_rect(Rect2(x, -31.5, 5, 63), _c(accent))
	# entrada de ar do capô
	_panel(_sym([Vector2(5, -26), Vector2(6, -15)]), body_color.darkened(0.2), false)
	draw_rect(Rect2(-4, -25, 8, 3), _c(OUTLINE))
	_mirrors(-8, 18, body_color)
	_glass(_sym([Vector2(12, -10), Vector2(14, 1)]))
	_glass(_sym([Vector2(11, 13), Vector2(12, 20)]))
	_box(Rect2(-15, 25, 30, 2.5), DARK, 1.0)
	# faróis redondos
	for x in [-11.5, 11.5]:
		var glow := HEAD
		glow.a = 0.22
		draw_circle(Vector2(x, -29), 5.0, _c(glow))
		draw_circle(Vector2(x, -29), 3.3, _c(OUTLINE))
		draw_circle(Vector2(x, -29), 2.4, _c(HEAD))
		draw_circle(Vector2(x - 0.8, -29.8), 0.8, _c(Color.WHITE))
	_lamps(5, 15, 29.5, 2.5, TAIL)
	for x in [-10, 10]:
		draw_circle(Vector2(x, 33.5), 2.0, _c(OUTLINE))
		draw_circle(Vector2(x, 33.5), 1.2, _c(METAL))
	_blinkers(-31, 31, 17)

func _draw_coupe() -> void:
	# superesportivo de motor central (mesma linha do carro azul)
	var body := _smooth(_sym([Vector2(9, -34), Vector2(15, -30), Vector2(18, -18),
		Vector2(18, 22), Vector2(16, 30), Vector2(10, 34)]))
	_shadow(body)
	_wheels([Rect2(-20, -22, 5, 12), Rect2(15, -22, 5, 12), Rect2(-20, 9, 5, 14), Rect2(15, 9, 5, 14)])
	_body(body, body_color)
	_seam(Vector2(4, -31), Vector2(9, -16))
	_lamp_poly(PackedVector2Array([Vector2(9, -31), Vector2(14, -28), Vector2(14, -25.5), Vector2(8.5, -28.5)]), HEAD)
	_mirrors(-12, 18, body_color)
	_glass(_sym([Vector2(11, -14), Vector2(14, -2), Vector2(13, 10)]))
	_panel(_sym([Vector2(9, -3), Vector2(9, 8)]), body_color)
	# lâminas laterais
	_box(Rect2(-18, -1, 3, 11), accent, 1.0)
	_box(Rect2(15, -1, 3, 11), accent, 1.0)
	# tampa do motor com grelhas
	_glass(_sym([Vector2(10, 12), Vector2(9, 24)]), false)
	for y in [14.5, 17.5, 20.5]:
		draw_line(Vector2(-8, y), Vector2(8, y), _c(OUTLINE), 1.5)
	draw_line(Vector2(0, 12), Vector2(0, 24), _c(OUTLINE), 1.5)
	for s in [-1.0, 1.0]:
		var vent := PackedVector2Array([Vector2(11 * s, 12), Vector2(14 * s, 13), Vector2(14 * s, 23), Vector2(11 * s, 23)])
		_panel(vent, DARK, false)
		for y in [15, 18, 21]:
			draw_line(Vector2(11 * s, y), Vector2(14 * s, y), _c(TAIL.darkened(0.2)), 1.0)
	_box(Rect2(-7, 29, 14, 3), accent, 1.0)
	_lamps(8, 14, 28.5, 2.5, TAIL)
	_blinkers(-30, 30, 17)

func _draw_f1() -> void:
	# braços da suspensão
	for s in [-1.0, 1.0]:
		draw_line(Vector2(5 * s, -22), Vector2(14 * s, -21), _c(OUTLINE), 1.5)
		draw_line(Vector2(5 * s, -17), Vector2(14 * s, -20), _c(OUTLINE), 1.5)
		draw_line(Vector2(10 * s, 16), Vector2(14 * s, 20), _c(OUTLINE), 1.5)
	var body := _smooth(_sym([Vector2(3.5, -34), Vector2(6, -16), Vector2(8, -8), Vector2(13, -2),
		Vector2(13, 20), Vector2(8, 30)]))
	_shadow(body)
	_wheels([Rect2(-21, -28, 8, 14), Rect2(13, -28, 8, 14), Rect2(-22, 12, 9, 17), Rect2(13, 12, 9, 17)])
	_body(body, body_color)
	# asa dianteira
	_box(Rect2(-19, -38, 38, 5), accent)
	_box(Rect2(-20, -39, 3, 7), DARK, 1.0)
	_box(Rect2(17, -39, 3, 7), DARK, 1.0)
	_box(Rect2(-12, 2, 3, 15), accent, 1.0)
	_box(Rect2(9, 2, 3, 15), accent, 1.0)
	_box(Rect2(-12, -2, 4, 3), DARK, 1.0)
	_box(Rect2(8, -2, 4, 3), DARK, 1.0)
	# cockpit + capacete + halo
	_panel(_sym([Vector2(4, -11), Vector2(5, 5)]), DARK)
	draw_circle(Vector2(0, -3), 3.8, _c(OUTLINE))
	draw_circle(Vector2(0, -3), 3.0, _c(Color(1, 0.85, 0.2)))
	draw_rect(Rect2(-2, -5, 4, 1.5), _c(GLASS))
	draw_arc(Vector2(0, -2), 6.5, PI, TAU, 14, _c(OUTLINE), 2.0, true)
	draw_line(Vector2(0, -8.5), Vector2(0, -14), _c(OUTLINE), 2.0)
	_seam(Vector2(0, 8), Vector2(0, 26), false)
	# asa traseira
	_box(Rect2(-17, 29, 34, 6), DARK)
	draw_rect(Rect2(-16, 29.5, 32, 2), _c(accent))
	_box(Rect2(-2, 35, 4, 2), TAIL, 0.8)
	_blinkers(-30, 30, 14)

func _draw_legend() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	var body := _smooth(_sym([Vector2(0, -36), Vector2(10, -26), Vector2(18, -4),
		Vector2(19, 22), Vector2(12, 33)]))
	var closed := body + PackedVector2Array([body[0]])
	draw_polyline(closed, Color(accent.r, accent.g, accent.b, 0.25 * pulse), 9.0, true)
	_shadow(body)
	_wheels([Rect2(-21, -16, 5, 13), Rect2(16, -16, 5, 13), Rect2(-21, 12, 5, 14), Rect2(16, 12, 5, 14)])
	_body(body, body_color)
	draw_polyline(closed, _c(accent), 1.6, true)
	# cockpit em gota
	var canopy := _smooth(_sym([Vector2(0, -19), Vector2(8, -6), Vector2(8, 12), Vector2(5, 15)]), 2, 4.0)
	draw_colored_polygon(canopy, _c(Color(0.05, 0.3, 0.35, 0.95)))
	draw_line(Vector2(-4, 8), Vector2(-2, -10), _c(Color(accent.r, accent.g, accent.b, 0.7)), 2.0, true)
	_line(canopy, OUTLINE, 1.6)
	_mirrors(-8, 17, body_color)
	# linhas de neon
	draw_line(Vector2(0, -33), Vector2(0, -21), _c(accent), 2.0)
	for s in [-1.0, 1.0]:
		draw_line(Vector2(14 * s, 0), Vector2(12 * s, 22), _c(accent), 2.0)
	_lamp_poly(PackedVector2Array([Vector2(4, -31), Vector2(10, -25), Vector2(9, -23), Vector2(4, -28)]), accent)
	# propulsores
	for x in [-7, 7]:
		draw_circle(Vector2(x, 33), 5.0 * pulse + 2.0, Color(accent.r, accent.g, accent.b, 0.35))
		draw_circle(Vector2(x, 32), 3.6, _c(OUTLINE))
		draw_circle(Vector2(x, 32), 2.8, _c(accent))
	_blinkers(-26, 30, 17)

func _draw_van() -> void:
	var body := _smooth(_sym([Vector2(15, -35), Vector2(19, -29), Vector2(19, 33), Vector2(17, 35)]), 2, 4.0)
	_shadow(body)
	_wheels([Rect2(-21, -26, 5, 13), Rect2(16, -26, 5, 13), Rect2(-21, 16, 5, 13), Rect2(16, 16, 5, 13)])
	_body(body, body_color)
	_box(Rect2(-8, -34.5, 16, 2.5), DARK, 1.0)
	_lamps(10, 15, -33, 3, HEAD)
	_glass(_sym([Vector2(14, -29), Vector2(16, -19)]))
	_mirrors(-25, 19, body_color)
	_panel(_sym([Vector2(15, -18), Vector2(15, 31)]), body_color.lightened(0.1), false)
	for y in [-6, 7, 20]:
		_seam(Vector2(-13, y), Vector2(13, y), false)
	_lamps(13, 17, 30.5, 4, TAIL)
	_blinkers(-33, 33, 18)

func _draw_truck() -> void:
	# caminhão: cabine na frente + baú comprido atrás
	var trailer := _smooth(_sym([Vector2(21, -32), Vector2(21, 62)]), 2, 4.0)
	var cab := _smooth(_sym([Vector2(15, -62), Vector2(19, -58), Vector2(19, -36)]), 2, 4.0)
	_shadow(cab)
	_shadow(trailer)
	_wheels([Rect2(-22, -56, 4, 12), Rect2(18, -56, 4, 12),
		Rect2(-23, 30, 4, 12), Rect2(19, 30, 4, 12), Rect2(-23, 45, 4, 12), Rect2(19, 45, 4, 12)])
	_box(Rect2(-6, -38, 12, 7), DARK)
	_body(cab, body_color)
	_box(Rect2(-9, -62.5, 18, 2.5), DARK, 1.0)
	_lamps(12, 17, -61, 3, HEAD)
	_glass(_sym([Vector2(16, -57), Vector2(16, -50)]))
	_panel(_sym([Vector2(14, -48), Vector2(15, -39)]), body_color.darkened(0.15))
	_box(Rect2(19, -55, 4, 6), DARK, 1.0)
	_box(Rect2(-23, -55, 4, 6), DARK, 1.0)
	_body(trailer, accent)
	for y in range(-24, 60, 10):
		draw_rect(Rect2(-17, y, 34, 1.5), _c(accent.darkened(0.2)))
	_box(Rect2(-21, 58, 42, 4), accent.darkened(0.35), 1.0)
	_lamps(14, 19, 58.5, 3, TAIL)
	_blinkers(-60, 60, 21)

func _draw_bus() -> void:
	var body := _smooth(_sym([Vector2(18, -68), Vector2(21, -64), Vector2(21, 66), Vector2(18, 68)]), 2, 4.0)
	_shadow(body)
	_wheels([Rect2(-23, -50, 4, 14), Rect2(19, -50, 4, 14), Rect2(-23, 38, 4, 14), Rect2(19, 38, 4, 14)])
	_body(body, body_color)
	_glass(_sym([Vector2(17, -65), Vector2(18, -56)]))
	_mirrors(-62, 21, DARK)
	for y in range(-50, 62, 14):
		_glass(PackedVector2Array([Vector2(16, y), Vector2(19, y), Vector2(19, y + 10), Vector2(16, y + 10)]), false)
		_glass(PackedVector2Array([Vector2(-19, y), Vector2(-16, y), Vector2(-16, y + 10), Vector2(-19, y + 10)]), false)
	# teto: ar-condicionado e escotilhas
	_panel(_sym([Vector2(11, -42), Vector2(11, -24)]), body_color.lightened(0.25))
	for y in [-38, -33, -28]:
		_seam(Vector2(-9, y), Vector2(9, y), false)
	_panel(_sym([Vector2(7, 30), Vector2(7, 40)]), body_color.lightened(0.25))
	_box(Rect2(-14, -5, 28, 3), accent, 1.0)
	_box(Rect2(-14, 8, 28, 3), accent, 1.0)
	_lamps(13, 18, -67.5, 2.5, HEAD)
	_lamps(13, 18, 64.5, 3, TAIL)
	_blinkers(-66, 66, 21)
