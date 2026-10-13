extends Node2D
## Académie galactique : salle d'entraînement de L'Arche galactique.
## Le vaisseau ne bouge pas ; les joueurs passent les épreuves dans six salles.

# ---------------------------------------------------------------- palette Art nouveau
const BG := Color("#0f0d16")
const GOLD := Color("#d4a64a")
const GOLD_DIM := Color("#8a6a33")
const COPPER := Color("#b8734a")
const IVORY := Color("#f2e8d5")
const SAGE := Color("#9caf88")
const TEAL := Color("#2a6f73")
const CELL := Color("#5fd4c4")
const WALL := Color("#4a3d33")

const PALETTE := [
	Color("#e8a33d"), Color("#3fb0a8"), Color("#d0603f"), Color("#9bc07a"),
	Color("#e08fae"), Color("#7d97e0"), Color("#f2e8d5"), Color("#62c6e6"),
]
const SPECIES := {
	"humain": "Répare deux fois plus vite",
	"automate": "Visée assistée au stand de tir",
	"salamandrin": "Éteint les feux deux fois plus vite",
	"colosse": "Porte les charges sans ralentir",
}
const ORNAMENTS := ["aucun", "fleur", "plume", "couronne"]
const MAX_PLAYERS := 8
const SPEED := 300.0
const INPUT_STALE_MS := 500

# ---------------------------------------------------------------- plan du vaisseau
const HULL := Rect2(40, 160, 920, 530)
const COLS := [40.0, 347.0, 653.0, 960.0]
const ROWS := [160.0, 425.0, 690.0]
const DOOR := 84.0
const WALL_T := 10.0
const ROOMS := [
	{"name": "Salle des machines", "col": 0, "row": 0, "floor": Color("#2b2128")},
	{"name": "Atelier", "col": 1, "row": 0, "floor": Color("#26232c")},
	{"name": "Stand de tir", "col": 2, "row": 0, "floor": Color("#21262b")},
	{"name": "Soute", "col": 0, "row": 1, "floor": Color("#28241f")},
	{"name": "Pont central", "col": 1, "row": 1, "floor": Color("#24212d")},
	{"name": "Réacteur", "col": 2, "row": 1, "floor": Color("#1f2729")},
]
const RANGE := Rect2(774, 174, 176, 240)   # zone des cibles, derrière la balustrade
const STAND_CONSOLE := Vector2(722, 292)
const REPAIR_POS := Vector2(500, 250)
const PILE_POS := Vector2(100, 630)
const SOCKET_POS := Vector2(900, 480)
const LEVER_A := Vector2(712, 640)
const LEVER_B := Vector2(900, 640)
const SPAWN := Vector2(500, 560)
const NEAR := 60.0

var net: NetServer
var players: Dictionary = {}          # peer_id -> Player
var profiles_by_token: Dictionary = {} # token -> emplacement, pour retrouver sa couleur
var walls: Array[Rect2] = []
var join_url := ""
var qr_texture: Texture2D
var title_font: Font
var stars: Array = []
var test_mode := false
var t := 0.0

# ---------------------------------------------------------------- état des épreuves
var missions := {
	"feu": {"label": "Feu aux machines", "hint": "Maintiens B près du feu", "done": 0, "last": ""},
	"repa": {"label": "Réparer l'atelier", "hint": "Maintiens B près de la console", "done": 0, "last": ""},
	"cellule": {"label": "Cellule d'énergie", "hint": "X à la soute, puis X au réacteur", "done": 0, "last": ""},
	"reacteur": {"label": "Redémarrer le réacteur", "hint": "À deux : A sur chaque levier", "done": 0, "last": ""},
	"tir": {"label": "Stand de tir", "hint": "A pour s'installer, vise et tire", "done": 0, "last": ""},
}
var fire := {"active": true, "pos": Vector2(190, 300), "intensity": 100.0, "respawn_at": 0.0, "helpers": {}}
var repair := {"broken": true, "progress": 0.0, "respawn_at": 0.0, "helpers": {}}
var stand := {"user": 0, "cross": Vector2(860, 292), "targets": [], "respawn_at": 0.0, "beam": 0.0, "beam_to": Vector2.ZERO}
var reactor := {"hold": 0.0, "cooldown_until": 0.0, "flash": 0.0}
var socket_flash := 0.0
var floor_cells: Array = []           # cellules posées par terre
var floaters: Array = []              # textes flottants (« +1 médaille »)


