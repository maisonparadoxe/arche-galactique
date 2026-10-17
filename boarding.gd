extends GameScene
## Abordage : tout l'équipage investit un navire marchand ou une île, salle après salle.
##
## Façon Hotline Miami : un coup tue (les ennemis comme les joueurs), les ennemis préviennent avant
## de frapper, on recommence vite. Un joueur à terre est relevé par un équipier proche.
## Le niveau dépasse la largeur de l'écran : la caméra suit le groupe, et personne ne peut sortir de
## l'image. Pour avancer, il faut donc rester ensemble : celui qui traîne retient tout le monde.
##
## Manette : joystick = déplacement ; A = coup d'épée ; B = pistolet (visée automatique) ; X = roulade.
## Les membres libres se battent seuls, un peu moins bien. Un joueur fait toujours mieux.

const CELL := 80.0
const TOP := 110.0                 # les salles commencent sous le bandeau
const VIEW := Vector2(1280, 720)
const MARGIN := 44.0               # distance minimale au bord de l'image
const CAM_SPEED := 430.0
const INTRO := 1.8
const END_DELAY := 4.5

const SPEED := 235.0
const AI_SPEED := 0.78
const ROLL_SPEED := 560.0
const ROLL_TIME := 0.24
const ROLL_COOLDOWN := 0.9
const SWING_REACH := 78.0
const SWING_COOLDOWN := 0.38
const AMMO_MAX := 3.0
const AMMO_REGEN := 0.45
const SHOOT_COOLDOWN := 0.22
const BULLET_SPEED := 720.0
const COMBO_WINDOW := 2.6
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 58.0
const RESPAWN_AFTER := 14.0
const RESCUE_AFTER := 18.0         # un joueur qui retient le groupe trop longtemps est ramené

const NEON_PINK := Color("#ff4d9d")
const NEON_CYAN := Color("#4dffe8")

var layout: ShipLayout
var def: Dictionary = {}
var layout_id := "galion"
var world := Rect2()
var cam := Vector2.ZERO
var shake := 0.0
var foes: Array = []
var bullets: Array = []
var chests: Array = []
var fx: Array = []
var stains: Array = []
var slashes: Array = []
var floaters: Array = []
var st: Dictionary = {}               # crew_id -> état du membre
var state := "intro"                  # intro, fight, won, lost
var end_at := -1.0
var kills := 0
var combo := 0
var combo_t := 0.0
var best_combo := 0
var score := 0
var loot := 0
var downs := 0
var blocked := Vector2.ZERO           # direction dans laquelle le groupe est retenu
var blocked_t := 0.0
var laggard: Player = null
var crowd := 1.0
var frozen := false                   # tests : les ennemis ne bougent plus
var enemy_charge := 1.0
var result_title := ""
var result_lines: Array = []


# ---------------------------------------------------------------- mise en place

func enter(args: Dictionary) -> void:
	if game.run == null:
		game.run = RunState.create("paikan", "normal")
	layout_id = str(args.get("layout", "galion"))
	if not ShipData.BOARDINGS.has(layout_id):
		layout_id = "galion"
	def = ShipData.BOARDINGS[layout_id]
	var maxx := 0
	var maxy := 0
	for r in def["layout"]["rooms"]:
		maxx = maxi(maxx, int(r["x"]) + int(r["w"]))
		maxy = maxi(maxy, int(r["y"]) + int(r["h"]))
	layout = ShipLayout.build(def["layout"], Rect2(Vector2(0, TOP), Vector2(maxx, maxy) * CELL), CELL)
	world = Rect2(Vector2.ZERO, Vector2(maxf(VIEW.x, layout.bounds.end.x + 60.0), maxf(VIEW.y, layout.bounds.end.y + 50.0)))
	var diff: Dictionary = game.run.diff
	var hull_k := float(diff.get("enemy_hull", 1.0))
	crowd = (0.55 + 0.12 * game.crew.size()) * (0.4 + 0.6 * hull_k)
	enemy_charge = float(diff.get("enemy_charge", 1.0))
	for sp in def["spawns"]:
		var room := layout.room(sp["room"])
		var n: int = int(sp["n"])
		if sp["type"] != "capitaine":
			n = maxi(1, int(round(float(n) * crowd)))
		for i in n:
			_spawn_foe(str(sp["type"]), layout.random_point(room, 58.0), hull_k)
	for c in def["chests"]:
		var rr: Rect2 = layout.room(c["room"])["rect"]
		var at: Array = c["at"]
		var amount: Array = c["scrap"]
		chests.append({"pos": rr.position + Vector2(rr.size.x * float(at[0]), rr.size.y * float(at[1])),
			"scrap": randi_range(int(amount[0]), int(amount[1])), "open": false, "big": bool(c.get("big", false))})
	var i := 0
	for p: Player in game.crew:
		_place(p, i)
		i += 1
	game.toast_all("À l'abordage ! Restez groupés : l'image n'avance que si personne ne traîne.")
	print("[abordage] %s : %d ennemis, %d coffres" % [layout_id, foes.size(), chests.size()])


func exit() -> void:
	game.position = Vector2.ZERO


func _spawn_foe(type: String, pos: Vector2, hull_k: float) -> void:
	var fd: Dictionary = ShipData.BOARDING_FOES[type]
	var hp: int = int(fd["hp"])
	if type == "capitaine":
		hp = maxi(2, int(round(float(hp) * hull_k)))
	foes.append({"type": type, "pos": pos, "hp": hp, "hp_max": hp, "radius": float(fd["radius"]), "face": Vector2.LEFT,
		"state": "move", "timer": 0.0, "dir": Vector2.LEFT, "cool": randf_range(0.2, 1.2), "aware": false, "react": 0.0,
		"anim": randf() * 6.0, "flash": 0.0, "fan_t": 2.0, "strafe": 1.0 if randf() < 0.5 else -1.0})


