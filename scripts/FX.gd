extends RefCounted

# Efeitos rápidos criados por código: explosões de partículas e
# textos flutuantes ("+100", "ESCUDO!" ...).

static func burst(parent: Node, pos: Vector2, color: Color, amount: int = 24, speed: float = 220.0,
		life: float = 0.6, size: float = 4.0, gravity: float = 0.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, gravity)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.3
	p.damping_max = speed * 0.6
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	p.z_index = 20
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)

static func explosion(parent: Node, pos: Vector2, big: bool = false) -> void:
	var k := 1.6 if big else 1.0
	burst(parent, pos, Color(1, 0.85, 0.3), int(26 * k), 260.0 * k, 0.45, 5.0 * k)
	burst(parent, pos, Color(1, 0.4, 0.05), int(30 * k), 200.0 * k, 0.7, 6.0 * k, 120.0)
	burst(parent, pos, Color(0.2, 0.2, 0.22, 0.8), int(18 * k), 90.0 * k, 1.1, 9.0 * k, -60.0)

# fumacinha de pneu: poucas bolinhas cinza que descem com a pista e somem
static func smoke(parent: Node, pos: Vector2, amount: int = 6, road_speed: float = 300.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.85
	p.direction = Vector2(0, 1)
	p.spread = 35.0
	p.initial_velocity_min = road_speed * 0.25
	p.initial_velocity_max = road_speed * 0.45
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(0.82, 0.84, 0.88, 0.35))
	g.set_color(1, Color(0.82, 0.84, 0.88, 0.0))
	p.color_ramp = g
	p.z_index = 2
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# faíscas de raspão: riscos claros e rápidos que caem
static func sparks(parent: Node, pos: Vector2, amount: int = 14) -> void:
	burst(parent, pos, Color(1, 0.85, 0.45), amount, 300.0, 0.28, 2.0, 500.0)

static func float_text(parent: Node, pos: Vector2, text: String, color: Color, size: int = 26) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", preload("res://scripts/UIKit.gd").font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.z_index = 30
	parent.add_child(l)
	l.size = Vector2(240, size + 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos - Vector2(120, size)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - 70.0, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.45)
	tw.tween_callback(l.queue_free)
