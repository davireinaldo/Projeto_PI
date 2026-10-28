extends RefCounted

# Pinturas e rastros (tela Pintura, aberta pela Garagem).
# Cada cor/rastro é comprado uma vez e serve para qualquer carro; o que cada
# carro está usando fica em SaveManager.data["paint"] e ["trail"] (por id do
# carro). Os que têm "rank" não se compram: liberam ao chegar na patente.
#
# Efeitos ("fx") das pinturas, animados em CarVisual:
#   chrome  -> brilho que passa de vez em quando
#   neon    -> pulsa clareando
#   rainbow -> troca de cor sem parar

const PAINTS := [
	{"id": "original", "name": "Original", "price": 0},
	{"id": "branco", "name": "Branco", "price": 200, "color": Color(0.92, 0.93, 0.96)},
	{"id": "preto", "name": "Preto", "price": 200, "color": Color(0.13, 0.13, 0.16)},
	{"id": "vermelho", "name": "Vermelho", "price": 250, "color": Color(0.9, 0.12, 0.15)},
	{"id": "azul", "name": "Azul", "price": 250, "color": Color(0.15, 0.42, 1.0)},
	{"id": "verde", "name": "Verde", "price": 250, "color": Color(0.2, 0.75, 0.32)},
	{"id": "amarelo", "name": "Amarelo", "price": 300, "color": Color(1.0, 0.83, 0.12)},
	{"id": "laranja", "name": "Laranja", "price": 300, "color": Color(1.0, 0.5, 0.1)},
	{"id": "rosa", "name": "Rosa", "price": 350, "color": Color(1.0, 0.42, 0.72)},
	{"id": "roxo", "name": "Roxo", "price": 350, "color": Color(0.56, 0.26, 0.92)},
	{"id": "cromado", "name": "Cromado", "price": 1200, "color": Color(0.74, 0.77, 0.83), "fx": "chrome"},
	{"id": "neon", "name": "Neon", "price": 2000, "color": Color(0.1, 0.95, 0.85), "fx": "neon"},
	{"id": "arco_iris", "name": "Arco-íris", "price": 4000, "color": Color(1, 0.3, 0.3), "fx": "rainbow"},
	{"id": "dourado", "name": "Dourado", "price": 0, "rank": 2, "color": Color(1.0, 0.76, 0.18), "fx": "chrome"},
	{"id": "diamante", "name": "Diamante", "price": 0, "rank": 4, "color": Color(0.55, 0.8, 1.0), "fx": "neon"},
]

# outer/inner: cores da chama do nitro e das faixas de luz atrás do carro.
# O "original" é o rastro de sempre (só a chama laranja do nitro).
const TRAILS := [
	{"id": "original", "name": "Fogo", "price": 0, "outer": Color(1, 0.4, 0.05), "inner": Color(1, 0.9, 0.4)},
	{"id": "azul", "name": "Fogo Azul", "price": 600, "outer": Color(0.2, 0.5, 1.0), "inner": Color(0.75, 0.95, 1.0)},
	{"id": "toxico", "name": "Tóxico", "price": 600, "outer": Color(0.35, 1.0, 0.2), "inner": Color(0.9, 1.0, 0.6)},
	{"id": "plasma", "name": "Plasma", "price": 900, "outer": Color(0.7, 0.2, 1.0), "inner": Color(1.0, 0.75, 1.0)},
	{"id": "chiclete", "name": "Chiclete", "price": 900, "outer": Color(1.0, 0.3, 0.62), "inner": Color(1.0, 0.86, 0.92)},
	{"id": "gelo", "name": "Gelo", "price": 1500, "outer": Color(0.6, 0.95, 1.0), "inner": Color(1, 1, 1), "sparks": true},
	{"id": "arco_iris", "name": "Arco-íris", "price": 3000, "outer": Color(1, 0.3, 0.3), "inner": Color(1, 1, 1), "fx": "rainbow"},
	{"id": "ouro", "name": "Ouro", "price": 0, "rank": 3, "outer": Color(1.0, 0.72, 0.1), "inner": Color(1, 1, 0.7), "sparks": true},
]

static func list(kind: String) -> Array:
	return PAINTS if kind == "paint" else TRAILS

static func def(kind: String, id: String) -> Dictionary:
	for d in list(kind):
		if d["id"] == id:
			return d
	return list(kind)[0]