func _place(p: Player, i: int) -> void:
	var start: Rect2 = layout.room(def["start"])["rect"]
	p.position = start.get_center() + Vector2(-80 + (i % 3) * 80, -90 + (i / 3) * 76)
	p.downed = false
	p.revive_frac = 0.0
	p.facing = Vector2.RIGHT


func _s(p: Player) -> Dictionary:
	if not st.has(p.crew_id):
		st[p.crew_id] = {"revive": 0.0, "down_t": 0.0, "inv": 0.0, "roll": 0.0, "roll_dir": Vector2.RIGHT, "roll_cd": 0.0,
			"swing_cd": 0.0, "ammo": AMMO_MAX, "shoot_cd": 0.0, "edge_t": 0.0, "stuck": 0.0}
	return st[p.crew_id]


# ---------------------------------------------------------------- interface avec le jeu

func shows_players() -> bool:
	return true


func layout_for(_p: Player) -> Dictionary:
	return {"t": "layout", "mode": "base"}


func on_join(p: Player) -> void:
	var mem := _alive()
	if mem.is_empty():
		_place(p, game.crew.size())
	else:
		p.position = (mem[0] as Player).position + Vector2(40, 0)
		if not layout.is_walkable(p.position, p.radius()):
			p.position = (mem[0] as Player).position
	p.downed = false


func location_name(p: Player) -> String:
	if p.downed:
		return "À terre"
	var r := layout.room_at(p.position)
	return r.get("name", "") if not r.is_empty() else ""


func hints_for(p: Player) -> Dictionary:
	if state == "won" or state == "lost":
		return {}
	if p.downed:
		return {3: "Changer"}
	var s := _s(p)
	var n := int(floor(float(s["ammo"])))
	var h := {0: "Frapper", 1: "Tirer " + "●".repeat(n) + "○".repeat(int(AMMO_MAX) - n)}
	if float(s["roll_cd"]) <= 0.0:
		h[2] = "Roulade"
	return h


func _alive() -> Array:
	var out: Array = []
	for p: Player in game.crew:
		if not p.downed:
			out.append(p)
	return out


func _member_by_id(id: int) -> Player:
	for p: Player in game.crew:
		if p.crew_id == id:
			return p
	return null


# ---------------------------------------------------------------- boucle

func update(delta: float) -> void:
	if state == "intro" and t >= INTRO:
		state = "fight"
	if state == "intro" or state == "fight":
		for p: Player in game.crew:
			_update_member(p, delta)
		_revive(delta)
		if state == "fight" and not frozen:
			for f in foes:
				_update_foe(f, delta)
		_separate_foes()
		_update_bullets(delta)
		_update_chests()
		_check_end()
	_update_camera(delta)
	_update_effects(delta)
	if end_at > 0.0 and t >= end_at:
		end_at = -1.0
		game.node_done()


func _update_member(p: Player, delta: float) -> void:
	var s := _s(p)
	for k in ["inv", "roll", "roll_cd", "swing_cd", "shoot_cd"]:
		s[k] = maxf(0.0, float(s[k]) - delta)
	p.blink = float(s["inv"])
	s["ammo"] = minf(AMMO_MAX, float(s["ammo"]) + AMMO_REGEN * delta)
	if p.downed:
		s["down_t"] = float(s["down_t"]) + delta
		return
	if p.is_free():
		_ai(p, s, delta)
	else:
		_control(p, s, delta)
	_leash(p, s, delta)


func _control(p: Player, s: Dictionary, delta: float) -> void:
	if float(s["roll"]) > 0.0:
		_move(p, (s["roll_dir"] as Vector2) * ROLL_SPEED * delta)
	else:
		_move(p, p.axis * SPEED * delta)
		if p.pressed(2) and float(s["roll_cd"]) <= 0.0:
			var dir: Vector2 = p.axis.normalized() if p.axis.length() > 0.2 else p.facing
			s["roll_dir"] = dir
			s["roll"] = ROLL_TIME
			s["roll_cd"] = 0.55 if p.species == "salamandrin" else ROLL_COOLDOWN
			s["inv"] = maxf(float(s["inv"]), ROLL_TIME + 0.1)
			p.facing = dir
	if p.pressed(0) and float(s["swing_cd"]) <= 0.0:
		_swing(p, s, 1.0)
	if p.held(1) and float(s["shoot_cd"]) <= 0.0 and float(s["ammo"]) >= 1.0:
		_shoot(p, s, 1.0)


func _move(p: Player, step: Vector2) -> void:
	p.position = layout.move(p.position, step, p.radius())


## Personne ne sort de l'image : le plus rapide attend les autres au bord de l'écran.
func _leash(p: Player, s: Dictionary, delta: float) -> void:
	var lo := cam + Vector2(MARGIN, MARGIN)
	var hi := cam + VIEW - Vector2(MARGIN, MARGIN)
	var c := p.position.clamp(lo, hi)
	var over := p.position - c
	if over.length() > 0.0001:
		s["edge_t"] = float(s["edge_t"]) + delta
		s["edge"] = Vector2(signf(over.x) if absf(over.x) > 0.0001 else 0.0, signf(over.y) if absf(over.y) > 0.0001 else 0.0)
		if layout.is_walkable(c, p.radius()):
			p.position = c
	else:
		s["edge_t"] = maxf(0.0, float(s["edge_t"]) - delta * 2.0)


# ---------------------------------------------------------------- attaques

func _swing(p: Player, s: Dictionary, cd_mult: float) -> void:
	var reach := SWING_REACH * (1.25 if p.species == "colosse" else 1.0)
	var near := _nearest_foe(p.position, reach + 26.0)
	if not near.is_empty():
		p.facing = ((near["pos"] as Vector2) - p.position).normalized()   # petite aide : on se tourne vers l'ennemi
	s["swing_cd"] = SWING_COOLDOWN * cd_mult
	var dir: Vector2 = p.facing
	slashes.append({"pos": p.position, "dir": dir, "life": 0.2, "reach": reach, "col": p.color})
	for f in foes.duplicate():
		var to: Vector2 = (f["pos"] as Vector2) - p.position
		var d := to.length()
		if d <= reach + float(f["radius"]) and (d < 34.0 or dir.dot(to / maxf(d, 0.001)) > 0.2):
			_damage_foe(f, p)
	for b in bullets.duplicate():
		if bool(b["friendly"]):
			continue
		var tb: Vector2 = (b["pos"] as Vector2) - p.position
		if tb.length() <= reach and dir.dot(tb.normalized()) > 0.0:
			bullets.erase(b)
			_burst(b["pos"], 5, [NEON_CYAN, Art.IVORY], 120.0)


