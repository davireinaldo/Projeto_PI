extends CharacterBody2D

# Carro do jogador: se move entre 3 faixas fixas (troca de faixa ao
# apertar esquerda/direita), com transição suave e leve inclinação.
# A cor e a característica (lane_change_speed / escudo inicial) vêm
# do carro escolhido na tela de seleção (GameManager.selected_car).

var lane_xs: Array = [140.0, 240.0, 340.0]
var current_lane: int = 1
var lane_change_speed: float = 10.0

func _ready() -> void:
	reset()

func reset() -> void:
	current_lane = 1
	position = Vector2(lane_xs[current_lane], 600)
	rotation = 0.0

	var def: Dictionary = GameManager.car_options[GameManager.selected_car]
	$Visual.set_color(def.color)
	lane_change_speed = def.lane_speed

	if def.get("start_shield", 0.0) > 0.0:
		GameManager.activate_shield(def.start_shield)

func _physics_process(delta: float) -> void:
	if GameManager.game_over:
		return

	if Input.is_action_just_pressed("ui_left") and current_lane > 0:
		current_lane -= 1
	if Input.is_action_just_pressed("ui_right") and current_lane < lane_xs.size() - 1:
		current_lane += 1

	var target_x: float = lane_xs[current_lane]
	var diff: float = target_x - position.x
	position.x += diff * clamp(delta * lane_change_speed, 0.0, 1.0)
	rotation = lerp(rotation, clamp(diff * 0.012, -0.25, 0.25), 0.25)

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("obstacles"):
		if GameManager.shield_active:
			area.queue_free()
		else:
			GameManager.trigger_game_over()
	elif area.is_in_group("powerups"):
		area.apply_effect()
		area.queue_free()
