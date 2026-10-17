extends RefCounted

# Missões: sempre 3 ativas, salvas em SaveManager.data["missions"].
# Cada uma olha um número da corrida (GameManager.run_stats). As de
# "numa corrida" guardam o melhor valor; as "no total" vão somando.
# Completou -> ganha as moedas e entra uma missão nova no lugar.

const ACTIVE := 3

const POOL := [
	{"id": "near_8", "type": "near_miss", "goal": 8, "reward": 80, "text": "Faça 8 raspões numa corrida"},
	{"id": "near_20", "type": "near_miss", "goal": 20, "reward": 200, "text": "Faça 20 raspões numa corrida"},
	{"id": "combo_4", "type": "max_combo", "goal": 4, "reward": 100, "text": "Chegue ao combo x4"},
	{"id": "combo_8", "type": "max_combo", "goal": 8, "reward": 250, "text": "Chegue ao combo x8"},
	{"id": "coins_40", "type": "coins", "goal": 40, "reward": 80, "text": "Pegue 40 moedas numa corrida"},
	{"id": "coins_90", "type": "coins", "goal": 90, "reward": 200, "text": "Pegue 90 moedas numa corrida"},
	{"id": "km_2", "type": "km", "goal": 2, "reward": 100, "text": "Corra 2 km numa corrida"},
	{"id": "km_5", "type": "km", "goal": 5, "reward": 300, "text": "Corra 5 km numa corrida"},
	{"id": "powers_4", "type": "powers", "goal": 4, "reward": 90, "text": "Pegue 4 poderes numa corrida"},
	{"id": "nitro_2", "type": "nitro", "goal": 2, "reward": 120, "text": "Use o nitro 2 vezes numa corrida"},
	{"id": "smash_5", "type": "smashed", "goal": 5, "reward": 150, "text": "Destrua 5 carros com o nitro"},
	{"id": "dodge_6", "type": "dodged", "goal": 6, "reward": 120, "text": "Passe raspando por 6 obstáculos"},
	{"id": "clean_1", "type": "clean_km", "goal": 1.5, "reward": 120, "text": "Corra 1,5 km sem bater"},
	{"id": "storm_1", "type": "storms", "goal": 1, "reward": 150, "text": "Sobreviva a uma tempestade de areia"},
	{"id": "tnear_50", "type": "near_miss", "total": true, "goal": 50, "reward": 250, "text": "Faça 50 raspões no total"},
	{"id": "tkm_15", "type": "km", "total": true, "goal": 15, "reward": 300, "text": "Rode 15 km no total"},
]

static func def(id: String) -> Dictionary:
	for d in POOL:
		if d["id"] == id:
			return d
	return {}

# Missões ativas: [{"id", "progress"}], completando até ter 3.
static func active() -> Array:
	var list: Array = SaveManager.data.get("missions", [])
	list = list.filter(func(m): return not def(String(m["id"])).is_empty())
	while list.size() < ACTIVE:
		list.append(_new_mission(list))
	SaveManager.data["missions"] = list
	return list

static func _new_mission(current: Array) -> Dictionary:
	var used := current.map(func(m): return def(String(m["id"]))["type"])
	var options := POOL.filter(func(d): return not d["type"] in used)
	if options.is_empty():
		options = POOL
	return {"id": options[randi() % options.size()]["id"], "progress": 0.0}

# Valor da missão contando a corrida atual.
static func value(m: Dictionary, stats: Dictionary) -> float:
	var d := def(String(m["id"]))
	var now := float(stats.get(d["type"], 0.0))
	if d.get("total", false):
		return float(m["progress"]) + now
	return max(float(m["progress"]), now)

static func is_done(m: Dictionary, stats: Dictionary) -> bool:
	return value(m, stats) >= float(def(String(m["id"]))["goal"])

# "3/8" ou "1.2/2.0 km"
static func progress_text(m: Dictionary, stats: Dictionary = {}) -> String:
	var d := def(String(m["id"]))
	var v: float = min(value(m, stats), float(d["goal"]))
	if d["type"] in ["km", "clean_km"]:
		return "%.1f / %.1f km" % [v, float(d["goal"])]
	return "%d / %d" % [int(v), int(d["goal"])]

# Fim da corrida: atualiza o progresso, paga as completas e troca por novas.
# Devolve as definições das missões completadas.
static func commit(stats: Dictionary) -> Array:
	var done: Array = []
	var list := active()
	for i in range(list.size()):
		var m: Dictionary = list[i]
		var d := def(String(m["id"]))
		m["progress"] = value(m, stats)
		if float(m["progress"]) >= float(d["goal"]):
			done.append(d)
			SaveManager.add_coins(int(d["reward"]))
			SaveManager.data["missions_done"] = int(SaveManager.data.get("missions_done", 0)) + 1
			list[i] = _new_mission(list)
	SaveManager.data["missions"] = list
	return done
