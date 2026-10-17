extends Area2D

# Power-ups: escudo (ciano), câmera lenta (magenta), estrela de pontos (dourado),
# nitro (laranja), ímã (vermelho) e moedas x2 (verde).
# Ícone desenhado, com brilho girando e pulsação.

const UI := preload("res://scripts/UIKit.gd")

const KINDS := ["escudo", "lentidao", "pontos", "nitro", "ima", "moedas2"]
const COLORS := {
	"escudo": Color(0.2, 0.9, 0.95),
	"lentidao": Color(0.85, 0.3, 0.95),
	"pontos": Color(1, 0.82, 0.2),
	"nitro": Color(1, 0.48, 0.1),
	"ima": Color(1, 0.28, 0.32),
	"moedas2": Color(0.35, 1, 0.45),
}
# nome que aparece na tela e no HUD
const NAMES := {
	"escudo": "ESCUDO", "lentidao": "CÂMERA LENTA", "pontos": "PONTOS",
	"nitro": "NITRO", "ima": "ÍMÃ", "moedas2": "MOEDAS x2",
}

var kind: String = "escudo"
var _t: float = 0.0

func _ready() -> void:
	add_to_group("powerups")
	z_index = 16 # acima da escuridão da noite
	kind = KINDS[randi() % KINDS.size()]
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

func color() -> Color:
	return COLORS[kind]

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	position.y += GameManager.speed * delta
	_t += delta
	scale = Vector2.ONE * (1.0 + 0.08 * sin(_t * 6.0))
	queue_redraw()
	if position.y > 800.0:
		queue_free()

func _draw() -> void:
	draw_icon(self, kind, _t)

# Também usado pelo HUD (ícone pequeno nas barras dos poderes).
static func draw_icon(ci: CanvasItem, kind: String, t: float, small: bool = false) -> void:
	var c: Color = COLORS[kind]
	if not small:
		ci.draw_circle(Vector2.ZERO, 26, Color(c.r, c.g, c.b, 0.12))
		ci.draw_circle(Vector2.ZERO, 20, Color(c.r, c.g, c.b, 0.25))
		for i in range(3):
			var a := t * 3.0 + i * TAU / 3.0
			ci.draw_arc(Vector2.ZERO, 24, a, a + 0.9, 10, Color(c.r, c.g, c.b, 0.9), 2.5, true)
	match kind:
		"escudo":
			var shield := PackedVector2Array([
				Vector2(0, -15), Vector2(12, -9), Vector2(12, 5),
				Vector2(0, 16), Vector2(-12, 5), Vector2(-12, -9)])
			ci.draw_colored_polygon(shield, c)
			ci.draw_polyline(shield + PackedVector2Array([shield[0]]), Color.WHITE, 2.0, true)
		"lentidao":
			ci.draw_circle(Vector2.ZERO, 13, c)
			ci.draw_arc(Vector2.ZERO, 13, 0, TAU, 32, Color.WHITE, 2.0, true)
			ci.draw_line(Vector2.ZERO, Vector2(0, -8), Color.WHITE, 2.0)
			ci.draw_line(Vector2.ZERO, Vector2(6, 2), Color.WHITE, 2.0)
		"pontos":
			var points := PackedVector2Array()
			for i in range(10):
				var angle: float = i * PI / 5.0 - PI / 2.0
				var r: float = 14.0 if i % 2 == 0 else 6.0
				points.append(Vector2(cos(angle) * r, sin(angle) * r))
			ci.draw_colored_polygon(points, c)
			ci.draw_polyline(points + PackedVector2Array([points[0]]), Color(0.7, 0.55, 0.05), 1.5, true)
		"nitro":
			# raio
			var bolt := PackedVector2Array([Vector2(3, -17), Vector2(-10, 2), Vector2(-1, 2),
				Vector2(-4, 17), Vector2(10, -3), Vector2(1, -3)])
			ci.draw_colored_polygon(bolt, c)
			ci.draw_polyline(bolt + PackedVector2Array([bolt[0]]), Color(1, 0.95, 0.7), 2.0, true)
		"ima":
			# ímã de ferradura
			ci.draw_arc(Vector2(0, -2), 9, PI * 0.0, -PI, 16, c, 7.0)
			ci.draw_rect(Rect2(-12.5, -2, 7, 10), c)
			ci.draw_rect(Rect2(5.5, -2, 7, 10), c)
			ci.draw_rect(Rect2(-12.5, 8, 7, 5), Color(0.92, 0.94, 1.0))
			ci.draw_rect(Rect2(5.5, 8, 7, 5), Color(0.92, 0.94, 1.0))
		"moedas2":
			UI.draw_coin(ci, Vector2(-4, 0), 10.0)
			ci.draw_string_outline(UI.font(), Vector2(0, 12), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0.05, 0.2, 0.05))
			ci.draw_string(UI.font(), Vector2(0, 12), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c.lightened(0.4))
