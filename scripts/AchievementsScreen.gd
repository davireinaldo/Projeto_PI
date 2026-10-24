extends Node2D

# Tela de Conquistas (Achievements): lista todas as conquistas do jogo,
# indicando quais já foram desbloqueadas e o progresso geral.

const World := preload("res://scripts/World.gd")
const UI := preload("res://scripts/UIKit.gd")
const Achievements := preload("res://scripts/Achievements.gd")

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	AudioManager.play_music("menu")
	GameManager.speed = 120.0

	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 0.5
	add_child(world)

	var root := UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.76)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	UI.label(root, "CONQUISTAS", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)

	var all_ach := Achievements.all()
	var unlocked_count := 0
	for a in all_ach:
		if Achievements.is_unlocked(String(a["id"])):
			unlocked_count += 1

	var pct := int((float(unlocked_count) / float(all_ach.size())) * 100.0) if all_ach.size() > 0 else 0
	UI.label(root, "%d DE %d DESBLOQUEADAS (%d%%)" % [unlocked_count, all_ach.size(), pct], Vector2(0, 56), 14, UI.GOLD, 480, HORIZONTAL_ALIGNMENT_CENTER)

	# Container com rolagem para as conquistas
	var panel := UI.panel(root, Rect2(16, 84, 448, 556))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 94)
	scroll.size = Vector2(432, 536)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	for a in all_ach:
		var id: String = a["id"]
		var done := Achievements.is_unlocked(id)

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(420, 54)
		var bg_col := Color(0.06, 0.16, 0.12, 0.9) if done else Color(0.05, 0.06, 0.09, 0.7)
		var border_col := Color(0.2, 0.85, 0.45) if done else Color(0.2, 0.22, 0.28)
		card.add_theme_stylebox_override("panel", UI.style(bg_col, border_col, 8, 1))
		vbox.add_child(card)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		card.add_child(hbox)

		var icon_lbl := Label.new()
		icon_lbl.text = String(a["icon"])
		icon_lbl.custom_minimum_size = Vector2(40, 48)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 22)
		icon_lbl.modulate = Color.WHITE if done else Color(0.4, 0.4, 0.4)
		hbox.add_child(icon_lbl)

		var text_box := VBoxContainer.new()
		text_box.alignment = BoxContainer.ALIGNMENT_CENTER
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(text_box)

		var title_lbl := Label.new()
		title_lbl.text = String(a["title"])
		title_lbl.add_theme_font_size_override("font_size", 15)
		title_lbl.modulate = UI.GOLD if done else Color(0.7, 0.72, 0.78)
		text_box.add_child(title_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = String(a["desc"])
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.modulate = Color(0.8, 0.85, 0.9) if done else Color(0.45, 0.48, 0.52)
		text_box.add_child(desc_lbl)

		var status_lbl := Label.new()
		status_lbl.text = "✓" if done else "—"
		status_lbl.custom_minimum_size = Vector2(36, 48)
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_lbl.add_theme_font_size_override("font_size", 20)
		status_lbl.modulate = Color(0.2, 1.0, 0.4) if done else Color(0.3, 0.35, 0.4)
		hbox.add_child(status_lbl)

	var back := UI.button(root, "VOLTAR", Rect2(140, 656, 200, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	back.grab_focus()
