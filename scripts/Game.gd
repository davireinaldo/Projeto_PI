extends Node2D

# A corrida em si: pista, jogador, tráfego, HUD, efeitos, pausa e game over.
# Também cuida do raspão/combo, dos obstáculos de cada cenário, do clima,
# do dia e noite e dos avisos de missão completa.

const World := preload("res://scripts/World.gd")
const Player := preload("res://scripts/Player.gd")
const Spawner := preload("res://scripts/Spawner.gd")
const Weather := preload("res://scripts/Weather.gd")
const Lighting := preload("res://scripts/Lighting.gd")
const PowerUp := preload("res://scripts/PowerUp.gd")
const Missions := preload("res://scripts/Missions.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

# tempo até um veículo na sua faixa bater: abaixo disso, desviar é "raspão"
const NEAR_MISS_TIME := 0.5

var world: Node2D
var entities: Node2D
var player: Area2D
var spawner: Node
var weather: Node2D
var lighting: Node2D
var camera: Camera2D
var hud: Control
var overlay: Control
var flash_rect: ColorRect
var banner: Label
var dist_label: Label
var score_label: Label
var coin_label: Label
var combo_label: Label
var pause_layer: Control
var _shake: float = 0.0
var _crash_pos: Vector2
var _t: float = 0.0
var _coins_shown: int = 0
var _score_shown: int = 0
var _km_shown: int = 0
var _splash: float = 0.0 # gotas na tela depois da poça
var _notified: Array = [] # missões já avisadas nesta corrida
var _mission_check: float = 0.0
var _toasts: int = 0

func _ready() -> void:
	# a cena roda sempre (para a pausa funcionar); o mundo para quando pausado
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.start_run()

	world = World.new()
	world.follow_game = true
	world.day_night = true
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
	player.hazard_hit.connect(_on_hazard)

	spawner = Spawner.new()
	spawner.container = entities
	spawner.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(spawner)

	weather = Weather.new()
	weather.world = world
	weather.storms = true
	weather.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(weather)
	weather.storm_started.connect(_on_storm_started)
	weather.storm_survived.connect(_on_storm_survived)

	lighting = Lighting.new()
	lighting.world = world
	lighting.hero = player
	add_child(lighting)

	camera = Camera2D.new()
	camera.position = Vector2(240, 360)
	add_child(camera)
	camera.make_current()

	GameManager.game_over_triggered.connect(_on_game_over)
	GameManager.shield_ended.connect(_on_shield_ended)
	GameManager.combo_ended.connect(_on_combo_ended)
	GameManager.nitro_ended.connect(_on_nitro_ended)

	_build_overlay()
	_build_hud()
	_show_banner(world.current_biome())
	AudioManager.play_music("race")
	AudioManager.engine_start()

func _process(delta: float) -> void:
	_t += delta
	_shake = max(_shake - delta * 30.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if GameManager.nitro_time > 0.0 and not get_tree().paused:
		camera.offset += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 1.5
	if not get_tree().paused:
		_splash = max(_splash - delta, 0.0)
	_update_hud()
	if GameManager.running and not GameManager.game_over and not get_tree().paused:
		_check_near_misses()
		_mission_check -= delta
		if _mission_check <= 0.0:
			_mission_check = 0.3
			_check_missions()
	if Input.is_action_just_pressed("ui_cancel") and not GameManager.game_over and not SaveManager.confirming:
		_toggle_pause()

func shake(amount: float) -> void:
	_shake = max(_shake, amount)

func flash(color: Color, alpha: float = 0.5, time: float = 0.35) -> void:
	flash_rect.color = Color(color.r, color.g, color.b, alpha)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, time)

# ---------- raspão ----------

# Um veículo (ou obstáculo) que vinha na sua faixa e chegou a menos de
# NEAR_MISS_TIME de bater vira "ameaça"; se passar sem bater, é raspão.
func _check_near_misses() -> void:
	var pp := player.position
	for t in get_tree().get_nodes_in_group("traffic"):
		if t.passed or t.kind == "racer":
			continue
		var half: float = t.length * 0.5
		var dy: float = pp.y - t.position.y
		if dy > 0.0 and abs(t.position.x - pp.x) < 38.0:
			var gap: float = dy - half - 28.0
			if gap < max(t.rel_speed, 1.0) * NEAR_MISS_TIME:
				t.threat = true
		if t.position.y - half > pp.y + 30.0:
			t.passed = true
			if t.threat:
				_near_miss(t)

func _near_miss(t: Node2D) -> void:
	var is_obstacle: bool = t.is_in_group("obstacles")
	var pts := GameManager.near_miss(is_obstacle)
	var combo := GameManager.combo
	AudioManager.play("near_miss", -3.0, 0.0, min(1.0 + (combo - 1) * 0.07, 1.8))
	var side := 1.0 if t.position.x < player.position.x else -1.0
	var pos: Vector2 = player.position + Vector2(side * 10.0, -50.0)
	var col := _combo_color(combo)
	FX.float_text(entities, pos, "RASPÃO! +%d" % pts, col, 20 + min(combo, 6) * 2)
	FX.burst(entities, Vector2((t.position.x + player.position.x) * 0.5, player.position.y - 10), Color(1, 1, 1), 10, 160.0, 0.3, 2.5)
	_punch(combo_label, 1.5)
	if combo % 5 == 0:
		flash(col, 0.18, 0.3)

func _combo_color(c: int) -> Color:
	if c >= 8:
		return UI.HOT
	if c >= 5:
		return Color(1, 0.55, 0.15)
	if c >= 3:
		return UI.GOLD
	return UI.ACCENT

func _on_combo_ended(count: int, points: int) -> void:
	if count >= 2 and not GameManager.game_over:
		FX.float_text(entities, Vector2(360, 170), "COMBO x%d  +%d" % [count, points], _combo_color(count), 22)

# ---------- eventos ----------

func _on_crash(t: Area2D) -> void:
	_crash_pos = t.global_position
	var res := GameManager.on_crash()
	match res:
		"nitro":
			var pts := int(30 * float(GameManager.selected_car()["score_mult"]))
			GameManager.score += pts
			AudioManager.play("crash", -8.0)
			_smash_fx(t)
			FX.float_text(entities, t.global_position + Vector2(0, -30), "ESMAGOU! +%d" % pts, Color(1, 0.6, 0.15), 22)
			t.queue_free()
			shake(8.0)
		"shield":
			AudioManager.play("shield_block")
			AudioManager.play("crash", -10.0)
			_smash_fx(t)
			FX.burst(entities, player.position, Color(0.5, 0.95, 1.0), 30, 260.0, 0.5, 4.0)
			FX.float_text(entities, player.position + Vector2(0, -60), "BLOQUEADO!", Color(0.5, 0.95, 1.0), 22)
			t.queue_free()
			shake(9.0)
			flash(Color(0.4, 0.95, 1.0), 0.3)
		"life":
			AudioManager.play("crash", -3.0)
			AudioManager.play("life_lost")
			_smash_fx(t)
			FX.float_text(entities, player.position + Vector2(0, -60), "-1 VIDA", Color(1, 0.35, 0.35), 24)
			t.queue_free()
			shake(15.0)
			flash(Color(1, 0.2, 0.2), 0.45)

# veículo explode; obstáculo voa em pedaços da cor dele
func _smash_fx(t: Area2D) -> void:
	if t.is_in_group("obstacles"):
		FX.burst(entities, t.global_position, t.color(), 26, 280.0, 0.6, 5.0, 300.0)
		FX.burst(entities, t.global_position, Color(1, 1, 1), 10, 200.0, 0.4, 3.0)
	else:
		FX.explosion(entities, t.global_position)

# buraco, duna, poça e gelo (não batem, mas atrapalham)
func _on_hazard(o: Area2D) -> void:
	var protected := GameManager.shield_time > 0.0 or GameManager.nitro_time > 0.0
	var pos: Vector2 = player.position
	match o.kind:
		"bueiro", "duna":
			FX.burst(entities, o.global_position, o.color(), 18, 180.0, 0.5, 4.0, 200.0)
			if protected:
				return
			GameManager.bump()
			player.bump()
			AudioManager.play("bump")
			FX.float_text(entities, pos + Vector2(0, -60), "BURACO!" if o.kind == "bueiro" else "AREIA!", o.color().lightened(0.3), 22)
			shake(8.0)
		"poca":
			AudioManager.play("splash", -2.0)
			FX.burst(entities, o.global_position, Color(0.6, 0.85, 1.0), 34, 260.0, 0.55, 4.0, 400.0)
			FX.float_text(entities, pos + Vector2(0, -60), "SPLASH!", Color(0.6, 0.85, 1.0), 22)
			if not protected:
				_splash = 1.8
		"gelo":
			FX.burst(entities, pos, Color(0.85, 0.97, 1.0), 20, 160.0, 0.5, 3.0)
			if protected:
				return
			player.ice_time = 2.2
			AudioManager.play("ice")
			FX.float_text(entities, pos + Vector2(0, -60), "GELO!", Color(0.75, 0.95, 1.0), 22)

func _on_coin(c: Area2D) -> void:
	var v := GameManager.add_coin()
	AudioManager.play("coin", -2.0, 0.08, 1.12 if v == 2 else 1.0)
	FX.burst(entities, c.global_position, Color(1, 0.85, 0.25), 8, 120.0, 0.35, 3.0)
	if v == 2:
		FX.float_text(entities, c.global_position + Vector2(0, -20), "+2", PowerUp.COLORS["moedas2"], 16)
	c.queue_free()

func _on_power(p: Area2D) -> void:
	var pos: Vector2 = p.global_position
	var col: Color = p.color()
	var sounds := {"escudo": "shield", "lentidao": "slow", "pontos": "points", "nitro": "nitro", "ima": "magnet", "moedas2": "x2"}
	AudioManager.play("power_" + sounds[p.kind], 0.0, 0.0)
	GameManager.run_stats["powers"] += 1
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
		"nitro":
			GameManager.activate_nitro(3.5)
			FX.burst(entities, pos, col, 40, 320.0, 0.6, 5.0)
			FX.burst(entities, player.position + Vector2(0, 30), Color(1, 0.9, 0.4), 30, 260.0, 0.5, 4.0, 500.0)
			FX.float_text(entities, pos + Vector2(0, -30), "NITRO!", col, 30)
			shake(10.0)
		"ima":
			GameManager.activate_magnet(8.0)
			FX.burst(entities, pos, col, 36, 280.0, 0.6, 4.0)
			FX.float_text(entities, pos + Vector2(0, -30), "ÍMÃ!", col)
		"moedas2":
			GameManager.activate_x2(10.0)
			FX.burst(entities, pos, col, 36, 280.0, 0.6, 4.0)
			FX.burst(entities, pos, UI.GOLD, 16, 200.0, 0.5, 3.0)
			FX.float_text(entities, pos + Vector2(0, -30), "MOEDAS x2!", col)
	flash(col, 0.3, 0.3)
	shake(4.0)
	p.queue_free()

func _on_shield_ended(_broken: bool) -> void:
	AudioManager.play("shield_end")
	FX.burst(entities, player.position, Color(0.5, 0.95, 1.0), 40, 300.0, 0.6, 4.0)

func _on_nitro_ended() -> void:
	FX.burst(entities, player.position + Vector2(0, 30), Color(1, 0.5, 0.15), 24, 200.0, 0.5, 4.0)

func _on_storm_started() -> void:
	AudioManager.play("storm", 0.0, 0.0)
	_show_text("TEMPESTADE DE AREIA!", Color(1, 0.8, 0.5))

func _on_storm_survived() -> void:
	GameManager.run_stats["storms"] += 1
	FX.float_text(entities, Vector2(240, 300), "PASSOU A TEMPESTADE!", Color(1, 0.85, 0.55), 22)

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

# ---------- missões ----------

func _check_missions() -> void:
	for m in Missions.active():
		if not m["id"] in _notified and Missions.is_done(m, GameManager.run_stats):
			_notified.append(m["id"])
			_mission_toast(Missions.def(String(m["id"])))

func _mission_toast(d: Dictionary) -> void:
	AudioManager.play("mission", 0.0, 0.0)
	var box := UI.panel(hud, Rect2(50, 250 + _toasts * 66, 380, 58), Color(0.05, 0.12, 0.08, 0.95), Color(0.4, 1, 0.5))
	_toasts += 1
	UI.label(box, "MISSÃO COMPLETA!", Vector2(14, 6), 16, Color(0.5, 1, 0.6))
	UI.label(box, String(d["text"]), Vector2(14, 28), 14, Color.WHITE, 280)
	UI.label(box, "+%d" % int(d["reward"]), Vector2(290, 14), 22, UI.GOLD, 76, HORIZONTAL_ALIGNMENT_RIGHT)
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(0.6, 0.6)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.4)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		box.queue_free()
		_toasts -= 1)

