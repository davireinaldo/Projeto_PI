extends CPUParticles2D

# Efeito de explosão simples ao bater. Se autodestrói depois de tocar.

func _ready() -> void:
	emitting = true
	await get_tree().create_timer(lifetime + 0.3).timeout
	queue_free()
