extends Node2D

# Efeitos presos ao carro do jogador:
#   mode "trail"  -> rastro/fantasmas durante a câmera lenta (fica embaixo do carro)
#   mode "bubble" -> bolha do escudo pulsando (fica em cima do carro)

var player: Node2D
var mode: String = "trail"
var _t: float = 0.0

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

# chamas saindo do escapamento + rastro alaranjado durante o nitro
func _draw_nitro() -> void:
	var k: float = clamp((GameManager.nitro_factor - 1.0) / 0.65, 0.0, 1.0)
	if k <= 0.02:
		return
	for i in range(1, player.history.size()):
		var ox: float = player.history[i] - player.position.x
		var a: float = 0.3 * k * (1.0 - float(i) / player.history.size())
		draw_rect(Rect2(Vector2(ox - 13, 10 + i * 12), Vector2(26, 30)), Color(1, 0.45, 0.1, a))
	for sx in [-8.0, 8.0]:
		var len := (26.0 + randf() * 18.0) * k
		var base := Vector2(sx, 30)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-6, 0), base + Vector2(6, 0), base + Vector2(0, len)]),
			Color(1, 0.4, 0.05, 0.85))
		draw_colored_polygon(PackedVector2Array([base + Vector2(-3.5, 0), base + Vector2(3.5, 0), base + Vector2(0, len * 0.6)]),
			Color(1, 0.9, 0.4, 0.95))
		draw_circle(base, 7, Color(1, 0.6, 0.1, 0.4))

func _draw_trail() -> void:
	var strength: float = clamp((1.0 - GameManager.slow_factor) * 2.0, 0.0, 1.0)
	if strength <= 0.02:
		return
	var c: Color = player.car["accent"] if player.car["model"] == "legend" else player.car["color"]
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