# ---------- overlay (câmera lenta, nitro, gelo, gotas + flash) ----------

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
	if s > 0.01:
		ci.draw_rect(Rect2(0, 0, 480, 720), Color(0.45, 0.15, 0.85, 0.16 * s))
		_vignette(ci, Color(0.25, 0.05, 0.5), 0.07 * s)

	# nitro: riscos de velocidade e bordas alaranjadas
	var n: float = clamp((GameManager.nitro_factor - 1.0) / 0.65, 0.0, 1.0)
	if n > 0.01:
		_vignette(ci, Color(1, 0.4, 0.05), 0.06 * n)
		for i in range(18):
			var x := 8.0 + fmod(i * 97.3, 464.0)
			var y := fmod(i * 151.7 + _t * (1400.0 + (i % 4) * 300.0), 900.0) - 120.0
			var len := 60.0 + (i % 3) * 40.0
			ci.draw_line(Vector2(x, y), Vector2(x, y + len), Color(1, 0.95, 0.85, 0.35 * n), 2.0)

	# gelo: bordas congeladas
	if player.ice_time > 0.0:
		var k: float = clamp(player.ice_time / 2.2, 0.0, 1.0)
		_vignette(ci, Color(0.7, 0.92, 1.0), 0.09 * k)

	# gotas d'água na tela depois da poça
	if _splash > 0.0:
		var a: float = clamp(_splash / 1.8, 0.0, 1.0)
		for i in range(16):
			var p := Vector2(30.0 + fmod(i * 137.1, 420.0), 60.0 + fmod(i * 241.3, 600.0) + (1.8 - _splash) * (10.0 + i % 4 * 8.0))
			var r := 14.0 + (i % 4) * 7.0
			ci.draw_circle(p, r, Color(0.7, 0.85, 1.0, 0.22 * a))
			ci.draw_arc(p, r, 0, TAU, 20, Color(1, 1, 1, 0.35 * a), 1.5, true)
			ci.draw_circle(p + Vector2(-r * 0.35, -r * 0.35), r * 0.2, Color(1, 1, 1, 0.55 * a))

