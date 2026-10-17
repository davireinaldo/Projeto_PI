extends Node

# Estado global do ZERO-IMPACT (autoload):
# carros, cenários, patentes e o estado da corrida em andamento.

const Missions := preload("res://scripts/Missions.gd")
const UI := preload("res://scripts/UIKit.gd")

# ---------- Carros ----------
# lane_speed   -> rapidez da troca de faixa
# start_shield -> segundos de escudo grátis no começo da corrida
# lives        -> batidas extras que o carro aguenta
# coin_mult    -> multiplicador de moedas
# score_mult   -> multiplicador de pontos
# magnet       -> raio (px) do ímã de moedas (0 = sem ímã)
var cars: Array = [
	{"id": "equilibrado", "name": "Equilibrado", "model": "texture", "color": Color(0.2, 0.5, 1.0), "accent": Color(0.9, 0.95, 1.0),
	 "price": 0, "desc": "Sem vantagem nem desvantagem.\nO clássico, direto e confiável.",
	 "lane_speed": 10.0, "start_shield": 0.0, "lives": 0, "coin_mult": 1.0, "score_mult": 1.0, "magnet": 0.0},
	{"id": "turbo", "name": "Turbo", "model": "sport", "color": Color(0.9, 0.18, 0.2), "accent": Color(1, 1, 1),
	 "price": 0, "desc": "Troca de faixa mais rápido.\nBom pra desviar de última hora.",
	 "lane_speed": 15.0, "start_shield": 0.0, "lives": 0, "coin_mult": 1.0, "score_mult": 1.0, "magnet": 0.0},
	{"id": "blindado", "name": "Blindado", "model": "armored", "color": Color(0.25, 0.6, 0.32), "accent": Color(0.75, 0.8, 0.75),
	 "price": 0, "desc": "Começa cada corrida com\n3 segundos de escudo grátis.",
	 "lane_speed": 9.0, "start_shield": 3.0, "lives": 0, "coin_mult": 1.0, "score_mult": 1.0, "magnet": 0.0},
	{"id": "pickup", "name": "Pickup", "model": "pickup", "color": Color(0.95, 0.55, 0.12), "accent": Color(0.2, 0.2, 0.22),
	 "price": 400, "desc": "Pesada, mas resistente.\nAguenta uma batida extra.",
	 "lane_speed": 9.0, "start_shield": 0.0, "lives": 1, "coin_mult": 1.0, "score_mult": 1.0, "magnet": 0.0},
	{"id": "muscle", "name": "Muscle", "model": "muscle", "color": Color(0.13, 0.13, 0.16), "accent": Color(1.0, 0.8, 0.1),
	 "price": 900, "desc": "Motor V8 que rende.\nGanha 50% mais moedas.",
	 "lane_speed": 11.0, "start_shield": 0.0, "lives": 0, "coin_mult": 1.5, "score_mult": 1.0, "magnet": 0.0},
	{"id": "esportivo", "name": "Esportivo", "model": "coupe", "color": Color(1.0, 0.82, 0.1), "accent": Color(0.1, 0.1, 0.12),
	 "price": 1800, "desc": "Ímã de moedas e +25% de pontos.\nRápido e elegante.",
	 "lane_speed": 14.0, "start_shield": 0.0, "lives": 0, "coin_mult": 1.0, "score_mult": 1.25, "magnet": 110.0},
	{"id": "f1", "name": "F1", "model": "f1", "color": Color(0.85, 0.08, 0.35), "accent": Color(0.15, 0.95, 1.0),
	 "price": 3500, "desc": "Agilidade máxima.\n+50% de pontos.",
	 "lane_speed": 19.0, "start_shield": 0.0, "lives": 0, "coin_mult": 1.0, "score_mult": 1.5, "magnet": 0.0},
	{"id": "zero", "name": "ZERO", "model": "legend", "color": Color(0.07, 0.09, 0.14), "accent": Color(0.1, 1.0, 0.9),
	 "price": 1, "desc": "O lendário. Escudo, vida extra,\nímã e moedas em dobro.",
	 "lane_speed": 16.0, "start_shield": 4.0, "lives": 1, "coin_mult": 2.0, "score_mult": 1.5, "magnet": 150.0},
]

