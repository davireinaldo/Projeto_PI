extends Area2D

# Carro do jogador: troca entre 3 faixas (setas, A/D, deslizar o dedo/mouse
# para o lado ou tocar na metade esquerda/direita da tela), com transição
# suave e inclinação.
# Os atributos vêm do carro selecionado na garagem.

const CarVisual := preload("res://scripts/CarVisual.gd")
const PlayerFX := preload("res://scripts/PlayerFX.gd")
const Paints := preload("res://scripts/Paints.gd")

signal crashed(other: Area2D)
signal coin_picked(coin: Area2D)
signal power_picked(power: Area2D)
signal hazard_hit(obstacle: Area2D)
signal steered

# quanto o dedo precisa andar na horizontal para contar como "deslizar"
const SWIPE_MIN := 40.0

var lane: int = 1
var lane_speed: float = 10.0
var car: Dictionary
var visual: Node2D
var history: Array = [] # posições x recentes (rastro da câmera lenta)
var ice_time: float = 0.0 # no gelo a troca de faixa fica lenta e o carro derrapa
var _touch_start: Variant = null # onde o dedo/mouse encostou (null = solto)
var _swiped: bool = false
var _t: float = 0.0

func _ready() -> void:
	add_to_group("player")
	car = GameManager.selected_car()
	lane_speed = car["lane_speed"]
	position = Vector2(GameManager.LANES[lane], GameManager.PLAYER_Y)

	var trail := PlayerFX.new()
	trail.player = self
	trail.mode = "trail"
	trail.z_index = -1
	add_child(trail)

	visual = CarVisual.new()
	Paints.apply(visual, car)
	add_child(visual)

	var bubble := PlayerFX.new()
	bubble.player = self
	bubble.mode = "bubble"
	bubble.z_index = 16 # o escudo brilha por cima da escuridão da noite
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
	var ls := lane_speed
	var wobble := 0.0
	if ice_time > 0.0:
		ice_time -= delta
		ls *= 0.3
		wobble = sin(_t * 14.0) * 0.12 * clamp(ice_time, 0.0, 1.0)
	position.x += diff * clamp(delta * ls, 0.0, 1.0)
	rotation = lerp(rotation, clamp(diff * 0.012, -0.25, 0.25) + wobble, 0.25)
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
		steered.emit()
	lane = new_lane

# Deslizar troca de faixa assim que o dedo anda SWIPE_MIN (dá para deslizar
# de novo sem soltar). Um toque rápido, sem deslizar, vale o lado da tela.
# O toque do celular chega aqui como mouse (emulação padrão do Godot).
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.game_over or get_tree().paused:
		_touch_start = null
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_start = event.position
			_swiped = false
		elif _touch_start != null:
			if not _swiped:
				_steer(-1 if event.position.x < get_viewport_rect().size.x * 0.5 else 1)
			_touch_start = null
	elif event is InputEventMouseMotion and _touch_start != null:
		var dx: float = event.position.x - _touch_start.x
		if abs(dx) >= SWIPE_MIN:
			_steer(1 if dx > 0.0 else -1)
			_swiped = true
			_touch_start = event.position

# Chamado pelo próprio obstáculo quando encosta no carro.
func hit_obstacle(o: Area2D) -> void:
	if GameManager.game_over:
		return
	if o.is_solid():
		crashed.emit(o)
	else:
		hazard_hit.emit(o)

# pulinho do carro ao passar num buraco
func bump() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(visual, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _on_area_entered(a: Area2D) -> void:
	if GameManager.game_over or a.is_in_group("obstacles"):
		return
	if a.is_in_group("traffic"):
		crashed.emit(a)
	elif a.is_in_group("coins"):
		coin_picked.emit(a)
	elif a.is_in_group("powerups"):
		power_picked.emit(a)