func _vignette(ci: Control, c: Color, a: float) -> void:
	for i in range(6):
		var w := 14.0 * (i + 1)
		var col := Color(c.r, c.g, c.b, a)
		ci.draw_rect(Rect2(0, 0, w, 720), col)
		ci.draw_rect(Rect2(480 - w, 0, w, 720), col)

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

	combo_label = UI.label(hud, "", Vector2(270, 104), 26, UI.ACCENT, 200, HORIZONTAL_ALIGNMENT_RIGHT)
	combo_label.add_theme_constant_override("outline_size", 8)

	banner = UI.label(hud, "", Vector2(0, 170), 30, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_constant_override("outline_size", 10)
	banner.modulate.a = 0.0

# textos do HUD + "pulinho" quando os números mudam
func _update_hud() -> void:
	var km := (GameManager.distance_m - GameManager.debug_start_m) / 1000.0
	dist_label.text = "%.2f km" % km
	if int(km) > _km_shown:
		_km_shown = int(km)
		_punch(dist_label, 1.35)
		dist_label.modulate = UI.GOLD
		create_tween().tween_property(dist_label, "modulate", Color.WHITE, 0.8)
		FX.float_text(entities, Vector2(240, 250), "%d KM!" % _km_shown, UI.GOLD, 30)

	var score := int(GameManager.score)
	if score - _score_shown >= 30:
		_punch(score_label, 1.25)
	_score_shown = score
	score_label.text = "PONTOS  %d" % score

	if GameManager.coins_run != _coins_shown:
		_coins_shown = GameManager.coins_run
		_punch(coin_label, 1.4)
	coin_label.text = str(GameManager.coins_run)

	var combo := GameManager.combo
	combo_label.visible = combo >= 1
	if combo >= 1:
		combo_label.text = "COMBO x%d" % combo
		combo_label.add_theme_color_override("font_color", _combo_color(combo))

func _punch(l: Label, amount: float) -> void:
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(amount, amount)
	l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw_hud(ci: Control) -> void:
	UI.draw_coin(ci, Vector2(366, 41), 11.0 * (1.0 + (coin_label.scale.x - 1.0) * 0.6))

	# progresso até o próximo cenário (linha fina embaixo do painel)
	var into := fposmod(GameManager.distance_m, GameManager.BIOME_LENGTH) / GameManager.BIOME_LENGTH
	ci.draw_rect(Rect2(22, 68, 436, 3), Color(1, 1, 1, 0.1))
	ci.draw_rect(Rect2(22, 68, 436 * into, 3), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.7))
	ci.draw_circle(Vector2(22 + 436 * into, 69.5), 3.0 + sin(_t * 6.0), UI.ACCENT)

	# vidas extras
	for i in range(GameManager.lives):
		_heart(ci, Vector2(250 + i * 26, 42) , 1.0 + 0.06 * sin(_t * 5.0 + i))

	# barras dos poderes ativos
	var y := 84.0
	var powers := [
		["escudo", GameManager.shield_time, GameManager.shield_total],
		["lentidao", GameManager.slow_time, GameManager.slow_total],
		["nitro", GameManager.nitro_time, GameManager.nitro_total],
		["ima", GameManager.magnet_time, GameManager.magnet_total],
		["moedas2", GameManager.x2_time, GameManager.x2_total],
	]
	for p in powers:
		if p[1] > 0.0:
			_power_bar(ci, y, p[0], p[1], p[1] / max(p[2], 0.01))
			y += 26.0

	# tempo restante do combo
	if GameManager.combo >= 1:
		var c := _combo_color(GameManager.combo)
		UI.draw_bar(ci, Rect2(330, 140, 140, 6), GameManager.combo_time / GameManager.COMBO_WINDOW, c)

	_speedometer(ci, Vector2(46, 668))

