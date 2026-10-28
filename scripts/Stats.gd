extends Node2D

# Estatísticas gerais: KM global, corridas, recordes, moedas e
# quantos KM cada carro já rodou.

const World := preload("res://scripts/World.gd")
const CarVisual := preload("res://scripts/CarVisual.gd")
const Paints := preload("res://scripts/Paints.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 120.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 1 + 100.0
	add_child(world)

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	UI.label(root, "ESTATÍSTICAS", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)

	var d := SaveManager.data
	var cards := [
		["KM TOTAL", "%.2f km" % SaveManager.total_km(), UI.ACCENT],
		["CORRIDAS", str(int(d["runs"])), Color.WHITE],
		["MAIOR DISTÂNCIA", "%.2f km" % float(d["best_distance_km"]), Color(0.6, 1.0, 0.6)],
		["MELHOR PONTUAÇÃO", str(int(d["best_score"])), UI.HOT],
		["MOEDAS GANHAS", str(int(d["total_coins_earned"])), UI.GOLD],
		["MOEDAS AGORA", str(SaveManager.coins()), UI.GOLD],
	]
	for i in range(cards.size()):
		var x := 16.0 + (i % 2) * 228.0
		var y := 66.0 + (i / 2) * 76.0
		UI.panel(root, Rect2(x, y, 220, 68))
		UI.label(root, cards[i][0], Vector2(x + 14, y + 8), 12, Color(0.65, 0.7, 0.8))
		UI.label(root, cards[i][1], Vector2(x + 14, y + 26), 26, cards[i][2])

	UI.panel(root, Rect2(16, 300, 448, 344))
	UI.label(root, "KM POR CARRO", Vector2(0, 308), 18, UI.ACCENT, 480, HORIZONTAL_ALIGNMENT_CENTER)
	var max_km := 0.01
	for c in GameManager.cars:
		max_km = max(max_km, SaveManager.car_km(c["id"]))
	for i in range(GameManager.cars.size()):
		var c: Dictionary = GameManager.cars[i]
		var y := 342.0 + i * 27.0
		var owned := SaveManager.is_owned(c["id"])
		var icon := CarVisual.new()
		Paints.apply(icon, c)
		icon.dim = 0.0 if owned else 0.6
		icon.rotation = PI * 0.5
		icon.scale = Vector2(0.42, 0.42)
		icon.position = Vector2(46, y + 12)
		root.add_child(icon)
		UI.label(root, c["name"] if owned else "%s (bloqueado)" % c["name"], Vector2(72, y + 2), 14,
			Color.WHITE if owned else Color(0.5, 0.52, 0.58))
		UI.label(root, "%.2f km" % SaveManager.car_km(c["id"]), Vector2(340, y + 2), 14, Color(0.85, 0.9, 1.0), 110, HORIZONTAL_ALIGNMENT_RIGHT)
	var bars := func(ci: Control) -> void:
		for i in range(GameManager.cars.size()):
			var c: Dictionary = GameManager.cars[i]
			var col: Color = c["accent"] if c["model"] == "legend" else c["color"]
			UI.draw_bar(ci, Rect2(72, 342.0 + i * 27.0 + 22, 378, 5), SaveManager.car_km(c["id"]) / max_km, col.lerp(Color.WHITE, 0.25))
	var hook := DrawHook.new(bars)
	hook.auto = false
	root.add_child(hook)

	var back := UI.button(root, "VOLTAR", Rect2(140, 656, 200, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	back.grab_focus()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		UI.go(get_tree(), "res://scenes/Menu.tscn")
