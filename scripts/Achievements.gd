extends RefCounted

# Sistema de Conquistas Permanentes (Achievements) do ZERO-IMPACT.
# As conquistas desbloqueadas ficam salvas em SaveManager.data["achievements"].

const UI := preload("res://scripts/UIKit.gd")

const LIST := [
	{
		"id": "first_run",
		"title": "Primeira Marcha",
		"desc": "Complete sua primeira corrida na pista.",
		"icon": "🏁"
	},
	{
		"id": "combo_10",
		"title": "Mestre dos Raspões",
		"desc": "Atinja um combo x10 de raspão.",
		"icon": "⚡"
	},
	{
		"id": "garage_3",
		"title": "Colecionador",
		"desc": "Tenha pelo menos 3 carros na Garagem.",
		"icon": "🚗"
	},
	{
		"id": "max_upgrade",
		"title": "Tunado ao Extremo",
		"desc": "Eleve qualquer melhoria ao nível 5 na Oficina.",
		"icon": "🔧"
	},
	{
		"id": "clean_3km",
		"title": "Piloto Imune",
		"desc": "Percorra 3 km seguidos sem bater.",
		"icon": "🛡️"
	},
	{
		"id": "roadster_jump",
		"title": "Asa Espacial",
		"desc": "Realize 5 pulos com o novo Roadster.",
		"icon": "🚀"
	},
	{
		"id": "storm_survivor",
		"title": "Olho do Furacão",
		"desc": "Sobreviva a 3 tempestades de areia no total.",
		"icon": "🌪️"
	},
	{
		"id": "coins_5000",
		"title": "Cofre Cheio",
		"desc": "Acumule 5.000 moedas ganhas no total.",
		"icon": "💰"
	},
	{
		"id": "legend_rank",
		"title": "Lenda do Asfalto",
		"desc": "Alcance a patente máxima de Lenda (150 km).",
		"icon": "👑"
	},
]

static func all() -> Array:
	return LIST

static func def(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}

static func is_unlocked(id: String) -> bool:
	var unlocked: Array = SaveManager.data.get("achievements", [])
	return id in unlocked

static func unlock(id: String, parent_node: Node = null) -> bool:
	if is_unlocked(id):
		return false
	var unlocked: Array = SaveManager.data.get("achievements", [])
	unlocked.append(id)
	SaveManager.data["achievements"] = unlocked
	SaveManager.save()
	var d := def(id)
	if parent_node != null and not d.is_empty():
		show_toast(parent_node, d)
	return true

# Exibe o banner animado de conquista no topo da tela
static func show_toast(parent_node: Node, d: Dictionary) -> void:
	AudioManager.play("ui_buy", 0.0, 0.0)
	var cl := CanvasLayer.new()
	cl.layer = 95
	parent_node.add_child(cl)

	var panel := Panel.new()
	panel.theme = UI.theme()
	panel.add_theme_stylebox_override("panel", UI.style(Color(0.04, 0.12, 0.1, 0.96), Color(0.2, 0.95, 0.5), 12, 2))
	panel.custom_minimum_size = Vector2(400, 64)
	panel.size = Vector2(400, 64)
	panel.position = Vector2(40, -80)
	cl.add_child(panel)

	UI.label(panel, "%s  CONQUISTA DESBLOQUEADA!" % d.get("icon", "🏆"), Vector2(16, 8), 13, Color(0.2, 0.95, 0.5))
	UI.label(panel, String(d["title"]).to_upper(), Vector2(16, 26), 18, Color.WHITE)
	UI.label(panel, String(d["desc"]), Vector2(16, 44), 11, Color(0.8, 0.85, 0.9))

	var tw := cl.create_tween()
	tw.tween_property(panel, "position:y", 24.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(panel, "position:y", -90.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(cl.queue_free)

# Checa condições de desbloqueio com base no estado do jogo
static func check_all(parent_node: Node = null) -> void:
	var runs := int(SaveManager.data.get("runs", 0))
	if runs >= 1:
		unlock("first_run", parent_node)

	var owned: Array = SaveManager.data.get("owned", [])
	if owned.size() >= 3:
		unlock("garage_3", parent_node)

	var total_coins := int(SaveManager.data.get("total_coins_earned", 0))
	if total_coins >= 5000:
		unlock("coins_5000", parent_node)

	var total_km := SaveManager.total_km()
	if total_km >= 150.0:
		unlock("legend_rank", parent_node)

	var upg: Dictionary = SaveManager.data.get("upgrades", {})
	for k in upg.keys():
		if int(upg[k]) >= 5:
			unlock("max_upgrade", parent_node)
			break

	var jump_count := int(SaveManager.data.get("roadster_jumps", 0))
	if jump_count >= 5:
		unlock("roadster_jump", parent_node)