func _shoot(p: Player, s: Dictionary, cd_mult: float) -> void:
	var cone := deg_to_rad(100.0 if p.species == "automate" else 55.0)
	var best: Dictionary = {}
	var best_score := 1.0e9
	for f in foes:
		var to: Vector2 = (f["pos"] as Vector2) - p.position
		var d := to.length()
		if d > 720.0 or d < 1.0:
			continue
		var ang := absf(p.facing.angle_to(to))
		if ang > cone or not _clear_line(p.position, f["pos"]):
			continue
		var sc := ang * 300.0 + d
		if sc < best_score:
			best_score = sc
			best = f
	var dir: Vector2 = p.facing
	if not best.is_empty():
		dir = ((best["pos"] as Vector2) - p.position).normalized()
		p.facing = dir
	s["ammo"] = float(s["ammo"]) - 1.0
	s["shoot_cd"] = SHOOT_COOLDOWN * cd_mult
	bullets.append({"pos": p.position + dir * (p.radius() + 6.0), "vel": dir * BULLET_SPEED, "friendly": true, "life": 1.1, "owner": p.crew_id})
	_burst(p.position + dir * (p.radius() + 8.0), 3, [NEON_CYAN, Art.IVORY], 90.0)


func _damage_foe(f: Dictionary, by: Player) -> void:
	f["hp"] = int(f["hp"]) - 1
	f["flash"] = 0.12
	if int(f["hp"]) > 0:
		_burst(f["pos"], 5, [Art.IVORY, NEON_PINK], 130.0)
		shake = maxf(shake, 3.0)
		return
	foes.erase(f)
	kills += 1
	combo += 1
	combo_t = COMBO_WINDOW
	best_combo = maxi(best_combo, combo)
	var pts := 100 * combo
	score += pts
	_burst(f["pos"], 14, [Art.GOLD, Art.IVORY, NEON_PINK, NEON_CYAN], 220.0)
	stains.append({"pos": f["pos"], "r": randf_range(10.0, 18.0), "col": Color(NEON_PINK, 0.16)})
	if stains.size() > 70:
		stains.pop_front()
	floaters.append({"pos": (f["pos"] as Vector2) + Vector2(0, -26), "text": "+%d" % pts if combo < 2 else "×%d  +%d" % [combo, pts],
		"col": NEON_CYAN if combo >= 3 else Art.GOLD, "life": 1.1})
	shake = maxf(shake, 5.0)
	if f["type"] == "capitaine":
		chests.append({"pos": f["pos"], "scrap": randi_range(8, 12), "open": false, "big": false})
		game.toast_all("Le capitaine est à terre !")
	if by != null and not by.is_free():
		game.net.send(by.peer_id, {"t": "buzz"})


func _down(q: Player) -> void:
	var s := _s(q)
	q.downed = true
	q.revive_frac = 0.0
	s["revive"] = 0.0
	s["down_t"] = 0.0
	s["roll"] = 0.0
	downs += 1
	combo = 0
	combo_t = 0.0
	_burst(q.position, 12, [q.color, Art.IVORY], 200.0)
	shake = maxf(shake, 9.0)
	if not q.is_free():
		q.axis = Vector2.ZERO
		game.net.send(q.peer_id, {"t": "buzz"})
		game.net.send(q.peer_id, {"t": "toast", "text": "À terre ! Un équipier peut te relever, ou change de personnage (Y)."})


func _try_hit(q: Player) -> bool:
	var s := _s(q)
	if q.downed or float(s["inv"]) > 0.0 or float(s["roll"]) > 0.0:
		return false
	_down(q)
	return true


func _stand_up(p: Player, pos: Vector2) -> void:
	var s := _s(p)
	p.downed = false
	p.revive_frac = 0.0
	p.position = pos
	s["revive"] = 0.0
	s["inv"] = 1.6
	_burst(pos, 10, [Art.SAGE, Art.IVORY], 150.0)
	floaters.append({"pos": pos + Vector2(0, -30), "text": "Debout !", "col": Art.SAGE, "life": 1.2})


func _revive(delta: float) -> void:
	for d: Player in game.crew:
		if not d.downed:
			continue
		var s := _s(d)
		var rate := 0.0
		for h: Player in game.crew:
			if h == d or h.downed or h.position.distance_to(d.position) > REVIVE_RANGE:
				continue
			var k := 1.0 / REVIVE_TIME
			if h.species == "humain":
				k *= 2.0
			if h.is_free():
				k *= 0.5
			rate += k
		if rate > 0.0:
			s["revive"] = float(s["revive"]) + rate * delta
		else:
			s["revive"] = maxf(0.0, float(s["revive"]) - delta * 0.4)
		d.revive_frac = float(s["revive"])
		if float(s["revive"]) >= 1.0:
			_stand_up(d, d.position)
		elif float(s["down_t"]) > RESPAWN_AFTER:
			var ally := _nearest_member(d.position)
			if ally != null:
				var spot: Vector2 = ally.position + Vector2(44, 0)
				if not layout.is_walkable(spot, d.radius()):
					spot = ally.position
				_stand_up(d, spot)


# ---------------------------------------------------------------- équipage libre