func _power_bar(ci: Control, y: float, kind: String, left: float, frac: float) -> void:
	if left < 1.0 and fmod(_t, 0.25) < 0.1:
		return # piscando: está acabando
	var c: Color = PowerUp.COLORS[kind]
	ci.draw_rect(Rect2(10, y, 196, 22), Color(0, 0, 0, 0.55))
	ci.draw_rect(Rect2(10, y, 3, 22), c)
	ci.draw_set_transform(Vector2(26, y + 11), 0.0, Vector2(0.55, 0.55))
	PowerUp.draw_icon(ci, kind, _t, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_string(UI.font(), Vector2(40, y + 16), PowerUp.NAMES[kind], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	UI.draw_bar(ci, Rect2(132, y + 7, 66, 8), frac, c)

func _heart(ci: Control, p: Vector2, s: float = 1.0) -> void:
	var c := Color(1, 0.3, 0.4)
	ci.draw_circle(p + Vector2(-5, -3) * s, 6 * s, c)
	ci.draw_circle(p + Vector2(5, -3) * s, 6 * s, c)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-10.5, -1) * s, p + Vector2(10.5, -1) * s, p + Vector2(0, 11) * s]), c)

func _speedometer(ci: Control, c: Vector2) -> void:
	var r := 38.0
	var frac: float = clamp(GameManager.speed / GameManager.max_speed, 0.0, 1.0)
	var nitro: float = clamp((GameManager.nitro_factor - 1.0) / 0.65, 0.0, 1.0)
	var col := Color(0.1, 0.95, 0.9).lerp(Color(1, 0.25, 0.4), frac).lerp(Color(1, 0.55, 0.1), nitro)
	# brilho pulsando perto do máximo (e no nitro)
	var hot: float = max(smoothstep(0.8, 1.0, frac), nitro)
	if hot > 0.01:
		var pulse := 0.5 + 0.5 * sin(_t * (10.0 + 10.0 * nitro))
		ci.draw_circle(c, r + 14 + 3 * pulse, Color(col.r, col.g, col.b, 0.12 * hot))
		ci.draw_circle(c, r + 9, Color(col.r, col.g, col.b, 0.18 * hot * pulse))
	ci.draw_circle(c, r + 6, Color(0, 0, 0, 0.6))
	var a0 := PI * 0.75
	var a1 := PI * 2.25
	# marcações
	for i in range(11):
		var a := a0 + (a1 - a0) * i / 10.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * (r - 10), c + d * (r - (6 if i % 5 else 3)), Color(1, 1, 1, 0.35), 1.5)
	ci.draw_arc(c, r, a0, a1, 32, Color(1, 1, 1, 0.15), 6.0, true)
	ci.draw_arc(c, r, a0, a0 + (a1 - a0) * frac, 32, col, 6.0, true)
	var na := a0 + (a1 - a0) * frac + (sin(_t * 40.0) * 0.03 * hot)
	ci.draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 8), Color.WHITE, 2.5, true)
	ci.draw_circle(c, 4, Color.WHITE)
	ci.draw_string(UI.font(), c + Vector2(-30, 24), str(GameManager.speed_kmh()), HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color.WHITE)
	ci.draw_string(UI.font(), c + Vector2(-30, 36), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(1, 1, 1, 0.6))
	if nitro > 0.01:
		ci.draw_string_outline(UI.font(), c + Vector2(-30, -48), "NITRO", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, 5, Color(0, 0, 0, 0.8 * nitro))
		ci.draw_string(UI.font(), c + Vector2(-30, -48), "NITRO", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Color(1, 0.6, 0.15, nitro))

