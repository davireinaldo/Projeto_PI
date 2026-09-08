extends Node2D

# Controla a telinha de seleção de carro: pinta cada um dos 3 carros de
# exemplo com a cor certa e desenha um destaque (círculo + setinha) em
# volta do carro atualmente selecionado.

@onready var previews: Array = [$Car1, $Car2, $Car3]
var index: int = 1

func _ready() -> void:
	for i in range(previews.size()):
		previews[i].set_color(GameManager.car_options[i].color)
	queue_redraw()

func set_index(i: int) -> void:
	index = i
	queue_redraw()

func _draw() -> void:
	var pos: Vector2 = previews[index].position
	draw_circle(pos, 38, Color(1, 1, 1, 0.15))
	draw_arc(pos, 38, 0, TAU, 40, Color(1, 0.85, 0.3, 0.9), 3.0, true)

	var arrow := PackedVector2Array([
		pos + Vector2(-9, 55), pos + Vector2(9, 55), pos + Vector2(0, 42)
	])
	draw_colored_polygon(arrow, Color(1, 0.85, 0.3, 0.9))