func _ai(p: Player, s: Dictionary, delta: float) -> void:
	var goal := Vector2.INF
	var foe := _nearest_foe(p.position, 260.0, true)   # un membre libre réagit aux menaces, il ne chasse pas les ennemis endormis
	if not foe.is_empty() and state == "fight" and not frozen:
		var fp: Vector2 = foe["pos"]
		var d := p.position.distance_to(fp)
		if d < SWING_REACH * 0.85 and float(s["swing_cd"]) <= 0.0:
			_swing(p, s, 2.2)
		elif d > 110.0 and d < 520.0 and float(s["shoot_cd"]) <= 0.0 and float(s["ammo"]) >= 1.0 and _clear_line(p.position, fp):
			p.facing = (fp - p.position).normalized()
			_shoot(p, s, 5.0)
		if d > 66.0:
			goal = fp
	else:
		var hurt: Player = null
		var best_d := 1.0e9
		for q: Player in game.crew:
			if q.downed and q.position.distance_to(p.position) < best_d:
				best_d = q.position.distance_to(p.position)
				hurt = q
		if hurt != null:
			goal = hurt.position
		else:
			var lead := _nearest_controlled(p.position)
			if lead != null and p.position.distance_to(lead.position) > 140.0:
				goal = lead.position
	if goal != Vector2.INF:
		var wp := _waypoint(p.position, goal)
		var dir := wp - p.position
		if dir.length() > 6.0:
			dir = dir.normalized()
			_move(p, dir * SPEED * AI_SPEED * delta)
			p.facing = dir


func _nearest_controlled(pos: Vector2) -> Player:
	var best: Player = null
	var best_d := 1.0e9
	for q: Player in game.crew:
		if not q.downed and not q.is_free() and q.position.distance_to(pos) < best_d:
			best_d = q.position.distance_to(pos)
			best = q
	return best


func _nearest_member(pos: Vector2) -> Player:
	var best: Player = null
	var best_d := 1.0e9
	for q: Player in game.crew:
		if not q.downed and q.position.distance_to(pos) < best_d:
			best_d = q.position.distance_to(pos)
			best = q
	return best


func _nearest_foe(pos: Vector2, max_d: float, awake_only := false) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_d
	for f in foes:
		var d := pos.distance_to(f["pos"])
		if awake_only and not bool(f["aware"]) and d > 70.0:
			continue
		if d < best_d:
			best_d = d
			best = f
	return best


# ---------------------------------------------------------------- ennemis

func _update_foe(f: Dictionary, delta: float) -> void:
	var fd: Dictionary = ShipData.BOARDING_FOES[f["type"]]
	f["anim"] = float(f["anim"]) + delta
	f["flash"] = maxf(0.0, float(f["flash"]) - delta)
	var tgt := _nearest_member(f["pos"])
	if tgt == null:
		return
	var fp: Vector2 = f["pos"]
	var dist := fp.distance_to(tgt.position)
	if not bool(f["aware"]):
		var same_room: bool = layout.room_at(fp).get("id", "") == layout.room_at(tgt.position).get("id", "x")
		if dist < 190.0 or (same_room and dist < 430.0):
			f["aware"] = true
			f["react"] = 0.35
		else:
			return
	if float(f["react"]) > 0.0:
		f["react"] = float(f["react"]) - delta
		return
	f["cool"] = maxf(0.0, float(f["cool"]) - delta)
	var r: float = f["radius"]
	var speed: float = fd["speed"]
	var wind: float = float(fd["windup"]) * clampf(enemy_charge, 0.85, 1.6)
	var cooldown: float = float(fd["cooldown"]) * clampf(enemy_charge, 0.85, 1.6)
	var to_t: Vector2 = (tgt.position - fp).normalized()
	match f["state"]:
		"move":
			if f["type"] == "fusilier":
				var desired := Vector2.ZERO
				if dist < 190.0:
					desired = -to_t
				elif dist > 340.0:
					desired = (_waypoint(fp, tgt.position) - fp).normalized()
				else:
					desired = Vector2(-to_t.y, to_t.x) * float(f["strafe"]) * 0.6
				f["pos"] = layout.move(fp, desired * speed * delta, r)
				f["face"] = to_t
				if float(f["cool"]) <= 0.0 and dist < 560.0 and _clear_line(fp, tgt.position):
					f["state"] = "wind"
					f["timer"] = wind
					f["dir"] = to_t
			else:
				var reach: float = fd["reach"]
				if dist > reach * 0.75:
					var dir := (_waypoint(fp, tgt.position) - fp).normalized()
					f["pos"] = layout.move(fp, dir * speed * delta, r)
					f["face"] = dir if dist > reach * 2.0 else to_t
				else:
					f["face"] = to_t
				if dist <= reach * 0.92 and float(f["cool"]) <= 0.0 and _clear_line(fp, tgt.position):
					f["state"] = "wind"
					f["timer"] = wind
					f["dir"] = to_t
				elif f["type"] == "capitaine":
					f["fan_t"] = float(f["fan_t"]) - delta
					if float(f["fan_t"]) <= 0.0 and dist > 150.0 and dist < 560.0 and _clear_line(fp, tgt.position):
						f["state"] = "wind_fan"
						f["timer"] = wind * 1.6
						f["dir"] = to_t
		"wind":
			f["timer"] = float(f["timer"]) - delta
			if float(f["timer"]) <= 0.0:
				if f["type"] == "fusilier":
					_foe_fire(f, f["dir"], float(fd["bullet"]))
				else:
					_foe_strike(f, float(fd["reach"]))
				f["state"] = "recover"
				f["timer"] = 0.4
				f["cool"] = cooldown
		"wind_fan":
			f["timer"] = float(f["timer"]) - delta
			if float(f["timer"]) <= 0.0:
				for a in [-0.32, 0.0, 0.32]:
					_foe_fire(f, (f["dir"] as Vector2).rotated(a), float(fd["bullet"]))
				f["fan_t"] = float(fd.get("fan_every", 3.6)) * clampf(enemy_charge, 0.85, 1.6)
				f["state"] = "recover"
				f["timer"] = 0.5
		"recover":
			f["timer"] = float(f["timer"]) - delta
			if float(f["timer"]) <= 0.0:
				f["state"] = "move"


