extends Node

# Ranking online (autoload): manda o recorde de cada jogador para uma
# tabela no Supabase (banco de dados grátis) e busca o top 10 mundial.
# Enquanto SUPABASE_URL e SUPABASE_KEY estiverem vazios, fica desligado
# e o jogo usa só o ranking local. Como criar a tabela: LEIA-ME.txt.
#
# Cada jogador tem uma linha só na tabela (pelo "online_id" salvo no PC),
# atualizada quando ele bate o próprio recorde ou troca de nome.

const SUPABASE_URL := "" # ex.: "https://abcdefgh.supabase.co"
const SUPABASE_KEY := "" # a chave pública do projeto (anon / publishable)
const TABLE := "scores"
const NAME_MAX := 12

signal top_loaded(ok: bool, list: Array)

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

# Melhor corrida guardada no PC (o top 10 local já está ordenado por pontos).
func _best() -> Dictionary:
	var top: Array = SaveManager.data["top"]
	return top[0] if not top.is_empty() else {}

# Envia o recorde se ele (ou o nome) mudou desde o último envio.
func submit_best() -> void:
	var best := _best()
	if not enabled() or _sending or player_name() == "" or best.is_empty():
		return
	var score := int(best["score"])
	if score == int(SaveManager.data["online_sent"]) and player_name() == SaveManager.data["online_sent_name"]:
		return
	if String(SaveManager.data["online_id"]) == "":
		SaveManager.data["online_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
		SaveManager.save()
	var body := JSON.stringify({
		"id": SaveManager.data["online_id"],
		"name": player_name(),
		"score": score,
		"km": float(best["km"]),
		"car": String(best["car"]),
	})
	var sent_name := player_name()
	_sending = true
	_request("%s/rest/v1/%s?on_conflict=id" % [SUPABASE_URL, TABLE], HTTPClient.METHOD_POST, body,
		func(ok: bool, _text: String) -> void:
			_sending = false
			if ok:
				SaveManager.data["online_sent"] = score
				SaveManager.data["online_sent_name"] = sent_name
				SaveManager.save()
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
