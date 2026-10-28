extends Node2D

# Garagem: escolher, comprar e ver os atributos de cada carro.
# Setas esquerda/direita (ou os botões < >) trocam o carro.
# PINTAR abre a tela de pintura e rastro do carro (Paint.tscn) e
# OFICINA as melhorias dos poderes (Upgrades.tscn).

const World := preload("res://scripts/World.gd")
const CarVisual := preload("res://scripts/CarVisual.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")
const Paints := preload("res://scripts/Paints.gd")

const CENTER := Vector2(240, 225)

var index: int = 0
var preview: Node2D
var root: Control
var name_label: Label
var status_label: Label
var desc_label: Label
var km_label: Label
var coins_label: Label
var msg_label: Label
var action_btn: Button
var paint_btn: Button
var shop_btn: Button
var back_btn: Button
var _t: float = 0.0
var _swap: float = 1.0 # animação de troca de carro

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	GameManager.speed = 140.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 5 + 100.0
	add_child(world)

	AudioManager.play_music("menu")
	# voltando da Pintura, abre no carro que estava sendo pintado
	var start_id := GameManager.paint_car if GameManager.paint_car != "" else String(SaveManager.data["selected"])
	GameManager.paint_car = ""
	index = GameManager.car_index(start_id)
	_build_ui()
	_refresh()

