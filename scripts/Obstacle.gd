extends Area2D

# Obstáculos de cada cenário, parados na pista (descem com a velocidade dela):
#   "cone"     -> cidade: cones de obra fechando a faixa (bate como um carro)
#   "bueiro"   -> cidade: bueiro aberto (solavanco: perde o combo e velocidade)
#   "duna"     -> deserto: monte de areia na pista (solavanco)
#   "poca"     -> beira-mar: poça d'água (espirra água na tela)
#   "gelo"     -> neve: placa de gelo (troca de faixa fica lenta)
#   "barreira" -> neon: barreira de energia que liga e desliga (bate quando acesa)
# Os sólidos também entram no grupo "traffic", então o Spawner sempre deixa
# uma faixa livre e a IA desvia deles. O próprio obstáculo avisa o jogador
# quando encosta (Player.hit_obstacle), porque a barreira pode acender
# com o carro já em cima.

const SIZES := {
	"cone": Vector2(70, 34), "barreira": Vector2(86, 22), "bueiro": Vector2(30, 30),
	"duna": Vector2(70, 26), "poca": Vector2(66, 52), "gelo": Vector2(84, 120),
}
const BARRIER_PERIOD := 2.4 # acesa na primeira metade, apagada na segunda
const BARRIER_COLOR := Color(1.0, 0.2, 0.75)

var kind: String = "cone"
var lane: int = 0
var length: float = 34.0
var rel_speed: float = 0.0
var threat: bool = false # estava vindo na faixa do jogador (raspão)
var passed: bool = false
var is_work_zone: bool = false
var _t: float = 0.0
var _hit: bool = false

func setup(k: String, l: int, y: float, work_zone: bool = false) -> void:
	kind = k
	lane = l
	is_work_zone = work_zone
	position = Vector2(GameManager.LANES[l], y)
	length = SIZES[k].y
	# a barreira começa apagada perto do fim do ciclo, pra dar tempo de ver
	_t = BARRIER_PERIOD * 0.5 + randf_range(0.0, 0.6) if k == "barreira" else randf() * 10.0

func _ready() -> void:
	add_to_group("obstacles")
	if is_solid_kind():
		add_to_group("traffic")
	else:
		z_index = -2 # no chão, embaixo dos carros
	var shape := RectangleShape2D.new()
	shape.size = SIZES[kind] - Vector2(10, 8)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

func is_solid_kind() -> bool:
	return kind in ["cone", "barreira"]

# Agora bate? (a barreira só quando está acesa)
func is_solid() -> bool:
	if kind == "barreira":
		return barrier_on()
	return is_solid_kind()

func barrier_on() -> bool:
	return fmod(_t, BARRIER_PERIOD) < BARRIER_PERIOD * 0.5

# luz da barreira 0..1 (pisca avisando antes de acender)
func barrier_glow() -> float:
	var ph := fmod(_t, BARRIER_PERIOD)
	if ph < BARRIER_PERIOD * 0.5:
		return 1.0
	if ph > BARRIER_PERIOD - 0.45:
		return 0.55 if fmod(_t, 0.12) < 0.06 else 0.15
	return 0.12

func occupies_lane(l: int) -> bool:
	return abs(position.x - GameManager.LANES[l]) < 60.0

func color() -> Color:
	match kind:
		"cone": return Color(1.0, 0.5, 0.1)
		"barreira": return BARRIER_COLOR
		"duna": return Color(0.9, 0.75, 0.45)
		"poca": return Color(0.55, 0.8, 1.0)
		"gelo": return Color(0.75, 0.95, 1.0)
	return Color(0.4, 0.4, 0.42)

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	_t += delta
	rel_speed = GameManager.speed
	position.y += GameManager.speed * delta
	if not _hit:
		for a in get_overlapping_areas():
			if a.is_in_group("player") and (is_solid() or not is_solid_kind()):
				_hit = true
				a.hit_obstacle(self)
				break
	queue_redraw()
	if position.y > 800.0:
		queue_free()

