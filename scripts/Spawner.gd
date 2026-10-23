extends Node

# Cria tráfego, moedas, power-ups, rivais velozes (racers) e zonas de obras.
# GARANTIA ESTRITA DE PASSABILIDADE:
# Nunca fecha as 3 faixas ao mesmo tempo nem cria situações sem rota de fuga.

const Traffic := preload("res://scripts/Traffic.gd")
const Coin := preload("res://scripts/Coin.gd")
const PowerUp := preload("res://scripts/PowerUp.gd")
const Obstacle := preload("res://scripts/Obstacle.gd")

signal racer_warning(lane: int)
signal work_zone_started(lane: int)
signal work_zone_ended()

# Obstáculos de cada cenário (o campo é tranquilo)
const BIOME_OBSTACLES := {
	"cidade": ["cone", "cone", "bueiro"],
	"deserto": ["duna"],
	"mar": ["poca"],
	"neve": ["gelo"],
	"neon": ["barreira"],
}

var container: Node2D
var spawn_coins: bool = true
var spawn_powerups: bool = true
var spawn_obstacles: bool = true

var _traffic_t: float = 1.2
var _coin_t: float = 1.5
var _power_t: float = 5.0
var _obstacle_t: float = 3.0

# Racers e Dinâmicas
var _racer_t: float = 14.0
var _racer_warning_lane: int = -1
var _racer_warning_timer: float = 0.0

# Trechos em obras
var work_zone_active: bool = false
var work_zone_lane: int = -1
var _work_zone_interval: float = 30.0
var _work_zone_timer: float = 0.0
var _work_cone_timer: float = 0.0

# 0 no começo, 1 na velocidade máxima
func difficulty() -> float:
	return clamp((GameManager.cruise_speed - GameManager.base_speed) / (GameManager.max_speed - GameManager.base_speed), 0.0, 1.0)

func _process(delta: float) -> void:
	if GameManager.game_over or container == null:
		return
	var f := difficulty()

	# Tráfego regular e emergências
	_traffic_t -= delta
	if _traffic_t <= 0.0:
		_spawn_traffic(f)
		_traffic_t = lerp(1.15, 0.48, f) * randf_range(0.85, 1.2)

	# Moedas
	if spawn_coins:
		_coin_t -= delta
		if _coin_t <= 0.0:
			_spawn_coin_line()
			_coin_t = randf_range(2.0, 3.4)

	# Power-ups
	if spawn_powerups:
		_power_t -= delta
		if _power_t <= 0.0:
			_spawn_powerup()
			_power_t = randf_range(6.5, 10.0)

	# Obstáculos
	if spawn_obstacles and GameManager.running:
		_obstacle_t -= delta
		if _obstacle_t <= 0.0:
			if _spawn_obstacle():
				_obstacle_t = randf_range(3.2, 5.8) - f * 1.0
			else:
				_obstacle_t = 0.4

	# Racers (durante a corrida, surgem do rodapé com aviso prévio)
	# NUNCA surgem durante trecho em obras nem na faixa do jogador
	if GameManager.running and not GameManager.game_over:
		if _racer_warning_lane >= 0:
			_racer_warning_timer -= delta
			if _racer_warning_timer <= 0.0:
				if not work_zone_active:
					spawn_racer(_racer_warning_lane)
				_racer_warning_lane = -1
		elif not work_zone_active:
			_racer_t -= delta
			if _racer_t <= 0.0 and GameManager.distance_m > 300.0:
				_racer_t = randf_range(18.0, 30.0)
				_try_start_racer_warning()

		# Trecho em Obras temporário
		if work_zone_active:
			_work_zone_timer -= delta
			_work_cone_timer -= delta
			if _work_cone_timer <= 0.0:
				_work_cone_timer = 0.55
				_spawn_work_cone(work_zone_lane)
			if _work_zone_timer <= 0.0:
				work_zone_active = false
				work_zone_lane = -1
				work_zone_ended.emit()
		else:
			_work_zone_interval -= delta
			if _work_zone_interval <= 0.0 and GameManager.distance_m > 400.0:
				_work_zone_interval = randf_range(35.0, 52.0)
				_start_work_zone()

func _traffic() -> Array:
	return container.get_tree().get_nodes_in_group("traffic")

# Faixa sem ninguém (veículo ou obstáculo) perto do topo da tela?
func lane_clear_top(l: int, depth: float) -> bool:
	for t in _traffic() + container.get_tree().get_nodes_in_group("obstacles"):
		if t.kind != "racer" and t.occupies_lane(l) and t.position.y - t.length * 0.5 < depth:
			return false
	return true

func _items_clear_top(l: int, depth: float) -> bool:
	for group in ["coins", "powerups"]:
		for it in container.get_tree().get_nodes_in_group(group):
			if abs(it.position.x - GameManager.LANES[l]) < 50.0 and it.position.y < depth:
				return false
	return true

# Regra matemática estrita de passabilidade:
# Garante que SEMPRE exista pelo menos um corredor totalmente transitável.
func _can_spawn(l: int, f: float) -> bool:
	if work_zone_active and l == work_zone_lane:
		return false

	# Durante obras, apenas UMA das faixas abertas pode ter veículos por vez!
	if work_zone_active:
		var remaining := [0, 1, 2]
		remaining.erase(work_zone_lane)
		var other_lane: int = remaining[1] if remaining[0] == l else remaining[0]
		for t in _traffic() + container.get_tree().get_nodes_in_group("obstacles"):
			if t.occupies_lane(other_lane) and t.position.y > -100.0 and t.position.y < 680.0:
				return false

	if not lane_clear_top(l, 180.0):
		return false

	# Verificação de ocupação horizontal em fatias verticais da pista:
	var all_items: Array = _traffic() + container.get_tree().get_nodes_in_group("obstacles")
	var slices := {}
	slices[0] = {l: true}

	for t in all_items:
		if t.kind == "racer":
			continue
		var ty: float = t.position.y
		if ty > -100.0 and ty < 680.0:
			var s_idx: int = int(round(ty / 130.0))
			if not slices.has(s_idx):
				slices[s_idx] = {}
			for k in range(3):
				if t.occupies_lane(k):
					slices[s_idx][k] = true

	for s_idx in slices.keys():
		var occ: Dictionary = slices[s_idx]
		if work_zone_active:
			occ[work_zone_lane] = true
		if occ.size() >= 3:
			return false

	return true

