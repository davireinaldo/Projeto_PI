extends Node

# Ranking online (autoload): manda o recorde de cada jogador para uma
# tabela no Supabase (banco de dados grátis) e busca o top 10 mundial.
# Enquanto SUPABASE_URL e SUPABASE_KEY estiverem vazios, fica desligado
# e o jogo usa só o ranking local. Como criar a tabela: LEIA-ME.txt.
#
# Cada jogador tem uma linha só na tabela (pelo "online_id" salvo no PC),
# atualizada quando ele bate o próprio recorde ou troca de nome.

const SUPABASE_URL := "https://ixpbonhwmscfukdabxxw.supabase.co"
const SUPABASE_KEY := "sb_publishable_xx_ZnZQEgb6zCQvLjSjpRg_qLaCEa3v" # chave pública (pode ficar no jogo)
const TABLE := "scores"
const NAME_MAX := 12

signal top_loaded(ok: bool, list: Array)
signal submitted # recorde ou nome chegou no servidor

var _sending := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # termina os envios até com o jogo pausado
	submit_best() # recorde que não foi enviado da última vez (estava sem internet)

func enabled() -> bool:
	return SUPABASE_URL != "" and SUPABASE_KEY != ""

func player_name() -> String:
	return String(SaveManager.data["online_name"])

func set_player_name(n: String) -> void:
	SaveManager.data["online_name"] = n.strip_edges().left(NAME_MAX)
	SaveManager.save()
	submit_best()

# Melhor corrida solo guardada no PC. As corridas do modo por turnos também
# entram no top local (com o nome de quem jogou) e não contam aqui.
func _best() -> Dictionary:
	for e in SaveManager.data["top"]:
		if String(e.get("name", "")) == "":
			return e
	return {}

# Envia o recorde se ele subiu (ou o nome mudou) desde o último envio.
# A pontuação online nunca baixa: depois de um reset só troca o nome.
func submit_best() -> void:
	if not enabled() or _sending or player_name() == "":
		return
	var best := _best()
	var score := int(best.get("score", 0))
	var sent := int(SaveManager.data["online_sent"])
	var name_changed := player_name() != String(SaveManager.data["online_sent_name"])
	if score <= sent and not (name_changed and sent > 0):
		return
	if String(SaveManager.data["online_id"]) == "":
		SaveManager.data["online_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
		SaveManager.save()
	var id := String(SaveManager.data["online_id"])
	var sent_name := player_name()
	var url := "%s/rest/v1/%s?on_conflict=id" % [SUPABASE_URL, TABLE]
	var method := HTTPClient.METHOD_POST
	var body := ""
	if score > sent:
		body = JSON.stringify({
			"id": id,
			"name": sent_name,
			"score": score,
			"km": float(best["km"]),
			"car": String(best["car"]),
		})
	else:
		url = "%s/rest/v1/%s?id=eq.%s" % [SUPABASE_URL, TABLE, id]
		method = HTTPClient.METHOD_PATCH
		body = JSON.stringify({"name": sent_name})
		score = sent
	_sending = true
	_request(url, method, body,
		func(ok: bool, _text: String) -> void:
			_sending = false
			if ok:
				SaveManager.data["online_sent"] = score
				SaveManager.data["online_sent_name"] = sent_name
				SaveManager.save()
				submitted.emit()
				submit_best() # o nome pode ter mudado durante o envio
	)

# Busca o top 10; a resposta chega pelo sinal top_loaded.
func fetch_top() -> void:
	if not enabled():
		top_loaded.emit(false, [])
		return
	var url := "%s/rest/v1/%s?select=name,score,km,car&order=score.desc&limit=10" % [SUPABASE_URL, TABLE]
	_request(url, HTTPClient.METHOD_GET, "", func(ok: bool, text: String) -> void:
		var parsed: Variant = JSON.parse_string(text) if ok else null
		top_loaded.emit(parsed is Array, parsed if parsed is Array else []))

func _request(url: String, method: int, body: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	# na web o navegador já descompacta a resposta; com isso ligado o Godot
	# tentava descompactar de novo, dava erro e o top 10 não carregava
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		http.queue_free()
		done.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, bytes.get_string_from_utf8()))
	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Content-Type: application/json",
		"Prefer: resolution=merge-duplicates,return=minimal",
	])
	# a chave antiga (anon) é um JWT e também vai no Authorization
	if SUPABASE_KEY.begins_with("eyJ"):
		headers.append("Authorization: Bearer " + SUPABASE_KEY)
	if http.request(url, headers, method, body) != OK:
		http.queue_free()
		done.call(false, "")
