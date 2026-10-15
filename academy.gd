extends GameScene
## Académie galactique : le hub. Les joueurs rejoignent, s'entraînent,
## puis lancent une expédition depuis la table de commandement.

const GOLD := Art.GOLD
const GOLD_DIM := Art.GOLD_DIM
const COPPER := Art.COPPER
const IVORY := Art.IVORY
const SAGE := Art.SAGE
const TEAL := Art.TEAL
const CELL := Art.CELL
const WALL := Art.WALL
const SPEED := 300.0

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
const COMMAND_POS := Vector2(500, 648)     # table de commandement : lance une expédition
const COMMAND_ZONE := Rect2(370, 590, 260, 100)   # où l'on peut appuyer sur A pour partir
const SPAWN := Vector2(500, 505)
const NEAR := 60.0

var walls: Array[Rect2] = []

# ---------------------------------------------------------------- état des épreuves
var missions := {
	"feu": {"label": "Feu aux machines", "hint": "Maintiens B près du feu", "done": 0},
	"repa": {"label": "Réparer l'atelier", "hint": "Maintiens B près de la console", "done": 0},
	"cellule": {"label": "Cellule d'énergie", "hint": "X à la soute, puis X au réacteur", "done": 0},
	"reacteur": {"label": "Redémarrer le réacteur", "hint": "A sur chaque levier, à deux", "done": 0},
	"tir": {"label": "Stand de tir", "hint": "A pour s'installer, vise et tire", "done": 0},
}
var fire := {"active": true, "pos": Vector2(190, 300), "intensity": 100.0, "respawn_at": 0.0, "helpers": {}}
var repair := {"broken": true, "progress": 0.0, "respawn_at": 0.0, "helpers": {}}
var stand := {"user": 0, "cross": Vector2(860, 292), "targets": [], "respawn_at": 0.0, "beam": 0.0, "beam_to": Vector2.ZERO}
var reactor := {"hold": 0.0, "cooldown_until": 0.0, "flash": 0.0}
var socket_flash := 0.0
var floor_cells: Array = []           # cellules posées par terre
var floaters: Array = []              # textes flottants (« +1 médaille »)
var near_command: Dictionary = {}     # peer_id -> vrai si le joueur est sur la table de départ


func enter(_args: Dictionary) -> void:
	_build_walls()
	_spawn_targets()
	for p: Player in game.crew:
		_place(p)


func shows_players() -> bool:
	return true


func layout_for(p: Player) -> Dictionary:
	if p.seated:
		return {"t": "layout", "mode": "armes", "title": "Stand de tir", "weapons": [{"name": "Tirer", "charge": 1.0, "ready": true, "powered": true}]}
	return {"t": "layout", "mode": "base"}


func on_join(p: Player) -> void:
	_place(p)


func _place(p: Player) -> void:
	# une rangée en haut du Pont central, puis les côtés : la flèche de départ reste dégagée
	var spots := [Vector2(385, 495), Vector2(462, 495), Vector2(539, 495), Vector2(616, 495),
		Vector2(385, 570), Vector2(616, 570), Vector2(385, 630), Vector2(616, 630)]
	p.position = spots[p.slot % spots.size()]


func on_leave(p: Player) -> void:
	on_release(p)
	if p.carrying:
		p.carrying = false
		floor_cells.append(p.position)


func on_release(p: Player) -> void:
	if p.seated and stand["user"] == p.peer_id:
		stand["user"] = 0


func location_name(p: Player) -> String:
	for i in ROOMS.size():
		if _room_rect(i).has_point(p.position):
			return ROOMS[i]["name"]
	return ""


func on_action(p: Player, action: String, _msg: Dictionary) -> void:
	match action:
		"quit":
			_unseat(p)
		"fire":
			if p.seated and stand["user"] == p.peer_id:
				_shoot(p)


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


func debug_info(_p: Player) -> Dictionary:
	var done := {}
	for k in missions:
		done[k] = missions[k]["done"]
	return {"done": done, "fire": fire["intensity"], "fire_x": fire["pos"].x, "fire_y": fire["pos"].y, "repair": repair["progress"],
		"cross_x": stand["cross"].x, "cross_y": stand["cross"].y,
		"targets": stand["targets"].map(func(tg): return [tg["base"].x, tg["base"].y + sin(t * 1.6 + tg["phase"]) * 34, tg["alive"]])}


