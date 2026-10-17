extends Node2D

# Tela de missões: as 3 missões ativas com progresso e recompensa.
# A lógica fica em Missions.gd; completar paga as moedas no fim da corrida.

const World := preload("res://scripts/World.gd")
const Missions := preload("res://scripts/Missions.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 120.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 3 + 100.0
	add_child(world)

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	UI.label(root, "MISSÕES", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "Complete para ganhar moedas.\nCada missão completa é trocada por uma nova.",
		Vector2(0, 62), 14, Color(0.75, 0.8, 0.9), 480, HORIZONTAL_ALIGNMENT_CENTER)

	var list := Missions.active()
	SaveManager.save()
	for i in range(list.size()):
		var m: Dictionary = list[i]
		var d := Missions.def(String(m["id"]))
		var y := 124.0 + i * 128.0
		UI.panel(root, Rect2(24, y, 432, 114), UI.PANEL_BG, Color(0.25, 0.35, 0.45))
		UI.label(root, "MISSÃO %d" % (i + 1), Vector2(42, y + 10), 12, UI.ACCENT)
		UI.label(root, "NO TOTAL" if d.get("total", false) else "NUMA CORRIDA", Vector2(200, y + 10), 12,
			Color(0.65, 0.7, 0.8), 238, HORIZONTAL_ALIGNMENT_RIGHT)
		UI.label(root, String(d["text"]), Vector2(42, y + 30), 19, Color.WHITE, 330)
		UI.label(root, Missions.progress_text(m), Vector2(42, y + 82), 13, Color(0.75, 0.8, 0.9))
		UI.label(root, str(int(d["reward"])), Vector2(330, y + 74), 22, UI.GOLD, 100, HORIZONTAL_ALIGNMENT_RIGHT)

	var total := int(SaveManager.data.get("missions_done", 0))
	UI.label(root, "Missões completadas: %d" % total, Vector2(0, 520), 16, Color(0.5, 1, 0.6), 480, HORIZONTAL_ALIGNMENT_CENTER)

	var draw := func(ci: Control) -> void:
		for i in range(list.size()):
			var m: Dictionary = list[i]
			var d := Missions.def(String(m["id"]))
			var y := 124.0 + i * 128.0
			UI.draw_bar(ci, Rect2(42, y + 66, 270, 9), float(m["progress"]) / float(d["goal"]), UI.ACCENT)
			var tw := UI.font().get_string_size(str(int(d["reward"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			UI.draw_coin(ci, Vector2(430 - tw - 16, y + 88), 10)
	var hook := DrawHook.new(draw)
	hook.auto = false
	root.add_child(hook)

	var back := UI.button(root, "VOLTAR", Rect2(140, 640, 200, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	back.grab_focus()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		UI.go(get_tree(), "res://scenes/Menu.tscn")
