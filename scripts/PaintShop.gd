extends Node2D

# Pintura: escolher a cor e o rastro do carro aberto na Garagem
# (GameManager.paint_car). Tocar num quadradinho mostra no carro; se já for
# seu, já passa a usar. O botão de baixo compra o que está sendo mostrado.
# Lista de cores/rastros e preços: Paints.gd.

const World := preload("res://scripts/World.gd")
const CarVisual := preload("res://scripts/CarVisual.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")
const Paints := preload("res://scripts/Paints.gd")

const CAR_POS := Vector2(240, 150)
const CAR_SCALE := 1.8
const GRID_Y := 440.0
const CELL_H := 54.0
const GAP := 6.0

var car: Dictionary
var kind: String = "paint" # aba aberta: "paint" ou "trail"
var shown: Dictionary # item que aparece no carro agora
var root: Control
var grid: Control # quadradinhos da aba aberta (refeitos ao trocar de aba)
var cells: Array = [] # {"def", "btn": Button, "rect": Rect2}
var tabs: Array = []
var preview: Node2D
var back: Button
var coins_label: Label
var info_label: Label
var action_btn: Button
var _t: float = 0.0

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	GameManager.speed = 260.0
	var world := World.new()
	world.follow_game = false
	world.distance_m = GameManager.BIOME_LENGTH * 5 + 100.0
	add_child(world)
	AudioManager.play_music("menu")
	car = GameManager.car_by_id(GameManager.paint_car if GameManager.paint_car != "" else String(SaveManager.data["selected"]))
	GameManager.paint_car = car["id"]
	_build_ui()
	_show_tab("paint")

func _process(delta: float) -> void:
	_t += delta
	preview.position = CAR_POS + Vector2(_weave(_t), 0)
	if Input.is_action_just_pressed("ui_cancel"):
		_back()

func _back() -> void:
	UI.go(get_tree(), "res://scenes/Garage.tscn")

# o carro desfila trocando de lado devagar, para o rastro aparecer
func _weave(t: float) -> float:
	return sin(t * 1.3) * 34.0

# ---------- interface ----------