# ---------- Oficina ----------
# Melhorias permanentes compradas com moedas: cada nível faz o poder
# durar "step" segundos a mais. O preço de cada nível está em UPGRADE_PRICES.
const UPGRADE_PRICES := [150, 300, 600, 1000, 1600]
var upgrades: Array = [
	{"id": "escudo", "base": 5.0, "step": 1.0},
	{"id": "lentidao", "base": 4.0, "step": 0.8},
	{"id": "nitro", "base": 3.5, "step": 0.6},
	{"id": "ima", "base": 8.0, "step": 1.5},
	{"id": "moedas2", "base": 10.0, "step": 2.0},
]

# ---------- Cenários ----------
# Cada cenário dura BIOME_LENGTH metros e se mistura com o próximo
# nos últimos BIOME_BLEND metros.
const BIOME_LENGTH := 2000.0
const BIOME_BLEND := 300.0

var biomes: Array = [
	{"id": "cidade", "name": "CIDADE", "sign": "ENTRANDO NA CIDADE",
	 "left": Color(0.42, 0.43, 0.46), "left2": Color(0.47, 0.48, 0.5),
	 "right": Color(0.42, 0.43, 0.46), "right2": Color(0.47, 0.48, 0.5),
	 "road": Color(0.15, 0.15, 0.18), "edge": Color(0.92, 0.92, 0.9), "dash": Color(1, 1, 0.85, 0.85),
	 "decor_left": ["building", "building", "lamp"], "decor_right": ["building", "building", "lamp"]},
	{"id": "campo", "name": "CAMPO", "sign": "ENTRANDO NO CAMPO",
	 "left": Color(0.16, 0.42, 0.19), "left2": Color(0.19, 0.47, 0.22),
	 "right": Color(0.16, 0.42, 0.19), "right2": Color(0.19, 0.47, 0.22),
	 "road": Color(0.17, 0.17, 0.2), "edge": Color(0.92, 0.92, 0.9), "dash": Color(1, 1, 0.85, 0.85),
	 "decor_left": ["tree", "tree", "bush", "hay"], "decor_right": ["tree", "tree", "bush", "hay"]},
	{"id": "deserto", "name": "DESERTO", "sign": "ENTRANDO NO DESERTO",
	 "left": Color(0.86, 0.71, 0.45), "left2": Color(0.82, 0.67, 0.41),
	 "right": Color(0.86, 0.71, 0.45), "right2": Color(0.82, 0.67, 0.41),
	 "road": Color(0.3, 0.27, 0.25), "edge": Color(0.95, 0.85, 0.6), "dash": Color(1, 0.9, 0.5, 0.85),
	 "decor_left": ["cactus", "rock", "cactus", "tumbleweed"], "decor_right": ["cactus", "rock", "cactus", "tumbleweed"]},
	{"id": "mar", "name": "BEIRA-MAR", "sign": "CHEGANDO NA BEIRA-MAR",
	 "left": Color(0.93, 0.84, 0.62), "left2": Color(0.9, 0.8, 0.58),
	 "right": Color(0.1, 0.45, 0.72), "right2": Color(0.12, 0.5, 0.78),
	 "road": Color(0.2, 0.2, 0.24), "edge": Color(1, 1, 1), "dash": Color(1, 1, 1, 0.85),
	 "decor_left": ["palm", "umbrella", "palm"], "decor_right": ["boat", "buoy", "wave"]},
	{"id": "neve", "name": "MONTANHA NEVADA", "sign": "SUBINDO A MONTANHA NEVADA",
	 "left": Color(0.9, 0.93, 0.97), "left2": Color(0.85, 0.89, 0.95),
	 "right": Color(0.9, 0.93, 0.97), "right2": Color(0.85, 0.89, 0.95),
	 "road": Color(0.26, 0.28, 0.32), "edge": Color(0.95, 0.4, 0.3), "dash": Color(1, 1, 1, 0.8),
	 "decor_left": ["pine", "pine", "snowrock"], "decor_right": ["pine", "pine", "snowrock"]},
	{"id": "neon", "name": "CIDADE NEON", "sign": "ENTRANDO NA CIDADE NEON",
	 "left": Color(0.06, 0.04, 0.11), "left2": Color(0.08, 0.05, 0.14),
	 "right": Color(0.06, 0.04, 0.11), "right2": Color(0.08, 0.05, 0.14),
	 "road": Color(0.07, 0.06, 0.12), "edge": Color(1.0, 0.2, 0.8), "dash": Color(0.2, 0.95, 1.0, 0.9),
	 "decor_left": ["neon_building", "neon_pole"], "decor_right": ["neon_building", "neon_pole"]},
]

