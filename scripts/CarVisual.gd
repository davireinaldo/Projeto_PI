extends Node2D

# Desenho (visto de cima, frente para cima) de todos os veículos: carros
# jogáveis, tráfego, caminhões e ônibus. Cada modelo é um conjunto de SVGs em
# assets/images/cars/ (gerados por tools/gerar_carros.py), no estilo do carro
# original assets/images/player_car.png, desenhados em camadas:
#   base   -> rodas e peças escuras
#   body   -> lataria, pintada com body_color
#   accent -> faixas/asas/baú, pintados com accent
#   detail -> sombras, reflexos, vidros, luzes e contornos
# O Equilibrado ("texture") usa a imagem original; pintado, vira o "gt".
# Por cima das camadas o código anima: banda dos pneus girando (wheel_speed),
# carroceria inclinando na curva (lean, a suspensão) e clarão de batida (hit).

const TEX := preload("res://assets/images/player_car.png")
const CarData := preload("res://scripts/CarData.gd")
const CARS_DIR := "res://assets/images/cars/"
const SVG_SCALE := 4.0 # os SVGs saem 4x maiores que o carro no jogo
const BLINK := Color(1, 0.65, 0.05)
const TREAD := Color(0.24, 0.25, 0.28)
const TREAD_GAP := 2.4

static var _textures: Dictionary = {} # "modelo_camada" -> Texture2D (null se não existir)

var model: String = "sedan"
var body_color: Color = Color(0.2, 0.6, 1.0)
var accent: Color = Color.WHITE
var blink: int = 0 # -1 seta esquerda, 1 seta direita
var dim: float = 0.0 # escurece o desenho (carro bloqueado na garagem)
var paint_fx: String = "" # efeito da pintura (ver Paints.gd)
var painted: bool = false
var _paint_base: Color = Color.WHITE
var wheel_speed: float = 0.0 # velocidade na pista (px/s): faz a banda dos pneus girar
var lean: float = 0.0 # -1..1: carroceria pende para o lado da curva
var _flash: float = 0.0 # clarão branco da batida
var _roll: float = 0.0
var _t: float = 0.0

static func model_size(m: String) -> Vector2:
	match m:
		"truck":
			return Vector2(42, 124)
		"bus":
			return Vector2(42, 136)
		"pickup", "van":
			return Vector2(38, 70)
		"f1":
			return Vector2(36, 70)
	return Vector2(36, 64)

func setup(m: String, c: Color, a: Color = Color.WHITE) -> void:
	model = m
	body_color = c
	accent = a
	queue_redraw()

func set_color(c: Color) -> void:
	body_color = c
	queue_redraw()

# Pintura da garagem (um item de Paints.PAINTS). "original" mantém a cor do carro.
func set_paint(p: Dictionary) -> void:
	painted = p.get("id", "original") != "original"
	paint_fx = String(p.get("fx", "")) if painted else ""
	if painted:
		_paint_base = p["color"]
		body_color = _paint_base
	queue_redraw()

# rodas de trás (no espaço do carro): de onde sai a fumaça e a marca de pneu
func rear_wheels() -> Array:
	var m := "gt" if model == "texture" else model
	return CarData.MODELS[m]["rear"] if CarData.MODELS.has(m) else []

# clarão rápido na lataria quando bate
func hit() -> void:
	_flash = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	if blink != 0 or model == "legend" or paint_fx != "" or wheel_speed > 0.0 or _flash > 0.0 or lean != 0.0:
		_t += delta
		_roll = fmod(_roll + wheel_speed * delta * 0.05, TREAD_GAP)
		_flash = max(_flash - delta * 5.0, 0.0)
		match paint_fx:
			"rainbow": body_color = Color.from_hsv(fmod(_t * 0.2, 1.0), 0.75, 1.0)
			"neon": body_color = _paint_base.lightened(0.35 * (0.5 + 0.5 * sin(_t * 5.0)))
			"chrome": body_color = _paint_base.lightened(0.45 * pow(0.5 + 0.5 * sin(_t * 1.8), 8.0))
		queue_redraw()

# ---------- desenho ----------

func _c(c: Color) -> Color:
	return c.darkened(dim) if dim > 0.0 else c