func _draw() -> void:
	var s: Vector2 = SIZES[kind]
	match kind:
		"cone":
			# Se for trecho de obras, desenha cavalete/barreira com faixas refletivas
			if is_work_zone:
				draw_rect(Rect2(-s.x * 0.5 - 4, -14, s.x + 8, 8), Color(0.9, 0.45, 0.05))
				for stripe in range(5):
					var sx := -s.x * 0.5 - 2.0 + stripe * 16.0
					draw_rect(Rect2(sx, -14, 8, 8), Color(1, 1, 1, 0.9))
				# Suportes do cavalete
				draw_line(Vector2(-s.x * 0.5 + 4, -14), Vector2(-s.x * 0.5 + 4, 10), Color(0.2, 0.2, 0.22), 3.0)
				draw_line(Vector2(s.x * 0.5 - 4, -14), Vector2(s.x * 0.5 - 4, 10), Color(0.2, 0.2, 0.22), 3.0)

			# Faixa zebrada no chão + 3 cones
			draw_rect(Rect2(-s.x * 0.5, -6, s.x, 12), Color(0, 0, 0, 0.25))
			for i in range(3):
				var p := Vector2(-24 + i * 24, -4 + (i % 2) * 8)
				draw_circle(p + Vector2(3, 5), 11, Color(0, 0, 0, 0.3))
				draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), Color(0.15, 0.15, 0.17))
				draw_circle(p, 9, Color(1.0, 0.45, 0.08))
				draw_arc(p, 6, 0, TAU, 16, Color(1, 1, 1, 0.95), 2.5)
				draw_circle(p, 3, Color(1.0, 0.6, 0.2))
				draw_circle(p + Vector2(-2, -2), 1.2, Color(1, 1, 1, 0.8))

				# Luz estroboscópica de aviso nos cones / obras (sinalizador luminoso âmbar)
				var flash_phase: bool = fmod(_t * 4.5 + i * 0.4, 1.0) < 0.5
				if flash_phase or is_work_zone:
					var l_col := Color(1.0, 0.88, 0.25)
					draw_circle(p, 4.5, l_col)
					draw_circle(p, 12.0, Color(1.0, 0.65, 0.05, 0.45))
					draw_circle(p, 20.0, Color(1.0, 0.5, 0.0, 0.18))
				else:
					draw_circle(p, 2.5, Color(0.4, 0.25, 0.05))
		"barreira":
			var g := barrier_glow()
			var c := BARRIER_COLOR
			# postes nas pontas
			for x in [-s.x * 0.5, s.x * 0.5]:
				draw_circle(Vector2(x + 2, 4), 8, Color(0, 0, 0, 0.3))
				draw_circle(Vector2(x, 0), 7, Color(0.12, 0.1, 0.18))
				draw_circle(Vector2(x, 0), 4, Color(c.r, c.g, c.b, 0.4 + 0.6 * g))
			# feixe de energia
			draw_rect(Rect2(-s.x * 0.5, -10, s.x, 20), Color(c.r, c.g, c.b, 0.18 * g))
			draw_rect(Rect2(-s.x * 0.5, -5, s.x, 10), Color(c.r, c.g, c.b, 0.45 * g))
			var zig := PackedVector2Array()
			for i in range(13):
				var x := -s.x * 0.5 + i * s.x / 12.0
				zig.append(Vector2(x, sin(_t * 30.0 + i * 1.7) * 4.0 * g))
			draw_polyline(zig, Color(1, 0.85, 1, 0.25 + 0.75 * g), 2.0, true)
		"bueiro":
			draw_circle(Vector2.ZERO, 15, Color(0.3, 0.3, 0.33))
			draw_circle(Vector2.ZERO, 12, Color(0.03, 0.03, 0.04))
			draw_arc(Vector2.ZERO, 15, 0, TAU, 20, Color(0.55, 0.55, 0.6), 2.0)
			# tampa deslocada ao lado
			draw_circle(Vector2(16, -10), 10, Color(0.38, 0.38, 0.42))
			draw_line(Vector2(9, -10), Vector2(23, -10), Color(0.25, 0.25, 0.28), 2.0)
		"duna":
			var c := color()
			draw_circle(Vector2(-14, 2), 14, c.darkened(0.15))
			draw_circle(Vector2(12, 3), 16, c.darkened(0.15))
			draw_circle(Vector2(-12, -1), 12, c)
			draw_circle(Vector2(12, 0), 13, c)
			draw_circle(Vector2(0, -4), 10, c.lightened(0.15))
			for i in range(3):
				draw_arc(Vector2(-18 + i * 16, 4), 6, PI * 1.1, PI * 1.9, 6, c.darkened(0.3), 1.5)
		"poca":
			var c := color()
			draw_circle(Vector2(-12, 0), 22, Color(0.25, 0.4, 0.6, 0.85))
			draw_circle(Vector2(14, 6), 18, Color(0.25, 0.4, 0.6, 0.85))
			draw_circle(Vector2(4, -12), 14, Color(0.25, 0.4, 0.6, 0.85))
			draw_circle(Vector2(-8, -4), 12, Color(c.r, c.g, c.b, 0.35))
			var r := fmod(_t * 14.0, 16.0)
			draw_arc(Vector2(6, 0), 4 + r, 0, TAU, 16, Color(1, 1, 1, 0.5 * (1.0 - r / 16.0)), 1.5)
			draw_line(Vector2(-18, -8), Vector2(-8, -14), Color(1, 1, 1, 0.7), 2.0)
		"gelo":
			var c := color()
			var pts := PackedVector2Array([Vector2(-36, -54), Vector2(-6, -60), Vector2(34, -48), Vector2(40, 10),
				Vector2(30, 56), Vector2(-10, 60), Vector2(-40, 40), Vector2(-42, -10)])
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.55))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.8), 2.0, true)
			for i in range(4):
				var a := Vector2(-28 + i * 16, -40 + (i % 2) * 20)
				draw_line(a, a + Vector2(14, 34), Color(1, 1, 1, 0.55), 1.5)
			var shine := 0.5 + 0.5 * sin(_t * 4.0)
			draw_line(Vector2(-20, -30), Vector2(6, -44), Color(1, 1, 1, 0.4 + 0.5 * shine), 3.0)