func _ready() -> void:
	test_mode = "--test" in OS.get_cmdline_user_args()
	RenderingServer.set_default_clear_color(BG)
	title_font = load("res://fonts/Federant-Regular.ttf")
	_build_walls()
	_spawn_targets()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		stars.append([Vector2(rng.randf() * 1280, rng.randf() * 720), rng.randf_range(0.6, 1.8), rng.randf()])
	net = NetServer.new()
	add_child(net)
	net.player_joined.connect(_on_joined)
	net.player_left.connect(_on_left)
	net.player_input.connect(_on_input)
	net.player_action.connect(_on_action)
	net.player_rtt.connect(func(id, ms): if players.has(id): players[id].rtt = ms)
	net.debug_requested.connect(_on_debug)
	join_url = "http://%s:%d" % [_local_ip(), NetServer.HTTP_PORT]
	var matrix := QR.encode(join_url)
	if not matrix.is_empty():
		qr_texture = ImageTexture.create_from_image(QR.to_image(matrix, 4, Color("#1a1420"), IVORY))
	print("[main] Les téléphones rejoignent sur ", join_url)


func _build_walls() -> void:
	var door_y := [(ROWS[0] + ROWS[1]) / 2, (ROWS[1] + ROWS[2]) / 2]
	for x in [COLS[1], COLS[2]]:
		for r in 2:
			var y0: float = ROWS[r]
			var y1: float = ROWS[r + 1]
			walls.append(Rect2(x - WALL_T / 2, y0, WALL_T, door_y[r] - DOOR / 2 - y0))
			walls.append(Rect2(x - WALL_T / 2, door_y[r] + DOOR / 2, WALL_T, y1 - door_y[r] - DOOR / 2))
	var door_x := [(COLS[0] + COLS[1]) / 2, (COLS[1] + COLS[2]) / 2, 705.0]
	var x0: float = COLS[0]
	for d in door_x:
		walls.append(Rect2(x0, ROWS[1] - WALL_T / 2, d - DOOR / 2 - x0, WALL_T))
		x0 = d + DOOR / 2
	walls.append(Rect2(x0, ROWS[1] - WALL_T / 2, COLS[3] - x0, WALL_T))
	# balustrade du stand de tir
	walls.append(Rect2(RANGE.position.x - 8, ROWS[0], 5, ROWS[1] - ROWS[0]))


func _spawn_targets() -> void:
	stand["targets"] = []
	for i in 3:
		stand["targets"].append({"base": Vector2(RANGE.position.x + 40 + i * 48, RANGE.position.y + 50 + i * 70), "phase": i * 2.1, "alive": true})


# ---------------------------------------------------------------- joueurs