# ---------- Dia e noite ----------
# Um dia inteiro dura DAY_CYCLE metros: dia, pôr do sol, noite e amanhecer.
# A Cidade Neon é sempre de noite.
const DAY_CYCLE := 4000.0

# ---------- Patentes (por KM global) ----------
var ranks: Array = [
	{"name": "Bronze", "km": 0.0, "color": Color(0.8, 0.5, 0.25)},
	{"name": "Prata", "km": 5.0, "color": Color(0.78, 0.8, 0.85)},
	{"name": "Ouro", "km": 15.0, "color": Color(1.0, 0.8, 0.2)},
	{"name": "Platina", "km": 40.0, "color": Color(0.45, 0.9, 0.85)},
	{"name": "Diamante", "km": 80.0, "color": Color(0.45, 0.65, 1.0)},
	{"name": "Lenda", "km": 150.0, "color": Color(1.0, 0.3, 0.55)},
]

# ---------- Pista ----------
const LANES: Array = [140.0, 240.0, 340.0]
const PLAYER_Y := 600.0
# 10 px de tela = 1 metro. velocidade em km/h = px/s * 0.36
const PX_PER_METER := 10.0

# ---------- Estado da corrida ----------
var running: bool = false # true só durante uma corrida de verdade
var game_over: bool = false # congela pista e tráfego
var speed: float = 300.0 # velocidade efetiva da pista (px/s)
var cruise_speed: float = 300.0
var base_speed: float = 300.0
var max_speed: float = 900.0
var speed_increase_rate: float = 5.0

var score: float = 0.0
var distance_m: float = 0.0
var coins_run: int = 0
var lives: int = 0
var shield_time: float = 0.0
var shield_total: float = 1.0
var grace_time: float = 0.0 # invencível depois de perder uma vida
var slow_time: float = 0.0
var slow_total: float = 1.0
var slow_factor: float = 1.0
var nitro_time: float = 0.0 # nitro: mais rápido e atravessa o tráfego
var nitro_total: float = 1.0
var nitro_factor: float = 1.0
var magnet_time: float = 0.0 # ímã temporário (para qualquer carro)
var magnet_total: float = 1.0
var x2_time: float = 0.0 # moedas valem 2
var x2_total: float = 1.0
var player_pos: Vector2 = Vector2(240, PLAYER_Y)
var last_summary: Dictionary = {}

# ---------- Raspão e combo ----------
# Passar raspando por um veículo que vinha na sua faixa vale pontos.
# Raspões seguidos (com menos de COMBO_WINDOW s entre eles) sobem o combo.
const COMBO_WINDOW := 4.0
const NEAR_MISS_POINTS := 40
var combo: int = 0
var combo_time: float = 0.0
var combo_points: int = 0

# números da corrida atual (usados pelas missões e pelo game over)
var run_stats: Dictionary = {}
var _clean_from_m: float = 0.0 # onde começou o trecho atual sem bater

# ---------- Modo por turnos ----------
# Cada jogador corre uma vez, na sua vez; no fim vence quem foi mais longe.
const TURN_MAX_PLAYERS := 8
var turn_mode: bool = false
var turn_players: Array = [] # nomes, na ordem das vezes
var turn_index: int = 0 # de quem é a vez agora
var turn_results: Array = [] # {"name", "km", "score", "car"} de quem já correu

# opções de teste via linha de comando:  -- --autopilot --start-km=4
var debug_autopilot: bool = false
var debug_start_m: float = 0.0

signal game_over_triggered
signal shield_ended(broken: bool)
signal life_lost
signal power_collected(kind: String, pos: Vector2)
signal combo_ended(count: int, points: int)
signal nitro_ended

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_input()
	for arg in OS.get_cmdline_user_args():
		if arg == "--autopilot":
			debug_autopilot = true
		elif arg.begins_with("--start-km="):
			debug_start_m = arg.split("=")[1].to_float() * 1000.0