func _spawn_traffic(f: float) -> void:
	var heavy_count := 0
	for t in _traffic():
		if t.kind in ["truck", "bus"]:
			heavy_count += 1

	var r := randf()
	var kind := "car"
	if r < 0.07 and GameManager.distance_m > 250.0:
		kind = "police"
	elif r < 0.14 and GameManager.distance_m > 250.0:
		kind = "ambulance"
	elif r < 0.28 + 0.08 * f and heavy_count == 0 and not work_zone_active:
		kind = "truck"
	elif r < 0.35 + 0.08 * f and heavy_count == 0 and not work_zone_active:
		kind = "bus"

	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if _can_spawn(l, f):
			var t := Traffic.new()
			var changer: bool = kind == "car" and randf() < 0.15 + 0.25 * f and not work_zone_active
			t.setup(kind, l, -90.0, changer)
			container.add_child(t)
			return

func _try_start_racer_warning() -> void:
	if work_zone_active:
		return

	var player_node: Node2D = container.get_tree().get_first_node_in_group("player")
	var p_lane: int = player_node.lane if is_instance_valid(player_node) and "lane" in player_node else 1

	# NUNCA escolher a faixa do jogador (o rival nunca deve vir por trás do jogador)
	var candidate_lanes: Array = []
	for l in [0, 1, 2]:
		if l != p_lane:
			candidate_lanes.append(l)
	candidate_lanes.shuffle()

	for l in candidate_lanes:
		# A faixa deve estar totalmente livre de cima a baixo
		if not _lane_completely_clear(l):
			continue
		_racer_warning_lane = l
		_racer_warning_timer = 1.5
		racer_warning.emit(l)
		return

func _lane_completely_clear(l: int) -> bool:
	for t in _traffic() + container.get_tree().get_nodes_in_group("obstacles"):
		if t.occupies_lane(l) and t.position.y > -100.0 and t.position.y < 700.0:
			return false
	return true

func _lane_clear_player(l: int) -> bool:
	for t in _traffic() + container.get_tree().get_nodes_in_group("obstacles"):
		if t.kind == "racer":
			continue
		if t.occupies_lane(l) and abs(t.position.y - GameManager.PLAYER_Y) < 140.0:
			return false
	return true

func _bottom_clear(l: int) -> bool:
	for t in get_tree().get_nodes_in_group("traffic"):
		if t.occupies_lane(l) and t.position.y > 520.0:
			return false
	return true

func spawn_racer(l: int) -> void:
	var t := Traffic.new()
	t.setup("racer", l, 740.0)
	container.add_child(t)

func _spawn_coin_line() -> void:
	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if (not work_zone_active or l != work_zone_lane) and lane_clear_top(l, 260.0):
			for i in range(5):
				var c := Coin.new()
				c.position = Vector2(GameManager.LANES[l], -30.0 - i * 46.0)
				container.add_child(c)
			return

func _spawn_obstacle() -> bool:
	if GameManager.distance_m - GameManager.debug_start_m < 300.0 or work_zone_active:
		return true
	var kinds: Array = BIOME_OBSTACLES.get(GameManager.biome_id_at(GameManager.distance_m), [])
	if kinds.is_empty():
		return true
	var kind: String = kinds[randi() % kinds.size()]
	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if not lane_clear_top(l, 200.0) or not _items_clear_top(l, 120.0):
			continue
		if kind in ["cone", "barreira"] and (not _can_spawn(l, difficulty()) or not _wont_catch_up(l)):
			continue
		var o := Obstacle.new()
		o.setup(kind, l, -70.0)
		container.add_child(o)
		return true
	return false

func _start_work_zone() -> void:
	# Escolhe sempre a faixa esquerda (0) ou direita (2) para fechar, deixando o resto limpo
	work_zone_lane = 0 if randf() < 0.5 else 2
	work_zone_active = true
	_work_zone_timer = 8.5 # dura cerca de 8.5s
	_work_cone_timer = 0.0
	work_zone_started.emit(work_zone_lane)

func _spawn_work_cone(l: int) -> void:
	var o := Obstacle.new()
	o.setup("cone", l, -60.0, true)
	container.add_child(o)

func _wont_catch_up(l: int) -> bool:
	for t in _traffic():
		if t.is_in_group("obstacles") or t.kind == "racer" or not t.occupies_lane(l):
			continue
		var half: float = t.length * 0.5
		var gap: float = (t.position.y - half) - (-70.0 + 20.0)
		var catch_t: float = gap / max(t.own_speed, 1.0)
		var exit_t: float = (760.0 + half - t.position.y) / max(GameManager.speed - t.own_speed, 1.0)
		if exit_t > catch_t - 0.3:
			return false
	return true

func _spawn_powerup() -> void:
	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if (not work_zone_active or l != work_zone_lane) and lane_clear_top(l, 200.0):
			var p := PowerUp.new()
			p.position = Vector2(GameManager.LANES[l], -40.0)
			container.add_child(p)
			return