func _on_joined(id: int, profile: Dictionary) -> void:
	if players.size() >= MAX_PLAYERS:
		net.kick(id, {"t": "full"})
		return
	var used := {}
	for p in players.values():
		used[p.slot] = true
	var wanted: int = profile["color"]
	if wanted < 0 and profiles_by_token.has(profile["token"]):
		wanted = profiles_by_token[profile["token"]]
	var slot := -1
	if wanted >= 0 and wanted < MAX_PLAYERS and not used.has(wanted):
		slot = wanted
	else:
		for i in range(MAX_PLAYERS):
			var c := (maxi(wanted, 0) + i) % MAX_PLAYERS
			if not used.has(c):
				slot = c
				break
	if profile["token"] != "":
		profiles_by_token[profile["token"]] = slot
	var p := Player.new()
	p.peer_id = id
	p.slot = slot
	p.token = profile["token"]
	p.player_name = profile["name"]
	p.color = PALETTE[slot]
	p.species = profile["species"] if SPECIES.has(profile["species"]) else "humain"
	p.ornament = profile["ornament"] if profile["ornament"] in ORNAMENTS else "aucun"
	p.position = SPAWN + Vector2(-90 + (slot % 4) * 60, -40 + (slot / 4) * 70)
	p.last_input_ms = Time.get_ticks_msec()
	players[id] = p
	add_child(p)
	net.send(id, {"t": "welcome", "slot": slot, "color": "#" + p.color.to_html(false), "name": p.player_name,
		"species": p.species, "ability": SPECIES[p.species]})
	net.send(id, {"t": "layout", "mode": "base"})
	if slot != wanted and wanted >= 0:
		net.send(id, {"t": "toast", "text": "Couleur déjà prise : on t'en a donné une autre."})
	print("[main] %s (%s) a rejoint" % [p.player_name, p.species])


func _on_left(id: int) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	if stand["user"] == id:
		stand["user"] = 0
	if p.carrying:
		floor_cells.append(p.position)
	print("[main] %s est parti" % p.player_name)
	players.erase(id)
	p.queue_free()


func _on_input(id: int, axis: Vector2, buttons: Array) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	p.axis = axis
	p.buttons = buttons
	p.last_input_ms = Time.get_ticks_msec()


func _on_action(id: int, action: String) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	match action:
		"quit":
			_unseat(p)
		"fire":
			if p.seated and stand["user"] == id:
				_shoot(p)


func _on_debug(id: int, msg: Dictionary) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	if msg.get("t") == "dbg_tp" and test_mode:
		p.position = Vector2(float(msg.get("x", 0)), float(msg.get("y", 0)))
	var done := {}
	for k in missions:
		done[k] = missions[k]["done"]
	net.send(id, {"t": "dbg", "x": p.position.x, "y": p.position.y, "seated": p.seated, "carrying": p.carrying,
		"medals": p.medals, "done": done, "fire": fire["intensity"], "fire_x": fire["pos"].x, "fire_y": fire["pos"].y, "repair": repair["progress"],
		"cross_x": stand["cross"].x, "cross_y": stand["cross"].y,
		"targets": stand["targets"].map(func(tg): return [tg["base"].x, tg["base"].y + sin(t * 1.6 + tg["phase"]) * 34, tg["alive"]])})


func _award(mission: String, who: Array) -> void:
	missions[mission]["done"] += 1
	var names: Array = []
	for p: Player in who:
		p.medals += 1
		names.append(p.player_name)
		floaters.append({"pos": p.position + Vector2(0, -40), "text": "+1 médaille", "life": 1.4, "color": p.color})
		net.send(p.peer_id, {"t": "medal", "text": missions[mission]["label"], "medals": p.medals})
	missions[mission]["last"] = " & ".join(names)


# ---------------------------------------------------------------- boucle

func _process(delta: float) -> void:
	t += delta
	_maybe_screenshot()
	var now := Time.get_ticks_msec()
	for p: Player in players.values():
		if now - p.last_input_ms > INPUT_STALE_MS:
			p.axis = Vector2.ZERO
		if p.seated:
			_update_stand(p, delta)
		else:
			_move(p, delta)
			_interact(p, delta)
	_update_missions(delta)
	for p: Player in players.values():
		p.prev_buttons = p.buttons.duplicate()
	for f in floaters:
		f["life"] -= delta
		f["pos"] += Vector2(0, -30) * delta
	floaters = floaters.filter(func(f): return f["life"] > 0)
	queue_redraw()


func _move(p: Player, delta: float) -> void:
	var speed := SPEED * (0.6 if p.carrying and p.species != "colosse" else 1.0)
	var r := p.radius()
	var step := p.axis * speed * delta
	for axis_i in 2:
		var old := p.position
		if axis_i == 0:
			p.position.x += step.x
		else:
			p.position.y += step.y
		var inner := HULL.grow(-r - 4)
		p.position = p.position.clamp(inner.position, inner.end)
		var box := Rect2(p.position - Vector2(r, r), Vector2(r, r) * 2)
		for w in walls:
			if w.intersects(box):
				p.position = old
				break


