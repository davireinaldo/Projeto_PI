extends Node2D

# Dia e noite: escurece a tela conforme a hora (World.sky) e "acende"
# faróis, lanternas, postes e poderes com um shader. Fica por cima da pista
# e dos carros (z 15); moedas, poderes, partículas e o HUD ficam acima dela.
# Duas camadas: uma escurece (com buracos onde há luz) e outra soma o
# brilho colorido das luzes (o facho amarelo do farol, o vermelho da lanterna).

const MAX_LIGHTS := 48
const MARGIN := 40.0 # sobra nas bordas para o tremor da câmera

const SHAPE := """
uniform vec2 origin;
uniform int count = 0;
uniform vec4 la[48]; // x, y, tamanho, tipo (0 = redonda, 1 = farol para cima)
uniform vec4 lc[48]; // cor rgb, intensidade
varying vec2 wpos;

void vertex() {
	wpos = VERTEX + origin;
}

float shape(vec4 l, vec2 p) {
	vec2 d = p - l.xy;
	if (l.w < 0.5) {
		return 1.0 - smoothstep(0.0, l.z, length(d));
	}
	float core = 1.0 - smoothstep(0.0, 24.0, length(d));
	float along = -d.y;
	if (along <= 0.0) {
		return core;
	}
	float w = 12.0 + along * 0.42;
	float beam = (1.0 - smoothstep(l.z * 0.3, l.z, along)) * (1.0 - smoothstep(w * 0.5, w, abs(d.x)));
	return max(beam, core);
}
"""

const DARK_SHADER := "shader_type canvas_item;\nuniform vec4 tint;\n" + SHAPE + """
void fragment() {
	float L = 0.0;
	for (int i = 0; i < count; i++) {
		L += lc[i].a * shape(la[i], wpos);
	}
	COLOR = vec4(tint.rgb, tint.a * (1.0 - clamp(L, 0.0, 1.0)));
}
"""

const GLOW_SHADER := "shader_type canvas_item;\nrender_mode blend_add;\nuniform float strength = 0.0;\n" + SHAPE + """
void fragment() {
	vec3 c = vec3(0.0);
	for (int i = 0; i < count; i++) {
		c += lc[i].rgb * lc[i].a * shape(la[i], wpos);
	}
	COLOR = vec4(c * strength, 1.0);
}
"""

const NIGHT := Color(0.02, 0.03, 0.14)
const DUSK := Color(0.55, 0.22, 0.08)
const HEADLIGHT := Color(1.0, 0.9, 0.65)
const TAILLIGHT := Color(1.0, 0.12, 0.1)

var world: Node2D # de onde vem a hora do dia e os postes
var hero: Node2D # carro com o farol grande (jogador ou o carro do menu)
var hero2: Node2D # o segundo jogador do versus
var _dark: ColorRect
var _glow: ColorRect
var _la := PackedVector4Array()
var _lc := PackedVector4Array()

func _ready() -> void:
	z_index = 15
	_dark = _layer(DARK_SHADER)
	_glow = _layer(GLOW_SHADER)
	_la.resize(MAX_LIGHTS)
	_lc.resize(MAX_LIGHTS)

func _layer(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.position = Vector2(-MARGIN, -MARGIN)
	r.size = Vector2(480, 720) + Vector2.ONE * MARGIN * 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("origin", r.position)
	r.material = m
	add_child(r)
	return r

func _process(_delta: float) -> void:
	var sky: Vector2 = world.sky() if world else Vector2.ZERO
	var night := sky.x
	var dusk := sky.y
	visible = night > 0.01 or dusk > 0.01
	if not visible:
		return
	var tint := NIGHT.lerp(DUSK, clamp(dusk / (dusk + night * 2.0 + 0.001), 0.0, 1.0))
	tint.a = max(0.64 * night, 0.2 * dusk)

	var n := _gather()
	for m in [_dark.material, _glow.material]:
		m.set_shader_parameter("count", n)
		m.set_shader_parameter("la", _la)
		m.set_shader_parameter("lc", _lc)
	_dark.material.set_shader_parameter("tint", tint)
	_glow.material.set_shader_parameter("strength", 0.32 * night)

# Junta as luzes visíveis (mais importantes primeiro). Devolve quantas.
var _n: int = 0

func _gather() -> int:
	_n = 0
	for h in [hero, hero2]:
		if is_instance_valid(h) and h.visible:
			var hp: Vector2 = h.global_position
			_add(hp + Vector2(0, -28), 330.0, 1, HEADLIGHT, 1.15)
			_add(hp + Vector2(0, 34), 30.0, 0, TAILLIGHT, 0.6)
	for p in get_tree().get_nodes_in_group("powerups"):
		_add(p.global_position, 60.0, 0, p.color(), 0.7)
	for t in get_tree().get_nodes_in_group("traffic"):
		if t.is_in_group("obstacles"):
			if t.kind == "barreira":
				_add(t.global_position, 80.0, 0, t.color(), 0.8 * t.barrier_glow())
			continue
		var half: float = t.length * 0.5
		_add(t.global_position + Vector2(0, -half + 4), 190.0, 1, HEADLIGHT, 0.8)
		_add(t.global_position + Vector2(0, half), 32.0, 0, TAILLIGHT, 0.7)
	if world:
		for l in world.light_sources():
			_add(l[0], l[1], 0, l[2], l[3])
	return _n

func _add(p: Vector2, size: float, type: int, c: Color, k: float) -> void:
	if _n < MAX_LIGHTS and p.y > -300.0 and p.y < 1000.0:
		_la[_n] = Vector4(p.x, p.y, size, type)
		_lc[_n] = Vector4(c.r, c.g, c.b, k)
		_n += 1