## Les médailles vont aux joueurs qui contrôlaient les membres ayant réussi l'épreuve.
func _award(mission: String, who: Array) -> void:
	missions[mission]["done"] += 1
	var credited := {}
	for p: Player in who:
		floaters.append({"pos": p.position + Vector2(0, -40), "text": "+1 médaille" if not p.is_free() else "Bravo !", "life": 1.4, "color": p.color})
		if p.is_free() or not game.people.has(p.peer_id) or credited.has(p.peer_id):
			continue
		credited[p.peer_id] = true
		var person: Dictionary = game.people[p.peer_id]
		person["medals"] += 1
		game.net.send(p.peer_id, {"t": "medal", "text": missions[mission]["label"], "medals": person["medals"]})


# ---------------------------------------------------------------- boucle

func update(delta: float) -> void:
	for p: Player in game.players.values():
		if p.seated:
			_update_stand(p, delta)
		else:
			_move(p, delta)
			_interact(p)
	_update_missions(delta)
	for f in floaters:
		f["life"] -= delta
		f["pos"] += Vector2(0, -30) * delta
	floaters = floaters.filter(func(f): return f["life"] > 0)


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


func _interact(p: Player) -> void:
	# A : table de commandement → lancer une expédition
	var on_table := COMMAND_ZONE.has_point(p.position)
	if on_table and not near_command.get(p.peer_id, false):
		game.net.send(p.peer_id, {"t": "toast", "text": "Appuie sur A pour lancer l'expédition !"})
		game.net.send(p.peer_id, {"t": "buzz"})
	near_command[p.peer_id] = on_table
	if p.pressed(0) and on_table:
		game.goto("choix")
		return
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
			game.net.send(p.peer_id, {"t": "buzz"})
		else:
			for c in floor_cells:
				if p.position.distance_to(c) < 45:
					floor_cells.erase(c)
					p.carrying = true
					game.net.send(p.peer_id, {"t": "buzz"})
					break



func _update_missions(delta: float) -> void:
	# --- Feu
	if fire["active"]:
		for p: Player in game.crew:
			var w := work_rate(p)
			if w > 0.0 and p.position.distance_to(fire["pos"]) < NEAR + 10:
				fire["intensity"] -= (70.0 if p.species == "salamandrin" else 35.0) * w * delta
				fire["helpers"][p.crew_id] = p
				p.working = p.is_free()
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
		for p: Player in game.crew:
			var w := work_rate(p)
			if w > 0.0 and p.position.distance_to(REPAIR_POS) < NEAR:
				repair["progress"] += (50.0 if p.species == "humain" else 25.0) * w * delta
				repair["helpers"][p.crew_id] = p
				p.working = p.is_free()
		if repair["progress"] >= 100:
			repair["broken"] = false
			repair["respawn_at"] = t + 8.0
			_award("repa", _alive(repair["helpers"]))
	elif t >= repair["respawn_at"]:
		repair = {"broken": true, "progress": 0.0, "respawn_at": 0.0, "helpers": {}}
	# --- Réacteur à deux
	var on_a: Player = null
	var on_b: Player = null
	for p: Player in game.crew:
		if work_rate(p, 0) <= 0.0:   # un membre libre posté sur un levier le tient tout seul
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
		var p: Player = helpers[id]
		if is_instance_valid(p) and p in game.crew:
			out.append(p)
	return out


func _seat(p: Player) -> void:
	stand["user"] = p.peer_id
	p.seated = true
	p.axis = Vector2.ZERO
	p.position = STAND_CONSOLE + Vector2(-34, 0)
	p.facing = Vector2.RIGHT
	game.net.send(p.peer_id, layout_for(p))


func _unseat(p: Player) -> void:
	if not p.seated:
		return
	p.seated = false
	if stand["user"] == p.peer_id:
		stand["user"] = 0
	game.net.send(p.peer_id, layout_for(p))


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
			game.net.send(p.peer_id, {"t": "buzz"})
			if stand["targets"].all(func(x): return not x["alive"]):
				stand["respawn_at"] = t + 3.0
				_award("tir", [p])
			return


