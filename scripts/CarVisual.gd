extends Node2D

# Script reutilizado pelo carro do jogador, pelos carros-obstáculo e pela
# telinha de seleção de carro.
#
# Se "car_texture" estiver definida (por padrão já vem preenchida com a
# imagem em res://assets/images/player_car.png), o carro é desenhado usando
# essa imagem. Caso contrário, cai de volta no desenho vetorial antigo.

@export var body_color: Color = Color(0.2, 0.6, 1.0)
@export var car_texture: Texture2D = preload("res://assets/images/player_car.png")
@export var tint_texture: bool = false # true = pinta a imagem com body_color
@export var visual_width: float = 36.0 # largura alvo do desenho (mesma da colisão)

func set_color(c: Color) -> void:
	body_color = c
	queue_redraw()

func _draw() -> void:
	if car_texture:
		_draw_textured()
	else:
		_draw_vector()

func _draw_textured() -> void:
	var tex_size: Vector2 = car_texture.get_size()
	var scale_factor: float = visual_width / tex_size.x
	var draw_size: Vector2 = tex_size * scale_factor
	var rect := Rect2(-draw_size * 0.5, draw_size)
	var modulate_color := Color(1, 1, 1, 1)
	if tint_texture:
		modulate_color = body_color.lightened(0.15)
	draw_texture_rect(car_texture, rect, false, modulate_color)

func _draw_vector() -> void:
	# carroceria (silhueta tipo "hexágono arredondado")
	var body := PackedVector2Array([
		Vector2(-14, -32), Vector2(14, -32),
		Vector2(18, -10), Vector2(18, 20),
		Vector2(14, 32), Vector2(-14, 32),
		Vector2(-18, 20), Vector2(-18, -10)
	])
	draw_colored_polygon(body, body_color)
	draw_polyline(body + PackedVector2Array([body[0]]), body_color.darkened(0.45), 2.0, true)

	# faixa central no teto
	draw_rect(Rect2(Vector2(-3, -8), Vector2(6, 16)), body_color.lightened(0.25))

	# para-brisa dianteiro
	var windshield := PackedVector2Array([
		Vector2(-10, -26), Vector2(10, -26), Vector2(8, -8), Vector2(-8, -8)
	])
	draw_colored_polygon(windshield, Color(0.08, 0.1, 0.16, 0.9))

	# vidro traseiro
	var rear_window := PackedVector2Array([
		Vector2(-8, 18), Vector2(8, 18), Vector2(10, 30), Vector2(-10, 30)
	])
	draw_colored_polygon(rear_window, Color(0.08, 0.1, 0.16, 0.7))

	# rodas
	var wheel_color := Color(0.05, 0.05, 0.05)
	draw_rect(Rect2(Vector2(-19, -20), Vector2(6, 14)), wheel_color)
	draw_rect(Rect2(Vector2(13, -20), Vector2(6, 14)), wheel_color)
	draw_rect(Rect2(Vector2(-19, 6), Vector2(6, 14)), wheel_color)
	draw_rect(Rect2(Vector2(13, 6), Vector2(6, 14)), wheel_color)

	# faróis e lanternas
	draw_rect(Rect2(Vector2(-12, -31), Vector2(5, 4)), Color(1, 0.95, 0.6))
	draw_rect(Rect2(Vector2(7, -31), Vector2(5, 4)), Color(1, 0.95, 0.6))
	draw_rect(Rect2(Vector2(-12, 27), Vector2(5, 4)), Color(0.9, 0.1, 0.1))
	draw_rect(Rect2(Vector2(7, 27), Vector2(5, 4)), Color(0.9, 0.1, 0.1))