func _process(delta: float) -> void:
	_t += delta
	_swap = min(_swap + delta * 4.0, 1.0)
	preview.rotation += delta * 0.7
	preview.scale = Vector2.ONE * 2.3 * (0.7 + 0.3 * ease(_swap, 0.4))
	if Input.is_action_just_pressed("ui_cancel"):
		UI.go(get_tree(), "res://scenes/Menu.tscn")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") or event.is_action_pressed("steer_left"):
		_change(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("steer_right"):
		_change(1)
		get_viewport().set_input_as_handled()

func _change(dir: int) -> void:
	index = (index + dir + GameManager.cars.size()) % GameManager.cars.size()
	_swap = 0.0
	AudioManager.play("whoosh", -2.0, 0.1)
	_refresh()

func _car() -> Dictionary:
	return GameManager.cars[index]

# ---------- interface ----------

func _build_ui() -> void:
	root = UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	root.add_child(DrawHook.new(_draw_screen))

	# o carro grande fica numa camada própria, acima do fundo escuro
	preview = CarVisual.new()
	preview.position = CENTER
	root.add_child(preview)

	UI.label(root, "GARAGEM", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	coins_label = UI.label(root, "", Vector2(330, 24), 20, UI.GOLD, 136, HORIZONTAL_ALIGNMENT_RIGHT)
	name_label = UI.label(root, "", Vector2(0, 346), 32, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	status_label = UI.label(root, "", Vector2(0, 388), 18, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	desc_label = UI.label(root, "", Vector2(0, 416), 15, Color(0.8, 0.85, 0.95), 480, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(4):
		UI.label(root, ["AGILIDADE", "DEFESA", "MOEDAS", "PONTOS"][i], Vector2(40, 476 + i * 26), 14, Color(0.8, 0.85, 0.95))
	km_label = UI.label(root, "", Vector2(0, 584), 14, Color(0.7, 0.9, 1.0), 480, HORIZONTAL_ALIGNMENT_CENTER)
	msg_label = UI.label(root, "", Vector2(0, 606), 16, Color(1, 0.4, 0.4), 480, HORIZONTAL_ALIGNMENT_CENTER)

	var back := UI.button(root, "VOLTAR", Rect2(12, 16, 100, 38), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"), 16)
	UI.button(root, "<", Rect2(14, CENTER.y - 32, 52, 64), func(): _change(-1), 30)
	UI.button(root, ">", Rect2(414, CENTER.y - 32, 52, 64), func(): _change(1), 30)
	paint_btn = UI.button(root, "PINTAR", Rect2(362, 282, 104, 40), _on_paint, 16)
	paint_btn.add_theme_color_override("font_color", UI.GOLD)
	shop_btn = UI.button(root, "OFICINA", Rect2(14, 282, 104, 40), func(): UI.go(get_tree(), "res://scenes/Upgrades.tscn"), 16)
	shop_btn.add_theme_color_override("font_color", UI.ACCENT)
	action_btn = UI.button(root, "", Rect2(24, 640, 210, 54), _on_action, 18)
	var race := UI.button(root, "CORRER", Rect2(246, 640, 210, 54), _on_race, 22)
	race.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
	for b in [back, action_btn, race]:
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)
	back.focus_neighbor_bottom = back.get_path_to(shop_btn)
	shop_btn.focus_neighbor_top = shop_btn.get_path_to(back)
	shop_btn.focus_neighbor_left = shop_btn.get_path_to(shop_btn)
	shop_btn.focus_neighbor_right = shop_btn.get_path_to(shop_btn)
	paint_btn.focus_neighbor_top = paint_btn.get_path_to(shop_btn)
	paint_btn.focus_neighbor_bottom = paint_btn.get_path_to(action_btn)
	action_btn.focus_neighbor_top = action_btn.get_path_to(paint_btn)
	action_btn.focus_neighbor_bottom = action_btn.get_path_to(race)
	race.focus_neighbor_top = race.get_path_to(action_btn)
	race.focus_neighbor_bottom = race.get_path_to(back)
	paint_btn.focus_neighbor_left = paint_btn.get_path_to(paint_btn)
	paint_btn.focus_neighbor_right = paint_btn.get_path_to(paint_btn)
	back_btn = back
	race.grab_focus()

func _refresh() -> void:
	var car := _car()
	var owned := SaveManager.is_owned(car["id"])
	var selected: bool = SaveManager.data["selected"] == car["id"]
	Paints.apply(preview, car)
	preview.dim = 0.0 if owned else 0.55
	# sem o PINTAR (carro bloqueado), as setas pulam direto entre OFICINA e o botão de ação
	paint_btn.visible = owned
	var mid: Button = paint_btn if owned else action_btn
	shop_btn.focus_neighbor_bottom = shop_btn.get_path_to(mid)
	action_btn.focus_neighbor_top = action_btn.get_path_to(paint_btn if owned else shop_btn)
	name_label.text = String(car["name"]).to_upper()
	desc_label.text = car["desc"]
	coins_label.text = str(SaveManager.coins())
	km_label.text = "%.2f km rodados com este carro" % SaveManager.car_km(car["id"])
	msg_label.text = ""
	if selected:
		status_label.text = "EM USO"
		status_label.add_theme_color_override("font_color", UI.ACCENT)
		action_btn.text = "SELECIONADO"
	elif owned:
		status_label.text = "NA GARAGEM"
		status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		action_btn.text = "SELECIONAR"
	else:
		status_label.text = "BLOQUEADO  •  %d moedas" % car["price"]
		status_label.add_theme_color_override("font_color", UI.GOLD)
		action_btn.text = "COMPRAR  %d" % car["price"]

func _on_action() -> void:
	var car := _car()
	if SaveManager.is_owned(car["id"]):
		_select(car)
		return
	if SaveManager.buy(car["id"], car["price"]):
		_select(car)
		AudioManager.play("ui_buy", 0.0, 0.0)
		FX.burst(root, CENTER, UI.GOLD, 60, 360.0, 0.9, 5.0)
		FX.burst(root, CENTER, car["accent"], 30, 240.0, 0.7, 4.0)
		FX.float_text(root, CENTER + Vector2(0, -90), "COMPRADO!", UI.GOLD, 30)
	else:
		_refresh()
		AudioManager.play("ui_error", 0.0, 0.0)
		msg_label.text = "Faltam %d moedas" % (int(car["price"]) - SaveManager.coins())
		var tw := create_tween()
		for i in range(4):
			tw.tween_property(msg_label, "position:x", 8.0 if i % 2 == 0 else -8.0, 0.05)
		tw.tween_property(msg_label, "position:x", 0.0, 0.05)

func _select(car: Dictionary) -> void:
	SaveManager.data["selected"] = car["id"]
	SaveManager.save()
	_refresh()

func _on_paint() -> void:
	GameManager.paint_car = _car()["id"]
	UI.go(get_tree(), "res://scenes/Paint.tscn")

func _on_race() -> void:
	var car := _car()
	if SaveManager.is_owned(car["id"]):
		_select(car)
	UI.go(get_tree(), "res://scenes/Game.tscn")

# ---------- desenho ----------

func _stats(car: Dictionary) -> Array:
	return [
		clamp((float(car["lane_speed"]) - 7.0) / 12.0, 0.08, 1.0),
		clamp(float(car["start_shield"]) / 8.0 + float(car["lives"]) * 0.5, 0.08, 1.0),
		clamp((float(car["coin_mult"]) - 1.0) * 0.6 + float(car["magnet"]) / 150.0 * 0.4, 0.08, 1.0),
		clamp((float(car["score_mult"]) - 1.0) * 2.0, 0.08, 1.0),
	]

func _draw_screen(ci: Control) -> void:
	var car := _car()
	var col: Color = car["accent"] if car["model"] == "legend" else car["color"]
	var owned := SaveManager.is_owned(car["id"])
	UI.draw_coin(ci, Vector2(466 - UI.font().get_string_size(coins_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x - 16, 38), 10)

	# plataforma giratória
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	ci.draw_circle(CENTER, 108, Color(col.r, col.g, col.b, 0.08 + 0.05 * pulse))
	ci.draw_circle(CENTER, 92, Color(0.08, 0.09, 0.13, 0.95))
	ci.draw_arc(CENTER, 92, 0, TAU, 64, Color(col.r, col.g, col.b, 0.8), 3.0, true)
	for i in range(12):
		var a := -_t * 0.5 + i * TAU / 12.0
		ci.draw_arc(CENTER, 82, a, a + 0.25, 6, Color(1, 1, 1, 0.18), 3.0, true)

	# cadeado
	if not owned:
		var p := CENTER + Vector2(62, -62)
		ci.draw_circle(p, 22, Color(0, 0, 0, 0.7))
		ci.draw_arc(p + Vector2(0, -4), 8, PI, TAU, 12, UI.GOLD, 3.0, true)
		ci.draw_rect(Rect2(p + Vector2(-10, -4), Vector2(20, 15)), UI.GOLD)
		ci.draw_circle(p + Vector2(0, 3), 2.5, Color(0.2, 0.15, 0.0))

	# bolinhas de posição
	var n := GameManager.cars.size()
	for i in range(n):
		var x := 240.0 - (n - 1) * 9.0 + i * 18.0
		ci.draw_circle(Vector2(x, 336), 5 if i == index else 3, UI.ACCENT if i == index else Color(1, 1, 1, 0.35))

	# barras de atributos
	var st := _stats(car)
	for i in range(4):
		UI.draw_bar(ci, Rect2(150, 481 + i * 26, 290, 11), st[i], col.lerp(Color.WHITE, 0.2))
