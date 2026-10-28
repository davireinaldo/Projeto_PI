extends Node

# Cria tráfego, moedas, power-ups, rivais velozes (racers) e zonas de obras.
# GARANTIA ESTRITA DE PASSABILIDADE:
# Nunca fecha as 3 faixas ao mesmo tempo nem cria situações sem rota de fuga.
# Durante bloqueios/obras em 1 faixa, os carros alternam entre as 2 faixas livres
# com espaçamento vertical seguro (zigue-zague), nunca vindo lado a lado.

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
var spawn_racers: bool = true
var spawn_work_zones: bool = true
# faixas que nunca ficam fechadas na mesma altura (no versus, 1 por jogador)
var min_free_lanes: int = 1
var traffic_rate: float = 1.0 # mais que 1 = carros saem mais seguido

var _traffic_t: float = 1.2
var _coin_t: float = 1.5
var _power_t: float = 5.0
var _obstacle_t: float = 3.0
var _last_traffic_lane: int = -1

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

func _ready() -> void:
	add_to_group("spawner")

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
		if _spawn_traffic(f):
			_traffic_t = lerp(1.1, 0.48, f) * randf_range(0.85, 1.15) / traffic_rate
		else:
			_traffic_t = 0.15

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
		var in_work: bool = work_zone_active or _has_work_cones_on_screen()
		if _racer_warning_lane >= 0:
			_racer_warning_timer -= delta
			if _racer_warning_timer <= 0.0:
				if not in_work:
					spawn_racer(_racer_warning_lane)
				_racer_warning_lane = -1
		elif not in_work and spawn_racers:
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
		elif spawn_work_zones:
			_work_zone_interval -= delta
			if _work_zone_interval <= 0.0 and GameManager.distance_m > 400.0:
				_start_work_zone()

func _traffic() -> Array:
	return container.get_tree().get_nodes_in_group("traffic")

func _all_blockers() -> Array:
	var res: Array = []
	var seen := {}
	for group in ["traffic", "obstacles"]:
		for n in container.get_tree().get_nodes_in_group(group):
			if not seen.has(n):
				seen[n] = true
				res.append(n)
	return res

func _has_work_cones_on_screen() -> bool:
	for o in container.get_tree().get_nodes_in_group("obstacles"):
		if "is_work_zone" in o and o.is_work_zone and o.position.y < 640.0:
			return true
	return false

