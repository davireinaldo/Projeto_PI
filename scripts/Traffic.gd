extends Area2D

# Veículo do tráfego. Tipos:
#   "car"   -> carro comum (alguns ligam a seta e trocam de faixa)
#   "truck" -> caminhão comprido e lento
#   "bus"   -> ônibus, raro e maior
#   "racer" -> rival que ultrapassa subindo a tela (só no menu)
# Todos andam para frente com own_speed; na tela descem com
# (velocidade da pista - own_speed).

const CarVisual := preload("res://scripts/CarVisual.gd")

const CAR_MODELS := ["sedan", "sedan", "taxi", "van", "sport", "coupe", "muscle"]
const CAR_COLORS := [
	Color(0.85, 0.2, 0.2), Color(0.9, 0.5, 0.1), Color(0.55, 0.25, 0.85), Color(0.35, 0.35, 0.4),
	Color(0.15, 0.5, 0.25), Color(0.92, 0.92, 0.94), Color(0.1, 0.3, 0.6), Color(0.6, 0.1, 0.15)]
const RACER_MODELS := ["sport", "coupe", "f1", "muscle", "legend"]

var kind: String = "car"
var lane: int = 0
var own_speed: float = 80.0
var racer_rel: float = -180.0
var length: float = 64.0
var rel_speed: float = 0.0
var changer: bool = false
var visual: Node2D

var _state: int = 0 # 0 normal, 1 seta ligada, 2 trocando, 3 já trocou
var _target: int = -1
var _signal_t: float = 0.0
var _change_at_y: float = 0.0

func setup(k: String, l: int, y: float, can_change: bool = false) -> void:
	kind = k
	lane = l
	changer = can_change
	position = Vector2(GameManager.LANES[l], y)

func _ready() -> void:
	add_to_group("traffic")
	var m: String = CAR_MODELS[randi() % CAR_MODELS.size()]
	var c: Color = CAR_COLORS[randi() % CAR_COLORS.size()]
	var a := Color.WHITE
	match kind:
		"truck":
			m = "truck"
			c = [Color(0.8, 0.15, 0.15), Color(0.15, 0.35, 0.75), Color(0.95, 0.95, 0.95), Color(0.2, 0.55, 0.3)][randi() % 4]
			a = [Color(0.88, 0.88, 0.9), Color(0.75, 0.78, 0.82), Color(0.95, 0.75, 0.3), Color(0.3, 0.5, 0.7)][randi() % 4]
			own_speed = randf_range(0.0, 40.0)
		"bus":
			m = "bus"
			c = [Color(1, 0.78, 0.1), Color(0.92, 0.92, 0.95), Color(0.2, 0.5, 0.85)][randi() % 3]
			a = Color(0.15, 0.6, 0.3)
			own_speed = randf_range(20.0, 50.0)
		"racer":
			m = RACER_MODELS[randi() % RACER_MODELS.size()]
			var def: Dictionary = GameManager.cars[randi() % GameManager.cars.size()]
			c = def["color"]
			a = def["accent"]
			racer_rel = -randf_range(140.0, 240.0)
		_:
			own_speed = randf_range(50.0, 120.0)
			if m == "muscle":
				a = Color(1, 1, 1)
	visual = CarVisual.new()
	visual.setup(m, c, a)
	add_child(visual)
	var size: Vector2 = CarVisual.model_size(m)
	length = size.y
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size.x - 8, size.y - 8)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	_change_at_y = randf_range(30.0, 260.0)

func occupies_lane(l: int) -> bool:
	if abs(position.x - GameManager.LANES[l]) < 60.0:
		return true
	return _target == l and (_state == 1 or _state == 2)

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	var rel: float
	if kind == "racer":
		rel = _racer_logic()
	else:
		rel = _keep_distance(GameManager.speed - own_speed)
	rel_speed = rel
	position.y += rel * delta
	_lane_logic(delta)
	if position.y > 720.0 + length or position.y < -length - 250.0:
		queue_free()

# não atravessa o veículo da frente na mesma faixa
func _keep_distance(rel: float) -> float:
	for o in get_tree().get_nodes_in_group("traffic"):
		if o == self or o.kind == "racer":
			continue
		if abs(o.position.x - position.x) > 34.0:
			continue
		var gap: float = o.position.y - position.y
		if gap > 0.0 and gap < (length + o.length) * 0.5 + 16.0:
			rel = min(rel, o.rel_speed)
	return rel

func _lane_free(l: int, margin: float) -> bool:
	for o in get_tree().get_nodes_in_group("traffic"):
		if o == self:
			continue
		if o.occupies_lane(l) and abs(o.position.y - position.y) < (length + o.length) * 0.5 + margin:
			return false
	return true

func _start_change(l: int, with_signal: bool) -> void:
	_target = l
	visual.blink = sign(l - lane)
	_state = 1 if with_signal else 2
	_signal_t = 0.9
	# às vezes o motorista buzina antes de mudar de faixa
	if with_signal and GameManager.running and randf() < 0.35:
		AudioManager.play("horn", -10.0, 0.15)

func _lane_logic(delta: float) -> void:
	match _state:
		0:
			if changer and kind == "car" and position.y > _change_at_y:
				var options: Array = []
				for l in [lane - 1, lane + 1]:
					if l >= 0 and l <= 2 and _lane_free(l, 90.0):
						options.append(l)
				if options.is_empty():
					_state = 3
				else:
					_start_change(options[randi() % options.size()], true)
		1:
			_signal_t -= delta
			if _signal_t <= 0.0:
				_state = 2
		2:
			var tx: float = GameManager.LANES[_target]
			position.x = move_toward(position.x, tx, 120.0 * delta)
			rotation = sign(tx - position.x) * 0.12
			if is_equal_approx(position.x, tx):
				lane = _target
				_target = -1
				rotation = 0.0
				visual.blink = 0
				_state = 0 if kind == "racer" else 3

func _racer_logic() -> float:
	var rel := racer_rel
	if _state != 0:
		return rel
	for o in get_tree().get_nodes_in_group("traffic"):
		if o == self or not o.occupies_lane(lane):
			continue
		var gap: float = position.y - o.position.y
		var need: float = (length + o.length) * 0.5
		if gap > 0.0 and gap < need + 150.0:
			for l in [lane - 1, lane + 1]:
				if l >= 0 and l <= 2 and _lane_free(l, 60.0):
					_start_change(l, false)
					return rel
			if gap < need + 20.0:
				rel = max(rel, o.rel_speed)
	return rel