func _interact(p: Player, _delta: float) -> void:
	# A : s'installer au stand de tir
	if p.pressed(0) and stand["user"] == 0 and p.position.distance_to(STAND_CONSOLE) < NEAR:
		_seat(p)
		return
	# X : prendre / poser une cellule
	if p.pressed(2):
		if p.carrying:
			p.carrying = false
			if p.position.distance_to(SOCKET_POS) < NEAR:
				socket_flash = 1.0
				_award("cellule", [p])
			else:
				floor_cells.append(p.position + p.facing * 20)
		elif p.position.distance_to(PILE_POS) < NEAR:
			p.carrying = true
			net.send(p.peer_id, {"t": "buzz"})
		else:
			for c in floor_cells:
				if p.position.distance_to(c) < 45:
					floor_cells.erase(c)
					p.carrying = true
					net.send(p.peer_id, {"t": "buzz"})
					break
	# Y : changer de personnage (prochaine étape)
	if p.pressed(3):
		net.send(p.peer_id, {"t": "toast", "text": "Changer de personnage : à la prochaine étape !"})


func _update_missions(delta: float) -> void:
	# --- Feu
	if fire["active"]:
		for p: Player in players.values():
			if not p.seated and p.held(1) and p.position.distance_to(fire["pos"]) < NEAR + 10:
				fire["intensity"] -= (70.0 if p.species == "salamandrin" else 35.0) * delta
				fire["helpers"][p.peer_id] = p
		fire["intensity"] = min(100.0, fire["intensity"] + 4.0 * delta)  # le feu reprend doucement
		if fire["intensity"] <= 0:
			fire["active"] = false
			fire["respawn_at"] = t + 6.0
			_award("feu", _alive(fire["helpers"]))
	elif t >= fire["respawn_at"]:
		var room := _room_rect(0).grow(-50)
		fire = {"active": true, "intensity": 100.0, "respawn_at": 0.0, "helpers": {},
			"pos": Vector2(randf_range(room.position.x, room.end.x), randf_range(room.position.y, room.end.y))}
	# --- Réparation
	if repair["broken"]:
		for p: Player in players.values():
			if not p.seated and p.held(1) and p.position.distance_to(REPAIR_POS) < NEAR:
				repair["progress"] += (50.0 if p.species == "humain" else 25.0) * delta
				repair["helpers"][p.peer_id] = p
		if repair["progress"] >= 100:
			repair["broken"] = false
			repair["respawn_at"] = t + 8.0
			_award("repa", _alive(repair["helpers"]))
	elif t >= repair["respawn_at"]:
		repair = {"broken": true, "progress": 0.0, "respawn_at": 0.0, "helpers": {}}
	# --- Réacteur à deux
	var on_a: Player = null
	var on_b: Player = null
	for p: Player in players.values():
		if p.seated or not p.held(0):
			continue
		if p.position.distance_to(LEVER_A) < 45 and on_a == null:
			on_a = p
		elif p.position.distance_to(LEVER_B) < 45 and on_b == null:
			on_b = p
	if t >= reactor["cooldown_until"] and on_a != null and on_b != null:
		reactor["hold"] += delta
		if reactor["hold"] >= 2.0:
			reactor["hold"] = 0.0
			reactor["cooldown_until"] = t + 5.0
			reactor["flash"] = 1.0
			_award("reacteur", [on_a, on_b])
	else:
		reactor["hold"] = max(0.0, reactor["hold"] - delta * 2)
	reactor["a"] = on_a
	reactor["b"] = on_b
	reactor["flash"] = max(0.0, reactor["flash"] - delta)
	socket_flash = max(0.0, socket_flash - delta)
	# --- Stand de tir
	stand["beam"] = max(0.0, stand["beam"] - delta)
	if stand["targets"].all(func(tg): return not tg["alive"]) and t >= stand["respawn_at"]:
		_spawn_targets()


