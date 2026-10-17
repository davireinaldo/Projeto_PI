extends Node

# Cria tráfego, moedas e power-ups. Usado pela corrida e pelo fundo do menu.
# Nunca fecha as 3 faixas ao mesmo tempo perto do topo, então sempre
# existe um caminho para desviar.

const Traffic := preload("res://scripts/Traffic.gd")
const Coin := preload("res://scripts/Coin.gd")
const PowerUp := preload("res://scripts/PowerUp.gd")
const Obstacle := preload("res://scripts/Obstacle.gd")

# obstáculos de cada cenário (o campo é tranquilo)
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

# 0 no começo, 1 na velocidade máxima
func difficulty() -> float:
	return clamp((GameManager.cruise_speed - GameManager.base_speed) / (GameManager.max_speed - GameManager.base_speed), 0.0, 1.0)

func _process(delta: float) -> void:
	if GameManager.game_over or container == null:
		return
	var f := difficulty()
	_traffic_t -= delta
	if _traffic_t <= 0.0:
		_spawn_traffic(f)
		_traffic_t = lerp(1.05, 0.42, f) * randf_range(0.8, 1.2)
	if spawn_coins:
		_coin_t -= delta
		if _coin_t <= 0.0:
			_spawn_coin_line()
			_coin_t = randf_range(2.0, 3.4)
	if spawn_powerups:
		_power_t -= delta
		if _power_t <= 0.0:
			_spawn_powerup()
			_power_t = randf_range(6.0, 9.5)
		if spawn_obstacles and GameManager.running:
			_obstacle_t -= delta
			if _obstacle_t <= 0.0:
				if _spawn_obstacle():
					_obstacle_t = randf_range(3.0, 5.5) - f * 1.2
				else:
					_obstacle_t = 0.3 # pista cheia agora: tenta de novo daqui a pouco

func _traffic() -> Array:
	return container.get_tree().get_nodes_in_group("traffic")

# faixa sem ninguém (veículo ou obstáculo) perto do topo da tela?
func lane_clear_top(l: int, depth: float) -> bool:
	for t in _traffic() + container.get_tree().get_nodes_in_group("obstacles"):
		if t.kind != "racer" and t.occupies_lane(l) and t.position.y - t.length * 0.5 < depth:
			return false
	return true

# sem moedas/poderes no topo da faixa (para o obstáculo não cair em cima)
func _items_clear_top(l: int, depth: float) -> bool:
	for group in ["coins", "powerups"]:
		for it in container.get_tree().get_nodes_in_group(group):
			if abs(it.position.x - GameManager.LANES[l]) < 50.0 and it.position.y < depth:
				return false
	return true

func _can_spawn(l: int, f: float) -> bool:
	var zone: float = 230.0 + f * 150.0
	var blocked := {l: true}
	for t in _traffic():
		if t.kind == "racer":
			continue
		var top: float = t.position.y - t.length * 0.5
		if top < zone:
			for k in range(3):
				if t.occupies_lane(k):
					blocked[k] = true
		if t.occupies_lane(l) and top < 90.0:
			return false
	return blocked.size() < 3

func _spawn_traffic(f: float) -> void:
	var r := randf()
	var kind := "car"
	if r < 0.12 + 0.08 * f:
		kind = "truck"
	elif r < 0.17 + 0.1 * f:
		kind = "bus"
	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if _can_spawn(l, f):
			var t := Traffic.new()
			var changer := kind == "car" and randf() < 0.15 + 0.25 * f
			t.setup(kind, l, -90.0, changer)
			container.add_child(t)
			return

func spawn_racer(l: int) -> void:
	var t := Traffic.new()
	t.setup("racer", l, 790.0)
	container.add_child(t)

func _spawn_coin_line() -> void:
	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if lane_clear_top(l, 260.0):
			for i in range(5):
				var c := Coin.new()
				c.position = Vector2(GameManager.LANES[l], -30.0 - i * 46.0)
				container.add_child(c)
			return

# Devolve false se não deu para colocar agora (para tentar de novo logo).
func _spawn_obstacle() -> bool:
	if GameManager.distance_m - GameManager.debug_start_m < 300.0:
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

# O obstáculo parado desce mais rápido que os carros. Só pode nascer na
# faixa se não alcançar nenhum carro antes de ele sair por baixo da tela.
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
		if lane_clear_top(l, 200.0):
			var p := PowerUp.new()
			p.position = Vector2(GameManager.LANES[l], -40.0)
			container.add_child(p)
			return