func _build_ui() -> void:
	root = UI.root(self)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	root.add_child(DrawHook.new(_draw_trail_preview))

	preview = CarVisual.new()
	preview.scale = Vector2.ONE * CAR_SCALE
	root.add_child(preview)

	UI.label(root, "PINTURA", Vector2(0, 18), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, String(car["name"]).to_upper(), Vector2(0, 58), 15, Color(0.8, 0.85, 0.95), 480, HORIZONTAL_ALIGNMENT_CENTER)
	coins_label = UI.label(root, "", Vector2(330, 24), 20, UI.GOLD, 136, HORIZONTAL_ALIGNMENT_RIGHT)
	back = UI.button(root, "VOLTAR", Rect2(12, 16, 100, 38), _back, 16)

	UI.panel(root, Rect2(16, 384, 448, 330))
	for i in range(2):
		var k: String = ["paint", "trail"][i]
		tabs.append(UI.button(root, ["COR", "RASTRO"][i], Rect2(34 + i * 210, 394, 202, 34), _show_tab.bind(k), 15))
	grid = Control.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(grid)
	info_label = UI.label(root, "", Vector2(0, 618), 15, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	action_btn = UI.button(root, "", Rect2(120, 652, 240, 50), _on_action, 17)
	root.add_child(DrawHook.new(_draw_cells))

func _show_tab(k: String) -> void:
	kind = k
	for c in grid.get_children():
		c.queue_free()
	cells.clear()
	var on := UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2)
	var off := UI.style(Color(0.06, 0.08, 0.13, 0.6), Color(0.25, 0.3, 0.4), 10, 1)
	for i in range(tabs.size()):
		tabs[i].add_theme_stylebox_override("normal", on if ["paint", "trail"][i] == k else off)

	# cores em 5 colunas, rastros em 4
	var items := Paints.list(k)
	var cols := 5 if k == "paint" else 4
	var w := (436.0 - GAP * (cols - 1)) / cols
	for i in range(items.size()):
		var d: Dictionary = items[i]
		var r := Rect2(22 + (i % cols) * (w + GAP), GRID_Y + (i / cols) * (CELL_H + GAP), w, CELL_H)
		var b := UI.button(grid, "", r, _pick.bind(d), 12)
		cells.append({"def": d, "btn": b, "rect": r})
		var l := UI.label(grid, "", Vector2(r.position.x, r.position.y + 34), 11, Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		cells[-1]["label"] = l
	_link_focus(cols)
	shown = Paints.current(k, car["id"])
	_refresh()
	for c in cells:
		if c["def"]["id"] == shown["id"]:
			c["btn"].grab_focus()

# setas navegam pela grade; de cima vai para as abas, de baixo para o botão
func _link_focus(cols: int) -> void:
	var tab: Button = tabs[0 if kind == "paint" else 1]
	for i in range(cells.size()):
		var b: Button = cells[i]["btn"]
		var up: Button = cells[i - cols]["btn"] if i >= cols else tab
		var down: Button = cells[i + cols]["btn"] if i + cols < cells.size() else action_btn
		b.focus_neighbor_top = b.get_path_to(up)
		b.focus_neighbor_bottom = b.get_path_to(down)
		b.focus_neighbor_left = b.get_path_to(cells[max(i - 1, 0)]["btn"])
		b.focus_neighbor_right = b.get_path_to(cells[min(i + 1, cells.size() - 1)]["btn"])
	for t in tabs:
		t.focus_neighbor_top = t.get_path_to(back)
		t.focus_neighbor_bottom = t.get_path_to(cells[0]["btn"])
	tabs[0].focus_neighbor_right = tabs[0].get_path_to(tabs[1])
	tabs[1].focus_neighbor_left = tabs[1].get_path_to(tabs[0])
	back.focus_neighbor_bottom = back.get_path_to(tab)
	action_btn.focus_neighbor_top = action_btn.get_path_to(cells[-1]["btn"])
	action_btn.focus_neighbor_bottom = action_btn.get_path_to(back)

func _pick(d: Dictionary) -> void:
	shown = d
	if Paints.is_owned(kind, d) and Paints.current(kind, car["id"])["id"] != d["id"]:
		Paints.equip(kind, car["id"], d["id"])
	_refresh()

func _refresh() -> void:
	coins_label.text = str(SaveManager.coins())
	Paints.apply(preview, car, shown if kind == "paint" else {})
	var using: String = Paints.current(kind, car["id"])["id"]
	var mark := UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 3)
	for c in cells:
		var d: Dictionary = c["def"]
		var b: Button = c["btn"]
		var l: Label = c["label"]
		if d["id"] == using:
			b.add_theme_stylebox_override("normal", mark)
		else:
			b.remove_theme_stylebox_override("normal")
		if Paints.is_owned(kind, d):
			l.text = d["name"]
			l.add_theme_color_override("font_color", Color.WHITE)
		elif d.has("rank"):
			l.text = GameManager.ranks[int(d["rank"])]["name"]
			l.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
		else:
			l.text = str(d["price"])
			l.add_theme_color_override("font_color", UI.GOLD)

	info_label.add_theme_color_override("font_color", Color.WHITE)
	action_btn.modulate = Color.WHITE
	action_btn.disabled = false
	if shown["id"] == using:
		info_label.text = "%s  •  em uso" % shown["name"]
		action_btn.text = "PRONTO"
	elif Paints.is_owned(kind, shown):
		info_label.text = shown["name"]
		action_btn.text = "USAR"
	elif shown.has("rank"):
		var rank: Dictionary = GameManager.ranks[int(shown["rank"])]
		info_label.text = "%s  •  libera na patente %s (%d km)" % [shown["name"], rank["name"], int(rank["km"])]
		action_btn.text = "BLOQUEADO"
		action_btn.disabled = true
	else:
		info_label.text = "%s  •  %d moedas" % [shown["name"], int(shown["price"])]
		action_btn.text = "COMPRAR  %d" % int(shown["price"])
		if SaveManager.coins() < int(shown["price"]):
			action_btn.modulate = Color(1, 1, 1, 0.55)