# o que o carro está usando agora
static func current(kind: String, car_id: String) -> Dictionary:
	return def(kind, String(SaveManager.data[kind].get(car_id, "original")))

static func is_owned(kind: String, d: Dictionary) -> bool:
	if d.has("rank"):
		return GameManager.rank_index(SaveManager.total_km()) >= int(d["rank"])
	return int(d["price"]) == 0 or d["id"] in SaveManager.data[kind + "s_owned"]

static func equip(kind: String, car_id: String, id: String) -> void:
	SaveManager.data[kind][car_id] = id
	SaveManager.save()

# Compra e já coloca no carro. Devolve false se faltar moeda.
static func buy(kind: String, car_id: String, d: Dictionary) -> bool:
	var price := int(d["price"])
	if SaveManager.coins() < price:
		return false
	SaveManager.data["coins"] = SaveManager.coins() - price
	SaveManager.data[kind + "s_owned"].append(d["id"])
	equip(kind, car_id, d["id"])
	return true

# Desenha o carro com a pintura que ele está usando.
static func apply(visual: Node2D, car: Dictionary, paint: Dictionary = {}) -> void:
	visual.sprite = String(car.get("sprite", ""))
	visual.setup(car["model"], car["color"], car["accent"])
	visual.set_paint(paint if not paint.is_empty() else current("paint", car["id"]))

# ---------- desenho do rastro ----------
# offs: deslocamento x do carro nos últimos quadros (o primeiro é agora).
# Tudo no espaço do carro (frente para cima, traseira em y ~ 30).

static func colors(d: Dictionary, t: float, i: int = 0) -> Array:
	if d.get("fx", "") == "rainbow":
		var h := fmod(t * 0.5 + i * 0.07, 1.0)
		return [Color.from_hsv(h, 0.85, 1.0), Color.from_hsv(fmod(h + 0.12, 1.0), 0.3, 1.0)]
	return [d["outer"], d["inner"]]

# Faixas de luz saindo das rodas de trás (só nos rastros comprados).
static func draw_ribbon(ci: CanvasItem, d: Dictionary, offs: Array, t: float, boost: float = 0.0) -> void:
	if d["id"] == "original" or offs.size() < 2:
		return
	for sx in [-11.0, 11.0]:
		for i in range(1, offs.size()):
			var a := 1.0 - float(i) / offs.size()
			var c: Color = colors(d, t, i)[0]
			var p0 := Vector2(offs[i - 1] + sx, 26 + (i - 1) * 14)
			var p1 := Vector2(offs[i] + sx, 26 + i * 14)
			ci.draw_line(p0, p1, Color(c.r, c.g, c.b, (0.4 + 0.3 * boost) * a), 5.0 + 4.0 * boost)
			ci.draw_line(p0, p1, Color(1, 1, 1, 0.45 * a), 1.5)
	if d.get("sparks", false):
		var c: Color = colors(d, t)[1]
		for k in range(8):
			var y := fmod(t * 260.0 + k * 19.0, 120.0)
			var x := sin(k * 12.9 + t * 3.0) * 13.0
			ci.draw_circle(Vector2(x, 32 + y), 2.2 * (1.0 - y / 120.0), Color(c.r, c.g, c.b, 0.9))

# Chamas do escapamento + borrão atrás do carro durante o nitro (k = força 0..1).
static func draw_nitro(ci: CanvasItem, d: Dictionary, offs: Array, t: float, k: float) -> void:
	if k <= 0.02:
		return
	var cols := colors(d, t)
	var outer: Color = cols[0]
	var inner: Color = cols[1]
	for i in range(1, offs.size()):
		var a: float = 0.3 * k * (1.0 - float(i) / offs.size())
		ci.draw_rect(Rect2(Vector2(offs[i] - 13, 10 + i * 12), Vector2(26, 30)), Color(outer.r, outer.g, outer.b, a))
	for sx in [-8.0, 8.0]:
		var len := (26.0 + randf() * 18.0) * k
		var base := Vector2(sx, 30)
		ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-6, 0), base + Vector2(6, 0), base + Vector2(0, len)]),
			Color(outer.r, outer.g, outer.b, 0.85))
		ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-3.5, 0), base + Vector2(3.5, 0), base + Vector2(0, len * 0.6)]),
			Color(inner.r, inner.g, inner.b, 0.95))
		ci.draw_circle(base, 7, Color(outer.r, outer.g, outer.b, 0.4))