static func _layer(m: String, layer: String) -> Texture2D:
	var key := m + "_" + layer
	if not _textures.has(key):
		var path := CARS_DIR + key + ".svg"
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _draw() -> void:
	if model == "texture" and not painted:
		_draw_texture()
		return
	var m := "gt" if model == "texture" else model
	if not CarData.MODELS.has(m):
		m = "sedan"
	var data: Dictionary = CarData.MODELS[m]
	var body_tex := _layer(m, "body")
	var size: Vector2 = body_tex.get_size() / SVG_SCALE
	var rect := Rect2(-size * 0.5, size)
	var sway := Vector2(lean * 1.2, 0) # a lataria anda um pouco em cima das rodas
	_shadow(m, rect, sway)
	draw_texture_rect(_layer(m, "base"), rect, false, _c(Color.WHITE))
	_treads(data["wheels"])
	var top := Rect2(rect.position + sway, rect.size)
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	if m == "legend":
		draw_texture_rect(_layer(m, "accent"), top.grow(2.5), false, Color(accent.r, accent.g, accent.b, 0.35 * pulse))
	var tint := {"body": body_color, "accent": accent, "detail": Color.WHITE}
	for layer in ["body", "accent", "detail"]:
		var tex := _layer(m, layer)
		if tex:
			draw_texture_rect(tex, top, false, _c(tint[layer]))
	if _flash > 0.0:
		draw_texture_rect(body_tex, top, false, Color(1, 1, 1, 0.75 * _flash))
	if m == "legend":
		for x in [-7, 7]:
			draw_circle(Vector2(x, 32) + sway, 1.6 * pulse + 1.0, Color(accent.r, accent.g, accent.b, 0.4))
	var b: Vector3 = data["blink"]
	_blinkers(b.x, b.y, b.z)

# Sombra de contato: uma larga e clara deslocada pela luz, outra justa e
# mais escura bem embaixo do carro (no caminhão o baú também faz sombra).
func _shadow(m: String, rect: Rect2, sway: Vector2) -> void:
	var texs: Array = [_layer(m, "body")]
	if m == "truck":
		texs.append(_layer(m, "accent"))
	for tex in texs:
		draw_texture_rect(tex, Rect2(rect.position + Vector2(3, 6) + sway, rect.size).grow(2.0), false, Color(0, 0, 0, 0.14))
		draw_texture_rect(tex, Rect2(rect.position + Vector2(2, 4) + sway, rect.size), false, Color(0, 0, 0, 0.2))
		draw_texture_rect(tex, Rect2(rect.position + Vector2(0.5, 1.5), rect.size).grow(0.6), false, Color(0, 0, 0, 0.28))

# banda de rodagem: frisos descendo conforme o carro anda
func _treads(wheels: Array) -> void:
	var c := _c(TREAD)
	for r: Rect2 in wheels:
		var y := r.position.y + 1.0 + _roll
		while y < r.end.y - 0.8:
			draw_line(Vector2(r.position.x + 0.8, y), Vector2(r.end.x - 0.8, y), c, 0.8)
			y += TREAD_GAP

func _draw_texture() -> void:
	var tex_size: Vector2 = TEX.get_size()
	var s: float = 38.0 / tex_size.x
	var size: Vector2 = tex_size * s
	var rect := Rect2(-size * 0.5 + Vector2(lean * 1.2, 0), size)
	draw_texture_rect(TEX, Rect2(rect.position + Vector2(3, 6), rect.size).grow(1.0), false, Color(0, 0, 0, 0.14))
	draw_texture_rect(TEX, Rect2(rect.position + Vector2(2, 4), rect.size).grow(-1.0), false, Color(0, 0, 0, 0.2))
	draw_texture_rect(TEX, Rect2(-size * 0.5 + Vector2(0.5, 1.5), size), false, Color(0, 0, 0, 0.25))
	# modulate acima de 1 clareia a imagem: é o clarão da batida
	var k := 1.0 + _flash * 1.6
	draw_texture_rect(TEX, rect, false, Color(k, k, k).darkened(dim))
	_blinkers(-31, 31, 17)

func _blinkers(front_y: float, rear_y: float, half_w: float) -> void:
	if blink == 0 or fmod(_t, 0.5) > 0.28:
		return
	var x := half_w * blink
	for y in [front_y + 3, rear_y - 3]:
		draw_circle(Vector2(x, y), 7, Color(1, 0.6, 0.0, 0.35))
		draw_circle(Vector2(x, y), 3.5, BLINK)
