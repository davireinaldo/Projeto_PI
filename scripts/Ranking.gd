extends Node2D

# Ranking: patente atual (por KM global), todas as patentes e o
# top 10 de melhores corridas salvo no computador.

const World := preload("res://scripts/World.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

var _t: float = 0.0

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

	# top 10
	UI.panel(root, Rect2(16, 310, 448, 330))
	UI.label(root, "TOP 10 CORRIDAS", Vector2(0, 318), 18, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	var head := Color(0.6, 0.65, 0.75)
	UI.label(root, "#", Vector2(30, 346), 12, head)
	UI.label(root, "JOGADOR", Vector2(56, 346), 12, head)
	UI.label(root, "PONTOS", Vector2(184, 346), 12, head)
	UI.label(root, "DISTÂNCIA", Vector2(262, 346), 12, head)
	UI.label(root, "CARRO", Vector2(364, 346), 12, head)
	var top: Array = SaveManager.data["top"]
	if top.is_empty():
		UI.label(root, "Nenhuma corrida ainda.\nVá para a pista!", Vector2(0, 440), 16, Color(0.7, 0.75, 0.85), 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(top.size()):
		var e: Dictionary = top[i]
		var y := 368.0 + i * 26.0
		var c: Color = [UI.GOLD, Color(0.85, 0.87, 0.92), Color(0.85, 0.55, 0.3)][i] if i < 3 else Color.WHITE
		var player := String(e.get("name", ""))
		UI.label(root, str(i + 1), Vector2(30, y), 15, c)
		var name_label := UI.label(root, player if player != "" else "—", Vector2(56, y), 15, Color.WHITE, 120)
		name_label.clip_text = true
		UI.label(root, str(int(e["score"])), Vector2(184, y), 15, c)
		UI.label(root, "%.2f km" % float(e["km"]), Vector2(262, y), 15, Color.WHITE)
		UI.label(root, GameManager.car_by_id(String(e["car"]))["name"], Vector2(364, y), 15, Color(0.7, 0.75, 0.85))

	var back := UI.button(root, "VOLTAR", Rect2(140, 656, 200, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	back.grab_focus()

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
