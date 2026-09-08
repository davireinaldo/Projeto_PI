extends Node

# ---------- Carros selecionáveis ----------
# Cada carro tem uma cor e uma pequena característica de jogo diferente.
var car_options: Array = [
	{
		"name": "Turbo",
		"description": "Troca de faixa mais rápido.\nBom pra desviar de última hora.",
		"color": Color(0.85, 0.2, 0.2),
		"lane_speed": 15.0,
		"start_shield": 0.0
	},
	{
		"name": "Equilibrado",
		"description": "Sem vantagem nem desvantagem.\nO clássico, direto e confiável.",
		"color": Color(0.2, 0.6, 1.0),
		"lane_speed": 10.0,
		"start_shield": 0.0
	},
	{
		"name": "Blindado",
		"description": "Começa cada corrida com um\nescudo de 3 segundos de graça.",
		"color": Color(0.25, 0.75, 0.35),
		"lane_speed": 9.0,
		"start_shield": 3.0
	}
]
var selected_car: int = 1

# ---------- Estado global do jogo ----------
var score: float = 0.0
var high_score: float = 0.0
var speed: float = 300.0
var base_speed: float = 300.0
var max_speed: float = 900.0
var speed_increase_rate: float = 5.0 # o quanto a velocidade sobe por segundo
var game_over: bool = false
var shield_active: bool = false
var slow_mo_active: bool = false

const SAVE_PATH := "user://highscore.save"

signal game_over_triggered
signal score_changed(new_score)
signal speed_changed(new_speed)
signal high_score_changed(new_high_score)

func _ready() -> void:
	_load_high_score()
	reset_game()

func _load_high_score() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		high_score = f.get_float()
		f.close()
	else:
		high_score = 0.0

func _save_high_score() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_float(high_score)
	f.close()

func reset_game() -> void:
	score = 0.0
	speed = base_speed
	game_over = false
	shield_active = false
	slow_mo_active = false

func _process(delta: float) -> void:
	if game_over:
		return

	# aumenta a velocidade gradativamente até o limite máximo
	if speed < max_speed:
		speed += speed_increase_rate * delta
		speed_changed.emit(speed)

	# pontuação por sobrevivência (quanto mais rápido, mais pontos por segundo)
	score += delta * (10.0 + speed * 0.02)
	score_changed.emit(score)

func trigger_game_over() -> void:
	game_over = true
	if score > high_score:
		high_score = score
		_save_high_score()
		high_score_changed.emit(high_score)
	game_over_triggered.emit()

func activate_shield(duration: float) -> void:
	shield_active = true
	await get_tree().create_timer(duration).timeout
	shield_active = false

func activate_slow_mo(duration: float) -> void:
	if slow_mo_active:
		return
	slow_mo_active = true
	var old_speed := speed
	speed *= 0.5
	await get_tree().create_timer(duration).timeout
	speed = old_speed
	slow_mo_active = false
