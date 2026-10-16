extends Node

# Salvamento permanente do ZERO-IMPACT (autoload).
# Tudo fica num JSON em user://zero_impact_save.json:
# moedas, carros comprados, KM global, KM por carro, estatísticas e top 10.

const PATH := "user://zero_impact_save.json"
const OLD_HIGHSCORE_PATH := "user://highscore.save"
const TOP_SIZE := 10

var data: Dictionary = {}
var just_reset := false  # o Menu mostra o aviso "PROGRESSO RESETADO"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ctrl+P funciona até com o jogo pausado
	load_data()

# Ctrl+P: apaga todo o progresso (mantém só as opções de som) e volta ao menu.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed and event.physical_keycode == KEY_P:
		get_viewport().set_input_as_handled()
		reset()
		get_tree().paused = false
		GameManager.stop_run()
		AudioManager.quiet_ui()
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func reset() -> void:
	var music: bool = data.get("music_on", true)
	var sfx: bool = data.get("sfx_on", true)
	data = _defaults()
	data["music_on"] = music
	data["sfx_on"] = sfx
	save()
	just_reset = true

func _defaults() -> Dictionary:
	return {
		"coins": 0,
		"total_km": 0.0,
		"runs": 0,
		"best_distance_km": 0.0,
		"best_score": 0,
		"total_coins_earned": 0,
		"owned": ["equilibrado", "turbo", "blindado"],
		"selected": "equilibrado",
		"car_km": {},
		"top": [],
		"turn_players": [], # últimos nomes usados no modo por turnos
		"music_on": true,
		"sfx_on": true
	}

func load_data() -> void:
	data = _defaults()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			for k in parsed.keys():
				data[k] = parsed[k]
	elif FileAccess.file_exists(OLD_HIGHSCORE_PATH):
		# aproveita o recorde da versão antiga (Carro Desviador)
		var f := FileAccess.open(OLD_HIGHSCORE_PATH, FileAccess.READ)
		data["best_score"] = int(f.get_float())
		f.close()
		save()

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

# ---------- atalhos ----------

func coins() -> int:
	return int(data["coins"])

func add_coins(amount: int) -> void:
	data["coins"] = coins() + amount
	if amount > 0:
		data["total_coins_earned"] = int(data["total_coins_earned"]) + amount

func is_owned(car_id: String) -> bool:
	return car_id in data["owned"]

func buy(car_id: String, price: int) -> bool:
	if is_owned(car_id) or coins() < price:
		return false
	data["coins"] = coins() - price
	data["owned"].append(car_id)
	save()
	return true

func total_km() -> float:
	return float(data["total_km"])

func car_km(car_id: String) -> float:
	return float(data["car_km"].get(car_id, 0.0))

# Registra uma corrida terminada. Devolve a posição no top 10 (1..10) ou 0.
func register_run(car_id: String, km: float, score: int, coins_gained: int, player_name: String = "") -> int:
	data["runs"] = int(data["runs"]) + 1
	data["total_km"] = total_km() + km
	data["car_km"][car_id] = car_km(car_id) + km
	data["best_distance_km"] = max(float(data["best_distance_km"]), km)
	data["best_score"] = max(int(data["best_score"]), score)
	add_coins(coins_gained)

	var entry := {
		"score": score,
		"km": snappedf(km, 0.01),
		"car": car_id,
		"name": player_name,
		"date": Time.get_date_string_from_system()
	}
	var top: Array = data["top"]
	top.append(entry)
	top.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	while top.size() > TOP_SIZE:
		top.pop_back()
	data["top"] = top
	save()

	var pos := top.find(entry) + 1
	return pos
