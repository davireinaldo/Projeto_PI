extends Node2D

# Oficina: gastar moedas em melhorias permanentes dos poderes.
# Cada nível faz o poder durar mais (valores em GameManager.upgrades).
# Abre pela Garagem (botão OFICINA) e volta para ela.

const World := preload("res://scripts/World.gd")
const PowerUp := preload("res://scripts/PowerUp.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

const ROW_Y := 96.0
const ROW_H := 98.0
const ROW_GAP := 8.0

var root: Control
var coins_label: Label
var msg_label: Label
var rows: Array = [] # {"id", "time": Label, "btn": Button}
var _t: float = 0.0

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	GameManager.speed = 140.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 3 + 100.0
	add_child(world)
	AudioManager.play_music("menu")
	_build_ui()
	_refresh()

func _process(delta: float) -> void:
	_t += delta
	if Input.is_action_just_pressed("ui_cancel"):
		UI.go(get_tree(), "res://scenes/Garage.tscn")

func _row_top(i: int) -> float:
	return ROW_Y + i * (ROW_H + ROW_GAP)

# ---------- interface ----------

func _build_ui() -> void:
	root = UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	UI.label(root, "OFICINA", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	coins_label = UI.label(root, "", Vector2(330, 24), 20, UI.GOLD, 136, HORIZONTAL_ALIGNMENT_RIGHT)
	UI.label(root, "Cada nível faz o poder durar mais", Vector2(0, 62), 14, Color(0.8, 0.85, 0.95), 480, HORIZONTAL_ALIGNMENT_CENTER)

	var buttons: Array = []
	for i in range(GameManager.upgrades.size()):
		var id: String = GameManager.upgrades[i]["id"]
		var y := _row_top(i)
		UI.panel(root, Rect2(16, y, 448, ROW_H))
		UI.label(root, PowerUp.NAMES[id], Vector2(104, y + 10), 20, PowerUp.COLORS[id])
		var time := UI.label(root, "", Vector2(104, y + 40), 14, Color(0.85, 0.9, 1.0))
		var btn := UI.button(root, "", Rect2(302, y + 26, 150, 46), _buy.bind(i), 15)
		rows.append({"id": id, "time": time, "btn": btn})
		buttons.append(btn)
	root.add_child(DrawHook.new(_draw_screen))

	msg_label = UI.label(root, "", Vector2(0, 622), 15, Color(1, 0.4, 0.4), 480, HORIZONTAL_ALIGNMENT_CENTER)
	var back := UI.button(root, "VOLTAR", Rect2(140, 652, 200, 48), func(): UI.go(get_tree(), "res://scenes/Garage.tscn"))
	buttons.append(back)
	UI.chain_vertical(buttons)
	buttons[0].grab_focus()

func _secs(s: float) -> String:
	return ("%.1f s" % s).replace(".", ",")

func _refresh() -> void:
	coins_label.text = str(SaveManager.coins())
	for r in rows:
		var id: String = r["id"]
		var level := SaveManager.upgrade_level(id)
		var price := GameManager.upgrade_price(id)
		var btn: Button = r["btn"]
		if price == 0:
			r["time"].text = "Dura %s  (máximo)" % _secs(GameManager.power_duration(id))
			btn.text = "MÁXIMO"
			btn.disabled = true
			btn.modulate = Color.WHITE
		else:
			r["time"].text = "Dura %s  →  %s" % [_secs(GameManager.power_duration(id)), _secs(GameManager.power_duration(id, level + 1))]
			btn.text = "COMPRAR %d" % price
			btn.modulate = Color.WHITE if SaveManager.coins() >= price else Color(1, 1, 1, 0.55)

func _buy(i: int) -> void:
	var r: Dictionary = rows[i]
	var id: String = r["id"]
	var price := GameManager.upgrade_price(id)
	if SaveManager.buy_upgrade(id, price):
		msg_label.text = ""
		AudioManager.play("ui_buy", 0.0, 0.0)
		var c: Vector2 = Vector2(60, _row_top(i) + ROW_H * 0.5)
		FX.burst(root, c, PowerUp.COLORS[id], 40, 260.0, 0.7, 4.0)
		FX.float_text(root, c + Vector2(130, -10), "NÍVEL %d!" % SaveManager.upgrade_level(id), UI.GOLD, 24)
		_refresh()
		return
	AudioManager.play("ui_error", 0.0, 0.0)
	msg_label.text = "Faltam %d moedas" % (price - SaveManager.coins())
	var tw := create_tween()
	for k in range(4):
		tw.tween_property(msg_label, "position:x", 8.0 if k % 2 == 0 else -8.0, 0.05)
	tw.tween_property(msg_label, "position:x", 0.0, 0.05)

# ---------- desenho ----------

func _draw_screen(ci: Control) -> void:
	UI.draw_coin(ci, Vector2(466 - UI.font().get_string_size(coins_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x - 16, 38), 10)
	var levels := GameManager.UPGRADE_PRICES.size()
	for i in range(rows.size()):
		var id: String = rows[i]["id"]
		var y := _row_top(i)
		var col: Color = PowerUp.COLORS[id]
		ci.draw_set_transform(Vector2(60, y + ROW_H * 0.5))
		PowerUp.draw_icon(ci, id, _t)
		ci.draw_set_transform(Vector2.ZERO)
		# um tracinho por nível
		var level := SaveManager.upgrade_level(id)
		for k in range(levels):
			var r := Rect2(104 + k * 36, y + 70, 30, 8)
			ci.draw_rect(r, col if k < level else Color(1, 1, 1, 0.12))
			ci.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
