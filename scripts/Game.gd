extends Node2D

# A corrida em si: pista, jogador, tráfego, HUD, efeitos, pausa e game over.

const World := preload("res://scripts/World.gd")
const Player := preload("res://scripts/Player.gd")
const Spawner := preload("res://scripts/Spawner.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

var world: Node2D
var entities: Node2D
var player: Area2D
var spawner: Node
var camera: Camera2D
var hud: Control
var overlay: Control
var flash_rect: ColorRect
var banner: Label
var dist_label: Label
var score_label: Label
var coin_label: Label
var pause_layer: Control
var _shake: float = 0.0
var _crash_pos: Vector2

func _ready() -> void:
	# a cena roda sempre (para a pausa funcionar); o mundo para quando pausado
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.start_run()

	world = World.new()
	world.follow_game = true
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.biome_changed.connect(_on_biome_changed)

	entities = Node2D.new()
	entities.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(entities)

	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.crashed.connect(_on_crash)
	player.coin_picked.connect(_on_coin)
	player.power_picked.connect(_on_power)

	spawner = Spawner.new()
	spawner.container = entities
	spawner.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(spawner)

	camera = Camera2D.new()
	camera.position = Vector2(240, 360)
	add_child(camera)
	camera.make_current()

	GameManager.game_over_triggered.connect(_on_game_over)
	GameManager.shield_ended.connect(_on_shield_ended)

	_build_overlay()
	_build_hud()
	_show_banner(world.current_biome())
	AudioManager.play_music("race")
	AudioManager.engine_start()

func _process(delta: float) -> void:
	_shake = max(_shake - delta * 30.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	dist_label.text = "%.2f km" % ((GameManager.distance_m - GameManager.debug_start_m) / 1000.0)
	score_label.text = "PONTOS  %d" % int(GameManager.score)
	coin_label.text = str(GameManager.coins_run)
	if Input.is_action_just_pressed("ui_cancel") and not GameManager.game_over and not SaveManager.confirming:
		_toggle_pause()

func shake(amount: float) -> void:
	_shake = max(_shake, amount)

func flash(color: Color, alpha: float = 0.5, time: float = 0.35) -> void:
	flash_rect.color = Color(color.r, color.g, color.b, alpha)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, time)

# ---------- eventos ----------

func _on_crash(t: Area2D) -> void:
	_crash_pos = t.global_position
	var res := GameManager.on_crash()
	match res:
		"shield":
			AudioManager.play("shield_block")
			AudioManager.play("crash", -10.0)
			FX.explosion(entities, t.global_position)
			FX.burst(entities, player.position, Color(0.5, 0.95, 1.0), 30, 260.0, 0.5, 4.0)
			FX.float_text(entities, player.position + Vector2(0, -60), "BLOQUEADO!", Color(0.5, 0.95, 1.0), 22)
			t.queue_free()
			shake(9.0)
			flash(Color(0.4, 0.95, 1.0), 0.3)
		"life":
			AudioManager.play("crash", -3.0)
			AudioManager.play("life_lost")
			FX.explosion(entities, t.global_position)
			FX.float_text(entities, player.position + Vector2(0, -60), "-1 VIDA", Color(1, 0.35, 0.35), 24)
			t.queue_free()
			shake(15.0)
			flash(Color(1, 0.2, 0.2), 0.45)

func _on_coin(c: Area2D) -> void:
	GameManager.add_coin()
	AudioManager.play("coin", -2.0, 0.08)
	FX.burst(entities, c.global_position, Color(1, 0.85, 0.25), 8, 120.0, 0.35, 3.0)
	c.queue_free()

func _on_power(p: Area2D) -> void:
	var pos: Vector2 = p.global_position
	var col: Color = p.color()
	AudioManager.play("power_" + {"escudo": "shield", "lentidao": "slow", "pontos": "points"}[p.kind], 0.0, 0.0)
	match p.kind:
		"escudo":
			GameManager.activate_shield(5.0)
			FX.burst(entities, pos, col, 36, 280.0, 0.6, 4.0)
			FX.float_text(entities, pos + Vector2(0, -30), "ESCUDO!", col)
		"lentidao":
			GameManager.activate_slow_mo(4.0)
			FX.burst(entities, pos, col, 36, 280.0, 0.6, 4.0)
			FX.float_text(entities, pos + Vector2(0, -30), "CÂMERA LENTA", col)
		"pontos":
			var bonus := int(100 * float(GameManager.selected_car()["score_mult"]))
			GameManager.score += bonus
			FX.burst(entities, pos, col, 50, 330.0, 0.8, 5.0, 200.0)
			FX.burst(entities, pos, Color(1, 1, 0.8), 20, 160.0, 0.5, 3.0)
			FX.float_text(entities, pos + Vector2(0, -30), "+%d" % bonus, col, 32)
	flash(col, 0.3, 0.3)
	shake(4.0)
	p.queue_free()

func _on_shield_ended(_broken: bool) -> void:
	AudioManager.play("shield_end")
	FX.burst(entities, player.position, Color(0.5, 0.95, 1.0), 40, 300.0, 0.6, 4.0)

func _on_game_over() -> void:
	AudioManager.play("crash")
	AudioManager.engine_stop()
	AudioManager.stop_music(0.3)
	FX.explosion(entities, player.position, true)
	player.visible = false
	shake(22.0)
	flash(Color(1, 0.9, 0.7), 0.7, 0.6)
	await get_tree().create_timer(1.3).timeout
	AudioManager.play_music("gameover", 0.05)
	_build_game_over()

func _on_biome_changed(index: int) -> void:
	AudioManager.play("biome", 0.0, 0.0)
	_show_banner(index)

# ---------- overlay (tinta da câmera lenta + flash) ----------

func _build_overlay() -> void:
	overlay = UI.root(self, 5)
	overlay.add_child(DrawHook.new(_draw_overlay))
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(flash_rect)

func _draw_overlay(ci: Control) -> void:
	var s: float = clamp((1.0 - GameManager.slow_factor) * 2.0, 0.0, 1.0)
	if s <= 0.01:
		return
	ci.draw_rect(Rect2(0, 0, 480, 720), Color(0.45, 0.15, 0.85, 0.16 * s))
	# vinheta nas bordas
	for i in range(6):
		var w := 14.0 * (i + 1)
		var c := Color(0.25, 0.05, 0.5, 0.07 * s)
		ci.draw_rect(Rect2(0, 0, w, 720), c)
		ci.draw_rect(Rect2(480 - w, 0, w, 720), c)

# ---------- HUD ----------

func _build_hud() -> void:
	hud = UI.root(self, 10)
	UI.panel(hud, Rect2(10, 10, 460, 64))
	dist_label = UI.label(hud, "0.00 km", Vector2(24, 12), 30, Color.WHITE)
	score_label = UI.label(hud, "PONTOS 0", Vector2(26, 46), 15, Color(0.75, 0.85, 1.0))
	coin_label = UI.label(hud, "0", Vector2(384, 24), 24, UI.GOLD)
	UI.label(hud, "ESC  pausa", Vector2(392, 694), 12, Color(1, 1, 1, 0.5))
	if GameManager.turn_mode:
		UI.label(hud, "VEZ DE " + GameManager.current_player().to_upper(), Vector2(210, 80), 15, UI.ACCENT, 260, HORIZONTAL_ALIGNMENT_RIGHT)
	hud.add_child(DrawHook.new(_draw_hud))

	banner = UI.label(hud, "", Vector2(0, 170), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_constant_override("outline_size", 10)
	banner.modulate.a = 0.0

func _draw_hud(ci: Control) -> void:
	UI.draw_coin(ci, Vector2(366, 41), 11.0)

	# vidas extras
	for i in range(GameManager.lives):
		_heart(ci, Vector2(250 + i * 26, 42))

	# barras dos poderes ativos
	var y := 84.0
	if GameManager.shield_time > 0.0:
		_power_bar(ci, y, "ESCUDO", Color(0.3, 0.9, 1.0), GameManager.shield_time / max(GameManager.shield_total, 0.01))
		y += 26.0
	if GameManager.slow_time > 0.0:
		_power_bar(ci, y, "CÂMERA LENTA", Color(0.85, 0.35, 1.0), GameManager.slow_time / max(GameManager.slow_total, 0.01))

	_speedometer(ci, Vector2(46, 668))

func _power_bar(ci: Control, y: float, text: String, c: Color, frac: float) -> void:
	ci.draw_rect(Rect2(10, y, 190, 22), Color(0, 0, 0, 0.55))
	ci.draw_circle(Vector2(22, y + 11), 7, c)
	ci.draw_string(UI.font(), Vector2(34, y + 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	UI.draw_bar(ci, Rect2(124, y + 7, 70, 8), frac, c)

func _heart(ci: Control, p: Vector2) -> void:
	var c := Color(1, 0.3, 0.4)
	ci.draw_circle(p + Vector2(-5, -3), 6, c)
	ci.draw_circle(p + Vector2(5, -3), 6, c)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-10.5, -1), p + Vector2(10.5, -1), p + Vector2(0, 11)]), c)

