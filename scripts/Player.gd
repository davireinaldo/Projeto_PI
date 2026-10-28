extends Area2D

# Carro do jogador: troca entre 3 faixas (setas, A/D, deslizar o dedo/mouse
# para o lado ou tocar na metade esquerda/direita da tela), com transição
# suave e inclinação.
# Os atributos vêm do carro selecionado na garagem.
# No versus (pid 1 ou 2) cada um tem os próprios controles e o Versus.gd
# cuida do toque na tela e decide cada troca de faixa (on_steer), que é
# onde entra o empurrão.

const CarVisual := preload("res://scripts/CarVisual.gd")
const PlayerFX := preload("res://scripts/PlayerFX.gd")
const Paints := preload("res://scripts/Paints.gd")
const Achievements := preload("res://scripts/Achievements.gd")
const FX := preload("res://scripts/FX.gd")

signal crashed(other: Area2D)
signal coin_picked(coin: Area2D)
signal power_picked(power: Area2D)
signal hazard_hit(obstacle: Area2D)
signal steered
signal turbo_started

# quanto o dedo precisa andar na horizontal para contar como "deslizar"
const SWIPE_MIN := 40.0
const JUMP_DURATION := 0.85
const JUMP_COOLDOWN := 15.0

var lane: int = 1
var pid: int = 0 # 0 = corrida normal; 1 ou 2 = jogador do versus
var car_id: String = "" # carro do versus ("" = o selecionado na garagem)
var on_steer: Callable # versus: (player, dir) -> true se já cuidou da troca
var lane_speed: float = 10.0
var car: Dictionary
var visual: Node2D
var history: Array = [] # posições x recentes (rastro da câmera lenta)
var ice_time: float = 0.0 # no gelo a troca de faixa fica lenta e o carro derrapa
var length: float = 54.0
var has_jump: bool = false
var has_turbo: bool = false
var turbo_cooldown: float = 0.0 # segundos até poder usar o nitro do Uno de novo
var is_jumping: bool = false
var jump_timer: float = 0.0
var jump_cooldown: float = 0.0
var _jump_smoke_t: float = 0.0
var _touch_start: Variant = null # onde o dedo/mouse encostou (null = solto)
var _swiped: bool = false
var _t: float = 0.0

