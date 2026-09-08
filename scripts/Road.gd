extends Node2D

# Desenha a pista: asfalto, faixas tracejadas rolando (na velocidade
# atual do jogo) e grama listrada nas laterais.
# A pista para de rolar assim que o jogo termina (GameManager.game_over).

var lane_xs: Array = [140.0, 240.0, 340.0]
var road_left: float = 90.0
var road_right: float = 390.0
var viewport_w: float = 480.0
var viewport_h: float = 720.0
var scroll_offset: float = 0.0

func _ready() -> void:
	z_index = -10

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	scroll_offset = fmod(scroll_offset + GameManager.speed * delta, 40.0)
	queue_redraw()

func _draw() -> void:
	# grama de fundo
	draw_rect(Rect2(Vector2(0, 0), Vector2(viewport_w, viewport_h)), Color(0.16, 0.42, 0.19))

	# listras de grama (efeito "gramado cortado")
	var stripe_w := 32.0
	var i := 0
	while i * stripe_w < road_left:
		if i % 2 == 0:
			draw_rect(Rect2(Vector2(i * stripe_w, 0), Vector2(stripe_w, viewport_h)), Color(0.19, 0.47, 0.22))
		i += 1

	i = 0
	while road_right + i * stripe_w < viewport_w:
		if i % 2 == 0:
			draw_rect(Rect2(Vector2(road_right + i * stripe_w, 0), Vector2(stripe_w, viewport_h)), Color(0.19, 0.47, 0.22))
		i += 1

	# asfalto
	draw_rect(Rect2(Vector2(road_left, 0), Vector2(road_right - road_left, viewport_h)), Color(0.16, 0.16, 0.19))

	# linhas laterais sólidas
	draw_rect(Rect2(Vector2(road_left - 4, 0), Vector2(6, viewport_h)), Color(0.92, 0.92, 0.9))
	draw_rect(Rect2(Vector2(road_right - 2, 0), Vector2(6, viewport_h)), Color(0.92, 0.92, 0.9))

	# linhas tracejadas entre as 3 faixas, rolando de acordo com a velocidade
	var dividers := [(lane_xs[0] + lane_xs[1]) / 2.0, (lane_xs[1] + lane_xs[2]) / 2.0]
	for dx in dividers:
		var y := -40.0 + scroll_offset
		while y < viewport_h:
			draw_rect(Rect2(Vector2(dx - 3, y), Vector2(6, 24)), Color(1, 1, 0.85, 0.85))
			y += 40.0