func _foe_fire(f: Dictionary, dir: Vector2, speed: float) -> void:
	bullets.append({"pos": (f["pos"] as Vector2) + dir * (float(f["radius"]) + 6.0), "vel": dir * speed, "friendly": false, "life": 3.0, "owner": 0})
	_burst((f["pos"] as Vector2) + dir * (float(f["radius"]) + 8.0), 3, [NEON_PINK, Art.GOLD], 90.0)


func _foe_strike(f: Dictionary, reach: float) -> void:
	var dir: Vector2 = f["dir"]
	var fp: Vector2 = f["pos"]
	slashes.append({"pos": fp, "dir": dir, "life": 0.2, "reach": reach, "col": NEON_PINK})
	for q: Player in game.crew:
		if q.downed:
			continue
		var to := q.position - fp
		if to.length() <= reach + q.radius() * 0.5 and dir.dot(to.normalized()) > 0.1:
			_try_hit(q)


func _separate_foes() -> void:
	for i in foes.size():
		for j in range(i + 1, foes.size()):
			var a: Dictionary = foes[i]
			var b: Dictionary = foes[j]
			var d := (a["pos"] as Vector2).distance_to(b["pos"])
			if d < 28.0 and d > 0.01:
				var push: Vector2 = ((a["pos"] as Vector2) - (b["pos"] as Vector2)).normalized() * (28.0 - d) * 0.5
				a["pos"] = layout.move(a["pos"], push, float(a["radius"]))
				b["pos"] = layout.move(b["pos"], -push, float(b["radius"]))


func _update_bullets(delta: float) -> void:
	for b in bullets.duplicate():
		b["life"] = float(b["life"]) - delta
		var vel: Vector2 = b["vel"]
		var steps := maxi(1, int(ceil(vel.length() * delta / 12.0)))
		var dead := float(b["life"]) <= 0.0
		for k in steps:
			if dead:
				break
			var np: Vector2 = (b["pos"] as Vector2) + vel * delta / float(steps)
			if not layout.is_walkable(np, 2.0):
				_burst(b["pos"], 3, [Art.GOLD_DIM, Art.IVORY], 70.0)
				dead = true
				break
			b["pos"] = np
			if bool(b["friendly"]):
				for f in foes:
					if np.distance_to(f["pos"]) < float(f["radius"]) + 5.0:
						_damage_foe(f, _member_by_id(int(b["owner"])))
						dead = true
						break
			else:
				for q: Player in game.crew:
					if not q.downed and np.distance_to(q.position) < q.radius() * 0.85:
						if _try_hit(q):
							dead = true
							break
			if dead:
				break
		if dead:
			bullets.erase(b)


func _update_chests() -> void:
	for c in chests:
		if bool(c["open"]):
			continue
		for q: Player in game.crew:
			if not q.downed and q.position.distance_to(c["pos"]) < 44.0:
				c["open"] = true
				loot += int(c["scrap"])
				score += 50
				_burst(c["pos"], 16, [Art.GOLD, Art.IVORY, Art.COPPER], 200.0)
				floaters.append({"pos": (c["pos"] as Vector2) + Vector2(0, -28), "text": "+%d ferraille" % int(c["scrap"]), "col": Art.GOLD, "life": 1.4})
				if not q.is_free():
					game.net.send(q.peer_id, {"t": "buzz"})
				break


func _check_end() -> void:
	if state != "fight" and state != "intro":
		return
	if foes.is_empty():
		_end(true)
	elif _alive().is_empty():
		_end(false)


func _end(won: bool) -> void:
	var run: RunState = game.run
	state = "won" if won else "lost"
	end_at = t + END_DELAY
	if won:
		var bonus := 0
		if best_combo >= 5:
			bonus += 3
		if downs == 0:
			bonus += 3
		run.apply({"scrap": loot + bonus})
		run.stats["abordages"] = int(run.stats.get("abordages", 0)) + 1
		result_title = "Butin récupéré !" if layout_id == "galion" else "Trésor trouvé !"
		result_lines = [["Ennemis vaincus", str(kills)], ["Meilleur enchaînement", "×%d%s" % [best_combo, "   (+3)" if best_combo >= 5 else ""]],
			["Chutes de l'équipage", "%d%s" % [downs, "   (+3)" if downs == 0 else ""]], ["Butin", "+%d ferraille" % (loot + bonus)],
			["Score", Art.num(score)]]
		game.toast_all("Abordage réussi ! +%d ferraille" % (loot + bonus))
	else:
		run.apply({"hull": -3})
		result_title = "Repli !"
		result_lines = [["Ennemis vaincus", str(kills)], ["Le vaisseau encaisse le feu de couverture", "-3 coque"]]
		game.toast_all("L'équipage bat en retraite…")


# ---------------------------------------------------------------- caméra

## La caméra suit le centre du groupe, sans jamais laisser quelqu'un sortir de l'image.
func _update_camera(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 28.0)
	var mem := _alive()
	if not mem.is_empty():
		var minp := Vector2(INF, INF)
		var maxp := Vector2(-INF, -INF)
		var sum := Vector2.ZERO
		for p: Player in mem:
			minp = minp.min(p.position)
			maxp = maxp.max(p.position)
			sum += p.position
		var want := sum / float(mem.size()) - VIEW / 2.0
		var limit := (world.size - VIEW).max(Vector2.ZERO)
		want = want.clamp(Vector2.ZERO, limit)
		var cam_lo := maxp - VIEW + Vector2(MARGIN, MARGIN)
		var cam_hi := minp - Vector2(MARGIN, MARGIN)
		var target := Vector2(_between(want.x, cam_lo.x, cam_hi.x), _between(want.y, cam_lo.y, cam_hi.y)).clamp(Vector2.ZERO, limit)
		cam = cam.move_toward(target, minf(CAM_SPEED, cam.distance_to(target) * 5.0 + 20.0) * delta)
		_update_blocked(mem, delta)
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	game.position = -(cam + off)


func _between(v: float, lo: float, hi: float) -> float:
	if lo > hi:
		return (lo + hi) / 2.0
	return clampf(v, lo, hi)


