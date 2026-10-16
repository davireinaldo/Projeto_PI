extends Control

# Control "em branco" que chama uma função de desenho de fora.
# Assim cada tela desenha velocímetro, barras, logo etc. sem precisar
# de um script separado para cada coisinha.

var fn: Callable
var auto: bool = true # redesenha todo frame

func _init(draw_fn: Callable = Callable(), rect: Rect2 = Rect2(0, 0, 480, 720)) -> void:
	fn = draw_fn
	position = rect.position
	size = rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if auto:
		queue_redraw()

func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