func _on_action() -> void:
	var using: String = Paints.current(kind, car["id"])["id"]
	if shown["id"] == using:
		_back()
		return
	if Paints.is_owned(kind, shown):
		Paints.equip(kind, car["id"], shown["id"])
		_refresh()
		return
	if Paints.buy(kind, car["id"], shown):
		AudioManager.play("ui_buy", 0.0, 0.0)
		var c: Color = shown["color"] if kind == "paint" else shown["outer"]
		FX.burst(root, preview.position, UI.GOLD, 50, 320.0, 0.9, 5.0)
		FX.burst(root, preview.position, c, 40, 240.0, 0.7, 4.0)
		FX.float_text(root, preview.position + Vector2(0, -80), "COMPRADO!", UI.GOLD, 28)
		_refresh()
		return
	AudioManager.play("ui_error", 0.0, 0.0)
	info_label.text = "Faltam %d moedas" % (int(shown["price"]) - SaveManager.coins())
	info_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(info_label, "position:x", 8.0 if i % 2 == 0 else -8.0, 0.05)
	tw.tween_property(info_label, "position:x", 0.0, 0.05)

# ---------- desenho ----------

# rastro atrás do carro (na aba RASTRO mostra o que está sendo escolhido,
# com a chama do nitro acesa de vez em quando)
func _draw_trail_preview(ci: Control) -> void:
	UI.draw_coin(ci, Vector2(466 - UI.font().get_string_size(coins_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x - 16, 38), 10)
	var d := shown if kind == "trail" else Paints.current("trail", car["id"])
	var x0 := _weave(_t)
	var offs: Array = []
	for i in range(8):
		offs.append((_weave(_t - i * 0.06) - x0) / CAR_SCALE)
	var k: float = clamp(sin(_t * 1.6) * 3.0, 0.0, 1.0) if kind == "trail" else 0.0
	ci.draw_set_transform(preview.position, 0.0, Vector2.ONE * CAR_SCALE)
	Paints.draw_ribbon(ci, d, offs, _t, k)
	Paints.draw_nitro(ci, d, offs, _t, k)
	ci.draw_set_transform(Vector2.ZERO)

# amostra de cor/rastro em cada quadradinho (e cadeado nos que não são seus)
func _draw_cells(ci: Control) -> void:
	for c in cells:
		var d: Dictionary = c["def"]
		var r: Rect2 = c["rect"]
		var p := r.position + Vector2(r.size.x * 0.5, 19)
		var owned := Paints.is_owned(kind, d)
		if kind == "paint":
			var col: Color = car["color"] if d["id"] == "original" else d["color"]
			match d.get("fx", ""):
				"rainbow": col = Color.from_hsv(fmod(_t * 0.25, 1.0), 0.75, 1.0)
				"neon": ci.draw_circle(p, 15 + 2 * sin(_t * 5.0), Color(col.r, col.g, col.b, 0.3))
			ci.draw_circle(p, 12, col)
			if d.get("fx", "") == "chrome":
				ci.draw_arc(p, 8, -2.4, -1.2, 8, Color(1, 1, 1, 0.8), 2.5, true)
			ci.draw_arc(p, 12, 0, TAU, 24, Color(0, 0, 0, 0.6), 1.5, true)
		else:
			for sx in [-6.0, 6.0]:
				for i in range(5):
					var col: Color = Paints.colors(d, _t, i)[0 if i % 2 == 0 else 1]
					ci.draw_line(p + Vector2(sx, -10 + i * 4), p + Vector2(sx, -6 + i * 4), col, 4.0)
		if not owned:
			var q := r.position + Vector2(r.size.x - 11, 10)
			ci.draw_arc(q + Vector2(0, -2), 3.5, PI, TAU, 8, Color(1, 1, 1, 0.8), 1.5, true)
			ci.draw_rect(Rect2(q + Vector2(-5, -2), Vector2(10, 7)), Color(1, 1, 1, 0.8))
