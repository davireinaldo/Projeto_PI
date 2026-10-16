extends Node

# Cria tráfego, moedas e power-ups. Usado pela corrida e pelo fundo do menu.
# Nunca fecha as 3 faixas ao mesmo tempo perto do topo, então sempre
# existe um caminho para desviar.

const Traffic := preload("res://scripts/Traffic.gd")
const Coin := preload("res://scripts/Coin.gd")
const PowerUp := preload("res://scripts/PowerUp.gd")

var container: Node2D
var spawn_coins: bool = true
var spawn_powerups: bool = true
var _traffic_t: float = 1.2
var _coin_t: float = 1.5
var _power_t: float = 5.0

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

func _traffic() -> Array:
	return container.get_tree().get_nodes_in_group("traffic")

# faixa sem ninguém perto do topo da tela?
func lane_clear_top(l: int, depth: float) -> bool:
	for t in _traffic():
		if t.kind != "racer" and t.occupies_lane(l) and t.position.y - t.length * 0.5 < depth:
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

func _spawn_powerup() -> void:
	var lanes := [0, 1, 2]
	lanes.shuffle()
	for l in lanes:
		if lane_clear_top(l, 200.0):
			var p := PowerUp.new()
			p.position = Vector2(GameManager.LANES[l], -40.0)
			container.add_child(p)
			return
