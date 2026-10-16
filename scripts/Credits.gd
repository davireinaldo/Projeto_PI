extends Node2D

# Créditos: quem desenvolveu o ZERO-IMPACT.

const World := preload("res://scripts/World.gd")
const UI := preload("res://scripts/UIKit.gd")

const DEVS := [
	"João de Sousa Galdino",
	"Davi Reinaldo da Silva",
	"João Nacélio Peixoto Santos",
	"Cicero Lorhan Ramos da Silva",
	"João Pedro Fernandes de Galiza",
]

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 120.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = 100.0
	add_child(world)

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	UI.label(root, "CRÉDITOS", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)

	UI.label(root, "ZERO-IMPACT", Vector2(0, 130), 44, UI.ACCENT, 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "A R C A D E   R A C I N G", Vector2(0, 190), 14, Color(1, 1, 1, 0.8), 480, HORIZONTAL_ALIGNMENT_CENTER)

	UI.panel(root, Rect2(32, 250, 416, 316))
	UI.label(root, "DESENVOLVIDO POR", Vector2(0, 270), 16, Color(0.65, 0.7, 0.8), 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(DEVS.size()):
		UI.label(root, DEVS[i], Vector2(0, 312 + i * 48), 22, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)

	var back := UI.button(root, "VOLTAR", Rect2(140, 656, 200, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	back.grab_focus()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		UI.go(get_tree(), "res://scenes/Menu.tscn")