func _speedometer(ci: Control, c: Vector2) -> void:
	var r := 38.0
	var frac: float = clamp(GameManager.speed / GameManager.max_speed, 0.0, 1.0)
	ci.draw_circle(c, r + 6, Color(0, 0, 0, 0.6))
	var a0 := PI * 0.75
	var a1 := PI * 2.25
	ci.draw_arc(c, r, a0, a1, 32, Color(1, 1, 1, 0.15), 6.0, true)
	var col := Color(0.1, 0.95, 0.9).lerp(Color(1, 0.25, 0.4), frac)
	ci.draw_arc(c, r, a0, a0 + (a1 - a0) * frac, 32, col, 6.0, true)
	var na := a0 + (a1 - a0) * frac
	ci.draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 8), Color.WHITE, 2.5, true)
	ci.draw_circle(c, 4, Color.WHITE)
	ci.draw_string(UI.font(), c + Vector2(-30, 24), str(GameManager.speed_kmh()), HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color.WHITE)
	ci.draw_string(UI.font(), c + Vector2(-30, 36), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(1, 1, 1, 0.6))

func _show_banner(index: int) -> void:
	var b: Dictionary = GameManager.biomes[index]
	banner.text = b["sign"]
	banner.pivot_offset = Vector2(240, 20)
	banner.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(banner, "modulate:a", 0.0, 0.5)