# Faixa sem ninguém (veículo ou obstáculo) perto do topo da tela?
func lane_clear_top(l: int, depth: float) -> bool:
	for t in _all_blockers():
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
# Simula a trajetória até passar pelo jogador e garante que as 3 faixas NUNCA fiquem
# fechadas na mesma faixa horizontal (mantendo um corredor de zigue-zague sempre aberto).
func _can_spawn(l: int, _f: float, spawn_y: float = -90.0, own_spd: float = 85.0, new_len: float = 64.0) -> bool:
	if work_zone_active and l == work_zone_lane:
		return false
	if _racer_warning_lane == l:
		return false

	var blockers: Array = _all_blockers()
	var reserved_lanes := {}
	if work_zone_active and work_zone_lane >= 0:
		reserved_lanes[work_zone_lane] = true
	if _racer_warning_lane >= 0:
		reserved_lanes[_racer_warning_lane] = true

	for b in blockers:
		if b.kind == "racer" and b.position.y > -100.0 and b.position.y < 740.0:
			if b.occupies_lane(l):
				return false
			for k in range(GameManager.lane_count):
				if b.occupies_lane(k):
					reserved_lanes[k] = true
		elif "is_work_zone" in b and b.is_work_zone and b.position.y < 640.0:
			if b.lane == l:
				return false
			reserved_lanes[b.lane] = true

	if not lane_clear_top(l, 230.0):
		return false

	var road_spd: float = max(GameManager.speed, 320.0)
	var new_rel: float = max(road_spd - own_spd, 60.0)

	# 1. Evita alcançar e colar na traseira de um veículo mais lento na mesma faixa
	for b in blockers:
		if b.kind == "racer":
			continue
		if b.occupies_lane(l) and b.position.y > spawn_y and b.position.y < 640.0:
			var b_own: float = b.own_speed if "own_speed" in b else 0.0
			var b_rel: float = max(road_spd - b_own, 60.0)
			var b_len: float = b.length if "length" in b else 50.0
			if new_rel > b_rel:
				var t_exit: float = (640.0 - b.position.y) / b_rel
				var ny_exit: float = spawn_y + new_rel * t_exit
				if 640.0 - ny_exit < (new_len + b_len) * 0.5 + 80.0:
					return false

	# 2. Simula a descida até passar pelo jogador (t = 0.0s .. 2.6s)
	# Nunca permite que as 3 faixas estejam ocupadas simultaneamente na mesma janela vertical
	var t_sim: float = 0.0
	while t_sim <= 2.6:
		var ny: float = spawn_y + new_rel * t_sim
		if ny > 640.0:
			break
		var blocked: Dictionary = reserved_lanes.duplicate()
		blocked[l] = true

		for b in blockers:
			if b.kind == "racer":
				continue
			var b_own: float = b.own_speed if "own_speed" in b else 0.0
			var b_rel: float = max(road_spd - b_own, 60.0)
			var by: float = b.position.y + b_rel * t_sim
			if by < -140.0 or by > 660.0:
				continue
			var b_len: float = b.length if "length" in b else 50.0
			var safe_gap: float = (new_len + b_len) * 0.5 + 165.0
			if abs(by - ny) < safe_gap:
				for k in range(GameManager.lane_count):
					if b.occupies_lane(k):
						blocked[k] = true

		if blocked.size() > GameManager.lane_count - min_free_lanes:
			return false
		t_sim += 0.12

	return true

func _spawn_traffic(f: float) -> bool:
	var in_work: bool = work_zone_active or _has_work_cones_on_screen()
	var heavy_count := 0
	for t in _traffic():
		if t.kind in ["truck", "bus"]:
			heavy_count += 1

	var r := randf()
	var kind := "car"
	var own_spd: float = randf_range(60.0, 115.0)
	var veh_len: float = 64.0

	if in_work:
		# Durante obras, os veículos têm velocidade uniforme para manter a distância
		# exata de zigue-zague entre as duas faixas abertas sem emparelharem
		if r < 0.05 and GameManager.distance_m > 250.0:
			kind = "police"
		elif r < 0.10 and GameManager.distance_m > 250.0:
			kind = "ambulance"
		own_spd = 85.0
		veh_len = 70.0 if kind == "ambulance" else 64.0
	else:
		if r < 0.07 and GameManager.distance_m > 250.0:
			kind = "police"
			own_spd = randf_range(155.0, 200.0)
		elif r < 0.14 and GameManager.distance_m > 250.0:
			kind = "ambulance"
			own_spd = randf_range(145.0, 185.0)
			veh_len = 70.0
		elif r < 0.28 + 0.08 * f and heavy_count == 0:
			kind = "truck"
			own_spd = randf_range(10.0, 40.0)
			veh_len = 124.0
		elif r < 0.35 + 0.08 * f and heavy_count == 0:
			kind = "bus"
			own_spd = randf_range(20.0, 50.0)
			veh_len = 136.0

	var lanes := range(GameManager.lane_count)
	lanes.shuffle()
	# Prioriza faixas diferentes da última usada para forçar a alternância entre faixas
	if _last_traffic_lane in lanes:
		lanes.erase(_last_traffic_lane)
		lanes.append(_last_traffic_lane)

	for l in lanes:
		if _can_spawn(l, f, -90.0, own_spd, veh_len):
			var t := Traffic.new()
			var changer: bool = kind == "car" and randf() < 0.15 + 0.25 * f and not in_work
			t.setup(kind, l, -90.0, changer, own_spd)
			container.add_child(t)
			_last_traffic_lane = l
			return true
	return false

