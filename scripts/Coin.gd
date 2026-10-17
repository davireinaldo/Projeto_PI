extends Area2D

# Moeda girando na pista. Com carro de ímã (ou o poder ímã), é puxada até o jogador.

const UI := preload("res://scripts/UIKit.gd")

var _t: float = 0.0

func _ready() -> void:
	add_to_group("coins")
	z_index = 16 # brilha por cima da escuridão da noite
	_t = randf() * TAU
	var shape := CircleShape2D.new()
	shape.radius = 13.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	_t += delta
	position.y += GameManager.speed * delta
	var magnet := GameManager.magnet_radius()
	if magnet > 0.0:
		var to := GameManager.player_pos - position
		if to.length() < magnet:
			position += to.normalized() * min(to.length(), 600.0 * delta)
	queue_redraw()
	if position.y > 760.0:
		queue_free()

func _draw() -> void:
	var sx: float = max(abs(cos(_t * 4.0)), 0.15)
	draw_circle(Vector2(2, 4), 10, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx, 1.0))
	draw_circle(Vector2.ZERO, 12, Color(1, 0.85, 0.2, 0.25))
	if GameManager.x2_time > 0.0:
		draw_circle(Vector2.ZERO, 15, Color(0.35, 1, 0.45, 0.3 + 0.15 * sin(_t * 8.0)))
	UI.draw_coin(self, Vector2.ZERO, 10.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
