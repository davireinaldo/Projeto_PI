extends Node

# Salvamento permanente do ZERO-IMPACT (autoload).
# Tudo fica num JSON em user://zero_impact_save.json:
# moedas, carros comprados, KM global, KM por carro, estatísticas e top 10.

const PATH := "user://zero_impact_save.json"
const TMP_PATH := "user://zero_impact_save.json.tmp"
const OLD_HIGHSCORE_PATH := "user://highscore.save"
const TOP_SIZE := 10
const UI := preload("res://scripts/UIKit.gd")

var data: Dictionary = {}
var just_reset := false  # o Menu mostra o aviso "PROGRESSO RESETADO"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ctrl+P funciona até com o jogo pausado
	load_data()

# ---------- Ctrl+P: resetar progresso (com confirmação) ----------
# Apaga todo o progresso (mantém as opções de som e o nome online) e volta ao menu.
# Na janela de confirmação: S confirma, N cancela (ou clique nos botões).

var confirming := false
var _confirm_layer: CanvasLayer
var _was_paused := false
var _prev_focus: Control

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if confirming:
		if event.physical_keycode == KEY_S:
			get_viewport().set_input_as_handled()
			_confirm_reset()
		elif event.physical_keycode == KEY_N:
			get_viewport().set_input_as_handled()
			_close_confirm()
		return
	if event.ctrl_pressed and event.physical_keycode == KEY_P:
		get_viewport().set_input_as_handled()
		_open_confirm()

func _open_confirm() -> void:
	confirming = true
	_was_paused = get_tree().paused
	_prev_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	AudioManager.play("ui_error", 0.0, 0.0)

	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 100
	add_child(_confirm_layer)
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	UI.panel(root, Rect2(50, 230, 380, 260), Color(0.05, 0.06, 0.1, 0.97), UI.HOT)
	UI.label(root, "RESETAR PROGRESSO?", Vector2(50, 250), 28, UI.HOT, 380, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "Apaga moedas, carros, km, estatísticas\ne todos os rankings. Não dá para desfazer.",
		Vector2(50, 302), 15, Color(0.85, 0.88, 0.95), 380, HORIZONTAL_ALIGNMENT_CENTER)
	var no := UI.button(root, "CANCELAR (N)", Rect2(74, 400, 160, 52), _close_confirm, 16)
	var yes := UI.button(root, "RESETAR (S)", Rect2(246, 400, 160, 52), _confirm_reset, 16)
	yes.add_theme_stylebox_override("normal", UI.style(Color(0.35, 0.05, 0.12, 0.9), UI.HOT, 10, 2))
	no.focus_neighbor_right = no.get_path_to(yes)
	yes.focus_neighbor_left = yes.get_path_to(no)
	no.grab_focus()

func _close_confirm() -> void:
	if not confirming:
		return
	confirming = false
	_confirm_layer.queue_free()
	_confirm_layer = null
	get_tree().paused = _was_paused
	if is_instance_valid(_prev_focus) and _prev_focus.is_inside_tree():
		_prev_focus.grab_focus()

func _confirm_reset() -> void:
	_close_confirm()
	reset()
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.quiet_ui()
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func reset() -> void:
	var old := data
	data = _defaults()
	# mantém as opções de som e a identidade no ranking online (senão o
	# jogador ganharia uma segunda linha lá)
	for k in ["music_on", "sfx_on", "online_id", "online_name", "online_sent", "online_sent_name"]:
		data[k] = old.get(k, data[k])
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
		"turn_cars": {}, # carro que cada jogador escolheu nos turnos
		"coop_top": [], # top 10 do modo por turnos, por distância
		"missions": [], # missões ativas (ver Missions.gd)
		"missions_done": 0,
		"upgrades": {}, # nível de cada melhoria da Oficina
		"paint": {}, # pintura que cada carro está usando (ver Paints.gd)
		"trail": {}, # rastro que cada carro está usando
		"paints_owned": [],
		"trails_owned": [],
		"tutorial_done": false,
		"online_id": "", # identificação no ranking online (ver OnlineRanking.gd)
		"online_name": "",
		"online_sent": 0, # último recorde enviado
		"online_sent_name": "",
		"music_on": true,
		"sfx_on": true,
		"radio_track": 0,
		"gol_track": 0, # música do rádio do Gol do Narcelio
		"achievements": []
	}

func load_data() -> void:
	data = _defaults()
	var loaded := false
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				for k in parsed.keys():
					data[k] = parsed[k]
				loaded = true
	if not loaded and FileAccess.file_exists(TMP_PATH):
		var f := FileAccess.open(TMP_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				for k in parsed.keys():
					data[k] = parsed[k]
				loaded = true
	if not loaded and FileAccess.file_exists(OLD_HIGHSCORE_PATH):
		# aproveita o recorde da versão antiga (Carro Desviador)
		var f := FileAccess.open(OLD_HIGHSCORE_PATH, FileAccess.READ)
		if f:
			data["best_score"] = int(f.get_float())
			f.close()
			save()

func save() -> void:
	# Salvamento atômico: escreve primeiro em .tmp e depois renomeia para evitar corrupção
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.flush()
		f.close()
		var dir := DirAccess.open("user://")
		if dir:
			var base_name := PATH.get_file()
			var tmp_name := TMP_PATH.get_file()
			if dir.file_exists(base_name):
				dir.remove(base_name)
			dir.rename(tmp_name, base_name)
	else:
		# Fallback direto caso o .tmp falhe
		var direct := FileAccess.open(PATH, FileAccess.WRITE)
		if direct:
			direct.store_string(JSON.stringify(data, "\t"))
			direct.close()

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

func upgrade_level(id: String) -> int:
	return int(data["upgrades"].get(id, 0))

func buy_upgrade(id: String, price: int) -> bool:
	if price <= 0 or coins() < price:
		return false
	data["coins"] = coins() - price
	data["upgrades"][id] = upgrade_level(id) + 1
	save()
	return true

# Trapaça (nome secreto no modo por turnos): todos os carros e melhorias no máximo.
func unlock_all() -> void:
	for c in GameManager.cars:
		if not is_owned(c["id"]):
			data["owned"].append(c["id"])
	for u in GameManager.upgrades:
		data["upgrades"][u["id"]] = GameManager.UPGRADE_PRICES.size()
	save()

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

# Top 10 do modo por turnos: quem foi mais longe (desempate pelos pontos).
func register_coop(player_name: String, car_id: String, km: float, score: int) -> void:
	var top: Array = data["coop_top"]
	top.append({
		"name": player_name,
		"km": snappedf(km, 0.01),
		"score": score,
		"car": car_id,
		"date": Time.get_date_string_from_system()
	})
	top.sort_custom(func(a, b):
		if is_equal_approx(float(a["km"]), float(b["km"])):
			return int(a["score"]) > int(b["score"])
		return float(a["km"]) > float(b["km"]))
	while top.size() > TOP_SIZE:
		top.pop_back()
	data["coop_top"] = top
	save()
