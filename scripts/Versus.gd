extends Node2D

# Versus local: dois jogadores na mesma tela, numa pista de 5 faixas.
# Trocar de faixa para cima do rival EMPURRA ele uma faixa; empurrado para
# cima de um carro, ele bate. Se o rival já está na faixa da borda (prensado
# na parede), os dois trocam de lugar. Quem bater perde a rodada e vence
# quem ganhar GameManager.VERSUS_WINS rodadas primeiro.
# Sem moedas, poderes, obstáculos, rivais nem rádio: só o tráfego e o outro jogador.
# Cada rodada é esta cena de novo (o placar fica no GameManager).

const World := preload("res://scripts/World.gd")
const Player := preload("res://scripts/Player.gd")
const Spawner := preload("res://scripts/Spawner.gd")
const Lighting := preload("res://scripts/Lighting.gd")
const FX := preload("res://scripts/FX.gd")
const UI := preload("res://scripts/UIKit.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

const COLORS := [Color(0.1, 0.95, 0.9), Color(1.0, 0.25, 0.55)] # jogador 1, jogador 2
const START_LANES := [1, 3]
const PUSH_COOLDOWN := 1.0 # segundos entre um empurrão e outro
const STUN_TIME := 0.35 # quem é empurrado fica esse tempo sem controle
const SIDE_BY_SIDE := 70.0 # diferença de altura máxima para conseguir empurrar

var world: Node2D
var entities: Node2D
var spawner: Node
var camera: Camera2D
var hud: Control
var big_label: Label
var pause_layer: Control
var players: Array = []
var cooldown: Array = [0.0, 0.0]
var stun: Array = [0.0, 0.0]
var dead: Array = [false, false]
var _countdown: bool = true
var _ending: bool = false
var _shake: float = 0.0
var _t: float = 0.0
var _touch: Dictionary = {} # dedo -> [onde encostou, já deslizou]

func _ready() -> void:
	# a cena roda sempre (para a pausa funcionar); o resto para quando pausado
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	GameManager.set_lanes(5)
	GameManager.start_versus_round()
	GameManager.running = false # a pista acelera só depois da contagem

	world = World.new()
	world.follow_game = true
	world.day_night = true
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	entities = Node2D.new()
	entities.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(entities)

	for i in range(2):
		var p := Player.new()
		p.pid = i + 1
		p.car_id = String(GameManager.versus_cars[i])
		p.lane = START_LANES[i]
		p.on_steer = _on_steer
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p)
		p.crashed.connect(_on_crash.bind(i))
		players.append(p)

	spawner = Spawner.new()
	spawner.container = entities
	spawner.spawn_coins = false
	spawner.spawn_powerups = false
	spawner.spawn_obstacles = false
	spawner.spawn_racers = false
	spawner.spawn_work_zones = false
	spawner.min_free_lanes = 2
	spawner.traffic_rate = 1.6
	spawner.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(spawner)
	spawner.set_process(false) # sem tráfego até a largada

	var lighting := Lighting.new()
	lighting.world = world
	lighting.hero = players[0]
	lighting.hero2 = players[1]
	add_child(lighting)

	camera = Camera2D.new()
	camera.position = Vector2(240, 360)
	add_child(camera)
	camera.make_current()

	_build_hud()
	# só a música da corrida: o rádio (do Gol e das estações) fica no modo normal
	AudioManager.play_music("race")
	AudioManager.engine_start()
	_run_countdown()