func _alive(helpers: Dictionary) -> Array:
	var out: Array = []
	for id in helpers:
		if players.has(id):
			out.append(players[id])
	return out


func _seat(p: Player) -> void:
	stand["user"] = p.peer_id
	p.seated = true
	p.axis = Vector2.ZERO
	p.position = STAND_CONSOLE + Vector2(-34, 0)
	p.facing = Vector2.RIGHT
	net.send(p.peer_id, {"t": "layout", "mode": "tir", "title": "Stand de tir"})


func _unseat(p: Player) -> void:
	if not p.seated:
		return
	p.seated = false
	if stand["user"] == p.peer_id:
		stand["user"] = 0
	net.send(p.peer_id, {"t": "layout", "mode": "base"})


func _update_stand(p: Player, delta: float) -> void:
	var c: Vector2 = stand["cross"] + p.axis * 380.0 * delta
	stand["cross"] = c.clamp(RANGE.position, RANGE.end)


func _target_pos(tg: Dictionary) -> Vector2:
	return tg["base"] + Vector2(0, sin(t * 1.6 + tg["phase"]) * 34)


func _shoot(p: Player) -> void:
	var hit_radius := 44.0 if p.species == "automate" else 24.0
	stand["beam"] = 0.15
	stand["beam_to"] = stand["cross"]
	for tg in stand["targets"]:
		if tg["alive"] and _target_pos(tg).distance_to(stand["cross"]) < hit_radius:
			tg["alive"] = false
			net.send(p.peer_id, {"t": "buzz"})
			if stand["targets"].all(func(x): return not x["alive"]):
				stand["respawn_at"] = t + 3.0
				_award("tir", [p])
			return


# ---------------------------------------------------------------- dessin

func _room_rect(i: int) -> Rect2:
	var r: Dictionary = ROOMS[i]
	return Rect2(COLS[r["col"]], ROWS[r["row"]], COLS[r["col"] + 1] - COLS[r["col"]], ROWS[r["row"] + 1] - ROWS[r["row"]])


func _draw() -> void:
	for s in stars:
		draw_circle(s[0], s[1], Color(IVORY, 0.25 + 0.25 * sin(t * 0.8 + s[2] * 10)))
	_draw_header()
	_draw_ship()
	_draw_missions()
	_draw_board()
	for f in floaters:
		draw_string(title_font, f["pos"] + Vector2(-70, 0), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 140, 20, Color(GOLD, clamp(f["life"], 0, 1)))


func _draw_header() -> void:
	draw_string(title_font, Vector2(44, 62), "Académie galactique", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, GOLD)
	draw_string(title_font, Vector2(48, 92), "L'Arche galactique · salle d'entraînement", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(IVORY, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(48, 134), "Scanne le code ou ouvre  %s  sur ton téléphone (même Wi-Fi)" % join_url, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(IVORY, 0.55))
	# filet doré sous le titre, terminé par deux volutes
	draw_line(Vector2(48, 104), Vector2(400, 104), Color(GOLD, 0.7), 1.5)
	draw_colored_polygon(PackedVector2Array([Vector2(224, 98), Vector2(230, 104), Vector2(224, 110), Vector2(218, 104)]), GOLD)
	draw_arc(Vector2(406, 98), 6, PI / 2, PI * 2.2, 16, Color(GOLD, 0.7), 1.5)
	if qr_texture:
		var qr_rect := Rect2(Vector2(1260 - 140, 12), Vector2(140, 140))
		draw_rect(qr_rect.grow(6), Color("#1a1420"))
		draw_texture_rect(qr_texture, qr_rect, false)
		_frame(qr_rect.grow(6), 0.6)


func _draw_ship() -> void:
	for i in ROOMS.size():
		draw_rect(_room_rect(i), ROOMS[i]["floor"])
	# carrelage discret
	for x in range(int(HULL.position.x) + 40, int(HULL.end.x), 40):
		draw_line(Vector2(x, HULL.position.y), Vector2(x, HULL.end.y), Color(1, 1, 1, 0.025))
	for y in range(int(HULL.position.y) + 40, int(HULL.end.y), 40):
		draw_line(Vector2(HULL.position.x, y), Vector2(HULL.end.x, y), Color(1, 1, 1, 0.025))
	# champ de tir
	draw_rect(RANGE, Color("#141a1f"))
	for x in range(int(RANGE.position.x), int(RANGE.end.x), 22):
		draw_line(Vector2(x, RANGE.position.y), Vector2(x, RANGE.end.y), Color(TEAL, 0.15))
	# murs et montants de porte en bronze
	for w in walls:
		draw_rect(w, WALL)
		draw_rect(w, GOLD_DIM, false, 1.0)
		for c in _wall_ends(w):
			draw_circle(c, 6.5, GOLD_DIM)
			draw_circle(c, 3.5, GOLD)
	# noms des salles
	for i in ROOMS.size():
		var rr := _room_rect(i)
		draw_string(title_font, rr.position + Vector2(40, 30), ROOMS[i]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(IVORY, 0.45))
	# coque : double filet doré et volutes aux angles
	_frame(HULL.grow(6), 1.0)


func _wall_ends(w: Rect2) -> Array:
	if w.size.x > w.size.y:
		return [Vector2(w.position.x, w.get_center().y), Vector2(w.end.x, w.get_center().y)]
	return [Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y)]


