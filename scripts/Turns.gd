extends Node2D

# Modo por turnos: cada jogador coloca o nome e corre uma vez, na sua vez.
# Esta tela tem três estados:
#   setup   -> digitar os nomes
#   next    -> "VEZ DE <nome>" entre uma corrida e outra, com o placar parcial
#   results -> classificação final: vence quem foi mais longe

const World := preload("res://scripts/World.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")

const NAME_MAX := 18
# digitar isto como nome libera todos os carros e melhorias
const CHEAT := "caitano melhor professor"
const MEDALS := [Color(1.0, 0.82, 0.2), Color(0.85, 0.87, 0.92), Color(0.85, 0.55, 0.3)]

var root: Control
var names: Array = []
var name_edit: LineEdit
var list_box: Control
var count_label: Label
var msg_label: Label
var start_btn: Button
var car_label: Label
var car_desc: Label

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 140.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 3 + 100.0
	add_child(world)

	if not GameManager.turn_mode:
		_build_setup()
	elif GameManager.turns_finished():
		_build_results()
	else:
		_build_next()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_to_menu()

func _to_menu() -> void:
	GameManager.end_turns()
	UI.go(get_tree(), "res://scenes/Menu.tscn")

func _new_root(title: String) -> void:
	root = UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	UI.label(root, title, Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)

# ---------- setup: nomes dos jogadores ----------

func _build_setup() -> void:
	_new_root("POR TURNOS")
	UI.label(root, "Cada um corre na sua vez. Quem for mais longe vence!", Vector2(0, 62), 14,
		Color(0.8, 0.85, 0.95), 480, HORIZONTAL_ALIGNMENT_CENTER)

	names = SaveManager.data.get("turn_players", []).duplicate()

	name_edit = LineEdit.new()
	name_edit.position = Vector2(24, 96)
	name_edit.size = Vector2(300, 50)
	name_edit.placeholder_text = "Nome do jogador"
	name_edit.max_length = 32 # cabe a trapaça (nomes normais: até NAME_MAX)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.add_theme_stylebox_override("normal", UI.style(Color(0.06, 0.08, 0.13, 0.95), Color(0.25, 0.3, 0.4)))
	name_edit.add_theme_stylebox_override("focus", UI.style(Color(0.1, 0.14, 0.2, 0.95), UI.ACCENT, 10, 3))
	name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	name_edit.text_submitted.connect(func(_t): _add_name())
	root.add_child(name_edit)
	var add_btn := UI.button(root, "ADICIONAR", Rect2(332, 96, 124, 50), _add_name, 16)

	msg_label = UI.label(root, "", Vector2(0, 152), 15, Color(1, 0.4, 0.4), 480, HORIZONTAL_ALIGNMENT_CENTER)

	UI.panel(root, Rect2(24, 180, 432, 444))
	count_label = UI.label(root, "", Vector2(0, 190), 16, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	list_box = Control.new()
	list_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(list_box)

	var back := UI.button(root, "VOLTAR", Rect2(24, 640, 200, 54), _to_menu)
	start_btn = UI.button(root, "COMEÇAR", Rect2(256, 640, 200, 54), _start, 22)
	start_btn.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))

	name_edit.focus_neighbor_right = name_edit.get_path_to(add_btn)
	name_edit.focus_neighbor_bottom = name_edit.get_path_to(start_btn)
	add_btn.focus_neighbor_left = add_btn.get_path_to(name_edit)
	add_btn.focus_neighbor_bottom = add_btn.get_path_to(start_btn)
	for b in [back, start_btn]:
		b.focus_neighbor_top = b.get_path_to(name_edit)
	back.focus_neighbor_right = back.get_path_to(start_btn)
	start_btn.focus_neighbor_left = start_btn.get_path_to(back)

	_refresh_list()
	name_edit.grab_focus()

func _add_name() -> void:
	var n := name_edit.text.strip_edges()
	if n.is_empty():
		_error("Digite um nome")
		return
	if " ".join(n.to_lower().split(" ", false)) == CHEAT:
		_cheat()
		return
	if n.length() > NAME_MAX:
		_error("Nome com no máximo %d letras" % NAME_MAX)
		return
	if names.size() >= GameManager.TURN_MAX_PLAYERS:
		_error("Máximo de %d jogadores" % GameManager.TURN_MAX_PLAYERS)
		return
	for other in names:
		if String(other).to_lower() == n.to_lower():
			_error("Esse nome já está na lista")
			return
	names.append(n)
	name_edit.clear()
	msg_label.text = ""
	AudioManager.play("coin", -4.0, 0.0)
	_refresh_list()
	name_edit.grab_focus()

