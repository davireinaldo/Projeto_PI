extends Node2D

# Marcas de pneu na pista (fica entre a pista e os carros). O jogador deixa
# marcas no gelo e nas trocas de faixa bruscas em alta velocidade; elas
# descem junto com o asfalto e vão sumindo.

const LIFE := 2.2
const COLOR := Color(0.04, 0.04, 0.05)

var marks: Array = [] # [ponto a, ponto b, idade]

func add(a: Vector2, b: Vector2) -> void:
	marks.append([a, b, 0.0])

func _process(delta: float) -> void:
	if GameManager.game_over:
		return # a pista para junto
	var dy := GameManager.speed * delta
	for m in marks:
		m[0].y += dy
		m[1].y += dy
		m[2] += delta
	marks = marks.filter(func(m): return m[2] < LIFE and m[0].y < 820.0)
	queue_redraw()

func _draw() -> void:
	for m in marks:
		var a: float = 0.55 * (1.0 - m[2] / LIFE)
		draw_line(m[0], m[1], Color(COLOR.r, COLOR.g, COLOR.b, a), 3.6)
