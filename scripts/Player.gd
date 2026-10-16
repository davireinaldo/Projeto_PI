extends Area2D

# Carro do jogador: troca entre 3 faixas (setas, A/D ou clique/toque na
# metade esquerda/direita da tela), com transição suave e inclinação.
# Os atributos vêm do carro selecionado na garagem.

const CarVisual := preload("res://scripts/CarVisual.gd")
const PlayerFX := preload("res://scripts/PlayerFX.gd")

signal crashed(other: Area2D)
signal coin_picked(coin: Area2D)
signal power_picked(power: Area2D)

var lane: int = 1
var lane_speed: float = 10.0
var car: Dictionary
var visual: Node2D
var history: Array = [] # posições x recentes (rastro da câmera lenta)
var _t: float = 0.0

func _ready() -> void:
	car = GameManager.selected_car()
	lane_speed = car["lane_speed"]
	position = Vector2(GameManager.LANES[lane], GameManager.PLAYER_Y)

	var trail := PlayerFX.new()
	trail.player = self
	trail.mode = "trail"
	trail.z_index = -1
	add_child(trail)

	visual = CarVisual.new()
	visual.setup(car["model"], car["color"], car["accent"])
	add_child(visual)

	var bubble := PlayerFX.new()
	bubble.player = self
	bubble.mode = "bubble"
	add_child(bubble)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(28, 54)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	_t += delta
	if GameManager.debug_autopilot:
		lane = GameManager.ai_pick_lane(lane, position.y)
	else:
		if Input.is_action_just_pressed("steer_left"):
			_steer(-1)
		if Input.is_action_just_pressed("steer_right"):
			_steer(1)

	var target_x: float = GameManager.LANES[lane]
	var diff: float = target_x - position.x
	position.x += diff * clamp(delta * lane_speed, 0.0, 1.0)
	rotation = lerp(rotation, clamp(diff * 0.012, -0.25, 0.25), 0.25)
	GameManager.player_pos = position

	history.push_front(position.x)
	if history.size() > 8:
		history.pop_back()

	# pisca enquanto está invencível depois de perder uma vida
	visual.modulate.a = 0.35 if GameManager.grace_time > 0.0 and fmod(_t, 0.16) < 0.08 else 1.0

func _steer(dir: int) -> void:
	var new_lane: int = clamp(lane + dir, 0, 2)
	if new_lane != lane:
		AudioManager.play("whoosh", -4.0, 0.12)
	lane = new_lane

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.game_over or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_steer(-1 if event.position.x < get_viewport_rect().size.x * 0.5 else 1)

func _on_area_entered(a: Area2D) -> void:
	if GameManager.game_over:
		return
	if a.is_in_group("traffic"):
		crashed.emit(a)
	elif a.is_in_group("coins"):
		coin_picked.emit(a)
	elif a.is_in_group("powerups"):
		power_picked.emit(a)
