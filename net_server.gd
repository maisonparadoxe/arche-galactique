extends Node
class_name NetServer
## Serveur réseau du prototype.
## - Sert la page manette (web/index.html) en HTTP sur HTTP_PORT.
## - Accepte les manettes en WebSocket sur WS_PORT.
## Les messages sont du JSON texte. Voir PROTOCOLE.md.

signal player_joined(peer_id: int, profile: Dictionary)
signal player_left(peer_id: int)
signal player_input(peer_id: int, axis: Vector2, buttons: Array)
signal player_action(peer_id: int, action: String)
signal player_rtt(peer_id: int, rtt_ms: int)
signal debug_requested(peer_id: int, msg: Dictionary)

const HTTP_PORT := 8080
const WS_PORT := 9080
const HANDSHAKE_TIMEOUT_MS := 3000
const HTTP_TIMEOUT_MS := 5000
const PAGE_PATH := "res://web/index.html"

var _http := TCPServer.new()
var _ws := TCPServer.new()
var _http_clients: Array[Dictionary] = []
var _peers: Dictionary = {}  # peer_id -> {ws, joined, born}
var _next_id := 1


func _ready() -> void:
	var e_http := _http.listen(HTTP_PORT)
	var e_ws := _ws.listen(WS_PORT)
	if e_http != OK:
		push_error("Impossible d'ouvrir le port HTTP %d (erreur %d)" % [HTTP_PORT, e_http])
	if e_ws != OK:
		push_error("Impossible d'ouvrir le port WebSocket %d (erreur %d)" % [WS_PORT, e_ws])
	print("[net] HTTP sur %d, WebSocket sur %d" % [HTTP_PORT, WS_PORT])


func _process(_delta: float) -> void:
	_poll_http()
	_poll_ws()


# ---------------------------------------------------------------- envoi

func send(peer_id: int, msg: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var ws: WebSocketPeer = _peers[peer_id]["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func kick(peer_id: int, msg: Dictionary) -> void:
	send(peer_id, msg)
	if _peers.has(peer_id):
		var ws: WebSocketPeer = _peers[peer_id]["ws"]
		ws.close(1000, "bye")


# ---------------------------------------------------------------- HTTP

func _poll_http() -> void:
	var now := Time.get_ticks_msec()
	while _http.is_connection_available():
		_http_clients.append({
			"conn": _http.take_connection(),
			"buf": PackedByteArray(),
			"born": now,
			"close_at": 0,
		})
	for c in _http_clients.duplicate():
		var conn: StreamPeerTCP = c["conn"]
		conn.poll()
		if c["close_at"] > 0:
			# On laisse le temps aux données de partir avant de fermer.
			if now >= c["close_at"]:
				conn.disconnect_from_host()
				_http_clients.erase(c)
			continue
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED or now - int(c["born"]) > HTTP_TIMEOUT_MS:
			conn.disconnect_from_host()
			_http_clients.erase(c)
			continue
		var n := conn.get_available_bytes()
		if n <= 0:
			continue
		var res: Array = conn.get_data(n)
		if res[0] != OK:
			continue
		var buf: PackedByteArray = c["buf"]
		buf.append_array(res[1])
		c["buf"] = buf
		var text := buf.get_string_from_utf8()
		if text.find("\r\n\r\n") != -1:
			_http_respond(conn, text)
			c["close_at"] = now + 1000


func _http_respond(conn: StreamPeerTCP, request: String) -> void:
	var first_line := request.get_slice("\r\n", 0)
	var path := first_line.get_slice(" ", 1)
	var status := "200 OK"
	var ctype := "text/html; charset=utf-8"
	var body: PackedByteArray
	var font_name := path.trim_prefix("/fonts/")
	if path == "/" or path == "/index.html" or path.begins_with("/?"):
		body = _load_page()  # relu à chaque requête : pratique pour itérer
	elif path.begins_with("/fonts/") and font_name.is_valid_filename() and font_name.ends_with(".ttf") \
			and FileAccess.file_exists("res://fonts/" + font_name):
		ctype = "font/ttf"
		body = FileAccess.get_file_as_bytes("res://fonts/" + font_name)
	else:
		status = "404 Not Found"
		ctype = "text/plain; charset=utf-8"
		body = "Introuvable".to_utf8_buffer()
	var head := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [status, ctype, body.size()]
	conn.put_data(head.to_utf8_buffer())
	conn.put_data(body)


func _load_page() -> PackedByteArray:
	var f := FileAccess.open(PAGE_PATH, FileAccess.READ)
	if f == null:
		return "<h1>Page manette introuvable</h1>".to_utf8_buffer()
	return f.get_buffer(f.get_length())


# ---------------------------------------------------------------- WebSocket

func _poll_ws() -> void:
	var now := Time.get_ticks_msec()
	while _ws.is_connection_available():
		var ws := WebSocketPeer.new()
		if ws.accept_stream(_ws.take_connection()) == OK:
			_peers[_next_id] = {"ws": ws, "joined": false, "born": now}
			_next_id += 1
	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					_handle(id, p, ws.get_packet().get_string_from_utf8())
			WebSocketPeer.STATE_CONNECTING:
				if now - int(p["born"]) > HANDSHAKE_TIMEOUT_MS:
					_drop(id)
			WebSocketPeer.STATE_CLOSED:
				_drop(id)


func _drop(id: int) -> void:
	if not _peers.has(id):
		return
	var was_joined: bool = _peers[id]["joined"]
	_peers.erase(id)
	if was_joined:
		player_left.emit(id)


func _handle(id: int, p: Dictionary, text: String) -> void:
	var msg = JSON.parse_string(text)
	if not (msg is Dictionary):
		return
	match str(msg.get("t", "")):
		"hello":
			if p["joined"]:
				return
			p["joined"] = true
			var player_name := str(msg.get("name", "")).strip_edges().left(12)
			if player_name == "":
				player_name = "Joueur %d" % id
			player_joined.emit(id, {
				"name": player_name,
				"token": str(msg.get("token", "")).left(64),
				"color": int(msg.get("color", -1)),
				"species": str(msg.get("species", "humain")),
				"ornament": str(msg.get("ornament", "aucun")),
			})
		"in":
			if not p["joined"]:
				return
			var axis := Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0))).limit_length(1.0)
			var raw = msg.get("b", [])
			var buttons: Array = [false, false, false, false]
			if raw is Array:
				for i in range(min(4, raw.size())):
					buttons[i] = bool(raw[i])
			player_input.emit(id, axis, buttons)
		"act":
			if p["joined"]:
				player_action.emit(id, str(msg.get("a", "")))
		"ping":
			send(id, {"t": "pong", "ts": msg.get("ts", 0)})
		"rtt":
			if p["joined"]:
				player_rtt.emit(id, int(msg.get("ms", -1)))
		"dbg", "dbg_tp":
			debug_requested.emit(id, msg)