## Quelqu'un pousse contre le bord de l'image alors qu'un équipier est loin derrière : le groupe est retenu.
func _update_blocked(mem: Array, delta: float) -> void:
	var lead: Player = null
	var dir := Vector2.ZERO
	for p: Player in mem:
		var s := _s(p)
		if float(s["edge_t"]) > 0.3:
			lead = p
			dir = s.get("edge", Vector2.ZERO)
	laggard = null
	if lead != null and dir != Vector2.ZERO:
		var worst := 0.0
		for p: Player in mem:
			var gap := (lead.position - p.position).dot(dir)
			if gap > 480.0 and gap > worst:
				worst = gap
				laggard = p
	if laggard != null:
		blocked = dir
		blocked_t += delta
		var limit := RESCUE_AFTER if not laggard.is_free() else 6.0
		if blocked_t > limit:
			blocked_t = 0.0
			laggard.position = lead.position - dir * 50.0
			if not layout.is_walkable(laggard.position, laggard.radius()):
				laggard.position = lead.position
			game.toast_all("%s est ramené auprès du groupe" % laggard.player_name)
	else:
		blocked = Vector2.ZERO
		blocked_t = maxf(0.0, blocked_t - delta * 2.0)


# ---------------------------------------------------------------- navigation

func _clear_line(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 24.0)
	for i in range(1, n + 1):
		if not layout.is_walkable(a.lerp(b, float(i) / float(n + 1)), 3.0):
			return false
	return true


## Prochain point à viser pour aller de « from » à « to » : la porte de la salle suivante.
func _waypoint(from: Vector2, to: Vector2) -> Vector2:
	var ra := layout.room_at(from)
	var rb := layout.room_at(to)
	if ra.is_empty() or rb.is_empty() or ra["id"] == rb["id"]:
		return to
	var prev := {ra["id"]: ""}
	var queue: Array = [ra["id"]]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == rb["id"]:
			break
		for n in layout.neighbors(cur):
			if not prev.has(n):
				prev[n] = cur
				queue.append(n)
	if not prev.has(rb["id"]):
		return to
	var step: String = rb["id"]
	while String(prev[step]) != String(ra["id"]):
		step = String(prev[step])
	for d in layout.doors:
		if (d["a"] == ra["id"] and d["b"] == step) or (d["b"] == ra["id"] and d["a"] == step):
			var dp: Vector2 = d["pos"]
			if from.distance_to(dp) < 46.0:
				return (layout.room(step)["rect"] as Rect2).get_center()
			return dp
	return to


# ---------------------------------------------------------------- effets

func _burst(pos: Vector2, n: int, colors: Array, speed: float) -> void:
	for i in n:
		var a := randf() * TAU
		fx.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * speed, "col": colors.pick_random(),
			"life": randf_range(0.3, 0.7), "life0": 0.7, "size": randf_range(2.0, 4.5)})


func _update_effects(delta: float) -> void:
	for e in fx.duplicate():
		e["life"] = float(e["life"]) - delta
		e["pos"] = (e["pos"] as Vector2) + (e["vel"] as Vector2) * delta
		e["vel"] = (e["vel"] as Vector2) * (1.0 - 3.0 * delta)
		if float(e["life"]) <= 0.0:
			fx.erase(e)
	for s in slashes.duplicate():
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			slashes.erase(s)
	for fl in floaters.duplicate():
		fl["life"] = float(fl["life"]) - delta
		fl["pos"] = (fl["pos"] as Vector2) + Vector2(0, -28) * delta
		if float(fl["life"]) <= 0.0:
			floaters.erase(fl)
	combo_t = maxf(0.0, combo_t - delta)
	if combo_t <= 0.0:
		combo = 0


# ---------------------------------------------------------------- tests

func debug_info(_p: Player) -> Dictionary:
	return {"state": state, "layout_id": layout_id, "foes": foes.size(), "chests_open": chests.filter(func(c): return c["open"]).size(),
		"chests": chests.size(), "cam_x": cam.x, "cam_y": cam.y, "world_w": world.size.x, "kills": kills, "best_combo": best_combo, "loot": loot,
		"downs": downs, "blocked": [blocked.x, blocked.y], "blocked_t": blocked_t, "laggard": laggard.crew_id if laggard else 0, "score": score,
		"members": game.crew.map(func(c): return {"id": c.crew_id, "x": c.position.x, "y": c.position.y, "downed": c.downed, "free": c.is_free(),
			"revive": c.revive_frac, "edge_t": snappedf(float(_s(c)["edge_t"]), 0.01)}),
		"foe_list": foes.map(func(f): return {"type": f["type"], "x": f["pos"].x, "y": f["pos"].y, "aware": f["aware"], "state": f["state"]}),
		"rooms": layout.rooms.map(func(r): return {"id": r["id"], "x": (r["rect"] as Rect2).get_center().x, "y": (r["rect"] as Rect2).get_center().y})}


func debug_command(p: Player, msg: Dictionary) -> void:
	match str(msg.get("cmd", "")):
		"kill_all":
			foes.clear()
		"down":
			var q := _member_by_id(int(msg.get("id", p.crew_id)))
			if q != null and not q.downed:
				_down(q)
		"tp_all":
			for q: Player in game.crew:
				q.position = Vector2(float(msg.get("x", 300)), float(msg.get("y", 300)))
		"tp_member":
			var q2 := _member_by_id(int(msg.get("id", 0)))
			if q2 != null:
				q2.position = Vector2(float(msg.get("x", 300)), float(msg.get("y", 300)))
		"skip_intro":
			state = "fight"
		"freeze":
			frozen = bool(msg.get("on", true))
		"wake":
			for f in foes:
				f["aware"] = true
		"cam":
			cam = Vector2(float(msg.get("x", 0)), float(msg.get("y", 0)))


# ---------------------------------------------------------------- dessin

func _floor_for(room: Dictionary) -> Color:
	var floors: Dictionary = def["floors"]
	if floors.has(room["id"]):
		return floors[room["id"]]
	var pal: Dictionary = def["palette"]
	return pal["floor"] if absi(hash(room["id"])) % 2 == 0 else pal["alt"]