func _ready() -> void:
	add_to_group("player")
	car = GameManager.car_by_id(car_id) if car_id != "" else GameManager.selected_car()
	lane_speed = car["lane_speed"]
	# no versus os poderes ficam de fora (o nitro e o rádio mexem na pista toda)
	has_jump = bool(car.get("has_jump", false)) and pid == 0
	has_turbo = bool(car.get("turbo", false)) and pid == 0
	position = Vector2(GameManager.LANES[lane], GameManager.PLAYER_Y)

	var trail := PlayerFX.new()
	trail.player = self
	trail.mode = "trail"
	trail.z_index = -1
	add_child(trail)

	visual = CarVisual.new()
	Paints.apply(visual, car)
	add_child(visual)

	var bubble := PlayerFX.new()
	bubble.player = self
	bubble.mode = "bubble"
	bubble.z_index = 16 # o escudo brilha por cima da escuridão da noite
	add_child(bubble)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(28, 54)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	_t += delta
	if jump_cooldown > 0.0:
		jump_cooldown = max(jump_cooldown - delta, 0.0)
	if turbo_cooldown > 0.0:
		turbo_cooldown = max(turbo_cooldown - delta, 0.0)
	if is_jumping:
		jump_timer -= delta
		_jump_smoke_t -= delta
		if _jump_smoke_t <= 0.0:
			_jump_smoke_t = 0.05
			var parent := get_parent()
			if is_instance_valid(parent):
				FX.burst(parent, global_position + Vector2(randf_range(-12, 12), 20), Color(0.92, 0.96, 1.0, 0.8), 12, 150.0, 0.45, 6.0, 60.0)
				FX.burst(parent, global_position + Vector2(randf_range(-8, 8), 16), Color(0.3, 0.85, 1.0, 0.7), 8, 130.0, 0.35, 4.5, 40.0)
		if jump_timer <= 0.0:
			_land_jump()
	if pid > 0:
		if Input.is_action_just_pressed("p%d_left" % pid):
			_steer(-1)
		if Input.is_action_just_pressed("p%d_right" % pid):
			_steer(1)
	elif GameManager.debug_autopilot:
		lane = GameManager.ai_pick_lane(lane, position.y)
	else:
		if Input.is_action_just_pressed("steer_left"):
			_steer(-1)
		if Input.is_action_just_pressed("steer_right"):
			_steer(1)
		if Input.is_action_just_pressed("horn"):
			_blow_horn()
		if Input.is_action_just_pressed("jump") and has_jump:
			try_jump()
		if has_turbo and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("gol_radio")):
			try_turbo()

	var target_x: float = GameManager.LANES[lane]
	var diff: float = target_x - position.x
	var ls := lane_speed
	var wobble := 0.0
	if ice_time > 0.0:
		ice_time -= delta
		ls *= 0.3
		wobble = sin(_t * 14.0) * 0.12 * clamp(ice_time, 0.0, 1.0)
	position.x += diff * clamp(delta * ls, 0.0, 1.0)
	rotation = lerp(rotation, clamp(diff * 0.012, -0.25, 0.25) + wobble, 0.25)
	if pid <= 1:
		GameManager.player_pos = position

	history.push_front(position.x)
	if history.size() > 8:
		history.pop_back()

	# pisca enquanto está invencível depois de perder uma vida
	visual.modulate.a = 0.35 if GameManager.grace_time > 0.0 and fmod(_t, 0.16) < 0.08 else 1.0

func _steer(dir: int) -> void:
	if on_steer.is_valid() and on_steer.call(self, dir):
		return
	var new_lane: int = clamp(lane + dir, 0, GameManager.lane_count - 1)
	if new_lane != lane:
		AudioManager.play("whoosh", -4.0, 0.12)
		steered.emit()
	lane = new_lane

func _blow_horn() -> void:
	AudioManager.play_horn()
	if is_instance_valid(visual):
		var tw := create_tween()
		tw.tween_property(visual, "modulate", Color(1.3, 1.3, 1.3), 0.06)
		tw.tween_property(visual, "modulate", Color.WHITE, 0.08)

func occupies_lane(l: int) -> bool:
	return abs(position.x - GameManager.LANES[l]) < 55.0 or lane == l

# Cada deslize (swipe) move exatamente 1 faixa. Para mudar 2 faixas, o jogador
# faz 2 swipes separados (levantando o dedo). Deslizar para cima aciona o pulo do Roadster.
# Um toque rápido, sem deslizar, vale o lado da tela.
# O toque do celular chega aqui como mouse (emulação padrão do Godot).
func _unhandled_input(event: InputEvent) -> void:
	if pid > 0:
		return # no versus o toque é do Versus.gd (metade da tela de cada um)
	if GameManager.game_over or get_tree().paused:
		_touch_start = null
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_start = event.position
			_swiped = false
		elif _touch_start != null:
			if not _swiped:
				var delta: Vector2 = event.position - _touch_start
				if delta.y <= -SWIPE_MIN and abs(delta.y) > abs(delta.x):
					if has_jump:
						try_jump()
					if has_turbo:
						try_turbo()
				else:
					_steer(-1 if event.position.x < get_viewport_rect().size.x * 0.5 else 1)
			_touch_start = null
	elif event is InputEventMouseMotion and _touch_start != null:
		if not _swiped:
			var dx: float = event.position.x - _touch_start.x
			var dy: float = event.position.y - _touch_start.y
			if dy <= -SWIPE_MIN and abs(dy) > abs(dx):
				if has_jump:
					try_jump()
				if has_turbo:
					try_turbo()
				_swiped = true
			elif abs(dx) >= SWIPE_MIN and abs(dx) >= abs(dy):
				_steer(1 if dx > 0.0 else -1)
				_swiped = true

