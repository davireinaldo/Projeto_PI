extends Node2D

# Controla o estado do jogo:
# MENU -> CAR_SELECT -> PLAYING -> GAME_OVER -> CAR_SELECT (de novo)
# Também spawna obstáculos/power-ups dentro das 3 faixas e atualiza a UI.

enum State { MENU, CAR_SELECT, PLAYING, GAME_OVER }

@export var obstacle_scene: PackedScene
@export var powerup_scene: PackedScene

var lane_xs: Array = [140.0, 240.0, 340.0]
var state: State = State.MENU

const ExplosionScene := preload("res://scenes/Explosion.tscn")

@onready var score_label: Label = $UI/ScoreLabel
@onready var speed_label: Label = $UI/SpeedLabel
@onready var menu_label: Label = $UI/MenuLabel
@onready var game_over_label: Label = $UI/GameOverLabel
@onready var car_select_title: Label = $UI/CarSelectTitle
@onready var car_select_high_score: Label = $UI/CarSelectHighScore
@onready var car_select_info: Label = $UI/CarSelectInfo
@onready var obstacle_timer: Timer = $ObstacleTimer
@onready var powerup_timer: Timer = $PowerUpTimer
@onready var car: CharacterBody2D = $Car
@onready var car_select: Node2D = $CarSelect

func _ready() -> void:
	GameManager.game_over_triggered.connect(_on_game_over)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.speed_changed.connect(_on_speed_changed)
	obstacle_timer.timeout.connect(_spawn_obstacle)
	powerup_timer.timeout.connect(_spawn_powerup)
	_enter_menu()

func _enter_menu() -> void:
	state = State.MENU
	menu_label.visible = true
	car_select.visible = false
	car_select_title.visible = false
	car_select_high_score.visible = false
	car_select_info.visible = false
	game_over_label.visible = false
	obstacle_timer.stop()
	powerup_timer.stop()
	car.visible = false
	get_tree().call_group("obstacles", "queue_free")
	get_tree().call_group("powerups", "queue_free")

func _enter_car_select() -> void:
	state = State.CAR_SELECT
	menu_label.visible = false
	game_over_label.visible = false
	car_select.visible = true
	car_select_title.visible = true
	car_select_high_score.visible = true
	car_select_info.visible = true
	car_select_high_score.text = "Melhor pontuação: %d" % int(GameManager.high_score)
	car_select.set_index(GameManager.selected_car)
	_update_car_select_info()

func _update_car_select_info() -> void:
	var def: Dictionary = GameManager.car_options[GameManager.selected_car]
	car_select_info.text = "%s\n%s\n\n◀ ▶  para trocar   —   ENTER para confirmar" % [def.name, def.description]

func _start_game() -> void:
	state = State.PLAYING
	car_select.visible = false
	car_select_title.visible = false
	car_select_high_score.visible = false
	car_select_info.visible = false
	game_over_label.visible = false
	car.visible = true
	car.reset()
	GameManager.reset_game()
	obstacle_timer.wait_time = 1.0
	obstacle_timer.start()
	powerup_timer.start()

func _spawn_obstacle() -> void:
	if state != State.PLAYING:
		return
	var obstacle := obstacle_scene.instantiate()
	var lane := randi() % lane_xs.size()
	obstacle.position = Vector2(lane_xs[lane], -50)
	add_child(obstacle)
	obstacle_timer.wait_time = clamp(1.1 - (GameManager.speed - GameManager.base_speed) / 900.0, 0.35, 1.1)

func _spawn_powerup() -> void:
	if state != State.PLAYING:
		return
	var powerup := powerup_scene.instantiate()
	var lane := randi() % lane_xs.size()
	powerup.position = Vector2(lane_xs[lane], -50)
	add_child(powerup)

func _on_score_changed(new_score: float) -> void:
	score_label.text = "Pontos: %d" % int(new_score)

func _on_speed_changed(new_speed: float) -> void:
	speed_label.text = "Velocidade: %d" % int(new_speed)

func _on_game_over() -> void:
	state = State.GAME_OVER
	game_over_label.visible = true
	obstacle_timer.stop()
	powerup_timer.stop()

	var explosion := ExplosionScene.instantiate()
	explosion.global_position = car.global_position
	add_child(explosion)
	car.visible = false

func _process(_delta: float) -> void:
	match state:
		State.MENU:
			if Input.is_action_just_pressed("ui_accept"):
				_enter_car_select()
		State.CAR_SELECT:
			if Input.is_action_just_pressed("ui_left") and GameManager.selected_car > 0:
				GameManager.selected_car -= 1
				car_select.set_index(GameManager.selected_car)
				_update_car_select_info()
			if Input.is_action_just_pressed("ui_right") and GameManager.selected_car < GameManager.car_options.size() - 1:
				GameManager.selected_car += 1
				car_select.set_index(GameManager.selected_car)
				_update_car_select_info()
			if Input.is_action_just_pressed("ui_accept"):
				_start_game()
		State.GAME_OVER:
			if Input.is_action_just_pressed("ui_accept"):
				_enter_car_select()