func _try_start_racer_warning() -> void:
	if work_zone_active or _has_work_cones_on_screen():
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
		# A faixa do rival deve estar totalmente livre e as outras duas não podem estar emparelhadas
		if not _lane_completely_clear(l) or not _other_lanes_passable(l):
			continue
		_racer_warning_lane = l
		_racer_warning_timer = 1.5
		racer_warning.emit(l)
		return

func _other_lanes_passable(reserved_l: int) -> bool:
	var rem := [0, 1, 2]
	rem.erase(reserved_l)
	var l_a: int = rem[0]
	var l_b: int = rem[1]
	var blockers: Array = _all_blockers()
	for a in blockers:
		if a.kind == "racer" or not a.occupies_lane(l_a) or a.position.y > 640.0:
			continue
		for b in blockers:
			if b == a or b.kind == "racer" or not b.occupies_lane(l_b) or b.position.y > 640.0:
				continue
			if abs(a.position.y - b.position.y) < 220.0:
				return false
	return true

func _lane_completely_clear(l: int) -> bool:
	for t in _all_blockers():
		if t.occupies_lane(l) and t.position.y > -100.0 and t.position.y < 700.0:
			return false
	return true

func _lane_clear_player(l: int) -> bool:
	for t in _all_blockers():
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
	var lanes := range(GameManager.lane_count)
	lanes.shuffle()
	for l in lanes:
		if (not work_zone_active or l != work_zone_lane) and lane_clear_top(l, 260.0):
			for i in range(5):
				var c := Coin.new()
				c.position = Vector2(GameManager.LANES[l], -30.0 - i * 46.0)
				container.add_child(c)
			return

func _spawn_obstacle() -> bool:
	if GameManager.distance_m - GameManager.debug_start_m < 300.0 or work_zone_active or _has_work_cones_on_screen():
		return true
	var kinds: Array = BIOME_OBSTACLES.get(GameManager.biome_id_at(GameManager.distance_m), [])
	if kinds.is_empty():
		return true
	var kind: String = kinds[randi() % kinds.size()]
	var obs_len: float = Obstacle.SIZES[kind].y
	var lanes := range(GameManager.lane_count)
	lanes.shuffle()
	for l in lanes:
		if not lane_clear_top(l, 220.0) or not _items_clear_top(l, 120.0):
			continue
		if not _can_spawn(l, difficulty(), -70.0, 0.0, obs_len) or not _wont_catch_up(l):
			continue
		var o := Obstacle.new()
		o.setup(kind, l, -70.0)
		container.add_child(o)
		return true
	return false

func _start_work_zone() -> void:
	# Escolhe a faixa esquerda (0) ou direita (2) para fechar, garantindo que o início não feche as 3 faixas
	var candidates := [0, 2]
	candidates.shuffle()
	for cand in candidates:
		if _can_spawn(cand, difficulty(), -60.0, 0.0, 34.0) and _other_lanes_passable(cand):
			work_zone_lane = cand
			work_zone_active = true
			_work_zone_timer = 8.5
			_work_cone_timer = 0.0
			_work_zone_interval = randf_range(35.0, 52.0)
			work_zone_started.emit(work_zone_lane)
			return
	# Se as outras faixas estiverem ocupadas no momento, aguarda 0.5s para iniciar a obra com segurança
	_work_zone_interval = 0.5

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
	var lanes := range(GameManager.lane_count)
	lanes.shuffle()
	for l in lanes:
		if (not work_zone_active or l != work_zone_lane) and lane_clear_top(l, 200.0):
			var p := PowerUp.new()
			p.position = Vector2(GameManager.LANES[l], -40.0)
			container.add_child(p)
			return
