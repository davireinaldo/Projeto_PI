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
var threat: bool = false # vinha na faixa do jogador (para contar o raspão)
var passed: bool = false

var _state: int = 0 # 0 normal, 1 seta ligada, 2 trocando, 3 já trocou
var _target: int = -1
var _signal_t: float = 0.0
var _change_at_y: float = 0.0
var _t_giroflex: float = 0.0
var _siren_played: bool = false
var _giro_node: Node2D

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
		"police":
			m = "sport"
			c = Color(0.06, 0.08, 0.12)
			a = Color(0.95, 0.95, 0.98)
			own_speed = randf_range(160.0, 220.0)
		"ambulance":
			m = "van"
			c = Color(0.96, 0.96, 0.98)
			a = Color(0.85, 0.12, 0.15)
			own_speed = randf_range(150.0, 200.0)
		"racer":
			m = RACER_MODELS[randi() % RACER_MODELS.size()]
			var def: Dictionary = GameManager.cars[randi() % GameManager.cars.size()]
			c = def["color"]
			a = def["accent"]
			racer_rel = -randf_range(220.0, 320.0)
		_:
			own_speed = randf_range(50.0, 120.0)
			if m == "muscle":
				a = Color(1, 1, 1)
	visual = CarVisual.new()
	visual.setup(m, c, a)
	add_child(visual)

	if kind in ["police", "ambulance"]:
		_giro_node = Node2D.new()
		_giro_node.z_index = 10 # Desenha bem por cima do teto do carro
		_giro_node.draw.connect(_on_draw_giro)
		add_child(_giro_node)
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

func _on_draw_giro() -> void:
	if not is_instance_valid(_giro_node):
		return
	var phase: bool = fmod(_t_giroflex * 9.0, 1.0) < 0.5
	if kind == "police":
		var blue := Color(0.1, 0.6, 1.0)
		var red := Color(1.0, 0.15, 0.15)
		var c1: Color = blue if phase else red
		var c2: Color = red if phase else blue
		_giro_node.draw_rect(Rect2(-14, -6, 12, 10), c1)
		_giro_node.draw_rect(Rect2(2, -6, 12, 10), c2)
		_giro_node.draw_rect(Rect2(-2, -5, 4, 8), Color.WHITE)
		_giro_node.draw_circle(Vector2(-8, -1), 22.0, Color(c1.r, c1.g, c1.b, 0.45))
		_giro_node.draw_circle(Vector2(8, -1), 22.0, Color(c2.r, c2.g, c2.b, 0.45))
	elif kind == "ambulance":
		var red := Color(1.0, 0.1, 0.15)
		var amber := Color(1.0, 0.75, 0.1)
		var c1: Color = red if phase else amber
		var c2: Color = amber if phase else red
		_giro_node.draw_rect(Rect2(-14, -18, 8, 8), c1)
		_giro_node.draw_rect(Rect2(6, -18, 8, 8), c2)
		_giro_node.draw_rect(Rect2(-14, 12, 8, 8), c2)
		_giro_node.draw_rect(Rect2(6, 12, 8, 8), c1)
		_giro_node.draw_rect(Rect2(-3, -8, 6, 16), red)
		_giro_node.draw_rect(Rect2(-8, -3, 16, 6), red)
		_giro_node.draw_circle(Vector2(0, -14), 20.0, Color(c1.r, c1.g, c1.b, 0.4))

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	if kind in ["police", "ambulance"]:
		_t_giroflex += delta
		if is_instance_valid(_giro_node):
			_giro_node.queue_redraw()
		if not _siren_played and position.y > -100.0 and position.y < 600.0:
			_siren_played = true
			AudioManager.play("siren", 2.0, 0.05)
	var rel: float
	if kind == "racer":
		rel = _racer_logic()
	else:
		rel = _keep_distance(GameManager.speed - own_speed)
	rel_speed = rel
	position.y += rel * delta
	_lane_logic(delta)
	if kind == "racer":
		if position.y < -length - 120.0 or position.y > 850.0:
			queue_free()
	else:
		if position.y > 720.0 + length + 80.0 or position.y < -length - 250.0:
			queue_free()

# Não atravessa o veículo da frente na mesma faixa; se for mais rápido, dá seta e ultrapassa
func _keep_distance(rel: float) -> float:
	for o in get_tree().get_nodes_in_group("traffic"):
		if o == self or o.kind == "racer":
			continue
		if abs(o.position.x - position.x) > 34.0:
			continue
		var gap: float = o.position.y - position.y
		var need: float = (length + o.length) * 0.5
		if gap > 0.0 and gap < need + 110.0:
			# Se estiver mais rápido que o carro da frente, dá seta e muda de faixa para não ficar preso
			if _state == 0 and rel > o.rel_speed - 15.0:
				var options: Array = []
				for l in [lane - 1, lane + 1]:
					if l >= 0 and l <= 2 and _lane_free(l, 75.0):
						options.append(l)
				if not options.is_empty():
					_start_change(options[randi() % options.size()], true)
			if gap < need + 20.0:
				rel = min(rel, o.rel_speed)
	return rel

func _lane_free(l: int, margin: float) -> bool:
	for o in get_tree().get_nodes_in_group("traffic"):
		if o == self:
			continue
		# obstáculo parado acima: ele vai descer em cima, então a faixa não serve
		if o.is_in_group("obstacles") and o.occupies_lane(l) and o.position.y < position.y:
			return false
		if o.occupies_lane(l) and abs(o.position.y - position.y) < (length + o.length) * 0.5 + margin:
			return false
	return true

func _start_change(l: int, with_signal: bool) -> void:
	_target = l
	visual.blink = sign(l - lane)
	_state = 1 if with_signal else 2
	_signal_t = 0.45
	if with_signal and GameManager.running and randf() < 0.25:
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
			position.x = move_toward(position.x, tx, 150.0 * delta)
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
	var ahead_nodes: Array = get_tree().get_nodes_in_group("traffic") + get_tree().get_nodes_in_group("player")
	for o in ahead_nodes:
		var occupies: bool = o.occupies_lane(lane) if o.has_method("occupies_lane") else (abs(o.position.x - GameManager.LANES[lane]) < 55.0)
		if o == self or not occupies:
			continue
		var gap: float = position.y - o.position.y
		var o_len: float = o.length if "length" in o else 54.0
		var need: float = (length + o_len) * 0.5
		if gap > 0.0 and gap < need + 160.0:
			for l in [lane - 1, lane + 1]:
				if l >= 0 and l <= 2 and _lane_free(l, 70.0):
					_start_change(l, false)
					return rel
			# Se estiver atrás do jogador e não puder desviar, freia imediatamente
			if gap < need + 40.0:
				rel = 0.0 if o.is_in_group("player") else max(rel, -30.0)
	return rel
