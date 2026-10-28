extends Node2D

# Tela inicial do ZERO-IMPACT: logo animado e, ao fundo, a pista rolando
# pelos cenários com tráfego, um carro "piloto automático" desviando e
# rivais ultrapassando.

const World := preload("res://scripts/World.gd")
const Spawner := preload("res://scripts/Spawner.gd")
const Weather := preload("res://scripts/Weather.gd")
const Lighting := preload("res://scripts/Lighting.gd")
const CarVisual := preload("res://scripts/CarVisual.gd")
const Paints := preload("res://scripts/Paints.gd")
const UI := preload("res://scripts/UIKit.gd")
const Achievements := preload("res://scripts/Achievements.gd")
const DrawHook := preload("res://scripts/DrawHook.gd")

var world: Node2D
var entities: Node2D
var spawner: Node
var hero: Node2D
var hero_lane: int = 1
var _t: float = 0.0
var _racer_t: float = 1.5
var _menu_bottom: float = 628.0 # fim da coluna de botões (para o fundo escuro)
var _fs_btn: Button

func _ready() -> void:
	get_tree().paused = false
	GameManager.stop_run()
	GameManager.end_turns()
	GameManager.cruise_speed = 520.0
	GameManager.speed = 520.0
	AudioManager.quiet_ui()
	AudioManager.play_music("menu")

	world = World.new()
	world.follow_game = false
	world.day_night = true
	world.distance_scale = 5.0
	world.distance_m = randi_range(0, GameManager.biomes.size() - 1) * GameManager.BIOME_LENGTH + 200.0
	add_child(world)

	entities = Node2D.new()
	add_child(entities)
	spawner = Spawner.new()
	spawner.container = entities
	spawner.spawn_coins = false
	spawner.spawn_powerups = false
	add_child(spawner)

	var car := GameManager.selected_car()
	hero = CarVisual.new()
	Paints.apply(hero, car)
	hero.position = Vector2(GameManager.LANES[1], 655)
	add_child(hero)

	var weather := Weather.new()
	weather.world = world
	add_child(weather)
	var lighting := Lighting.new()
	lighting.world = world
	lighting.hero = hero
	add_child(lighting)

	_build_ui()
	Achievements.check_all(self)

func _process(delta: float) -> void:
	_t += delta
	hero_lane = GameManager.ai_pick_lane(hero_lane, hero.position.y)
	var diff: float = GameManager.LANES[hero_lane] - hero.position.x
	hero.position.x += diff * clamp(delta * 9.0, 0.0, 1.0)
	hero.rotation = lerp(hero.rotation, clamp(diff * 0.012, -0.25, 0.25), 0.25)
	# o jogador pode sair da tela cheia pelo navegador (Esc), então confere sempre
	_fs_btn.text = "TELA CHEIA: " + ("ON" if UI.is_fullscreen() else "OFF")

	_racer_t -= delta
	if _racer_t <= 0.0:
		_racer_t = randf_range(2.5, 5.0)
		var lanes := range(GameManager.lane_count)
		lanes.shuffle()
		for l in lanes:
			if l != hero_lane and _bottom_clear(l):
				spawner.spawn_racer(l)
				break

func _bottom_clear(l: int) -> bool:
	for t in get_tree().get_nodes_in_group("traffic"):
		if t.occupies_lane(l) and t.position.y > 420.0:
			return false
	return true

# ---------- interface ----------