func _frame(r: Rect2, s: float) -> void:
	draw_rect(r, GOLD, false, 2.5 * s)
	draw_rect(r.grow(6 * s), Color(GOLD, 0.45), false, 1.0)
	_whiplash(r.position, 1, 1, s)
	_whiplash(Vector2(r.end.x, r.position.y), -1, 1, s)
	_whiplash(Vector2(r.position.x, r.end.y), 1, -1, s)
	_whiplash(r.end, -1, -1, s)


## Volute « coup de fouet » typique de l'Art nouveau, posée sur un angle.
func _whiplash(corner: Vector2, sx: float, sy: float, s: float) -> void:
	var pts := PackedVector2Array()
	var p0 := corner + Vector2(sx * 2, sy * 46) * s
	var p1 := corner + Vector2(sx * 4, sy * 10) * s
	var p2 := corner + Vector2(sx * 30, sy * 6) * s
	var p3 := corner + Vector2(sx * 22, sy * 22) * s
	for i in 17:
		var u := i / 16.0
		pts.append(p0.bezier_interpolate(p1, p2, p3, u))
	draw_polyline(pts, GOLD, 2.0 * s, true)
	draw_circle(p3, 3.5 * s, GOLD)
	var q := PackedVector2Array()
	var q0 := corner + Vector2(sx * 46, sy * 2) * s
	var q1 := corner + Vector2(sx * 14, sy * 3) * s
	var q2 := corner + Vector2(sx * 9, sy * 26) * s
	var q3 := corner + Vector2(sx * 18, sy * 16) * s
	for i in 17:
		q.append(q0.bezier_interpolate(q1, q2, q3, i / 16.0))
	draw_polyline(q, Color(GOLD, 0.7), 1.5 * s, true)


