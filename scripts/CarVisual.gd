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
# Os carros jogáveis com "sprite" (GameManager.cars) usam um desenho próprio
# em assets/images/cars/sprites/ (tools/importar_sprites.py): <id>.png e a
# máscara da lataria <id>_paint.png, pintada por cima quando há pintura, e a
# sombra suave <id>_shadow.png. Os três têm SPRITE_PAD px de margem em volta.

const TEX := preload("res://assets/images/player_car.png")
const CARS_DIR := "res://assets/images/cars/"
const SPRITES_DIR := "res://assets/images/cars/sprites/"
const SPRITE_PAD := 16.0 # margem dos sprites (PAD em tools/importar_sprites.py)
const SVG_SCALE := 4.0 # os SVGs saem 4x maiores que o carro no jogo
const LAYERS := ["base", "body", "accent", "detail"]
const BLINK := Color(1, 0.65, 0.05)
# piscas de cada modelo: y da frente, y de trás e meia largura
const BLINK_POS := {
	"gt": Vector3(-31, 31, 17), "sedan": Vector3(-30, 30, 17), "taxi": Vector3(-30, 30, 17),
	"sport": Vector3(-30, 30, 17), "armored": Vector3(-28, 30, 18), "pickup": Vector3(-32, 33, 18),
	"muscle": Vector3(-31, 31, 17), "coupe": Vector3(-30, 30, 17), "f1": Vector3(-30, 30, 14),
	"legend": Vector3(-26, 30, 17), "roadster": Vector3(-28, 30, 17), "van": Vector3(-33, 33, 18), "truck": Vector3(-60, 60, 21),
	"bus": Vector3(-66, 66, 21),
}

static var _textures: Dictionary = {} # "modelo_camada" -> Texture2D (null se não existir)

var model: String = "sedan"
var sprite: String = "" # id do desenho em SPRITES_DIR ("" = desenho em camadas)
var body_color: Color = Color(0.2, 0.6, 1.0)
var accent: Color = Color.WHITE
var blink: int = 0 # -1 seta esquerda, 1 seta direita
var dim: float = 0.0 # escurece o desenho (carro bloqueado na garagem)
var paint_fx: String = "" # efeito da pintura (ver Paints.gd)
var painted: bool = false
var _paint_base: Color = Color.WHITE
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

func _process(delta: float) -> void:
	if blink != 0 or model == "legend" or paint_fx != "":
		_t += delta
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
	if sprite != "" and _sprite(sprite, ""):
		_draw_sprite()
		return
	if model == "texture" and not painted:
		_draw_texture()
		return
	var m := "gt" if model == "texture" else model
	if not BLINK_POS.has(m):
		m = "sedan"
	var size: Vector2 = _layer(m, "body").get_size() / SVG_SCALE
	var rect := Rect2(-size * 0.5, size)
	# sombra no chão (no caminhão o baú também faz sombra)
	var shadow := Rect2(rect.position + Vector2(3, 6), rect.size)
	draw_texture_rect(_layer(m, "body"), shadow, false, Color(0, 0, 0, 0.3))
	if m == "truck":
		draw_texture_rect(_layer(m, "accent"), shadow, false, Color(0, 0, 0, 0.3))
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	if m == "legend":
		draw_texture_rect(_layer(m, "accent"), rect.grow(2.5), false, Color(accent.r, accent.g, accent.b, 0.35 * pulse))
	var tint := {"base": Color.WHITE, "body": body_color, "accent": accent, "detail": Color.WHITE}
	for layer in LAYERS:
		var tex := _layer(m, layer)
		if tex:
			draw_texture_rect(tex, rect, false, _c(tint[layer]))
	if m == "legend":
		for x in [-7, 7]:
			draw_circle(Vector2(x, 32), 2.5 * pulse + 1.5, Color(accent.r, accent.g, accent.b, 0.45))
	var b: Vector3 = BLINK_POS[m]
	_blinkers(b.x, b.y, b.z)

static func _sprite(id: String, suffix: String) -> Texture2D:
	var key := "sprite_" + id + suffix
	if not _textures.has(key):
		var path := SPRITES_DIR + id + suffix + ".png"
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]

# Desenho do sprite com a mesma altura do modelo em camadas do carro.
func _draw_sprite() -> void:
	var tex := _sprite(sprite, "")
	var h: float = model_size(model).y
	var k: float = h / (tex.get_height() - SPRITE_PAD * 2.0) # px do jogo por px do sprite
	var full := Vector2(tex.get_width(), tex.get_height()) * k
	var size := full - Vector2.ONE * SPRITE_PAD * 2.0 * k # só o carro, sem a margem
	var rect := Rect2(-full * 0.5, full)
	var shadow := _sprite(sprite, "_shadow")
	if shadow:
		draw_texture_rect(shadow, Rect2(rect.position + Vector2(3, 6), rect.size), false, Color(1, 1, 1, 0.75))
	else:
		draw_texture_rect(tex, Rect2(rect.position + Vector2(3, 6), rect.size), false, Color(0, 0, 0, 0.3))
	draw_texture_rect(tex, rect, false, _c(Color.WHITE))
	var mask := _sprite(sprite, "_paint")
	if painted and mask:
		draw_texture_rect(mask, rect, false, _c(body_color))
	if model == "legend":
		var pulse := 0.6 + 0.4 * sin(_t * 4.0)
		for x in [-7, 7]:
			draw_circle(Vector2(x, size.y * 0.5 - 2), 2.5 * pulse + 1.5, Color(accent.r, accent.g, accent.b, 0.45))
	_blinkers(-size.y * 0.5 + 2, size.y * 0.5 - 2, size.x * 0.5 - 3)

func _draw_texture() -> void:
	var tex_size: Vector2 = TEX.get_size()
	var s: float = 38.0 / tex_size.x
	var size: Vector2 = tex_size * s
	draw_rect(Rect2(-size * 0.5 + Vector2(3, 6), size).grow(-3), Color(0, 0, 0, 0.25))
	draw_texture_rect(TEX, Rect2(-size * 0.5, size), false, Color(1, 1, 1).darkened(dim))

func _blinkers(front_y: float, rear_y: float, half_w: float) -> void:
	if blink == 0 or fmod(_t, 0.5) > 0.28:
		return
	var x := half_w * blink
	for y in [front_y + 3, rear_y - 3]:
		draw_circle(Vector2(x, y), 7, Color(1, 0.6, 0.0, 0.35))
		draw_circle(Vector2(x, y), 3.5, BLINK)
