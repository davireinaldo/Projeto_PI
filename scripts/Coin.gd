extends Area2D

# Moeda girando na pista. Com carro de ímã, é puxada até o jogador.

const UI := preload("res://scripts/UIKit.gd")

var magnet: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	add_to_group("coins")
	z_index = -1
	_t = randf() * TAU
	var shape := CircleShape2D.new()
	shape.radius = 13.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	if GameManager.running:
		magnet = float(GameManager.selected_car()["magnet"])

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	_t += delta
	position.y += GameManager.speed * delta
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
	UI.draw_coin(self, Vector2.ZERO, 10.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