func _draw_missions() -> void:
	# Feu
	if fire["active"]:
		var k: float = 0.35 + 0.65 * fire["intensity"] / 100.0
		for i in 6:
			var a := t * 3.0 + i * 1.7
			var off := Vector2(cos(a) * 9, sin(a * 1.3) * 6 - i * 3) * k
			var col: Color = [Color("#ffcf5a"), Color("#ff8a3d"), Color("#e8452e")][i % 3]
			draw_circle(fire["pos"] + off, (22 - i * 2.5) * k * (0.9 + 0.1 * sin(t * 9 + i)), Color(col, 0.75))
		_progress_arc(fire["pos"], 40, 1.0 - fire["intensity"] / 100.0, SAGE)
	# Réparation
	var cr := Rect2(REPAIR_POS - Vector2(26, 18), Vector2(52, 36))
	draw_rect(cr, Color("#1a1620"))
	draw_rect(cr, GOLD, false, 2.0)
	draw_circle(REPAIR_POS + Vector2(0, -2), 6, Color("#e8452e") if repair["broken"] else SAGE)
	if repair["broken"]:
		for i in 4:
			var a := fmod(t * 7.0 + i * 2.3, TAU)
			var o := REPAIR_POS + Vector2(cos(a), sin(a)) * 22
			draw_line(o, o + Vector2(cos(a * 3), sin(a * 3)) * 7, Color("#ffd27a"), 2.0)
		_progress_arc(REPAIR_POS, 44, repair["progress"] / 100.0, SAGE)
	# Pile de cellules et socle
	for i in 3:
		var c := PILE_POS + Vector2(-16 + i * 16, 0)
		draw_rect(Rect2(c - Vector2(6, 11), Vector2(12, 22)), CELL)
		draw_rect(Rect2(c - Vector2(6, 11), Vector2(12, 22)), GOLD, false, 1.5)
	draw_string(ThemeDB.fallback_font, PILE_POS + Vector2(-60, 30), "cellules", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(IVORY, 0.5))
	for c in floor_cells:
		draw_rect(Rect2(c - Vector2(6, 11), Vector2(12, 22)), CELL)
	draw_circle(SOCKET_POS, 24 + socket_flash * 14, Color(CELL, 0.15 + socket_flash * 0.5))
	draw_arc(SOCKET_POS, 22, 0, TAU, 40, GOLD, 2.5)
	draw_arc(SOCKET_POS, 14, 0, TAU, 32, Color(GOLD, 0.6), 1.5)
	draw_string(ThemeDB.fallback_font, SOCKET_POS + Vector2(-60, 42), "socle", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(IVORY, 0.5))
	# Leviers du réacteur
	var ready: bool = t >= reactor["cooldown_until"]
	for pair in [[LEVER_A, reactor.get("a")], [LEVER_B, reactor.get("b")]]:
		var pos: Vector2 = pair[0]
		var who = pair[1]
		draw_rect(Rect2(pos - Vector2(16, 8), Vector2(32, 16)), Color("#1a1620"))
		draw_rect(Rect2(pos - Vector2(16, 8), Vector2(32, 16)), GOLD, false, 1.5)
		var ang := -0.6 if who != null else 0.6
		var tip := pos + Vector2(sin(ang), -cos(ang)) * 26
		draw_line(pos, tip, GOLD, 4.0)
		draw_circle(tip, 6, who.color if who != null else (COPPER if ready else Color(IVORY, 0.3)))
	if reactor["hold"] > 0:
		var w: float = (LEVER_B.x - LEVER_A.x - 60) * reactor["hold"] / 2.0
		draw_rect(Rect2(LEVER_A.x + 30, LEVER_A.y - 4, w, 8), CELL)
	draw_circle((LEVER_A + LEVER_B) / 2 + Vector2(0, -60), 30 + reactor["flash"] * 20, Color(CELL, 0.08 + reactor["flash"] * 0.4))
	draw_arc((LEVER_A + LEVER_B) / 2 + Vector2(0, -60), 26, 0, TAU, 48, GOLD if ready else GOLD_DIM, 2.5)
	draw_circle((LEVER_A + LEVER_B) / 2 + Vector2(0, -60), 10 + 3 * sin(t * 2.0), Color(CELL, 0.5 if ready else 0.15))
	# Stand de tir
	var sc := Rect2(STAND_CONSOLE - Vector2(14, 22), Vector2(28, 44))
	draw_rect(sc, Color("#1a1620"))
	draw_rect(sc, GOLD if stand["user"] == 0 else GOLD_DIM, false, 2.0)
	for tg in stand["targets"]:
		if tg["alive"]:
			var tp := _target_pos(tg)
			draw_circle(tp, 15, Color("#3a2f2a"))
			draw_arc(tp, 15, 0, TAU, 32, GOLD, 2.0)
			draw_circle(tp, 5, COPPER)
	if stand["user"] != 0 and players.has(stand["user"]):
		var shooter: Player = players[stand["user"]]
		var c: Vector2 = stand["cross"]
		var hr := 44.0 if shooter.species == "automate" else 24.0
		draw_arc(c, hr, 0, TAU, 40, Color(shooter.color, 0.8), 2.0)
		draw_line(c - Vector2(hr + 6, 0), c - Vector2(hr - 8, 0), shooter.color, 2.0)
		draw_line(c + Vector2(hr - 8, 0), c + Vector2(hr + 6, 0), shooter.color, 2.0)
		draw_line(c - Vector2(0, hr + 6), c - Vector2(0, hr - 8), shooter.color, 2.0)
		draw_line(c + Vector2(0, hr - 8), c + Vector2(0, hr + 6), shooter.color, 2.0)
		if stand["beam"] > 0:
			draw_line(STAND_CONSOLE + Vector2(14, 0), stand["beam_to"], Color(shooter.color, stand["beam"] / 0.15), 3.0)