# ---------- pausa ----------

func _toggle_pause() -> void:
	if pause_layer:
		_resume()
		return
	get_tree().paused = true
	pause_layer = UI.root(self, 20)
	pause_layer.get_parent().process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	UI.panel(pause_layer, Rect2(90, 220, 300, 280), Color(0.05, 0.06, 0.1, 0.95), UI.ACCENT)
	UI.label(pause_layer, "PAUSADO", Vector2(90, 236), 36, Color.WHITE, 300, HORIZONTAL_ALIGNMENT_CENTER)
	var b1 := UI.button(pause_layer, "CONTINUAR", Rect2(130, 300, 220, 48), _resume)
	if GameManager.turn_mode:
		# nos turnos não dá para recomeçar: cada um tem uma chance só
		UI.label(pause_layer, "Vez de " + GameManager.current_player(), Vector2(90, 368), 16, UI.ACCENT, 300, HORIZONTAL_ALIGNMENT_CENTER)
		var quit := UI.button(pause_layer, "DESISTIR DA PARTIDA", Rect2(130, 416, 220, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"), 17)
		UI.chain_vertical([b1, quit])
	else:
		var b2 := UI.button(pause_layer, "RECOMEÇAR", Rect2(130, 358, 220, 48), func(): UI.go(get_tree(), "res://scenes/Game.tscn"))
		var b3 := UI.button(pause_layer, "MENU", Rect2(130, 416, 220, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
		UI.chain_vertical([b1, b2, b3])
	b1.grab_focus()

func _resume() -> void:
	get_tree().paused = false
	if pause_layer:
		pause_layer.get_parent().queue_free()
		pause_layer = null

# ---------- game over ----------

func _build_game_over() -> void:
	var s: Dictionary = GameManager.last_summary
	var root := UI.root(self, 20)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := UI.panel(root, Rect2(40, 90, 400, 560), Color(0.05, 0.06, 0.1, 0.95), Color(1, 0.3, 0.4))
	box.modulate.a = 0.0
	box.position.y += 30
	create_tween().tween_property(box, "modulate:a", 1.0, 0.3)
	create_tween().tween_property(box, "position:y", 90.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	UI.label(box, "BATEU!", Vector2(0, 14), 44, Color(1, 0.3, 0.4), 400, HORIZONTAL_ALIGNMENT_CENTER)
	var y := 78.0
	if s["new_best"]:
		var nb := UI.label(box, "NOVO RECORDE!", Vector2(0, y), 22, UI.GOLD, 400, HORIZONTAL_ALIGNMENT_CENTER)
		var tw := create_tween().set_loops()
		tw.tween_property(nb, "modulate:a", 0.35, 0.4)
		tw.tween_property(nb, "modulate:a", 1.0, 0.4)
	elif s["top_pos"] > 0:
		UI.label(box, "#%d NO TOP 10!" % s["top_pos"], Vector2(0, y), 22, UI.ACCENT, 400, HORIZONTAL_ALIGNMENT_CENTER)
	y += 40.0

	var rows := [
		["Distância", "%.2f km" % s["km"]],
		["Pontos", str(s["score"])],
		["Moedas coletadas", "+%d" % s["collected"]],
		["Bônus da corrida", "+%d" % s["bonus"]],
		["Total de moedas", str(SaveManager.coins())],
	]
	if GameManager.turn_mode:
		var last: Dictionary = GameManager.turn_results.back()
		rows.push_front(["Jogador", String(last["name"])])
	for r in rows:
		UI.label(box, r[0], Vector2(30, y), 18, Color(0.75, 0.8, 0.9))
		UI.label(box, r[1], Vector2(200, y), 20, Color.WHITE, 170, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 32.0

	# patente
	y += 8.0
	var ri: int = s["new_rank"]
	var rank: Dictionary = GameManager.ranks[ri]
	var rank_text := "PATENTE: %s" % String(rank["name"]).to_upper()
	if ri > s["old_rank"]:
		rank_text = "SUBIU PARA %s!" % String(rank["name"]).to_upper()
	UI.label(box, rank_text, Vector2(100, y), 20, rank["color"])
	var km: float = s["total_km"]
	var next_text := "Patente máxima!"
	if ri < GameManager.ranks.size() - 1:
		var nk: float = GameManager.ranks[ri + 1]["km"]
		next_text = "Próxima: %s em %.1f km" % [GameManager.ranks[ri + 1]["name"], nk - km]
	UI.label(box, next_text, Vector2(100, y + 52), 14, Color(0.75, 0.8, 0.9))
	var by := y
	var draw_rank := func(ci: Control) -> void:
		UI.draw_rank_badge(ci, Vector2(60, by + 36), 30, ri)
		UI.draw_bar(ci, Rect2(100, by + 34, 270, 12), GameManager.rank_progress(km), rank["color"])
	box.add_child(DrawHook.new(draw_rank, Rect2(0, 0, 400, 560)))
	y += 90.0

	if GameManager.turn_mode:
		var turn_text := "VER RESULTADO"
		if not GameManager.turns_finished():
			turn_text = "PRÓXIMO: " + GameManager.current_player().to_upper()
		var nb := UI.button(box, turn_text, Rect2(40, y, 320, 50), func(): UI.go(get_tree(), "res://scenes/Turns.tscn"), 20)
		nb.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
		nb.clip_text = true
		nb.grab_focus()
		return

	var b1 := UI.button(box, "CORRER DE NOVO", Rect2(40, y, 320, 50), func(): UI.go(get_tree(), "res://scenes/Game.tscn"), 22)
	var b2 := UI.button(box, "GARAGEM", Rect2(40, y + 60, 155, 44), func(): UI.go(get_tree(), "res://scenes/Garage.tscn"))
	var b3 := UI.button(box, "MENU", Rect2(205, y + 60, 155, 44), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
	b1.focus_neighbor_bottom = b1.get_path_to(b2)
	b2.focus_neighbor_top = b2.get_path_to(b1)
	b3.focus_neighbor_top = b3.get_path_to(b1)
	b1.grab_focus()
