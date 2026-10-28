extends Node2D

# Efeitos presos ao carro do jogador:
#   mode "trail"  -> rastro escolhido na Pintura, chamas do nitro e fantasmas
#                    da câmera lenta (fica embaixo do carro)
#   mode "bubble" -> bolha do escudo pulsando (fica em cima do carro)

const Paints := preload("res://scripts/Paints.gd")

var player: Node2D
var mode: String = "trail"
var _t: float = 0.0
var _trail: Dictionary = {}

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if GameManager.game_over:
		return
	if mode == "trail":
		_draw_nitro()
		_draw_trail()
	else:
		_draw_bubble()

# rastro escolhido na Pintura: faixas de luz sempre e chamas no nitro
func _draw_nitro() -> void:
	if _trail.is_empty():
		_trail = Paints.current("trail", player.car["id"])
	var offs: Array = []
	for x in player.history:
		offs.append(x - player.position.x)
	var k: float = clamp((GameManager.nitro_factor - 1.0) / 0.65, 0.0, 1.0)
	Paints.draw_ribbon(self, _trail, offs, _t, k)
	Paints.draw_nitro(self, _trail, offs, _t, k)

func _draw_trail() -> void:
	var strength: float = clamp((1.0 - GameManager.slow_factor) * 2.0, 0.0, 1.0)
	if strength <= 0.02:
		return
	var c: Color = player.car["accent"] if player.car["model"] == "legend" and not player.visual.painted else player.visual.body_color
	var hist: Array = player.history
	for i in range(1, hist.size()):
		var ox: float = hist[i] - player.position.x
		var a := strength * 0.4 * (1.0 - float(i) / hist.size())
		var r := Rect2(Vector2(ox - 15, -26 + i * 14), Vector2(30, 56))
		draw_rect(r, Color(c.r, c.g, c.b, a))
		draw_rect(r.grow(3), Color(0.85, 0.4, 1.0, a * 0.5), false, 2.0)
	# linhas de velocidade
	for i in range(6):
		var x := -40.0 + i * 16.0
		var y := fmod(_t * 900.0 + i * 37.0, 160.0)
		draw_line(Vector2(x, y), Vector2(x, y + 40), Color(0.9, 0.7, 1.0, 0.35 * strength), 2.0)

func _draw_bubble() -> void:
	if GameManager.shield_time > 0.0:
		var left := GameManager.shield_time
		if left < 1.5 and fmod(_t, 0.2) < 0.1:
			return # piscando: o escudo está acabando
		var r := 46.0 + sin(_t * 6.0) * 2.5
		draw_circle(Vector2.ZERO, r, Color(0.3, 0.9, 1.0, 0.12))
		draw_circle(Vector2.ZERO, r * 0.8, Color(0.3, 0.9, 1.0, 0.06))
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(0.45, 0.95, 1.0, 0.9), 3.0, true)
		for i in range(6):
			var a := _t * 1.6 + i * TAU / 6.0
			draw_arc(Vector2.ZERO, r - 7, a, a + 0.55, 8, Color(0.8, 1.0, 1.0, 0.65), 2.0, true)
		draw_arc(Vector2.ZERO, r + 4, -PI * 0.5, -PI * 0.5 + TAU * (left / max(GameManager.shield_total, 0.01)),
			48, Color(1, 1, 1, 0.5), 2.0, true)
	elif GameManager.grace_time > 0.0:
		draw_arc(Vector2.ZERO, 40, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0, true)
