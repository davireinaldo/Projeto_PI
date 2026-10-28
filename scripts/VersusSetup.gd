extends Node2D

# Antes do versus: cada jogador escolhe o carro (entre os comprados na garagem).
# Jogador 1: A/D troca o carro e W confirma. Jogador 2: setas ←/→ e ↑.
# No celular cada um usa os botões do seu lado. Com os dois prontos, começa.

const World := preload("res://scripts/World.gd")
const CarVisual := preload("res://scripts/CarVisual.gd")
const Paints := preload("res://scripts/Paints.gd")
const UI := preload("res://scripts/UIKit.gd")
const Versus := preload("res://scripts/Versus.gd")

const COL_X := [20.0, 250.0] # coluna de cada jogador
const COL_W := 210.0

var owned: Array = []
var pick: Array = [0, 0] # índice em owned
var confirmed: Array = [false, false]
var visuals: Array = []
var name_labels: Array = []
var info_labels: Array = []
var ready_btns: Array = []
var status_label: Label
var _starting: bool = false

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 140.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 5 + 100.0
	add_child(world)

	owned = GameManager.cars.filter(func(c): return SaveManager.is_owned(c["id"]))
	# começa nos carros da última partida; senão o da garagem e o próximo
	var sel := _owned_index(String(SaveManager.data["selected"]))
	pick = [sel, (sel + 1) % owned.size()]
	for i in range(2):
		var last := _owned_index(String(GameManager.versus_cars[i]), -1)
		if last >= 0:
			pick[i] = last

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	UI.label(root, "VERSUS", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "2 jogadores, 5 faixas. Empurre o rival para ele bater!\nQuem ganhar %d rodadas vence." % GameManager.VERSUS_WINS,
		Vector2(0, 58), 13, Color(0.8, 0.85, 0.95), 480, HORIZONTAL_ALIGNMENT_CENTER)

	# os carros ficam numa camada acima dos painéis
	var cars_layer := CanvasLayer.new()
	cars_layer.layer = 11
	add_child(cars_layer)

	for i in range(2):
		var x: float = COL_X[i]
		var col: Color = Versus.COLORS[i]
		UI.panel(root, Rect2(x, 104, COL_W, 500), Color(0.05, 0.06, 0.1, 0.9), col.darkened(0.3))
		UI.label(root, "JOGADOR %d" % (i + 1), Vector2(x, 116), 20, col, COL_W, HORIZONTAL_ALIGNMENT_CENTER)
		var v := CarVisual.new()
		v.position = Vector2(x + COL_W * 0.5, 248)
		v.scale = Vector2(2.2, 2.2)
		cars_layer.add_child(v)
		visuals.append(v)
		name_labels.append(UI.label(root, "", Vector2(x, 334), 18, Color.WHITE, COL_W, HORIZONTAL_ALIGNMENT_CENTER))
		var info := UI.label(root, "", Vector2(x + 10, 364), 12, Color(0.75, 0.8, 0.9), COL_W - 20, HORIZONTAL_ALIGNMENT_CENTER)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_labels.append(info)
		var prev := UI.button(root, "<", Rect2(x + 14, 456, 56, 44), _cycle.bind(i, -1), 22)
		var next := UI.button(root, ">", Rect2(x + COL_W - 70, 456, 56, 44), _cycle.bind(i, 1), 22)
		var ok := UI.button(root, "", Rect2(x + 14, 510, COL_W - 28, 48), _toggle_ready.bind(i), 18)
		ready_btns.append(ok)
		var keys := "A / D  troca  •  W  pronto" if i == 0 else "← / →  troca  •  ↑  pronto"
		UI.label(root, keys, Vector2(x, 570), 11, Color(1, 1, 1, 0.55), COL_W, HORIZONTAL_ALIGNMENT_CENTER)
		# as setas são do jogador 2: os botões não pegam o foco do teclado
		for b in [prev, next, ok]:
			b.focus_mode = Control.FOCUS_NONE
		_refresh(i)

	status_label = UI.label(root, "", Vector2(0, 612), 15, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)
	var back := UI.button(root, "VOLTAR", Rect2(140, 644, 200, 50), _back)
	back.focus_mode = Control.FOCUS_NONE
	_refresh_status()

func _process(_delta: float) -> void:
	if _starting:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		_back()
		return
	for i in range(2):
		var p := "p%d" % (i + 1)
		if Input.is_action_just_pressed(p + "_left"):
			_cycle(i, -1)
		if Input.is_action_just_pressed(p + "_right"):
			_cycle(i, 1)
		if Input.is_action_just_pressed(p + "_up"):
			_toggle_ready(i)

func _owned_index(id: String, fallback: int = 0) -> int:
	for k in range(owned.size()):
		if owned[k]["id"] == id:
			return k
	return fallback

func _cycle(i: int, dir: int) -> void:
	if _starting:
		return
	pick[i] = (pick[i] + dir + owned.size()) % owned.size()
	confirmed[i] = false
	AudioManager.play("ui_move", -4.0, 0.0)
	_refresh(i)
	_refresh_status()

func _toggle_ready(i: int) -> void:
	if _starting:
		return
	confirmed[i] = not confirmed[i]
	AudioManager.play("ui_click", 0.0, 0.0)
	_refresh(i)
	_refresh_status()
	if confirmed[0] and confirmed[1]:
		_start()

func _refresh(i: int) -> void:
	var car: Dictionary = owned[pick[i]]
	Paints.apply(visuals[i], car)
	name_labels[i].text = String(car["name"])
	info_labels[i].text = "Troca de faixa: %s" % _speed_text(float(car["lane_speed"]))
	var b: Button = ready_btns[i]
	b.text = "PRONTO!" if confirmed[i] else "CONFIRMAR"
	var col: Color = Versus.COLORS[i]
	b.add_theme_stylebox_override("normal", UI.style(col.darkened(0.6) if confirmed[i] else Color(0.06, 0.08, 0.13, 0.88), col if confirmed[i] else Color(0.25, 0.3, 0.4), 10, 2))

func _speed_text(s: float) -> String:
	if s >= 16.0:
		return "muito rápida"
	if s >= 12.0:
		return "rápida"
	if s >= 10.0:
		return "normal"
	return "lenta"

func _refresh_status() -> void:
	var n := int(confirmed[0]) + int(confirmed[1])
	status_label.text = "Os dois precisam confirmar" if n < 2 else "Valendo!"

func _start() -> void:
	_starting = true
	GameManager.start_versus(owned[pick[0]]["id"], owned[pick[1]]["id"])
	AudioManager.play("power_points", 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout
	UI.go(get_tree(), "res://scenes/Versus.tscn")

func _back() -> void:
	UI.go(get_tree(), "res://scenes/Minigames.tscn")