func _process(delta: float) -> void:
	_t += delta
	_shake = max(_shake - delta * 30.0, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if Input.is_action_just_pressed("ui_cancel") and not _ending:
		_toggle_pause()
	if get_tree().paused:
		return
	for i in range(2):
		cooldown[i] = max(cooldown[i] - delta, 0.0)
		stun[i] = max(stun[i] - delta, 0.0)

func shake(amount: float) -> void:
	_shake = max(_shake, amount)

# ---------- largada ----------

func _run_countdown() -> void:
	await get_tree().create_timer(0.6, false).timeout
	for n in [3, 2, 1]:
		_big(str(n), Color.WHITE)
		AudioManager.play("ui_move", 0.0, 0.0)
		await get_tree().create_timer(0.75, false).timeout
	_big("JÁ!", UI.GOLD)
	AudioManager.play("power_nitro", -2.0, 0.0)
	_countdown = false
	GameManager.running = true
	spawner.set_process(true)

func _big(text: String, color: Color) -> void:
	big_label.text = text
	big_label.add_theme_color_override("font_color", color)
	big_label.scale = Vector2(1.6, 1.6)
	big_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(big_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(big_label, "modulate:a", 0.0, 0.3).set_delay(0.25)

# ---------- controles ----------

# Toque na tela: a metade esquerda é do jogador 1 e a direita do jogador 2.
# Deslizar para o lado troca de faixa; um toque rápido vale o lado da metade.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch[event.index] = [event.position, false]
		elif _touch.has(event.index):
			var t: Array = _touch[event.index]
			_touch.erase(event.index)
			if not t[1]:
				var side := 0 if t[0].x < 240.0 else 1
				var mid := 120.0 if side == 0 else 360.0
				players[side]._steer(-1 if event.position.x < mid else 1)
	elif event is InputEventScreenDrag and _touch.has(event.index):
		var t: Array = _touch[event.index]
		var dx: float = event.position.x - t[0].x
		if not t[1] and abs(dx) >= Player.SWIPE_MIN:
			t[1] = true
			players[0 if t[0].x < 240.0 else 1]._steer(1 if dx > 0.0 else -1)

# Chamado em cada troca de faixa (Player.on_steer). Devolve true quando a
# troca já foi resolvida aqui (empurrão, ou carro sem controle).
func _on_steer(p: Area2D, dir: int) -> bool:
	var i: int = p.pid - 1
	if _countdown or _ending or dead[i] or stun[i] > 0.0 or get_tree().paused:
		return true
	var target: int = p.lane + dir
	if target < 0 or target >= GameManager.lane_count:
		return false
	var j := 1 - i
	var o: Area2D = players[j]
	if dead[j] or o.lane != target or abs(o.position.y - p.position.y) > SIDE_BY_SIDE:
		return false
	if cooldown[i] > 0.0:
		# ainda recarregando: só raspa no rival e fica onde está
		AudioManager.play("bump", -6.0)
		_hit_fx(p, o, false)
		return true
	cooldown[i] = PUSH_COOLDOWN
	var dest: int = o.lane + dir
	AudioManager.play("crash", -10.0, 0.1, 1.35)
	AudioManager.play("whoosh", -4.0, 0.12)
	_hit_fx(p, o, true)
	if dest < 0 or dest >= GameManager.lane_count:
		# prensado na parede: os dois trocam de lugar
		o.lane = p.lane
		FX.float_text(entities, o.position + Vector2(0, -56), "TROCA!", COLORS[i], 22)
	else:
		o.lane = dest
		FX.float_text(entities, o.position + Vector2(0, -56), "EMPURRÃO!", COLORS[i], 22)
	p.lane = target
	stun[j] = STUN_TIME
	return true

func _hit_fx(p: Node2D, o: Node2D, strong: bool) -> void:
	var mid := (p.position + o.position) * 0.5
	FX.burst(entities, mid, Color(1, 0.85, 0.4), 22 if strong else 8, 240.0 if strong else 140.0, 0.4, 3.5)
	if strong:
		FX.burst(entities, mid, Color(1, 1, 1), 10, 180.0, 0.3, 2.5)
	shake(9.0 if strong else 3.0)

# ---------- batidas e rodadas ----------

func _on_crash(other: Area2D, i: int) -> void:
	if dead[i] or _countdown:
		return
	if other.is_in_group("traffic") and not other.is_in_group("obstacles"):
		FX.explosion(entities, other.global_position)
		other.queue_free()
	_kill(i)

func _kill(i: int) -> void:
	if dead[i]:
		return
	dead[i] = true
	var p: Area2D = players[i]
	AudioManager.play("crash")
	FX.explosion(entities, p.position, true)
	p.visible = false
	p.set_deferred("monitoring", false)
	p.set_deferred("monitorable", false)
	shake(18.0)
	if not _ending:
		_ending = true
		_end_round()

func _end_round() -> void:
	# espera um instantinho: se o outro bater junto, é empate
	await get_tree().create_timer(0.35, false).timeout
	GameManager.end_versus_round()
	AudioManager.engine_stop()
	var winner := -1
	if dead[0] and not dead[1]:
		winner = 1
	elif dead[1] and not dead[0]:
		winner = 0
	if winner >= 0:
		GameManager.versus_wins[winner] += 1
	await get_tree().create_timer(0.6, false).timeout
	if GameManager.versus_winner() >= 0:
		AudioManager.stop_music(0.3)
		_build_final(GameManager.versus_winner())
		return
	_build_round_result(winner)
	await get_tree().create_timer(2.6, false).timeout
	GameManager.versus_round += 1
	UI.go(get_tree(), "res://scenes/Versus.tscn")

func _score_text() -> String:
	return "%d  x  %d" % [GameManager.versus_wins[0], GameManager.versus_wins[1]]

func _build_round_result(winner: int) -> void:
	var root := UI.root(self, 20)
	var box := UI.panel(root, Rect2(50, 230, 380, 170), Color(0.05, 0.06, 0.1, 0.94), COLORS[winner] if winner >= 0 else UI.GOLD)
	var title := "EMPATE!" if winner < 0 else "JOGADOR %d VENCEU A RODADA!" % (winner + 1)
	UI.label(box, title, Vector2(0, 18), 22, COLORS[winner] if winner >= 0 else UI.GOLD, 380, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(box, _score_text(), Vector2(0, 56), 44, Color.WHITE, 380, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(box, "Próxima rodada...", Vector2(0, 126), 14, Color(0.75, 0.8, 0.9), 380, HORIZONTAL_ALIGNMENT_CENTER)
	_pop_in(box)
	AudioManager.play("mission", 0.0, 0.0)

func _build_final(winner: int) -> void:
	var root := UI.root(self, 20)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := UI.panel(root, Rect2(40, 150, 400, 400), Color(0.05, 0.06, 0.1, 0.95), COLORS[winner])
	UI.label(box, "VENCEDOR", Vector2(0, 16), 18, UI.GOLD, 400, HORIZONTAL_ALIGNMENT_CENTER)
	var who := UI.label(box, "JOGADOR %d" % (winner + 1), Vector2(0, 40), 40, COLORS[winner], 400, HORIZONTAL_ALIGNMENT_CENTER)
	who.pivot_offset = Vector2(200, 24)
	var tw := create_tween().set_loops()
	tw.tween_property(who, "scale", Vector2(1.06, 1.06), 0.5)
	tw.tween_property(who, "scale", Vector2.ONE, 0.5)
	var car: Dictionary = GameManager.car_by_id(String(GameManager.versus_cars[winner]))
	UI.label(box, "com o %s" % car["name"], Vector2(0, 94), 16, Color(0.8, 0.85, 0.95), 400, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(box, _score_text(), Vector2(0, 124), 48, Color.WHITE, 400, HORIZONTAL_ALIGNMENT_CENTER)
	var again := UI.button(box, "REVANCHE", Rect2(50, 210, 300, 50), _rematch, 22)
	again.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
	var cars := UI.button(box, "TROCAR CARROS", Rect2(50, 270, 300, 44), func(): UI.go(get_tree(), "res://scenes/VersusSetup.tscn"), 18)
	var menu := UI.button(box, "MENU", Rect2(50, 324, 300, 44), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"), 18)
	UI.chain_vertical([again, cars, menu])
	again.grab_focus()
	_pop_in(box)
	AudioManager.play("power_points", 0.0, 0.0)
	FX.burst(root, Vector2(240, 210), COLORS[winner], 70, 380.0, 1.0, 5.0)
	FX.burst(root, Vector2(240, 210), UI.GOLD, 30, 260.0, 0.8, 4.0)

func _rematch() -> void:
	GameManager.start_versus(GameManager.versus_cars[0], GameManager.versus_cars[1])
	UI.go(get_tree(), "res://scenes/Versus.tscn")

func _pop_in(box: Control) -> void:
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(0.7, 0.7)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "modulate:a", 1.0, 0.2)

# ---------- HUD ----------

func _build_hud() -> void:
	hud = UI.root(self, 10)
	UI.panel(hud, Rect2(10, 10, 460, 60))
	for i in range(2):
		var car: Dictionary = players[i].car
		var x := 24.0 if i == 0 else 266.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		UI.label(hud, "JOGADOR %d" % (i + 1), Vector2(x, 14), 16, COLORS[i], 190, align)
		UI.label(hud, String(car["name"]), Vector2(x, 38), 12, Color(0.8, 0.85, 0.95), 190, align)
	UI.label(hud, "RODADA %d" % GameManager.versus_round, Vector2(140, 16), 15, Color.WHITE, 200, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(hud, "ESC  pausa", Vector2(392, 694), 12, Color(1, 1, 1, 0.5))
	hud.add_child(DrawHook.new(_draw_hud))

	big_label = UI.label(hud, "", Vector2(0, 250), 72, Color.WHITE, 480, HORIZONTAL_ALIGNMENT_CENTER)
	big_label.add_theme_constant_override("outline_size", 12)
	big_label.pivot_offset = Vector2(240, 45)
	big_label.modulate.a = 0.0

	if GameManager.versus_round == 1:
		var help := UI.panel(hud, Rect2(30, 380, 420, 120), Color(0.05, 0.06, 0.1, 0.88), UI.GOLD)
		UI.label(help, "VÁ PARA CIMA DO RIVAL PARA EMPURRAR!", Vector2(0, 10), 16, UI.GOLD, 420, HORIZONTAL_ALIGNMENT_CENTER)
		UI.label(help, "Jogue ele em cima do tráfego. Quem bater perde.\nPrensou na parede? Vocês trocam de lugar.", Vector2(0, 36), 13, Color.WHITE, 420, HORIZONTAL_ALIGNMENT_CENTER)
		UI.label(help, "P1: A / D        P2: ← / →        Celular: cada um na sua metade", Vector2(0, 82), 11, Color(0.75, 0.8, 0.9), 420, HORIZONTAL_ALIGNMENT_CENTER)
		create_tween().tween_property(help, "modulate:a", 0.0, 0.5).set_delay(4.5)

func _draw_hud(ci: Control) -> void:
	# rodadas ganhas
	for i in range(2):
		for k in range(GameManager.VERSUS_WINS):
			var cx := 170.0 + k * 16.0 if i == 0 else 310.0 - k * 16.0
			var c := Vector2(cx, 50)
			if k < GameManager.versus_wins[i]:
				ci.draw_circle(c, 6.0, COLORS[i])
			else:
				ci.draw_arc(c, 6.0, 0, TAU, 16, Color(1, 1, 1, 0.35), 1.5, true)
	var km := (GameManager.distance_m - ((GameManager.versus_round - 1) % GameManager.biomes.size()) * GameManager.BIOME_LENGTH - 50.0) / 1000.0
	ci.draw_string(UI.font(), Vector2(140, 56), "%.2f km" % max(km, 0.0), HORIZONTAL_ALIGNMENT_CENTER, 200, 12, Color(0.75, 0.8, 0.9))

	# "P1"/"P2" em cima de cada carro, com a carga do empurrão
	for i in range(2):
		var p: Node2D = players[i]
		if dead[i]:
			continue
		var pos: Vector2 = p.position + Vector2(0, -50)
		var col: Color = COLORS[i]
		ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(-6, 6), pos + Vector2(6, 6), pos + Vector2(0, 12)]), col)
		ci.draw_string_outline(UI.font(), pos + Vector2(-20, 2), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, 5, Color(0, 0, 0, 0.85))
		ci.draw_string(UI.font(), pos + Vector2(-20, 2), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, col)
		var frac: float = 1.0 - cooldown[i] / PUSH_COOLDOWN
		UI.draw_bar(ci, Rect2(pos.x - 16, pos.y + 82, 32, 4), frac, col if frac >= 1.0 else col.darkened(0.5))

# ---------- pausa ----------

func _toggle_pause() -> void:
	if pause_layer:
		_resume()
		return
	get_tree().paused = true
	pause_layer = UI.root(self, 30)
	pause_layer.get_parent().process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	UI.panel(pause_layer, Rect2(90, 220, 300, 230), Color(0.05, 0.06, 0.1, 0.95), UI.ACCENT)
	UI.label(pause_layer, "PAUSADO", Vector2(90, 236), 36, Color.WHITE, 300, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(pause_layer, "Placar  " + _score_text(), Vector2(90, 286), 16, UI.GOLD, 300, HORIZONTAL_ALIGNMENT_CENTER)
	var b1 := UI.button(pause_layer, "CONTINUAR", Rect2(130, 320, 220, 48), _resume)
	var b2 := UI.button(pause_layer, "SAIR DO VERSUS", Rect2(130, 378, 220, 48), func(): UI.go(get_tree(), "res://scenes/Menu.tscn"), 17)
	UI.chain_vertical([b1, b2])
	b1.grab_focus()

func _resume() -> void:
	get_tree().paused = false
	if pause_layer:
		pause_layer.get_parent().queue_free()
		pause_layer = null
