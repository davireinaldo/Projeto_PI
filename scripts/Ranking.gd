extends Node2D

# Ranking: patente atual (por KM global), todas as patentes e o top 10
# em três abas: GERAL e COOP (salvos no computador) e ONLINE (mundial,
# ver OnlineRanking.gd).

const World := preload("res://scripts/World.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

var _t: float = 0.0
enum Tab { GENERAL, COOP, ONLINE }

var tabs: Array = [] # um botão por aba, na ordem do enum Tab
var tab: int = Tab.GENERAL
var top_box: Control
var online_box: Control # lista do top online (preenchida quando a resposta chega)

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 120.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 2 + 100.0
	add_child(world)

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	root.add_child(DrawHook.new(_draw_screen))

	var km := SaveManager.total_km()
	var ri := GameManager.rank_index(km)
	var rank: Dictionary = GameManager.ranks[ri]
	UI.label(root, "RANKING", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.panel(root, Rect2(16, 66, 448, 140))
	UI.label(root, "SUA PATENTE", Vector2(140, 78), 13, Color(0.7, 0.75, 0.85))
	UI.label(root, String(rank["name"]).to_upper(), Vector2(140, 94), 34, rank["color"])
	UI.label(root, "%.2f km rodados no total" % km, Vector2(140, 136), 14, Color(0.85, 0.9, 1.0))
	var next_text := "Você chegou na patente máxima!"
	if ri < GameManager.ranks.size() - 1:
		var nxt: Dictionary = GameManager.ranks[ri + 1]
		next_text = "Próxima: %s em %.1f km" % [nxt["name"], float(nxt["km"]) - km]
	UI.label(root, next_text, Vector2(140, 176), 13, Color(0.7, 0.75, 0.85))

	# todas as patentes
	for i in range(GameManager.ranks.size()):
		var r: Dictionary = GameManager.ranks[i]
		var x := 16.0 + i * 74.67
		UI.label(root, r["name"], Vector2(x, 268), 12, r["color"] if i <= ri else Color(0.45, 0.47, 0.52), 74.67, HORIZONTAL_ALIGNMENT_CENTER)
		UI.label(root, "%d km" % int(r["km"]), Vector2(x, 284), 11, Color(0.6, 0.62, 0.7), 74.67, HORIZONTAL_ALIGNMENT_CENTER)

	# top 10: GERAL (por pontos), COOP (modo por turnos, por distância) e ONLINE
	UI.panel(root, Rect2(16, 310, 448, 330))
	var names := ["GERAL", "COOP", "ONLINE"]
	for i in range(names.size()):
		tabs.append(UI.button(root, names[i], Rect2(34 + i * 140, 316, 132, 30), _show_top.bind(i), 14))
	top_box = Control.new()
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(top_box)

	var back := UI.button(root, "VOLTAR", Rect2(140, 656, 200, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	for i in range(tabs.size()):
		var t: Button = tabs[i]
		t.focus_neighbor_bottom = t.get_path_to(back)
		t.focus_neighbor_left = t.get_path_to(tabs[max(i - 1, 0)])
		t.focus_neighbor_right = t.get_path_to(tabs[min(i + 1, tabs.size() - 1)])
	back.focus_neighbor_top = back.get_path_to(tabs[0])
	OnlineRanking.top_loaded.connect(_on_online_top)
	OnlineRanking.submit_best()
	_show_top(Tab.GENERAL)
	back.grab_focus()

func _show_top(which: int) -> void:
	tab = which
	for c in top_box.get_children():
		c.queue_free()
	var on := UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2)
	var off := UI.style(Color(0.06, 0.08, 0.13, 0.6), Color(0.25, 0.3, 0.4), 10, 1)
	for i in range(tabs.size()):
		tabs[i].add_theme_stylebox_override("normal", on if i == which else off)
	if which == Tab.ONLINE:
		_show_online()
		return
	var coop := which == Tab.COOP

	var head := Color(0.6, 0.65, 0.75)
	UI.label(top_box, "#", Vector2(30, 350), 12, head)
	UI.label(top_box, "JOGADOR", Vector2(56, 350), 12, head)
	UI.label(top_box, "DISTÂNCIA" if coop else "PONTOS", Vector2(184, 350), 12, head)
	UI.label(top_box, "PONTOS" if coop else "DISTÂNCIA", Vector2(272, 350), 12, head)
	UI.label(top_box, "CARRO", Vector2(364, 350), 12, head)
	var top: Array = SaveManager.data["coop_top" if coop else "top"]
	if top.is_empty():
		var empty := "Nenhuma partida por turnos ainda.\nChame a galera!" if coop else "Nenhuma corrida ainda.\nVá para a pista!"
		UI.label(top_box, empty, Vector2(0, 440), 16, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(top.size()):
		var e: Dictionary = top[i]
		var y := 370.0 + i * 26.0
		var c: Color = [UI.GOLD, Color(0.85, 0.87, 0.92), Color(0.85, 0.55, 0.3)][i] if i < 3 else Color.WHITE
		var player := String(e.get("name", ""))
		var km := "%.2f km" % float(e["km"])
		var pts := str(int(e["score"]))
		UI.label(top_box, str(i + 1), Vector2(30, y), 15, c)
		var name_label := UI.label(top_box, player if player != "" else "—", Vector2(56, y), 15, Color.WHITE, 120)
		name_label.clip_text = true
		UI.label(top_box, km if coop else pts, Vector2(184, y), 15, c)
		UI.label(top_box, pts if coop else km, Vector2(272, y), 15, Color.WHITE)
		UI.label(top_box, GameManager.car_by_id(String(e["car"]))["name"], Vector2(364, y), 15, Color(0.7, 0.75, 0.85))

# ---------- aba ONLINE ----------

func _show_online() -> void:
	if not OnlineRanking.enabled():
		UI.label(top_box, "Ranking online ainda não configurado.
Veja RANKING ONLINE no LEIA-ME.txt.",
			Vector2(0, 450), 16, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
		return
	UI.label(top_box, "SEU NOME", Vector2(30, 356), 12, Color(0.6, 0.65, 0.75))
	var edit := LineEdit.new()
	edit.position = Vector2(100, 350)
	edit.size = Vector2(220, 32)
	edit.placeholder_text = "Digite seu nome"
	edit.text = OnlineRanking.player_name()
	edit.max_length = OnlineRanking.NAME_MAX
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_stylebox_override("normal", UI.style(Color(0.06, 0.08, 0.13, 0.95), Color(0.25, 0.3, 0.4), 8, 2))
	edit.add_theme_stylebox_override("focus", UI.style(Color(0.1, 0.14, 0.2, 0.95), UI.ACCENT, 8, 2))
	edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	top_box.add_child(edit)
	var save_name := func() -> void:
		edit.release_focus()
		if edit.text.strip_edges() == "":
			return
		OnlineRanking.set_player_name(edit.text)
		edit.text = OnlineRanking.player_name()
		# dá um tempinho para o recorde chegar antes de recarregar a lista
		get_tree().create_timer(1.2).timeout.connect(OnlineRanking.fetch_top)
	edit.text_submitted.connect(func(_t: String): save_name.call())
	UI.button(top_box, "SALVAR", Rect2(328, 350, 120, 32), save_name, 14)
	var hint := "Seu recorde entra aqui automaticamente." if OnlineRanking.player_name() != "" 		else "Coloque seu nome para entrar no ranking mundial."
	UI.label(top_box, hint, Vector2(0, 388), 12, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)

	online_box = Control.new()
	online_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_box.add_child(online_box)
	UI.label(online_box, "Carregando...", Vector2(0, 470), 16, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	OnlineRanking.fetch_top()

func _on_online_top(ok: bool, list: Array) -> void:
	if tab != Tab.ONLINE or not is_instance_valid(online_box):
		return
	for c in online_box.get_children():
		c.queue_free()
	if not ok:
		UI.label(online_box, "Não deu para carregar o ranking.
Confira a internet e tente de novo.",
			Vector2(0, 460), 15, Color(1, 0.5, 0.5), 480, HORIZONTAL_ALIGNMENT_CENTER)
		return
	if list.is_empty():
		UI.label(online_box, "Ninguém no ranking ainda.
Seja o primeiro!", Vector2(0, 460), 16,
			Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var head := Color(0.6, 0.65, 0.75)
	UI.label(online_box, "#", Vector2(30, 408), 12, head)
	UI.label(online_box, "JOGADOR", Vector2(56, 408), 12, head)
	UI.label(online_box, "PONTOS", Vector2(184, 408), 12, head)
	UI.label(online_box, "DISTÂNCIA", Vector2(272, 408), 12, head)
	UI.label(online_box, "CARRO", Vector2(364, 408), 12, head)
	for i in range(list.size()):
		var e: Dictionary = list[i]
		var y := 426.0 + i * 21.0
		var c: Color = [UI.GOLD, Color(0.85, 0.87, 0.92), Color(0.85, 0.55, 0.3)][i] if i < 3 else Color.WHITE
		var me := String(e.get("name", "")) == OnlineRanking.player_name()
		UI.label(online_box, str(i + 1), Vector2(30, y), 14, c)
		var name_label := UI.label(online_box, String(e.get("name", "")), Vector2(56, y), 14, UI.ACCENT if me else Color.WHITE, 120)
		name_label.clip_text = true
		UI.label(online_box, str(int(e.get("score", 0))), Vector2(184, y), 14, c)
		UI.label(online_box, "%.2f km" % float(e.get("km", 0.0)), Vector2(272, y), 14, Color.WHITE)
		UI.label(online_box, GameManager.car_by_id(String(e.get("car", "")))["name"], Vector2(364, y), 14, Color(0.7, 0.75, 0.85))

func _process(delta: float) -> void:
	_t += delta
	if Input.is_action_just_pressed("ui_cancel"):
		UI.go(get_tree(), "res://scenes/Menu.tscn")

func _draw_screen(ci: Control) -> void:
	var km := SaveManager.total_km()
	var ri := GameManager.rank_index(km)
	var rank: Dictionary = GameManager.ranks[ri]
	UI.draw_rank_badge(ci, Vector2(76, 136), 46 + sin(_t * 2.0) * 2.0, ri)
	UI.draw_bar(ci, Rect2(140, 160, 300, 10), GameManager.rank_progress(km), rank["color"])
	for i in range(GameManager.ranks.size()):
		UI.draw_rank_badge(ci, Vector2(16.0 + i * 74.67 + 37.33, 240), 20, i, i > ri)