func _build_ui() -> void:
	var root := UI.root(self)
	root.add_child(DrawHook.new(_draw_back))

	var ri := GameManager.rank_index(SaveManager.total_km())
	var rank: Dictionary = GameManager.ranks[ri]
	UI.label(root, String(rank["name"]).to_upper(), Vector2(56, 14), 18, rank["color"])
	UI.label(root, "%.1f km rodados" % SaveManager.total_km(), Vector2(56, 36), 13, Color(0.8, 0.85, 0.95))
	UI.label(root, str(SaveManager.coins()), Vector2(300, 20), 22, UI.GOLD, 160, HORIZONTAL_ALIGNMENT_RIGHT)

	var x := 120.0
	var w := 240.0
	var screens := [
		["MINIGAMES", "res://scenes/Minigames.tscn"],
		["MISSÕES", "res://scenes/Missions.tscn"],
		["GARAGEM", "res://scenes/Garage.tscn"],
		["RANKING", "res://scenes/Ranking.tscn"],
		["CONQUISTAS", "res://scenes/Achievements.tscn"],
		["ESTATÍSTICAS", "res://scenes/Stats.tscn"],
		["CRÉDITOS", "res://scenes/Credits.tscn"],
	]
	var buttons := [UI.button(root, "JOGAR", Rect2(x, 274, w, 48), _play, 24)]
	buttons[0].add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.3, 0.32, 0.9), UI.ACCENT, 10, 2))
	var y := 328.0
	for s in screens:
		var scene: String = s[1]
		buttons.append(UI.button(root, s[0], Rect2(x, y, w, 32), func(): UI.go(get_tree(), scene), 14))
		y += 35.0
	# no navegador "sair" não fecha nada, então só aparece no PC
	if not OS.has_feature("web"):
		buttons.append(UI.button(root, "SAIR", Rect2(x, y, w, 32), func(): get_tree().quit(), 14))
		y += 35.0
	_menu_bottom = y + 2.0

	# opções de som
	var music_btn := UI.button(root, "", Rect2(266, 56, 102, 30), func(): AudioManager.toggle_music(), 12)
	var sfx_btn := UI.button(root, "", Rect2(372, 56, 98, 30), func(): AudioManager.toggle_sfx(), 12)
	var refresh := func() -> void:
		music_btn.text = "MÚSICA: " + ("ON" if AudioManager.music_on() else "OFF")
		sfx_btn.text = "EFEITOS: " + ("ON" if AudioManager.sfx_on() else "OFF")
		music_btn.modulate.a = 1.0 if AudioManager.music_on() else 0.55
		sfx_btn.modulate.a = 1.0 if AudioManager.sfx_on() else 0.55
	music_btn.pressed.connect(refresh)
	sfx_btn.pressed.connect(refresh)
	refresh.call()
	_fs_btn = UI.button(root, "", Rect2(10, 56, 140, 30), UI.toggle_fullscreen, 12)
	buttons.append(_fs_btn)
	buttons.append(music_btn)
	buttons.append(sfx_btn)
	UI.chain_vertical(buttons)
	buttons[0].grab_focus()

	var car := GameManager.selected_car()
	UI.label(root, "Carro: %s" % car["name"], Vector2(0, _menu_bottom + 8), 14, Color(1, 1, 1, 0.75), 480, HORIZONTAL_ALIGNMENT_CENTER)
	UI.label(root, "Setas + ENTER  ou  mouse  •  F11 tela cheia", Vector2(0, 698), 12, Color(1, 1, 1, 0.45), 480, HORIZONTAL_ALIGNMENT_CENTER)

	if SaveManager.just_reset:
		SaveManager.just_reset = false
		var msg := UI.label(root, "PROGRESSO RESETADO", Vector2(0, 244), 20, UI.HOT, 480, HORIZONTAL_ALIGNMENT_CENTER)
		create_tween().tween_property(msg, "modulate:a", 0.0, 1.0).set_delay(2.5)

func _play() -> void:
	UI.go(get_tree(), "res://scenes/Game.tscn")

func _draw_back(ci: Control) -> void:
	# escurece o topo para o logo aparecer
	for i in range(30):
		ci.draw_rect(Rect2(0, i * 10, 480, 10), Color(0.02, 0.02, 0.05, 0.8 * (1.0 - i / 30.0)))
	ci.draw_rect(Rect2(100, 268, 280, _menu_bottom - 268), Color(0, 0, 0, 0.25))

	UI.draw_rank_badge(ci, Vector2(32, 34), 18, GameManager.rank_index(SaveManager.total_km()))
	UI.draw_coin(ci, Vector2(462 - UI.font().get_string_size(str(SaveManager.coins()), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x - 16, 34), 11)
	_draw_logo(ci)

func _draw_logo(ci: Control) -> void:
	var f := UI.font()
	var size := 60
	var a := "ZERO-"
	var b := "IMPACT"
	var wa := f.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var wb := f.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)

	# riscos de velocidade atrás do logo
	for i in range(7):
		var y := 112.0 + i * 11.0
		var x := fmod(_t * (500.0 + i * 70.0) + i * 130.0, 700.0) - 150.0
		ci.draw_line(Vector2(x, y), Vector2(x + 60 + i * 8, y), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.35), 2.0)

	ci.draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, -0.22, Vector2(240, 168)))
	var p := Vector2(-(wa + wb) * 0.5, 0)
	ci.draw_string_outline(f, p, a + b, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 22, Color(UI.HOT.r, UI.HOT.g, UI.HOT.b, 0.18 + 0.15 * pulse))
	ci.draw_string_outline(f, p, a + b, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(0, 0, 0, 0.9))
	ci.draw_string(f, p + Vector2(3, 4), a + b, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(UI.HOT.r, UI.HOT.g, UI.HOT.b, 0.8))
	ci.draw_string(f, p, a, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
	ci.draw_string(f, p + Vector2(wa, 0), b, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UI.ACCENT.lerp(Color.WHITE, 0.3 * pulse))
	ci.draw_rect(Rect2(p.x, 12, wa + wb, 4), UI.HOT)
	ci.draw_rect(Rect2(p.x, 12, (wa + wb) * (0.5 + 0.5 * sin(_t * 1.3)), 4), UI.ACCENT)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

	var sub := "A R C A D E   R A C I N G"
	var ws := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ci.draw_string(f, Vector2(240 - ws * 0.5, 210), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