func try_jump() -> bool:
	if not has_jump or is_jumping or jump_cooldown > 0.0 or GameManager.game_over:
		return false
	is_jumping = true
	jump_timer = JUMP_DURATION
	jump_cooldown = JUMP_COOLDOWN
	_jump_smoke_t = 0.0
	AudioManager.play("jump", 0.0)

	var parent := get_parent()
	if is_instance_valid(parent):
		FX.burst(parent, global_position + Vector2(0, 16), Color(0.96, 0.98, 1.0, 0.95), 45, 320.0, 0.7, 7.5)
		FX.burst(parent, global_position + Vector2(0, 22), Color(0.25, 0.85, 1.0, 0.85), 35, 270.0, 0.55, 6.0)
		FX.burst(parent, global_position + Vector2(-15, 8), Color(1, 1, 1, 0.85), 24, 230.0, 0.5, 5.0)
		FX.burst(parent, global_position + Vector2(15, 8), Color(1, 1, 1, 0.85), 24, 230.0, 0.5, 5.0)
		FX.burst(parent, global_position + Vector2(0, 26), Color(0.75, 0.8, 0.85, 0.65), 30, 170.0, 0.9, 9.0, 40.0)

	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector2(1.35, 1.35), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var count := int(SaveManager.data.get("roadster_jumps", 0)) + 1
	SaveManager.data["roadster_jumps"] = count
	SaveManager.save()
	if count >= 5:
		Achievements.unlock("roadster_jump", get_tree().current_scene)
	return true

# Poder do Fiat Uno: o nitro normal (o mesmo do item), um a cada 20 s.
func try_turbo() -> bool:
	if not has_turbo or turbo_cooldown > 0.0 or GameManager.game_over or not GameManager.running:
		return false
	turbo_cooldown = GameManager.TURBO_EVERY
	GameManager.activate_nitro(GameManager.power_duration("nitro"))
	AudioManager.play("power_nitro", 2.0, 0.0, 0.85)
	var parent := get_parent()
	if is_instance_valid(parent):
		FX.burst(parent, global_position + Vector2(0, 30), Color(1, 0.55, 0.1, 0.95), 50, 340.0, 0.6, 6.0)
		FX.burst(parent, global_position + Vector2(0, 34), Color(1, 0.9, 0.4, 0.9), 30, 260.0, 0.5, 4.5)
	turbo_started.emit()
	return true

func _land_jump() -> void:
	is_jumping = false
	visual.scale = Vector2.ONE
	AudioManager.play("bump", -4.0, 0.08)
	var parent := get_parent()
	if is_instance_valid(parent):
		FX.burst(parent, global_position + Vector2(0, 10), Color(0.95, 0.95, 0.98, 0.85), 32, 220.0, 0.5, 6.5)
		FX.burst(parent, global_position + Vector2(0, 14), Color(0.35, 0.85, 1.0, 0.65), 20, 180.0, 0.4, 5.0)

# Chamado pelo próprio obstáculo quando encosta no carro.
func hit_obstacle(o: Area2D) -> void:
	if GameManager.game_over or is_jumping:
		return
	if o.is_solid():
		crashed.emit(o)
	else:
		hazard_hit.emit(o)

# pulinho do carro ao passar num buraco
func bump() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(visual, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _on_area_entered(a: Area2D) -> void:
	if GameManager.game_over or a.is_in_group("obstacles"):
		return
	if a.is_in_group("traffic"):
		if not is_jumping:
			if a.kind == "racer" and a.position.y > position.y - 15.0:
				a.position.y = position.y + 50.0
				a.rel_speed = 0.0
				return
			crashed.emit(a)
	elif a.is_in_group("coins"):
		coin_picked.emit(a)
	elif a.is_in_group("powerups"):
		power_picked.emit(a)