func _show_banner(index: int) -> void:
	_show_text(GameManager.biomes[index]["sign"], Color.WHITE)

func _show_text(text: String, color: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.pivot_offset = Vector2(240, 20)
	banner.scale = Vector2(1.4, 1.4)
	banner.modulate.a = 0.0
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
	UI.panel(pause_layer, Rect2(90, 150, 300, 280), Color(0.05, 0.06, 0.1, 0.95), UI.ACCENT)
	UI.label(pause_layer, "PAUSADO", Vector2(90, 166), 36, Color.WHITE, 300, HORIZONTAL_ALIGNMENT_CENTER)
	var b1 := UI.button(pause_layer, "CONTINUAR", Rect2(130, 230, 220, 48), _resume)
	if GameManager.turn_mode:
		# nos turnos não dá para recomeçar: cada um tem uma chance só
		UI.label(pause_layer, "Vez de " + GameManager.current_player(), Vector2(90, 298), 16, UI.ACCENT, 300, HORIZONTAL_ALIGNMENT_CENTER)
		var quit := UI.button(pause_layer, "DESISTIR DA PARTIDA", Rect2(130, 346, 220, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"), 17)
		UI.chain_vertical([b1, quit])
	else:
		var b2 := UI.button(pause_layer, "RECOMEÇAR", Rect2(130, 288, 220, 48), func(): UI.go(get_tree(), "res://scenes/Game.tscn"))
		var b3 := UI.button(pause_layer, "MENU", Rect2(130, 346, 220, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
		UI.chain_vertical([b1, b2, b3])
	_mission_list(pause_layer, 448)
	b1.grab_focus()

# Lista das 3 missões com o progresso (contando a corrida atual).
func _mission_list(parent: Control, y: float) -> void:
	UI.panel(parent, Rect2(30, y, 420, 250), Color(0.05, 0.06, 0.1, 0.92))
	UI.label(parent, "MISSÕES", Vector2(30, y + 8), 18, UI.ACCENT, 420, HORIZONTAL_ALIGNMENT_CENTER)
	var list := Missions.active()
	for i in range(list.size()):
		var m: Dictionary = list[i]
		var d := Missions.def(String(m["id"]))
		var done := Missions.is_done(m, GameManager.run_stats)
		var my := y + 42 + i * 68
		UI.label(parent, String(d["text"]), Vector2(48, my), 15, Color(0.5, 1, 0.6) if done else Color.WHITE, 300)
		UI.label(parent, "+%d" % int(d["reward"]), Vector2(340, my), 15, UI.GOLD, 92, HORIZONTAL_ALIGNMENT_RIGHT)
		UI.label(parent, "COMPLETA!" if done else Missions.progress_text(m, GameManager.run_stats), Vector2(48, my + 38), 12, Color(0.7, 0.75, 0.85))
		var frac: float = Missions.value(m, GameManager.run_stats) / float(d["goal"])
		var bar_y := my + 26
		var draw_bar := func(ci: Control) -> void:
			UI.draw_bar(ci, Rect2(48, bar_y, 384, 8), frac, Color(0.4, 1, 0.5) if done else UI.ACCENT)
		var hook := DrawHook.new(draw_bar)
		hook.auto = false
		parent.add_child(hook)

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

	UI.label(box, "BATEU!", Vector2(0, 10), 40, Color(1, 0.3, 0.4), 400, HORIZONTAL_ALIGNMENT_CENTER)
	var y := 64.0
	if s["new_best"]:
		var nb := UI.label(box, "NOVO RECORDE!", Vector2(0, y), 22, UI.GOLD, 400, HORIZONTAL_ALIGNMENT_CENTER)
		var tw := create_tween().set_loops()
		tw.tween_property(nb, "modulate:a", 0.35, 0.4)
		tw.tween_property(nb, "modulate:a", 1.0, 0.4)
	elif s["top_pos"] > 0:
		UI.label(box, "#%d NO TOP 10!" % s["top_pos"], Vector2(0, y), 22, UI.ACCENT, 400, HORIZONTAL_ALIGNMENT_CENTER)
	y += 36.0

	var rows := [
		["Distância", "%.2f km" % s["km"]],
		["Pontos", str(s["score"])],
		["Raspões", "%d  (combo máx. x%d)" % [s["near_miss"], s["max_combo"]] if s["max_combo"] > 1 else str(s["near_miss"])],
		["Moedas coletadas", "+%d" % s["collected"]],
		["Bônus da corrida", "+%d" % s["bonus"]],
		["Total de moedas", str(SaveManager.coins())],
	]
	if GameManager.turn_mode:
		var last: Dictionary = GameManager.turn_results.back()
		rows.push_front(["Jogador", String(last["name"])])
	for r in rows:
		UI.label(box, r[0], Vector2(30, y), 17, Color(0.75, 0.8, 0.9))
		UI.label(box, r[1], Vector2(160, y), 18, Color.WHITE, 210, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 28.0

	# patente
	y += 8.0
	var ri: int = s["new_rank"]
	var rank: Dictionary = GameManager.ranks[ri]
	var rank_text := "PATENTE: %s" % String(rank["name"]).to_upper()
	if ri > s["old_rank"]:
		rank_text = "SUBIU PARA %s!" % String(rank["name"]).to_upper()
	UI.label(box, rank_text, Vector2(100, y), 19, rank["color"])
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
	box.add_child(DrawHook.new(draw_rank, Rect2(0, 0, 400, 720)))
	y += 84.0

	# missões completadas nesta corrida
	var done: Array = s["missions"]
	if not done.is_empty():
		UI.label(box, "MISSÕES COMPLETAS", Vector2(30, y), 16, Color(0.5, 1, 0.6))
		y += 26.0
		for d in done:
			UI.label(box, String(d["text"]), Vector2(30, y), 14, Color.WHITE, 280)
			UI.label(box, "+%d" % int(d["reward"]), Vector2(300, y), 15, UI.GOLD, 70, HORIZONTAL_ALIGNMENT_RIGHT)
			y += 22.0
		y += 10.0

	var height: float
	if GameManager.turn_mode:
		var turn_text := "VER RESULTADO"
		if not GameManager.turns_finished():
			turn_text = "PRÓXIMO: " + GameManager.current_player().to_upper()
		var nb := UI.button(box, turn_text, Rect2(40, y, 320, 50), func(): UI.go(get_tree(), "res://scenes/Turns.tscn"), 20)
		nb.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
		nb.clip_text = true
		nb.grab_focus()
		height = y + 66.0
	else:
		var b1 := UI.button(box, "CORRER DE NOVO", Rect2(40, y, 320, 50), func(): UI.go(get_tree(), "res://scenes/Game.tscn"), 22)
		var b2 := UI.button(box, "GARAGEM", Rect2(40, y + 60, 155, 44), func(): UI.go(get_tree(), "res://scenes/Garage.tscn"))
		var b3 := UI.button(box, "MENU", Rect2(205, y + 60, 155, 44), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"))
		b1.focus_neighbor_bottom = b1.get_path_to(b2)
		b2.focus_neighbor_top = b2.get_path_to(b1)
		b3.focus_neighbor_top = b3.get_path_to(b1)
		b1.grab_focus()
		height = y + 120.0

	# centraliza a caixa na tela e anima a entrada
	box.size.y = height
	var top: float = max((720.0 - height) * 0.5, 6.0)
	box.position.y = top + 30.0
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.3)
	create_tween().tween_property(box, "position:y", top, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
