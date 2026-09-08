extends Area2D

# Carro-obstáculo: agora nasce dentro de uma das 3 faixas e usa o
# mesmo desenho vetorial do carro do jogador, só que com cor aleatória.

var visual_colors: Array = [
	Color(0.85, 0.2, 0.2),
	Color(0.9, 0.5, 0.1),
	Color(0.55, 0.25, 0.85),
	Color(0.35, 0.35, 0.4),
	Color(0.15, 0.5, 0.25)
]

func _ready() -> void:
	add_to_group("obstacles")
	$Visual.set_color(visual_colors[randi() % visual_colors.size()])

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	position.y += GameManager.speed * delta
	if position.y > 800:
		queue_free()