func _draw() -> void:
	var pal: Dictionary = def["palette"]
	draw_rect(Rect2(cam - Vector2(60, 60), VIEW + Vector2(120, 120)), pal["back"])
	layout.draw(self, _floor_for, true, pal["wall"], Art.GOLD_DIM)
	for s in stains:
		draw_circle(s["pos"], s["r"], s["col"])
	for c in chests:
		_draw_chest(c)
	for f in foes:
		_draw_foe(f)
	_draw_tether()
	for b in bullets:
		_draw_bullet(b)
	for sl in slashes:
		_draw_slash(sl)
	for e in fx:
		draw_circle(e["pos"], float(e["size"]), Color(e["col"], clampf(float(e["life"]) / 0.4, 0.0, 1.0)))
	for p: Player in game.crew:
		_draw_pips(p)
	for fl in floaters:
		Art.title(self, (fl["pos"] as Vector2) + Vector2(-80, 0), fl["text"], 20, Color(fl["col"], clampf(float(fl["life"]), 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_draw_overlay()


func _draw_chest(c: Dictionary) -> void:
	var p: Vector2 = c["pos"]
	var big: bool = c["big"]
	var k := 1.5 if big else 1.0
	if not bool(c["open"]):
		if big:
			draw_circle(p, 38.0 + 4.0 * sin(t * 4.0), Color(Art.GOLD, 0.14))
		draw_rect(Rect2(p - Vector2(18, 12) * k, Vector2(36, 24) * k), Color("#6b3f25"))
		draw_rect(Rect2(p - Vector2(18, 12) * k, Vector2(36, 11) * k), Color("#84502f"))
		draw_rect(Rect2(p - Vector2(18, 12) * k, Vector2(36, 24) * k), Art.GOLD, false, 2.0)
		draw_rect(Rect2(p - Vector2(3, 3) * k, Vector2(6, 8) * k), Art.GOLD)
	else:
		draw_rect(Rect2(p - Vector2(18, 12) * k, Vector2(36, 24) * k), Color("#2a1d14"))
		draw_rect(Rect2(p - Vector2(18, 12) * k, Vector2(36, 24) * k), Art.GOLD_DIM, false, 1.5)
		draw_rect(Rect2(p - Vector2(15, 9) * k, Vector2(30, 14) * k), Color("#120c08"))


func _draw_foe(f: Dictionary) -> void:
	var fd: Dictionary = ShipData.BOARDING_FOES[f["type"]]
	var p: Vector2 = f["pos"]
	var r: float = f["radius"]
	var face: Vector2 = f["face"]
	var awake: bool = f["aware"]
	var coat := Color("#a8483a")
	if f["type"] == "fusilier":
		coat = Color("#4d7a80")
	elif f["type"] == "capitaine":
		coat = Color("#7d3a8f")
	if float(f["flash"]) > 0.0:
		coat = Color.WHITE
	if not awake:
		coat = coat.darkened(0.3)
	draw_set_transform(p + Vector2(0, r * 0.9), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# préparation d'une attaque : la zone s'allume en rose
	if f["state"] == "wind" or f["state"] == "wind_fan":
		var dir: Vector2 = f["dir"]
		var pulse := 0.5 + 0.5 * sin(t * 28.0)
		if f["type"] == "fusilier" or f["state"] == "wind_fan":
			var span := [-0.32, 0.0, 0.32] if f["state"] == "wind_fan" else [0.0]
			for a in span:
				draw_line(p, p + dir.rotated(a) * 380.0, Color(NEON_PINK, 0.35 + 0.35 * pulse), 2.0)
		else:
			var reach: float = fd["reach"]
			var pts := PackedVector2Array([p])
			for i in 11:
				pts.append(p + dir.rotated(-0.9 + 1.8 * i / 10.0) * reach)
			draw_colored_polygon(pts, Color(NEON_PINK, 0.18 + 0.2 * pulse))
		draw_arc(p, r + 8.0 + 4.0 * pulse, 0, TAU, 24, NEON_PINK, 3.0)
	draw_circle(p, r, coat)
	draw_arc(p, r, 0, TAU, 28, Art.GOLD if f["type"] == "capitaine" else Art.GOLD_DIM, 2.0)
	# tricorne
	var up := Vector2(0, -r)
	var hat := PackedVector2Array([p + up + Vector2(-r * 0.9, 3), p + up + Vector2(0, -r * 0.7), p + up + Vector2(r * 0.9, 3)])
	draw_colored_polygon(hat, Color("#1a1420"))
	draw_polyline(hat, Art.GOLD_DIM, 1.5)
	if f["type"] == "capitaine":
		draw_line(p + up + Vector2(r * 0.4, -r * 0.4), p + up + Vector2(r * 1.0, -r * 0.9), Art.IVORY, 3.0)
	# yeux et arme
	var perp := Vector2(-face.y, face.x)
	for sgn: float in [-1.0, 1.0]:
		draw_circle(p + face * r * 0.35 + perp * sgn * r * 0.3, r * 0.15, Art.IVORY if awake else Color(Art.IVORY, 0.4))
	if f["type"] == "fusilier":
		draw_line(p + face * r * 0.4, p + face * (r + 16.0), Color("#c9c4b8"), 4.0)
	else:
		draw_line(p + face * (r * 0.5), p + face * (r + 20.0), Color("#dcdcdc"), 3.0)
	if not awake:
		Art.text(self, p + Vector2(-r, -r - 14), "z", 14, Color(Art.IVORY, 0.4))
	if int(f["hp_max"]) > 1:
		Art.bar(self, Rect2(p + Vector2(-r - 4, -r - 22), Vector2(r * 2 + 8, 6)), float(f["hp"]) / float(f["hp_max"]), Art.DANGER)


func _draw_bullet(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var col: Color = NEON_CYAN if bool(b["friendly"]) else NEON_PINK
	var v: Vector2 = (b["vel"] as Vector2).normalized()
	draw_line(p - v * 14.0, p, Color(col, 0.5), 5.0)
	draw_circle(p, 9.0, Color(col, 0.2))
	draw_circle(p, 4.5, col)
	draw_circle(p, 2.0, Color.WHITE)


func _draw_slash(sl: Dictionary) -> void:
	var a := clampf(float(sl["life"]) / 0.2, 0.0, 1.0)
	var dir: Vector2 = sl["dir"]
	var reach: float = sl["reach"]
	var p: Vector2 = sl["pos"]
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(p + dir.rotated(-1.1 + 2.2 * i / 12.0) * reach)
	draw_polyline(pts, Color(sl["col"], a), 7.0 * a + 1.0, true)
	draw_polyline(pts, Color(Art.IVORY, a), 2.5, true)


func _draw_pips(p: Player) -> void:
	if p.downed or p.is_free():
		return
	var n := int(floor(float(_s(p)["ammo"])))
	for i in int(AMMO_MAX):
		draw_circle(p.position + Vector2((i - 1) * 11, -p.radius() - 16), 3.5, NEON_CYAN if i < n else Color(NEON_CYAN, 0.18))


## Quand le groupe est retenu : l'équipier en retard est entouré et le bord de l'image s'allume.
func _draw_tether() -> void:
	if laggard == null or blocked_t < 0.3:
		return
	var pulse := 0.5 + 0.5 * sin(t * 7.0)
	draw_arc(laggard.position, laggard.radius() + 14.0 + 5.0 * pulse, 0, TAU, 32, Art.GOLD, 4.0)
	draw_arc(laggard.position, laggard.radius() + 26.0 + 8.0 * pulse, 0, TAU, 32, Color(Art.GOLD, 0.4), 2.0)
	var mid := cam + VIEW / 2.0
	var tip := mid + Vector2(blocked.x * (VIEW.x / 2.0 - 30.0), blocked.y * (VIEW.y / 2.0 - 30.0))
	var side := Vector2(-blocked.y, blocked.x)
	if blocked != Vector2.ZERO:
		var tri := PackedVector2Array([tip, tip - blocked * 34.0 + side * 18.0, tip - blocked * 34.0 - side * 18.0])
		draw_colored_polygon(tri, Color(Art.GOLD, 0.4 + 0.5 * pulse))
		var edge := Rect2(cam, VIEW)
		var strip := Rect2(edge.end.x - 10.0, edge.position.y, 10.0, VIEW.y) if blocked.x > 0 else \
			Rect2(edge.position.x, edge.position.y, 10.0, VIEW.y) if blocked.x < 0 else \
			Rect2(edge.position.x, edge.end.y - 10.0, VIEW.x, 10.0) if blocked.y > 0 else \
			Rect2(edge.position.x, edge.position.y, VIEW.x, 10.0)
		draw_rect(strip, Color(Art.GOLD, 0.18 + 0.3 * pulse))


func _draw_overlay() -> void:
	Hud.draw(self, game.run, cam.y + 18.0, cam.x + 40.0)
	game.draw_small_qr(self, cam + Vector2(1190, 22), 64)
	var y := cam.y + 84.0
	Art.title(self, Vector2(cam.x + 40, y), "%s · ennemis restants : %d" % [def["name"], foes.size()], 20, Color(Art.IVORY, 0.8))
	Art.title(self, Vector2(cam.x + 840, y), "Butin : %d    Score : %s" % [loot, Art.num(score)], 20, Art.GOLD)
	if combo >= 2:
		var k := 1.0 + 0.05 * minf(float(combo), 10.0)
		Art.title(self, Vector2(cam.x + 440, y + 6), "ENCHAÎNEMENT ×%d" % combo, int(26 * k), NEON_PINK, HORIZONTAL_ALIGNMENT_CENTER, 400)
		draw_rect(Rect2(cam.x + 540, y + 14, 200.0 * combo_t / COMBO_WINDOW, 4), NEON_CYAN)
	if laggard != null and blocked_t >= 0.3:
		Art.title(self, Vector2(cam.x, cam.y + VIEW.y - 52.0), "Attendez %s !" % laggard.player_name, 30, Art.GOLD, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
		Art.text(self, Vector2(cam.x, cam.y + VIEW.y - 28.0), "Le groupe n'avance que s'il reste uni", 15, Color(Art.IVORY, 0.7), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	if state == "intro":
		var a := clampf((INTRO - t) / 0.7, 0.0, 1.0)
		var band := Rect2(cam.x, cam.y + 290, VIEW.x, 110)
		draw_rect(band, Color(0, 0, 0, 0.55 * a))
		Art.title(self, Vector2(cam.x, cam.y + 362), "À L'ABORDAGE !" if layout_id == "galion" else "TERRE EN VUE !", 58, Color(NEON_PINK, a), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	elif t < INTRO + 6.0 and state == "fight":
		var a2 := clampf((INTRO + 6.0 - t) / 1.5, 0.0, 1.0)
		Art.text(self, Vector2(cam.x, cam.y + VIEW.y - 20.0), "A frapper  ·  B tirer (visée automatique)  ·  X roulade (esquive les coups)  ·  restez près d'un équipier à terre pour le relever",
			15, Color(Art.IVORY, 0.8 * a2), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	if state == "won" or state == "lost":
		var card := Rect2(cam.x + 320, cam.y + 150, 640, 420)
		var col := Art.GOLD if state == "won" else Art.CORRUPT
		draw_rect(Rect2(cam, VIEW), Color(0, 0, 0, 0.45))
		Art.panel(self, card, 1.0, col)
		Art.title(self, card.position + Vector2(0, 76), result_title, 46, col, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
		Art.rule(self, Vector2(card.get_center().x - 160, card.position.y + 98), 320, col)
		var yy := card.position.y + 160
		for row in result_lines:
			Art.text(self, Vector2(card.position.x + 70, yy), row[0], 19, Color(Art.IVORY, 0.65))
			Art.title(self, Vector2(card.position.x + 360, yy), row[1], 22, Art.IVORY)
			yy += 40