# F11: tela cheia em qualquer tela
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		UI.toggle_fullscreen()

func _setup_input() -> void:
	var extra := {"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D]}
	for action in extra.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in extra[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

# ---------- carros ----------

func car_by_id(car_id: String) -> Dictionary:
	for c in cars:
		if c["id"] == car_id:
			return c
	return cars[0]

func car_index(car_id: String) -> int:
	for i in range(cars.size()):
		if cars[i]["id"] == car_id:
			return i
	return 0

# No modo por turnos cada jogador usa o carro que escolheu na sua vez.
func selected_car() -> Dictionary:
	if turn_mode and current_player() != "":
		return car_by_id(turn_car_id(current_player()))
	return car_by_id(String(SaveManager.data["selected"]))

# Carro do jogador nos turnos: o último que ele usou (se ainda tiver),
# senão o carro selecionado na garagem.
func turn_car_id(player_name: String) -> String:
	var id := String(SaveManager.data["turn_cars"].get(player_name, ""))
	if id == "" or not SaveManager.is_owned(id):
		id = String(SaveManager.data["selected"])
	return id

func set_turn_car(player_name: String, car_id: String) -> void:
	SaveManager.data["turn_cars"][player_name] = car_id
	SaveManager.save()

# ---------- oficina ----------

func upgrade_def(id: String) -> Dictionary:
	for u in upgrades:
		if u["id"] == id:
			return u
	return {}

# Segundos que o poder dura com o nível que o jogador tem (ou "level").
func power_duration(id: String, level: int = -1) -> float:
	var u := upgrade_def(id)
	if level < 0:
		level = SaveManager.upgrade_level(id)
	return float(u["base"]) + float(u["step"]) * level

# Preço do próximo nível (0 = já está no máximo).
func upgrade_price(id: String) -> int:
	var level := SaveManager.upgrade_level(id)
	return UPGRADE_PRICES[level] if level < UPGRADE_PRICES.size() else 0

# ---------- cenários ----------

# Devolve [índice_atual, índice_próximo, mistura 0..1]
func biome_state(dist_m: float) -> Array:
	var idx := int(floor(dist_m / BIOME_LENGTH))
	var into := dist_m - idx * BIOME_LENGTH
	var a := idx % biomes.size()
	var b := (idx + 1) % biomes.size()
	var t := 0.0
	if into > BIOME_LENGTH - BIOME_BLEND:
		t = smoothstep(0.0, 1.0, (into - (BIOME_LENGTH - BIOME_BLEND)) / BIOME_BLEND)
	return [a, b, t]

func biome_id_at(dist_m: float) -> String:
	var bs := biome_state(dist_m)
	return biomes[bs[0] if bs[2] < 0.5 else bs[1]]["id"]

# Quanto de cada cenário aparece agora (0..1), considerando a transição.
func biome_weight(dist_m: float, id: String) -> float:
	var bs := biome_state(dist_m)
	var w := 0.0
	if biomes[bs[0]]["id"] == id:
		w += 1.0 - bs[2]
	if biomes[bs[1]]["id"] == id:
		w += bs[2]
	return w

# Hora do dia: Vector2(noite 0..1, pôr do sol 0..1)
func sky(dist_m: float) -> Vector2:
	var f := fposmod(dist_m, DAY_CYCLE) / DAY_CYCLE
	var night := 0.0
	if f > 0.45 and f < 0.55:
		night = smoothstep(0.45, 0.55, f)
	elif f >= 0.55 and f < 0.9:
		night = 1.0
	elif f >= 0.9:
		night = 1.0 - smoothstep(0.9, 1.0, f)
	var dusk: float = max(1.0 - abs(f - 0.47) / 0.07, 0.0) + max(1.0 - abs(f - 0.95) / 0.06, 0.0) * 0.6
	night = max(night, 0.8 * biome_weight(dist_m, "neon"))
	return Vector2(night, clamp(dusk, 0.0, 1.0))

# ---------- patentes ----------

func rank_index(km: float) -> int:
	var r := 0
	for i in range(ranks.size()):
		if km >= ranks[i]["km"]:
			r = i
	return r

# progresso 0..1 até a próxima patente (1 se já é a última)
func rank_progress(km: float) -> float:
	var i := rank_index(km)
	if i >= ranks.size() - 1:
		return 1.0
	var a: float = ranks[i]["km"]
	var b: float = ranks[i + 1]["km"]
	return clamp((km - a) / (b - a), 0.0, 1.0)

# ---------- corrida ----------

func start_run() -> void:
	var car := selected_car()
	running = true
	game_over = false
	cruise_speed = base_speed
	speed = base_speed
	score = 0.0
	distance_m = debug_start_m
	coins_run = 0
	lives = int(car["lives"])
	shield_time = 0.0
	grace_time = 0.0
	slow_time = 0.0
	slow_factor = 1.0
	nitro_time = 0.0
	nitro_factor = 1.0
	magnet_time = 0.0
	x2_time = 0.0
	combo = 0
	combo_time = 0.0
	combo_points = 0
	_clean_from_m = distance_m
	run_stats = {"near_miss": 0, "max_combo": 0, "coins": 0, "powers": 0, "nitro": 0,
		"dodged": 0, "storms": 0, "smashed": 0, "clean_km": 0.0, "km": 0.0}
	if car["start_shield"] > 0.0:
		activate_shield(car["start_shield"])

func stop_run() -> void:
	running = false
	game_over = false

func _process(delta: float) -> void:
	if not running or game_over:
		return

	if cruise_speed < max_speed:
		cruise_speed = min(cruise_speed + speed_increase_rate * delta, max_speed)

	var target_factor := 0.5 if slow_time > 0.0 else 1.0
	slow_factor = move_toward(slow_factor, target_factor, delta * 1.5)
	nitro_factor = move_toward(nitro_factor, 1.65 if nitro_time > 0.0 else 1.0, delta * 2.5)
	speed = cruise_speed * slow_factor * nitro_factor

	distance_m += speed * delta / PX_PER_METER
	var car := selected_car()
	score += delta * (10.0 + speed * 0.02) * float(car["score_mult"])
	run_stats["km"] = (distance_m - debug_start_m) / 1000.0
	run_stats["clean_km"] = max(float(run_stats["clean_km"]), (distance_m - _clean_from_m) / 1000.0)

	if combo > 0:
		combo_time -= delta
		if combo_time <= 0.0:
			end_combo()

	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			shield_time = 0.0
			shield_ended.emit(false)
	if grace_time > 0.0:
		grace_time -= delta
	if slow_time > 0.0:
		slow_time = max(slow_time - delta, 0.0)
	if nitro_time > 0.0:
		nitro_time -= delta
		if nitro_time <= 0.0:
			nitro_time = 0.0
			grace_time = max(grace_time, 0.8) # um respiro para sair do meio do tráfego
			nitro_ended.emit()
	magnet_time = max(magnet_time - delta, 0.0)
	x2_time = max(x2_time - delta, 0.0)

func speed_kmh() -> int:
	return int(speed * 0.36)

func is_protected() -> bool:
	return shield_time > 0.0 or grace_time > 0.0 or nitro_time > 0.0

func activate_shield(duration: float) -> void:
	shield_time = max(shield_time, duration)
	shield_total = shield_time

func activate_slow_mo(duration: float) -> void:
	slow_time = max(slow_time, duration)
	slow_total = slow_time

func activate_nitro(duration: float) -> void:
	nitro_time = max(nitro_time, duration)
	nitro_total = nitro_time
	run_stats["nitro"] += 1

func activate_magnet(duration: float) -> void:
	magnet_time = max(magnet_time, duration)
	magnet_total = magnet_time

func activate_x2(duration: float) -> void:
	x2_time = max(x2_time, duration)
	x2_total = x2_time

# raio do ímã agora (o do carro ou o do poder, o que for maior)
func magnet_radius() -> float:
	if not running:
		return 0.0
	var r := float(selected_car()["magnet"])
	if magnet_time > 0.0:
		r = max(r, 190.0)
	return r

# Devolve quantas moedas a moeda valeu.
func add_coin() -> int:
	var v := 2 if x2_time > 0.0 else 1
	coins_run += v
	run_stats["coins"] += v
	return v

# Raspão: sobe o combo e devolve os pontos ganhos.
func near_miss(obstacle: bool) -> int:
	combo += 1
	combo_time = COMBO_WINDOW
	var pts := int(NEAR_MISS_POINTS * combo * float(selected_car()["score_mult"]))
	combo_points += pts
	score += pts
	run_stats["near_miss"] += 1
	run_stats["max_combo"] = max(int(run_stats["max_combo"]), combo)
	if obstacle:
		run_stats["dodged"] += 1
	return pts

func end_combo() -> void:
	if combo > 0:
		combo_ended.emit(combo, combo_points)
	combo = 0
	combo_time = 0.0
	combo_points = 0

# Buraco/duna: perde o combo e um pouco de velocidade.
func bump() -> void:
	end_combo()
	cruise_speed = max(base_speed, cruise_speed * 0.93)

# Chamado quando o jogador bate num veículo.
# Devolve "nitro", "shield", "life" ou "dead".
func on_crash() -> String:
	if nitro_time > 0.0:
		run_stats["smashed"] += 1
		return "nitro"
	_clean_from_m = distance_m
	end_combo()
	if shield_time > 0.0 or grace_time > 0.0:
		return "shield"
	if lives > 0:
		lives -= 1
		grace_time = 1.5
		life_lost.emit()
		return "life"
	trigger_game_over()
	return "dead"

func trigger_game_over() -> void:
	if game_over:
		return
	game_over = true
	running = false
	_finish_run()
	game_over_triggered.emit()

func _finish_run() -> void:
	var car := selected_car()
	var km := (distance_m - debug_start_m) / 1000.0
	run_stats["km"] = km
	var missions_done := Missions.commit(run_stats)
	var final_score := int(score)
	var collected := int(round(coins_run * float(car["coin_mult"])))
	var bonus := int(round((int(km * 10.0) + int(final_score / 200.0)) * float(car["coin_mult"])))
	var old_km := SaveManager.total_km()
	var old_rank := rank_index(old_km)
	var was_best := final_score > int(SaveManager.data["best_score"])
	var player_name := current_player() if turn_mode else ""
	var top_pos := SaveManager.register_run(car["id"], km, final_score, collected + bonus, player_name)
	var new_km := SaveManager.total_km()
	OnlineRanking.submit_best()
	if turn_mode:
		turn_results.append({"name": player_name, "km": km, "score": final_score, "car": car["id"]})
		SaveManager.register_coop(player_name, car["id"], km, final_score)
		turn_index += 1
	last_summary = {
		"km": km,
		"score": final_score,
		"collected": collected,
		"bonus": bonus,
		"new_best": was_best,
		"top_pos": top_pos,
		"old_rank": old_rank,
		"new_rank": rank_index(new_km),
		"total_km": new_km,
		"near_miss": int(run_stats["near_miss"]),
		"max_combo": int(run_stats["max_combo"]),
		"missions": missions_done,
	}

# ---------- turnos ----------

func start_turns(names: Array) -> void:
	turn_mode = true
	turn_players = names.duplicate()
	turn_index = 0
	turn_results = []

func end_turns() -> void:
	turn_mode = false
	turn_index = 0
	turn_results = []

func current_player() -> String:
	if turn_index < turn_players.size():
		return String(turn_players[turn_index])
	return ""

func turns_finished() -> bool:
	return turn_index >= turn_players.size()

# Resultados do mais longe para o mais perto (desempate pelos pontos).
func turn_standings() -> Array:
	var list := turn_results.duplicate()
	list.sort_custom(func(a, b):
		if is_equal_approx(float(a["km"]), float(b["km"])):
			return int(a["score"]) > int(b["score"])
		return float(a["km"]) > float(b["km"]))
	return list

# ---------- IA simples de desvio (menu e piloto automático) ----------

func ai_pick_lane(current_lane: int, car_y: float) -> int:
	var clear := [9999.0, 9999.0, 9999.0]
	for t in get_tree().get_nodes_in_group("traffic"):
		var dy: float = car_y - t.position.y
		var half: float = t.length * 0.5
		if dy > -half - 50.0 and dy < 520.0:
			for l in range(3):
				if t.occupies_lane(l):
					clear[l] = min(clear[l], dy - half)
	if clear[current_lane] > 300.0:
		return current_lane
	var best := current_lane
	for l in range(3):
		if abs(l - current_lane) == 2 and clear[1] < 140.0:
			continue
		if clear[l] > clear[best] + 20.0:
			best = l
	return best
