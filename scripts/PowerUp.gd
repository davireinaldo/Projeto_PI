extends Area2D

# Power-ups: escudo (ciano), câmera lenta (magenta) e estrela de pontos (dourado).
# Ícone desenhado, com brilho girando e pulsação.

const KINDS := ["escudo", "lentidao", "pontos"]
const COLORS := {
	"escudo": Color(0.2, 0.9, 0.95),
	"lentidao": Color(0.85, 0.3, 0.95),
	"pontos": Color(1, 0.82, 0.2),
}

var kind: String = "escudo"
var _t: float = 0.0

func _ready() -> void:
	add_to_group("powerups")
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
	var c := color()
	draw_circle(Vector2.ZERO, 26, Color(c.r, c.g, c.b, 0.12))
	draw_circle(Vector2.ZERO, 20, Color(c.r, c.g, c.b, 0.25))
	for i in range(3):
		var a := _t * 3.0 + i * TAU / 3.0
		draw_arc(Vector2.ZERO, 24, a, a + 0.9, 10, Color(c.r, c.g, c.b, 0.9), 2.5, true)
	match kind:
		"escudo":
			var shield := PackedVector2Array([
				Vector2(0, -15), Vector2(12, -9), Vector2(12, 5),
				Vector2(0, 16), Vector2(-12, 5), Vector2(-12, -9)])
			draw_colored_polygon(shield, c)
			draw_polyline(shield + PackedVector2Array([shield[0]]), Color.WHITE, 2.0, true)
		"lentidao":
			draw_circle(Vector2.ZERO, 13, c)
			draw_arc(Vector2.ZERO, 13, 0, TAU, 32, Color.WHITE, 2.0, true)
			draw_line(Vector2.ZERO, Vector2(0, -8), Color.WHITE, 2.0)
			draw_line(Vector2.ZERO, Vector2(6, 2), Color.WHITE, 2.0)
		"pontos":
			var points := PackedVector2Array()
			for i in range(10):
				var angle: float = i * PI / 5.0 - PI / 2.0
				var r: float = 14.0 if i % 2 == 0 else 6.0
				points.append(Vector2(cos(angle) * r, sin(angle) * r))
			draw_colored_polygon(points, c)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.7, 0.55, 0.05), 1.5, true)
