extends Area2D

# Power-up com ícone desenhado (não é mais um círculo liso):
# escudo (ciano), relógio de lentidão (magenta) e estrela de pontos (dourado).
# Também tem uma leve "pulsação" de escala.

enum Type { ESCUDO, LENTIDAO, PONTOS }

var type: Type = Type.ESCUDO
var _t: float = 0.0

func _ready() -> void:
	add_to_group("powerups")
	type = Type.values()[randi() % Type.size()]

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	position.y += GameManager.speed * delta
	_t += delta
	scale = Vector2.ONE * (1.0 + 0.08 * sin(_t * 6.0))
	queue_redraw()
	if position.y > 800:
		queue_free()

func _draw() -> void:
	var glow_color: Color
	match type:
		Type.ESCUDO:
			glow_color = Color(0.2, 0.9, 0.95, 0.25)
		Type.LENTIDAO:
			glow_color = Color(0.85, 0.3, 0.9, 0.25)
		Type.PONTOS:
			glow_color = Color(1, 0.85, 0.2, 0.25)
	draw_circle(Vector2.ZERO, 20, glow_color)

	match type:
		Type.ESCUDO:
			var shield := PackedVector2Array([
				Vector2(0, -15), Vector2(12, -9), Vector2(12, 5),
				Vector2(0, 16), Vector2(-12, 5), Vector2(-12, -9)
			])
			draw_colored_polygon(shield, Color(0.2, 0.85, 0.95))
			draw_polyline(shield + PackedVector2Array([shield[0]]), Color.WHITE, 2.0, true)
		Type.LENTIDAO:
			draw_circle(Vector2.ZERO, 13, Color(0.85, 0.3, 0.9))
			draw_arc(Vector2.ZERO, 13, 0, TAU, 32, Color.WHITE, 2.0, true)
			draw_line(Vector2.ZERO, Vector2(0, -8), Color.WHITE, 2.0)
			draw_line(Vector2.ZERO, Vector2(6, 2), Color.WHITE, 2.0)
		Type.PONTOS:
			var points := PackedVector2Array()
			var outer := 14.0
			var inner := 6.0
			for i in range(10):
				var angle: float = i * PI / 5.0 - PI / 2.0
				var r: float = outer if i % 2 == 0 else inner
				points.append(Vector2(cos(angle) * r, sin(angle) * r))
			draw_colored_polygon(points, Color(1, 0.85, 0.2))
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.7, 0.55, 0.05), 1.5, true)

func apply_effect() -> void:
	match type:
		Type.ESCUDO:
			GameManager.activate_shield(5.0)
		Type.LENTIDAO:
			GameManager.activate_slow_mo(4.0)
		Type.PONTOS:
			GameManager.score += 100