func _cheat() -> void:
	SaveManager.unlock_all()
	name_edit.clear()
	AudioManager.play("ui_buy", 0.0, 0.0)
	FX.burst(root, Vector2(240, 120), UI.GOLD, 70, 380.0, 1.0, 5.0)
	FX.burst(root, Vector2(240, 120), UI.ACCENT, 30, 260.0, 0.8, 4.0)
	msg_label.add_theme_color_override("font_color", Color(0.5, 1, 0.6))
	msg_label.text = "TRAPAÇA ATIVADA! Tudo liberado"
	name_edit.grab_focus()

func _remove_name(i: int) -> void:
	names.remove_at(i)
	_refresh_list()
	name_edit.grab_focus()

func _refresh_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	count_label.text = "JOGADORES  %d/%d" % [names.size(), GameManager.TURN_MAX_PLAYERS]
	if names.is_empty():
		UI.label(list_box, "Adicione pelo menos um jogador.\nA ordem da lista é a ordem das vezes.", Vector2(0, 360), 15,
			Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(names.size()):
		var y := 224.0 + i * 49.0
		UI.panel(list_box, Rect2(36, y, 408, 42), Color(0.08, 0.1, 0.16, 0.9))
		UI.label(list_box, "%d." % (i + 1), Vector2(48, y + 8), 20, UI.ACCENT)
		UI.label(list_box, names[i], Vector2(86, y + 8), 20, Color.WHITE)
		var x := UI.button(list_box, "X", Rect2(400, y + 4, 38, 34), _remove_name.bind(i), 16)
		x.focus_mode = Control.FOCUS_NONE
	start_btn.disabled = names.is_empty()

func _error(text: String) -> void:
	msg_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	msg_label.text = text
	AudioManager.play("ui_error", 0.0, 0.0)
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(msg_label, "position:x", 8.0 if i % 2 == 0 else -8.0, 0.05)
	tw.tween_property(msg_label, "position:x", 0.0, 0.05)

func _start() -> void:
	if names.is_empty():
		_error("Adicione pelo menos um jogador")
		return
	SaveManager.data["turn_players"] = names.duplicate()
	SaveManager.save()
	GameManager.start_turns(names)
	UI.go(get_tree(), "res://scenes/Turns.tscn")

# ---------- next: de quem é a vez ----------

func _build_next() -> void:
	_new_root("POR TURNOS")
	var total := GameManager.turn_players.size()
	UI.label(root, "JOGADOR %d DE %d" % [GameManager.turn_index + 1, total], Vector2(0, 76), 16,
		Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "VEZ DE", Vector2(0, 112), 20, UI.ACCENT, 480, HORIZONTAL_ALIGNMENT_CENTER)
	var who := UI.label(root, GameManager.current_player().to_upper(), Vector2(0, 140), 38, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	who.pivot_offset = Vector2(240, 24)
	who.scale = Vector2(1.4, 1.4)
	create_tween().tween_property(who, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# cada jogador escolhe o próprio carro (entre os comprados na garagem)
	var prev_car := UI.button(root, "<", Rect2(40, 188, 44, 40), _cycle_car.bind(-1), 20)
	var next_car := UI.button(root, ">", Rect2(396, 188, 44, 40), _cycle_car.bind(1), 20)
	car_label = UI.label(root, "", Vector2(84, 186), 18, Color.WHITE, 312, HORIZONTAL_ALIGNMENT_CENTER)
	car_desc = UI.label(root, "", Vector2(0, 211), 11, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	_refresh_car()

	UI.panel(root, Rect2(24, 236, 432, 388))
	UI.label(root, "PLACAR ATÉ AGORA", Vector2(0, 248), 18, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	var standings := GameManager.turn_standings()
	if standings.is_empty():
		UI.label(root, "Ninguém correu ainda.\nBoa sorte!", Vector2(0, 400), 16, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(standings.size()):
		_standing_row(standings[i], i, 286.0 + i * 40.0, false)

	var quit := UI.button(root, "DESISTIR", Rect2(24, 640, 200, 54), _to_menu)
	var go := UI.button(root, "CORRER!", Rect2(256, 640, 200, 54), func(): UI.go(get_tree(), "res://scenes/Game.tscn"), 24)
	go.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
	quit.focus_neighbor_right = quit.get_path_to(go)
	go.focus_neighbor_left = go.get_path_to(quit)
	quit.focus_neighbor_top = quit.get_path_to(prev_car)
	go.focus_neighbor_top = go.get_path_to(next_car)
	prev_car.focus_neighbor_right = prev_car.get_path_to(next_car)
	next_car.focus_neighbor_left = next_car.get_path_to(prev_car)
	prev_car.focus_neighbor_bottom = prev_car.get_path_to(quit)
	next_car.focus_neighbor_bottom = next_car.get_path_to(go)
	go.grab_focus()

func _cycle_car(dir: int) -> void:
	var owned: Array = GameManager.cars.filter(func(c): return SaveManager.is_owned(c["id"]))
	var who := GameManager.current_player()
	var cur := GameManager.turn_car_id(who)
	var i := 0
	for k in range(owned.size()):
		if owned[k]["id"] == cur:
			i = k
	i = (i + dir + owned.size()) % owned.size()
	GameManager.set_turn_car(who, owned[i]["id"])
	_refresh_car()

func _refresh_car() -> void:
	var car := GameManager.selected_car()
	car_label.text = "Carro: %s" % car["name"]
	car_desc.text = String(car["desc"]).replace("\n", " ")

# ---------- results: classificação final ----------

func _build_results() -> void:
	_new_root("RESULTADO")
	var standings := GameManager.turn_standings()
	var best: Dictionary = standings[0]
	var winners := PackedStringArray()
	for e in standings:
		if is_equal_approx(float(e["km"]), float(best["km"])) and int(e["score"]) == int(best["score"]):
			winners.append(String(e["name"]).to_upper())
	var title := "VENCEDOR" if winners.size() == 1 else "EMPATE"
	if standings.size() == 1:
		title = "MANDOU BEM"
	var who := " e ".join(winners)
	UI.label(root, title, Vector2(0, 64), 16, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	var w := UI.label(root, who, Vector2(0, 84), 36, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	w.pivot_offset = Vector2(240, 22)
	var tw := create_tween().set_loops()
	tw.tween_property(w, "scale", Vector2(1.06, 1.06), 0.5)
	tw.tween_property(w, "scale", Vector2.ONE, 0.5)
	UI.label(root, "chegou até %.2f km" % float(best["km"]), Vector2(0, 134), 20, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)

	UI.panel(root, Rect2(24, 176, 432, 448))
	UI.label(root, "CLASSIFICAÇÃO", Vector2(0, 186), 18, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(standings.size()):
		_standing_row(standings[i], i, 222.0 + i * 49.0, true)

	var menu := UI.button(root, "MENU", Rect2(24, 640, 136, 54), _to_menu, 18)
	var players := UI.button(root, "JOGADORES", Rect2(172, 640, 136, 54), _edit_players, 16)
	var again := UI.button(root, "REVANCHE", Rect2(320, 640, 136, 54), _rematch, 18)
	again.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
	var row := [menu, players, again]
	for i in range(row.size()):
		row[i].focus_neighbor_left = row[i].get_path_to(row[(i + 2) % 3])
		row[i].focus_neighbor_right = row[i].get_path_to(row[(i + 1) % 3])
	again.grab_focus()

	AudioManager.play("power_points", 0.0, 0.0)
	FX.burst(root, Vector2(240, 106), UI.GOLD, 70, 380.0, 1.0, 5.0)
	FX.burst(root, Vector2(240, 106), UI.ACCENT, 30, 260.0, 0.8, 4.0)

# volta para a tela de nomes (a lista salva já vem preenchida)
func _edit_players() -> void:
	GameManager.end_turns()
	UI.go(get_tree(), "res://scenes/Turns.tscn")

# mesmos jogadores, placar zerado
func _rematch() -> void:
	GameManager.start_turns(GameManager.turn_players)
	UI.go(get_tree(), "res://scenes/Turns.tscn")

func _standing_row(e: Dictionary, i: int, y: float, detail: bool) -> void:
	var c: Color = MEDALS[i] if i < 3 else Color.WHITE
	if detail:
		UI.panel(root, Rect2(36, y, 408, 44), Color(0.08, 0.1, 0.16, 0.9), c.darkened(0.3) if i < 3 else Color(0.2, 0.25, 0.35))
	UI.label(root, "%dº" % (i + 1), Vector2(48, y + 8), 20, c)
	UI.label(root, String(e["name"]), Vector2(96, y + (2 if detail else 8)), 20, Color.WHITE)
	if detail:
		UI.label(root, "%d pontos  •  %s" % [int(e["score"]), GameManager.car_by_id(String(e["car"]))["name"]],
			Vector2(96, y + 24), 12, Color(0.7, 0.75, 0.85))
	UI.label(root, "%.2f km" % float(e["km"]), Vector2(290, y + 8), 20, c, 140, HORIZONTAL_ALIGNMENT_RIGHT)