# ---------------------------------------------------------------- dessin

func _room_rect(i: int) -> Rect2:
	var r: Dictionary = ROOMS[i]
	return Rect2(COLS[r["col"]], ROWS[r["row"]], COLS[r["col"] + 1] - COLS[r["col"]], ROWS[r["row"] + 1] - ROWS[r["row"]])


func _draw() -> void:
	_draw_header()
	_draw_ship()
	_draw_missions()
	_draw_command()
	_draw_board()
	for f in floaters:
		Art.title(self, f["pos"] + Vector2(-70, 0), f["text"], 20, Color(GOLD, clamp(f["life"], 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, 140)


func _draw_header() -> void:
	Art.title(self, Vector2(44, 62), "Académie galactique", 44)
	Art.title(self, Vector2(48, 92), "L'Arche galactique · salle d'entraînement", 20, Color(IVORY, 0.7))
	Art.text(self, Vector2(48, 134), "Scanne le code ou ouvre  %s  sur ton téléphone (même Wi-Fi)" % game.join_url, 16, Color(IVORY, 0.55))
	draw_line(Vector2(48, 104), Vector2(400, 104), Color(GOLD, 0.7), 1.5)
	draw_colored_polygon(PackedVector2Array([Vector2(224, 98), Vector2(230, 104), Vector2(224, 110), Vector2(218, 104)]), GOLD)
	draw_arc(Vector2(406, 98), 6, PI / 2, PI * 2.2, 16, Color(GOLD, 0.7), 1.5)
	if game.qr_texture:
		var qr_rect := Rect2(Vector2(1260 - 140, 12), Vector2(140, 140))
		draw_rect(qr_rect.grow(6), Color("#1a1420"))
		draw_texture_rect(game.qr_texture, qr_rect, false)
		Art.frame(self, qr_rect.grow(6), 0.6)


func _draw_ship() -> void:
	for i in ROOMS.size():
		draw_rect(_room_rect(i), ROOMS[i]["floor"])
	for x in range(int(HULL.position.x) + 40, int(HULL.end.x), 40):
		draw_line(Vector2(x, HULL.position.y), Vector2(x, HULL.end.y), Color(1, 1, 1, 0.025))
	for y in range(int(HULL.position.y) + 40, int(HULL.end.y), 40):
		draw_line(Vector2(HULL.position.x, y), Vector2(HULL.end.x, y), Color(1, 1, 1, 0.025))
	draw_rect(RANGE, Color("#141a1f"))
	for x in range(int(RANGE.position.x), int(RANGE.end.x), 22):
		draw_line(Vector2(x, RANGE.position.y), Vector2(x, RANGE.end.y), Color(TEAL, 0.15))
	for w in walls:
		draw_rect(w, WALL)
		draw_rect(w, GOLD_DIM, false, 1.0)
		for c in _wall_ends(w):
			draw_circle(c, 6.5, GOLD_DIM)
			draw_circle(c, 3.5, GOLD)
	for i in ROOMS.size():
		Art.title(self, _room_rect(i).position + Vector2(40, 30), ROOMS[i]["name"], 17, Color(IVORY, 0.45))
	Art.frame(self, HULL.grow(6), 1.0)


func _wall_ends(w: Rect2) -> Array:
	if w.size.x > w.size.y:
		return [Vector2(w.position.x, w.get_center().y), Vector2(w.end.x, w.get_center().y)]
	return [Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y)]


func _draw_command() -> void:
	# Table de commandement : grande, dorée, qui clignote, avec une flèche animée au-dessus
	var c := COMMAND_POS
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	var blink := fmod(t, 1.0) < 0.5
	# ondes qui s'élargissent depuis la table, comme un signal
	for k in 3:
		var u := fmod(t * 0.6 + k / 3.0, 1.0)
		draw_arc(c, 60 + u * 90, 0, TAU, 64, Color(GOLD, 0.35 * (1.0 - u)), 2.0)
	draw_circle(c, 80, Color(GOLD, 0.05 + pulse * 0.07))
	var table := Rect2(c - Vector2(120, 24), Vector2(240, 48))
	draw_rect(table.grow(4), Color(GOLD, 0.25 + 0.25 * pulse))
	draw_rect(table, Color("#241a12"))
	draw_rect(table, Art.IVORY if blink else GOLD, false, 3.0)
	for i in 9:
		draw_circle(c + Vector2(-96 + i * 24, 15 + sin(i * 1.7 + t * 2.0) * 2), 2.0, Art.CELL if i != 4 else GOLD)
	Art.title(self, table.position + Vector2(0, 27), "LANCER L'EXPÉDITION", 17, Art.IVORY if blink else GOLD, HORIZONTAL_ALIGNMENT_CENTER, table.size.x)
	# pastille « A » comme sur le téléphone
	var a := Vector2(table.end.x + 4, table.position.y + 2)
	draw_circle(a, 15, Color("#8fbf7a"))
	draw_arc(a, 15, 0, TAU, 24, GOLD, 2.0)
	Art.title(self, a + Vector2(-15, 7), "A", 19, Color("#140f0a"), HORIZONTAL_ALIGNMENT_CENTER, 30)
	# grosse flèche qui rebondit vers la table
	var bob := absf(sin(t * 4.0)) * 12.0
	var tip := Vector2(c.x, table.position.y - 6 - bob)
	var arrow := PackedVector2Array([
		tip, tip + Vector2(-30, -30), tip + Vector2(-12, -30), tip + Vector2(-12, -62),
		tip + Vector2(12, -62), tip + Vector2(12, -30), tip + Vector2(30, -30)])
	draw_colored_polygon(arrow, Color(GOLD, 0.85))
	arrow.append(arrow[0])
	draw_polyline(arrow, Art.IVORY if blink else Art.COPPER, 2.5, true)
	# bulle « A » au-dessus des joueurs qui sont sur la table
	for p: Player in game.players.values():
		if COMMAND_ZONE.has_point(p.position):
			var b := p.position + Vector2(0, -p.radius() - 26 - absf(sin(t * 6.0)) * 4)
			draw_circle(b, 13, Color("#8fbf7a"))
			draw_arc(b, 13, 0, TAU, 24, GOLD, 2.0)
			Art.title(self, b + Vector2(-13, 7), "A", 17, Color("#140f0a"), HORIZONTAL_ALIGNMENT_CENTER, 26)


func _draw_missions() -> void:
	if fire["active"]:
		Art.fire(self, fire["pos"], fire["intensity"], t)
		Art.progress_arc(self, fire["pos"], 40, 1.0 - fire["intensity"] / 100.0, SAGE)
	var cr := Rect2(REPAIR_POS - Vector2(26, 18), Vector2(52, 36))
	draw_rect(cr, Color("#1a1620"))
	draw_rect(cr, GOLD, false, 2.0)
	draw_circle(REPAIR_POS + Vector2(0, -2), 6, Art.DANGER if repair["broken"] else SAGE)
	if repair["broken"]:
		for i in 4:
			var a := fmod(t * 7.0 + i * 2.3, TAU)
			var o := REPAIR_POS + Vector2(cos(a), sin(a)) * 22
			draw_line(o, o + Vector2(cos(a * 3), sin(a * 3)) * 7, Color("#ffd27a"), 2.0)
		Art.progress_arc(self, REPAIR_POS, 44, repair["progress"] / 100.0, SAGE)
	for i in 3:
		var c := PILE_POS + Vector2(-16 + i * 16, 0)
		draw_rect(Rect2(c - Vector2(6, 11), Vector2(12, 22)), CELL)
		draw_rect(Rect2(c - Vector2(6, 11), Vector2(12, 22)), GOLD, false, 1.5)
	Art.text(self, PILE_POS + Vector2(-60, 30), "cellules", 12, Color(IVORY, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 120)
	for c in floor_cells:
		draw_rect(Rect2(c - Vector2(6, 11), Vector2(12, 22)), CELL)
	draw_circle(SOCKET_POS, 24 + socket_flash * 14, Color(CELL, 0.15 + socket_flash * 0.5))
	draw_arc(SOCKET_POS, 22, 0, TAU, 40, GOLD, 2.5)
	draw_arc(SOCKET_POS, 14, 0, TAU, 32, Color(GOLD, 0.6), 1.5)
	Art.text(self, SOCKET_POS + Vector2(-60, 42), "socle", 12, Color(IVORY, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 120)
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
	var core := (LEVER_A + LEVER_B) / 2 + Vector2(0, -60)
	draw_circle(core, 30 + reactor["flash"] * 20, Color(CELL, 0.08 + reactor["flash"] * 0.4))
	draw_arc(core, 26, 0, TAU, 48, GOLD if ready else GOLD_DIM, 2.5)
	draw_circle(core, 10 + 3 * sin(t * 2.0), Color(CELL, 0.5 if ready else 0.15))
	var sc := Rect2(STAND_CONSOLE - Vector2(14, 22), Vector2(28, 44))
	draw_rect(sc, Color("#1a1620"))
	draw_rect(sc, GOLD if stand["user"] == 0 else GOLD_DIM, false, 2.0)
	for tg in stand["targets"]:
		if tg["alive"]:
			var tp := _target_pos(tg)
			draw_circle(tp, 15, Color("#3a2f2a"))
			draw_arc(tp, 15, 0, TAU, 32, GOLD, 2.0)
			draw_circle(tp, 5, COPPER)
	if stand["user"] != 0 and game.players.has(stand["user"]):
		var shooter: Player = game.players[stand["user"]]
		var c: Vector2 = stand["cross"]
		var hr := 44.0 if shooter.species == "automate" else 24.0
		draw_crosshair(c, hr, shooter.color)
		if stand["beam"] > 0:
			draw_line(STAND_CONSOLE + Vector2(14, 0), stand["beam_to"], Color(shooter.color, stand["beam"] / 0.15), 3.0)


func draw_crosshair(c: Vector2, hr: float, col: Color) -> void:
	draw_arc(c, hr, 0, TAU, 40, Color(col, 0.8), 2.0)
	draw_line(c - Vector2(hr + 6, 0), c - Vector2(hr - 8, 0), col, 2.0)
	draw_line(c + Vector2(hr - 8, 0), c + Vector2(hr + 6, 0), col, 2.0)
	draw_line(c - Vector2(0, hr + 6), c - Vector2(0, hr - 8), col, 2.0)
	draw_line(c + Vector2(0, hr - 8), c + Vector2(0, hr + 6), col, 2.0)


func _draw_board() -> void:
	var r := Rect2(988, 172, 266, 518)
	Art.panel(self, r)
	var y := r.position.y + 38
	Art.title(self, Vector2(r.position.x + 18, y), "Épreuves", 26)
	y += 16
	for k in ["feu", "repa", "cellule", "reacteur", "tir"]:
		var m: Dictionary = missions[k]
		y += 30
		draw_circle(Vector2(r.position.x + 24, y - 5), 6, SAGE if m["done"] > 0 else Color(IVORY, 0.25))
		Art.text(self, Vector2(r.position.x + 38, y), m["label"], 15, IVORY, HORIZONTAL_ALIGNMENT_LEFT, 180)
		Art.text(self, Vector2(r.end.x - 52, y), "×%d" % m["done"], 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 36)
		y += 17
		Art.text(self, Vector2(r.position.x + 38, y), m["hint"], 12, Color(IVORY, 0.5), HORIZONTAL_ALIGNMENT_LEFT, 210)
	y += 40
	Art.title(self, Vector2(r.position.x + 18, y), "Médailles", 24)
	var ranked: Array = game.people.values()
	ranked.sort_custom(func(a, b): return a["medals"] > b["medals"])
	for who in ranked:
		y += 26
		if y > r.end.y - 12:
			break
		draw_circle(Vector2(r.position.x + 24, y - 5), 7, who["color"])
		Art.text(self, Vector2(r.position.x + 38, y), who["name"], 15, IVORY, HORIZONTAL_ALIGNMENT_LEFT, 150)
		Art.text(self, Vector2(r.end.x - 52, y), str(who["medals"]), 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 36)
	if game.people.is_empty():
		Art.text(self, Vector2(r.position.x + 18, y + 28), "En attente d'équipage…", 14, Color(IVORY, 0.45))
