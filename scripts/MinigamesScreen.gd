extends Node2D

# Tela de minigames: os modos para jogar com os amigos (Versus e Por Turnos),
# para o menu inicial ficar mais enxuto.

const World := preload("res://scripts/World.gd")
const UI := preload("res://scripts/UIKit.gd")

const GAMES := [
	["VERSUS", "2 jogadores na mesma tela, 5 faixas.\nEmpurre o rival para ele bater!", "res://scenes/VersusSetup.tscn", Color(1.0, 0.25, 0.55)],
	["POR TURNOS", "Até 8 jogadores, cada um na sua vez.\nQuem for mais longe vence!", "res://scenes/Turns.tscn", Color(0.1, 0.95, 0.9)],
]

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 120.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 5 + 100.0
	add_child(world)

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	UI.label(root, "MINIGAMES", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "Para jogar com os amigos", Vector2(0, 62), 14, Color(0.75, 0.8, 0.9), 480, HORIZONTAL_ALIGNMENT_CENTER)

	var buttons: Array = []
	for i in range(GAMES.size()):
		var g: Array = GAMES[i]
		var y := 110.0 + i * 190.0
		var col: Color = g[3]
		UI.panel(root, Rect2(24, y, 432, 172), UI.PANEL_BG, col.darkened(0.3))
		UI.label(root, g[0], Vector2(24, y + 14), 26, col, 432, HORIZONTAL_ALIGNMENT_CENTER)
		UI.label(root, g[1], Vector2(24, y + 54), 14, Color(0.85, 0.9, 1.0), 432, HORIZONTAL_ALIGNMENT_CENTER)
		var scene: String = g[2]
		var b := UI.button(root, "JOGAR", Rect2(120, y + 108, 240, 48), func(): UI.go(get_tree(), scene), 20)
		b.add_theme_stylebox_override("normal", UI.style(col.darkened(0.7), col, 10, 2))
		buttons.append(b)

	var back := UI.button(root, "VOLTAR", Rect2(140, 640, 200, 48), _back)
	buttons.append(back)
	UI.chain_vertical(buttons)
	buttons[0].grab_focus()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_back()

func _back() -> void:
	UI.go(get_tree(), "res://scenes/Menu.tscn")