func _progress_arc(center: Vector2, r: float, frac: float, col: Color) -> void:
	if frac <= 0.0:
		return
	draw_arc(center, r, -PI / 2, -PI / 2 + TAU * clamp(frac, 0, 1), 48, col, 4.0)


func _draw_board() -> void:
	var r := Rect2(988, 172, 266, 518)
	draw_rect(r, Color("#17131d"))
	_frame(r, 0.7)
	var y := r.position.y + 38
	draw_string(title_font, Vector2(r.position.x + 18, y), "Épreuves", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD)
	y += 16
	var f := ThemeDB.fallback_font
	for k in ["feu", "repa", "cellule", "reacteur", "tir"]:
		var m: Dictionary = missions[k]
		y += 30
		draw_circle(Vector2(r.position.x + 24, y - 5), 6, SAGE if m["done"] > 0 else Color(IVORY, 0.25))
		draw_string(f, Vector2(r.position.x + 38, y), m["label"], HORIZONTAL_ALIGNMENT_LEFT, 180, 15, IVORY)
		draw_string(f, Vector2(r.end.x - 52, y), "×%d" % m["done"], HORIZONTAL_ALIGNMENT_RIGHT, 36, 15, GOLD)
		y += 17
		draw_string(f, Vector2(r.position.x + 38, y), m["hint"], HORIZONTAL_ALIGNMENT_LEFT, 210, 12, Color(IVORY, 0.5))
	y += 40
	draw_string(title_font, Vector2(r.position.x + 18, y), "Médailles", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, GOLD)
	var ranked := players.values()
	ranked.sort_custom(func(a, b): return a.medals > b.medals)
	for p: Player in ranked:
		y += 26
		if y > r.end.y - 12:
			break
		draw_circle(Vector2(r.position.x + 24, y - 5), 7, p.color)
		draw_string(f, Vector2(r.position.x + 38, y), p.player_name, HORIZONTAL_ALIGNMENT_LEFT, 150, 15, IVORY)
		draw_string(f, Vector2(r.end.x - 52, y), str(p.medals), HORIZONTAL_ALIGNMENT_RIGHT, 36, 15, GOLD)
	if players.is_empty():
		draw_string(f, Vector2(r.position.x + 18, y + 28), "En attente d'équipage…", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(IVORY, 0.45))


# ---------------------------------------------------------------- utilitaires

## Tests : « -- --test --shot=/chemin.png --shot-at=6 » enregistre une capture de l'écran.
func _maybe_screenshot() -> void:
	if not test_mode:
		return
	var path := ""
	var at := 5.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-at="):
			at = float(a.trim_prefix("--shot-at="))
	if path != "" and t >= at and not has_meta("shot_done"):
		set_meta("shot_done", true)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		print("[test] capture enregistrée : ", path)


func _local_ip() -> String:
	var fallback := ""
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168."):
			return a
		if fallback == "" or a.begins_with("10."):
			fallback = a
	return fallback if fallback != "" else "127.0.0.1"
