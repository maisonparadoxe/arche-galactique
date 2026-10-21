extends GameScene
## Combat entre vaisseaux.
##
## Règle de base : tout fonctionne en automatique, un joueur fait toujours mieux.
## - Les armes chargent seules et tirent au hasard ; un artilleur au poste vise la salle de son choix.
## - Les incendies et les systèmes endommagés ne se réparent qu'avec l'équipage (B maintenu).

const PLAYER_AREA := Rect2(40, 150, 780, 470)
const ENEMY_AREA := Rect2(880, 200, 360, 380)
const SPEED := 260.0
const NEAR := 58.0
const SHIELD_RECHARGE := 2.5
const ENEMY_SHIELD_RECHARGE := 3.2
const AUTO_DELAY := 0.25         # l'automatique attend 25 % de la charge en plus avant de tirer
const FIRE_SYSTEM_DAMAGE_EVERY := 6.0
const FIRE_HULL_DAMAGE_EVERY := 14.0
const FIRE_SPREAD_EVERY := 15.0
const ENEMY_REPAIR_EVERY := 9.0
const END_DELAY := 3.0

var layout: ShipLayout
var enemy_layout: ShipLayout
var ship_def: Dictionary
var sys: Dictionary = {}              # nom -> {level, damage, repair}
var weapons: Array = []               # [{id, charge, ready_for}]
var shield_layers := 0
var shield_t := 0.0
var enemy: Dictionary = {}
var fires: Array = []                 # [{room, pos, intensity, burn_sys, burn_hull, spread}]
var shots: Array = []                 # projectiles en vol
var floaters: Array = []
var flashes: Array = []               # [{rect, col, life}]
var gunner := 0
var cross := Vector2.ZERO
var shake := 0.0
var state := "fight"                  # fight, won, lost
var end_at := 0.0
var reward_text := ""
var weapons_console := Vector2.ZERO
var _last_armes_push := 0.0


# ---------------------------------------------------------------- mise en place

func enter(args: Dictionary) -> void:
	var run: RunState = game.run
	ship_def = ShipData.PLAYER_SHIPS[run.ship_id]
	layout = ShipLayout.build(ship_def["layout"], PLAYER_AREA, 64.0)
	sys = {
		"boucliers": {"level": run.shields, "damage": 0, "repair": 0.0},
		"armes": {"level": run.weapons.size(), "damage": 0, "repair": 0.0},
		"moteurs": {"level": run.engines, "damage": 0, "repair": 0.0},
		"pilotage": {"level": 1, "damage": 0, "repair": 0.0},
	}
	weapons = run.weapons.map(func(id): return {"id": id, "charge": 0.0, "ready_for": 0.0})
	shield_layers = run.shields
	var armes_room := layout.room_with_system("armes")
	var ar: Rect2 = armes_room["rect"]
	weapons_console = Vector2(ar.end.x - 30, ar.get_center().y)
	_setup_enemy(str(args.get("enemy", "eclaireur")))
	cross = enemy_layout.bounds.get_center()
	# Les avatars des joueurs démarrent dans la coursive, les recrues à leurs postes.
	var posts := ["armes", "boucliers", "moteurs", "pilotage"]
	var k := 0
	for p: Player in game.crew:
		if p.owner_token == "" and k < posts.size():
			var room := layout.room_with_system(posts[k])
			k += 1
			if not room.is_empty():
				p.position = (room["rect"] as Rect2).get_center() + Vector2(-24, 18)
				continue
		_place(p)


func _setup_enemy(id: String) -> void:
	var def: Dictionary = ShipData.ENEMIES[id]
	var cell := 50.0 if def["layout"] == "boss" else 52.0
	enemy_layout = ShipLayout.build(ShipData.ENEMY_LAYOUTS[def["layout"]], ENEMY_AREA, cell)
	var diff: Dictionary = game.run.diff
	var hull_e: int = maxi(3, int(round(float(def["hull"]) * float(diff.get("enemy_hull", 1.0)))))
	enemy = {
		"id": id, "def": def, "name": def["name"], "hull": hull_e, "hull_max": hull_e,
		"charge_mult": float(diff.get("enemy_charge", 1.0)),
		"shields": def["shields"], "shield_t": 0.0, "repair_t": 0.0, "corrupt": def["corrupt"],
		"sys": {
			"boucliers": {"level": def["shields"], "damage": 0},
			"armes": {"level": (def["weapons"] as Array).size(), "damage": 0},
			"moteurs": {"level": def["engines"], "damage": 0},
			"pilotage": {"level": 1, "damage": 0},
		},
		"weapons": (def["weapons"] as Array).map(func(w): return {"id": w, "charge": randf_range(0.0, 2.0), "ready_for": 0.0}),
	}


func _place(p: Player) -> void:
	var c := layout.room("coursive")
	if c.is_empty():
		c = layout.rooms[0]
	var rr: Rect2 = c["rect"]
	p.position = rr.get_center() + Vector2(-60 + (p.slot % 4) * 40, -18 + (p.slot / 4) * 36)


func shows_players() -> bool:
	return true


func layout_for(p: Player) -> Dictionary:
	if p.seated:
		return {"t": "layout", "mode": "armes", "title": "Poste d'armes", "weapons": _weapons_state()}
	return {"t": "layout", "mode": "base"}


func on_join(p: Player) -> void:
	_place(p)


func on_leave(p: Player) -> void:
	on_release(p)


func on_release(p: Player) -> void:
	if p.seated and gunner == p.peer_id:
		gunner = 0


func location_name(p: Player) -> String:
	var r := layout.room_at(p.position)
	return r.get("name", "") if not r.is_empty() else ""


# ---------------------------------------------------------------- systèmes

func eff(s: String) -> int:
	return maxi(0, int(sys[s]["level"]) - int(sys[s]["damage"]))


func enemy_eff(s: String) -> int:
	if not enemy["sys"].has(s):
		return 0
	return maxi(0, int(enemy["sys"][s]["level"]) - int(enemy["sys"][s]["damage"]))


func player_evasion() -> float:
	return 0.0 if eff("pilotage") <= 0 else 0.06 * eff("moteurs")


func enemy_evasion() -> float:
	return 0.0 if enemy_eff("pilotage") <= 0 else 0.05 * enemy_eff("moteurs")


func _weapons_state() -> Array:
	var out: Array = []
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var def: Dictionary = ShipData.WEAPONS[w["id"]]
		out.append({"name": def["name"], "charge": snappedf(w["charge"] / def["charge"], 0.01),
			"ready": w["charge"] >= def["charge"], "powered": i < eff("armes")})
	return out


# ---------------------------------------------------------------- boucle

func update(delta: float) -> void:
	for p: Player in game.players.values():
		if p.seated:
			var c: Vector2 = cross + p.axis * 340.0 * delta
			cross = c.clamp(enemy_layout.bounds.grow(40).position, enemy_layout.bounds.grow(40).end)
		else:
			p.position = layout.move(p.position, p.axis * SPEED * delta, p.radius())
			_interact(p)
	if state == "fight":
		_update_crew_work(delta)
		_update_fires(delta)
		_update_shields(delta)
		_update_player_weapons(delta)
		_update_enemy(delta)
		if game.run.hull <= 0:
			_end(false)
		elif enemy["hull"] <= 0:
			_end(true)
	_update_shots(delta)
	_update_effects(delta)
	if gunner != 0 and t - _last_armes_push > 0.15 and game.players.has(gunner):
		_last_armes_push = t
		game.net.send(gunner, {"t": "armes", "weapons": _weapons_state(), "target": _target_name()})
	if state != "fight" and t >= end_at and end_at > 0.0:
		end_at = -1.0
		if state == "won":
			game.node_done()
		else:
			game.end_run(false)


func _interact(p: Player) -> void:
	if p.pressed(0) and gunner == 0 and p.position.distance_to(weapons_console) < NEAR:
		gunner = p.peer_id
		p.seated = true
		p.axis = Vector2.ZERO
		p.position = weapons_console + Vector2(-30, 0)
		p.facing = Vector2.RIGHT
		game.net.send(p.peer_id, layout_for(p))


func hints_for(p: Player) -> Dictionary:
	var h := {}
	if state != "fight":
		return h
	if gunner == 0 and p.position.distance_to(weapons_console) < NEAR:
		h[0] = "Armes"
	for f in fires:
		if p.position.distance_to(f["pos"]) < NEAR + 6:
			h[1] = "Éteindre"
	if not h.has(1):
		var room := layout.room_at(p.position)
		if not room.is_empty() and sys.has(room["system"]) and sys[room["system"]]["damage"] > 0:
			h[1] = "Réparer"
	return h


func on_action(p: Player, action: String, msg: Dictionary) -> void:
	match action:
		"quit":
			if p.seated:
				p.seated = false
				if gunner == p.peer_id:
					gunner = 0
				game.net.send(p.peer_id, layout_for(p))
		"fire":
			if p.seated and gunner == p.peer_id and state == "fight":
				var i := int(msg.get("w", 0))
				if i >= 0 and i < weapons.size():
					_try_fire(i, p)


func _target_name() -> String:
	var r := enemy_layout.room_at(cross)
	return ShipData.SYSTEM_NAMES.get(r.get("system", ""), "") if not r.is_empty() else ""


## Le joueur à l'arme tire sur la salle visée.
func _try_fire(i: int, p: Player) -> void:
	var w: Dictionary = weapons[i]
	var def: Dictionary = ShipData.WEAPONS[w["id"]]
	if i >= eff("armes") or w["charge"] < def["charge"]:
		game.net.send(p.peer_id, {"t": "toast", "text": "Pas encore chargée"})
		return
	var target := cross
	var room := enemy_layout.room_at(cross)
	if room.is_empty() and p.species == "automate":
		# Visée assistée : on accroche la salle la plus proche
		var best := 60.0
		for r in enemy_layout.rooms:
			var d := (r["rect"] as Rect2).get_center().distance_to(cross)
			if d < best:
				best = d
				room = r
		if not room.is_empty():
			target = (room["rect"] as Rect2).get_center()
	_launch_player_shot(i, target, room)
	game.net.send(p.peer_id, {"t": "buzz"})


func _launch_player_shot(i: int, target: Vector2, room: Dictionary) -> void:
	var w: Dictionary = weapons[i]
	var def: Dictionary = ShipData.WEAPONS[w["id"]]
	w["charge"] = 0.0
	w["ready_for"] = 0.0
	game.sfx.play("tir", 0.55, -3.0)
	shots.append({"owner": "player", "from": weapons_console + Vector2(16, -10 + i * 10), "to": target, "t0": t,
		"dur": 0.7, "dmg": def["dmg"], "pierce": def.get("pierce", false), "room": room.get("id", ""), "weapon": w["id"]})


func _update_player_weapons(delta: float) -> void:
	var powered := eff("armes")
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var def: Dictionary = ShipData.WEAPONS[w["id"]]
		if i < powered:
			w["charge"] = minf(def["charge"], w["charge"] + delta)
		else:
			w["charge"] = maxf(0.0, w["charge"] - delta * 2.0)
		if w["charge"] >= def["charge"]:
			w["ready_for"] += delta
		# Sans artilleur : tir automatique, plus lent, sur une salle au hasard
		if gunner == 0 and w["charge"] >= def["charge"] and w["ready_for"] >= def["charge"] * AUTO_DELAY:
			var room: Dictionary = enemy_layout.rooms.pick_random()
			_launch_player_shot(i, enemy_layout.random_point(room, 12), room)


func _update_shields(delta: float) -> void:
	var max_layers := eff("boucliers")
	if shield_layers > max_layers:
		shield_layers = max_layers
	if shield_layers < max_layers:
		shield_t += delta
		if shield_t >= SHIELD_RECHARGE:
			shield_t = 0.0
			shield_layers += 1
	else:
		shield_t = 0.0
	# boucliers ennemis
	var emax := enemy_eff("boucliers")
	if enemy["shields"] > emax:
		enemy["shields"] = emax
	if enemy["shields"] < emax:
		enemy["shield_t"] += delta
		if enemy["shield_t"] >= ENEMY_SHIELD_RECHARGE:
			enemy["shield_t"] = 0.0
			enemy["shields"] += 1


func _update_enemy(delta: float) -> void:
	# Réparations automatiques de l'équipage ennemi
	enemy["repair_t"] += delta
	if enemy["repair_t"] >= ENEMY_REPAIR_EVERY:
		enemy["repair_t"] = 0.0
		for s in enemy["sys"]:
			if enemy["sys"][s]["damage"] > 0:
				enemy["sys"][s]["damage"] -= 1
				break
	# Armes : l'ennemi tire en salve quand toutes ses armes alimentées sont prêtes
	var powered := enemy_eff("armes")
	var all_ready := powered > 0
	for i in enemy["weapons"].size():
		var w: Dictionary = enemy["weapons"][i]
		var def: Dictionary = ShipData.WEAPONS[w["id"]]
		if i < powered:
			# la difficulté ralentit (ou accélère) la charge des armes ennemies
			w["charge"] = minf(def["charge"], w["charge"] + delta / float(enemy["charge_mult"]))
			if w["charge"] >= def["charge"]:
				w["ready_for"] += delta
			else:
				all_ready = false
		else:
			w["charge"] = maxf(0.0, w["charge"] - delta * 2.0)
	for i in enemy["weapons"].size():
		var w: Dictionary = enemy["weapons"][i]
		var def: Dictionary = ShipData.WEAPONS[w["id"]]
		if i < powered and w["charge"] >= def["charge"] and (all_ready or w["ready_for"] > 3.0):
			w["charge"] = 0.0
			w["ready_for"] = 0.0
			var rooms_with_sys := layout.rooms.filter(func(r): return r["system"] != "")
			var room: Dictionary = rooms_with_sys.pick_random() if randf() < 0.7 else layout.rooms.pick_random()
			var from := enemy_layout.bounds.get_center() + Vector2(-enemy_layout.bounds.size.x / 2, randf_range(-30, 30))
			shots.append({"owner": "enemy", "from": from, "to": layout.random_point(room, 20), "t0": t + i * 0.18,
				"dur": 0.9, "dmg": def["dmg"], "pierce": def.get("pierce", false), "room": room["id"], "weapon": w["id"]})


func _update_shots(_delta: float) -> void:
	var still: Array = []
	for s in shots:
		if t < s["t0"] + s["dur"]:
			still.append(s)
			continue
		if state != "fight":
			continue
		if s["owner"] == "player":
			_player_shot_hits(s)
		else:
			_enemy_shot_hits(s)
	shots = still


func _player_shot_hits(s: Dictionary) -> void:
	if s["room"] == "":
		_float(s["to"], "Raté", Art.IVORY)
		return
	if randf() < enemy_evasion():
		_float(s["to"], "Esquivé", Art.IVORY)
		return
	if enemy["shields"] > 0 and not s["pierce"]:
		enemy["shields"] -= 1
		enemy["shield_t"] = 0.0
		_float(s["to"], "Bouclier", Art.SHIELD)
		return
	var room := enemy_layout.room(s["room"])
	var dmg: int = s["dmg"] * (2 if room["system"] == "coeur" else 1)
	enemy["hull"] = maxi(0, enemy["hull"] - dmg)
	var sname: String = room["system"]
	if enemy["sys"].has(sname):
		enemy["sys"][sname]["damage"] = mini(enemy["sys"][sname]["level"], enemy["sys"][sname]["damage"] + 1)
	flashes.append({"rect": room["rect"], "col": Color(1, 0.6, 0.3), "life": 0.5})
	_float(s["to"], "-%d" % dmg, Art.GOLD)


func _enemy_shot_hits(s: Dictionary) -> void:
	var run: RunState = game.run
	game.sfx.play("touche", 0.7)
	if randf() < player_evasion():
		_float(s["to"], "Esquivé !", Art.SAGE)
		return
	if shield_layers > 0 and not s["pierce"]:
		shield_layers -= 1
		shield_t = 0.0
		_float(s["to"], "Bouclier", Art.SHIELD)
		return
	var room := layout.room(s["room"])
	run.hull = maxi(0, run.hull - int(s["dmg"]))
	shake = 0.35
	var sname: String = room["system"]
	if sys.has(sname):
		sys[sname]["damage"] = mini(sys[sname]["level"], sys[sname]["damage"] + 1)
	flashes.append({"rect": room["rect"], "col": Color(1, 0.3, 0.2), "life": 0.6})
	_float(s["to"], "-%d" % s["dmg"], Art.DANGER)
	var fire_chance: float = (0.4 if s["weapon"] == "spore" else 0.2) * float(run.diff.get("fire", 1.0))
	if randf() < fire_chance:
		_start_fire(room)
	for p: Player in game.players.values():
		if (room["rect"] as Rect2).has_point(p.position):
			game.net.send(p.peer_id, {"t": "buzz"})


func _start_fire(room: Dictionary, at := Vector2.INF) -> void:
	var n := fires.filter(func(f): return f["room"] == room["id"]).size()
	if n >= 2:
		return
	var pos := at if at != Vector2.INF else layout.random_point(room, 30)
	fires.append({"room": room["id"], "pos": pos, "intensity": 100.0, "burn_sys": 0.0, "burn_hull": 0.0, "spread": 0.0})


func _update_fires(delta: float) -> void:
	var run: RunState = game.run
	for f in fires.duplicate():
		f["intensity"] = minf(100.0, f["intensity"] + 3.0 * delta)
		for p: Player in game.crew:
			var w := work_rate(p)
			# un membre contrôlé éteint le feu devant lui ; un membre libre s'occupe des feux de sa salle
			var reach: bool = p.position.distance_to(f["pos"]) < NEAR + 6 if not p.is_free() \
				else layout.room_at(p.position).get("id", "") == f["room"]
			if w > 0.0 and reach:
				f["intensity"] -= (70.0 if p.species == "salamandrin" else 35.0) * w * delta
				p.working = p.is_free()
		if f["intensity"] <= 0.0:
			fires.erase(f)
			continue
		var room := layout.room(f["room"])
		f["burn_sys"] += delta
		if f["burn_sys"] >= FIRE_SYSTEM_DAMAGE_EVERY:
			f["burn_sys"] = 0.0
			var sname: String = room["system"]
			if sys.has(sname):
				sys[sname]["damage"] = mini(sys[sname]["level"], sys[sname]["damage"] + 1)
		f["burn_hull"] += delta
		if f["burn_hull"] >= FIRE_HULL_DAMAGE_EVERY:
			f["burn_hull"] = 0.0
			run.hull = maxi(0, run.hull - 1)
			_float(f["pos"], "-1", Art.DANGER)
		f["spread"] += delta
		if f["spread"] >= FIRE_SPREAD_EVERY:
			f["spread"] = 0.0
			var neigh := layout.neighbors(f["room"])
			if not neigh.is_empty() and randf() < 0.25:
				_start_fire(layout.room(neigh.pick_random()))


## Réparations : maintenir B dans une salle dont le système est endommagé (hors des flammes).
## Un membre libre répare tout seul, à mi-vitesse, le système de la salle où il se trouve.
func _update_crew_work(delta: float) -> void:
	for p: Player in game.crew:
		var w := work_rate(p)
		if w <= 0.0:
			continue
		var room := layout.room_at(p.position)
		var near_fire := false
		for f in fires:
			if p.position.distance_to(f["pos"]) < NEAR + 6 or (p.is_free() and f["room"] == room.get("id", "")):
				near_fire = true
		if near_fire:
			continue
		if room.is_empty() or not sys.has(room["system"]):
			continue
		var s: Dictionary = sys[room["system"]]
		if s["damage"] <= 0:
			continue
		s["repair"] += (45.0 if p.species == "humain" else 25.0) * w * delta
		p.working = p.is_free()
		if s["repair"] >= 100.0:
			s["repair"] = 0.0
			s["damage"] -= 1
			_float((room["rect"] as Rect2).get_center(), "Réparé", Art.SAGE)
			game.net.send(p.peer_id, {"t": "buzz"})


func _update_effects(delta: float) -> void:
	shake = maxf(0.0, shake - delta)
	position = Vector2(randf_range(-6, 6), randf_range(-6, 6)) * shake / 0.35 if shake > 0.0 else Vector2.ZERO
	for f in floaters:
		f["life"] -= delta
		f["pos"] += Vector2(0, -28) * delta
	floaters = floaters.filter(func(f): return f["life"] > 0)
	for f in flashes:
		f["life"] -= delta
	flashes = flashes.filter(func(f): return f["life"] > 0)


func _float(pos: Vector2, text: String, col: Color) -> void:
	floaters.append({"pos": pos + Vector2(0, -10), "text": text, "col": col, "life": 1.2})


func _end(won: bool) -> void:
	var run: RunState = game.run
	state = "won" if won else "lost"
	game.sfx.play("victoire" if won else "defaite")
	end_at = t + END_DELAY
	for p: Player in game.players.values():
		if p.seated:
			p.seated = false
			game.net.send(p.peer_id, layout_for(p))
	gunner = 0
	if won:
		run.stats["combats"] += 1
		var def: Dictionary = enemy["def"]
		var effects := {}
		var lo: int = def["scrap"][0]
		var hi: int = def["scrap"][1]
		if hi > 0:
			effects["scrap"] = randi_range(lo, hi)
		if not def.get("boss", false) and randf() < 0.5:
			effects["fuel"] = 1
		reward_text = run.apply(effects)
		game.toast_all("Victoire ! " + reward_text if reward_text != "" else "Victoire !")
	else:
		game.toast_all("Le vaisseau est perdu…")


# ---------------------------------------------------------------- tests

func debug_info(_p: Player) -> Dictionary:
	var dmg := {}
	for s in sys:
		dmg[s] = sys[s]["damage"]
	return {"time": snappedf(t, 0.1), "state": state, "enemy": enemy["id"], "enemy_hull": enemy["hull"], "enemy_shields": enemy["shields"],
		"shields": shield_layers, "sys_damage": dmg, "fires": fires.map(func(f): return [f["pos"].x, f["pos"].y, f["room"]]),
		"gunner": gunner, "cross_x": cross.x, "cross_y": cross.y, "weapons": _weapons_state(),
		"console_x": weapons_console.x, "console_y": weapons_console.y,
		"enemy_rooms": enemy_layout.rooms.map(func(r): return {"id": r["id"], "x": (r["rect"] as Rect2).get_center().x, "y": (r["rect"] as Rect2).get_center().y}),
		"rooms": layout.rooms.map(func(r): return {"id": r["id"], "system": r["system"], "x": (r["rect"] as Rect2).get_center().x, "y": (r["rect"] as Rect2).get_center().y}),
		"doors": layout.doors.map(func(d): return [d["a"], d["b"], d["pos"].x, d["pos"].y])}


func debug_command(_p: Player, msg: Dictionary) -> void:
	match str(msg.get("cmd", "")):
		"enemy_hull": enemy["hull"] = int(msg.get("value", 0))
		"hull": game.run.hull = int(msg.get("value", 0))
		"fire":
			var room := layout.room(str(msg.get("room", "coursive")))
			if not room.is_empty():
				_start_fire(room, (room["rect"] as Rect2).get_center())
		"damage":
			var s := str(msg.get("system", "armes"))
			sys[s]["damage"] = mini(sys[s]["level"], sys[s]["damage"] + 1)
		"freeze_enemy":
			for w in enemy["weapons"]:
				w["charge"] = -9999.0


# ---------------------------------------------------------------- dessin

func _draw() -> void:
	var run: RunState = game.run
	Hud.draw(self, run)
	game.draw_small_qr(self, Vector2(1190, 22), 64)
	var boss: bool = enemy["def"].get("boss", false)
	Art.title(self, Vector2(40, 100), "Affrontement final" if boss else "Saut %d / %d" % [run.depth(), run.layers - 1], 22, Color(Art.IVORY, 0.55))
	_draw_player_ship()
	_draw_enemy_ship()
	_draw_shots()
	_draw_weapon_panel()
	for f in floaters:
		Art.title(self, f["pos"] + Vector2(-60, 0), f["text"], 20, Color(f["col"], clampf(f["life"], 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, 120)
	if state != "fight":
		var won := state == "won"
		var band := Rect2(0, 300, 1280, 110)
		draw_rect(band, Color(0, 0, 0, 0.6))
		Art.title(self, Vector2(0, 360), "Victoire !" if won else "Coque détruite…", 54, Art.GOLD if won else Art.DANGER, HORIZONTAL_ALIGNMENT_CENTER, 1280)
		if won and reward_text != "":
			Art.title(self, Vector2(0, 396), reward_text, 22, Art.IVORY, HORIZONTAL_ALIGNMENT_CENTER, 1280)


func _draw_player_ship() -> void:
	var b := layout.bounds
	var hull_r := b.grow(26)
	# bulle de bouclier
	for i in shield_layers:
		var rr := hull_r.grow(14 + i * 9)
		draw_set_transform(rr.get_center(), 0, Vector2(1.0, rr.size.y / rr.size.x))
		draw_arc(Vector2.ZERO, rr.size.x / 2, 0, TAU, 72, Color(Art.SHIELD, 0.55 - i * 0.12), 2.5)
		draw_set_transform(Vector2.ZERO)
	if shield_t > 0.0 and shield_layers < eff("boucliers"):
		var rr := hull_r.grow(14 + shield_layers * 9)
		draw_set_transform(rr.get_center(), 0, Vector2(1.0, rr.size.y / rr.size.x))
		draw_arc(Vector2.ZERO, rr.size.x / 2, -PI / 2, -PI / 2 + TAU * shield_t / SHIELD_RECHARGE, 72, Color(Art.SHIELD, 0.25), 2.0)
		draw_set_transform(Vector2.ZERO)
	# coque
	var hull_col: Color = ship_def["hull_color"]
	draw_rect(hull_r, Color(0, 0, 0, 0.25))
	Art.frame(self, hull_r, 0.9)
	for room in layout.rooms:   # silhouette de la coque, qui épouse les salles
		draw_rect((room["rect"] as Rect2).grow(14), hull_col.darkened(0.35))
	for room in layout.rooms:
		draw_rect((room["rect"] as Rect2).grow(14), Color(Art.GOLD_DIM, 0.5), false, 1.0)
	for room in layout.rooms:
		draw_rect((room["rect"] as Rect2).grow(13), hull_col.darkened(0.35))
	# salles
	layout.draw(self, func(room): return _floor_for(room, hull_col), true)
	for room in layout.rooms:
		var rr: Rect2 = room["rect"]
		if room["system"] != "" and sys.has(room["system"]):
			var s: Dictionary = sys[room["system"]]
			var damaged: bool = s["damage"] > 0
			Art.system_glyph(self, room["system"], rr.get_center() + Vector2(0, -6), 0.9, Art.DANGER if damaged else Color(Art.GOLD, 0.8))
			_draw_pips(rr.get_center() + Vector2(0, 20), s["level"], s["damage"])
			if damaged and s["repair"] > 0.0:
				Art.progress_arc(self, rr.get_center() + Vector2(0, -6), 26, s["repair"] / 100.0, Art.SAGE)
	for f in flashes:
		draw_rect(f["rect"], Color(f["col"], f["life"] * 0.5))
	# poste d'armes
	var cr := Rect2(weapons_console - Vector2(12, 20), Vector2(24, 40))
	draw_rect(cr, Color("#1a1620"))
	draw_rect(cr, Art.GOLD if gunner == 0 else Art.GOLD_DIM, false, 2.0)
	if gunner == 0 and state == "fight":
		Art.text(self, weapons_console + Vector2(-70, -28), "A : poste d'armes", 11, Color(Art.GOLD, 0.7 + 0.3 * sin(t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, 120)
	for f in fires:
		Art.fire(self, f["pos"], f["intensity"], t, 0.85)


func _floor_for(room: Dictionary, hull_col: Color) -> Color:
	var base := hull_col.lightened(0.14)
	if room["system"] != "" and sys.has(room["system"]) and sys[room["system"]]["damage"] > 0:
		base = base.lerp(Color("#5a2420"), 0.35 + 0.1 * sin(t * 4.0))
	if fires.any(func(f): return f["room"] == room["id"]):
		base = base.lerp(Color("#6a3010"), 0.25)
	return base


func _draw_pips(c: Vector2, level: int, damage: int) -> void:
	var w := 10.0
	var x0 := c.x - (level * (w + 3)) / 2.0
	for i in level:
		var r := Rect2(x0 + i * (w + 3), c.y, w, 6)
		var ok := i < level - damage
		draw_rect(r, Art.SAGE if ok else Art.DANGER)
		draw_rect(r, Art.GOLD_DIM, false, 1.0)


func _draw_enemy_ship() -> void:
	var b := enemy_layout.bounds
	var corrupt: bool = enemy["corrupt"]
	var trim := Art.CORRUPT if corrupt else Art.COPPER
	var hull_r := b.grow(18)
	var alive: bool = enemy["hull"] > 0
	if not alive:
		# explosion
		var k := clampf(t - (end_at - END_DELAY), 0.0, 1.5)
		for i in 10:
			var a := i * 2.4
			draw_circle(b.get_center() + Vector2(cos(a), sin(a)) * k * 90, 22 * (1.5 - k), Color(Art.GOLD, 0.5 * (1.5 - k)))
		return
	for i in enemy["shields"]:
		var rr := hull_r.grow(12 + i * 8)
		draw_set_transform(rr.get_center(), 0, Vector2(1.0, rr.size.y / rr.size.x))
		draw_arc(Vector2.ZERO, rr.size.x / 2, 0, TAU, 64, Color(Art.SHIELD, 0.5), 2.0)
		draw_set_transform(Vector2.ZERO)
	draw_rect(hull_r, Color("#1b1420") if corrupt else Color("#241b17"))
	draw_rect(hull_r, trim, false, 2.5)
	if corrupt:
		for k in 4:
			var pts := PackedVector2Array()
			var base := Vector2(hull_r.position.x + 20 + k * hull_r.size.x / 4, hull_r.end.y)
			for i in 10:
				var u := i / 9.0
				pts.append(base + Vector2(sin(u * 5 + t * 2 + k) * 10, u * 40))
			draw_polyline(pts, Color(Art.CORRUPT2, 0.6), 3.0, true)
	enemy_layout.draw(self, func(room): return _enemy_floor(room, corrupt), false, Color("#30242a"), trim)
	for room in enemy_layout.rooms:
		var rr: Rect2 = room["rect"]
		var sname: String = room["system"]
		var damaged: bool = enemy["sys"].has(sname) and enemy["sys"][sname]["damage"] > 0
		Art.system_glyph(self, sname, rr.get_center(), 0.75, Art.DANGER if damaged else (Art.CORRUPT2 if corrupt else Art.GOLD))
	# barre de coque ennemie
	Art.title(self, Vector2(ENEMY_AREA.position.x, ENEMY_AREA.position.y - 52), enemy["name"], 22, trim, HORIZONTAL_ALIGNMENT_CENTER, ENEMY_AREA.size.x)
	var bar := Rect2(ENEMY_AREA.get_center().x - 110, ENEMY_AREA.position.y - 38, 220, 12)
	Art.bar(self, bar, float(enemy["hull"]) / float(enemy["hull_max"]), Art.DANGER)
	Art.text(self, bar.position + Vector2(0, 30), "Coque %d/%d · Boucliers %d" % [enemy["hull"], enemy["hull_max"], enemy["shields"]], 13, Color(Art.IVORY, 0.7), HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)
	# viseur
	if gunner != 0 and game.players.has(gunner):
		var gp: Player = game.players[gunner]
		var hr := 22.0
		draw_arc(cross, hr, 0, TAU, 40, Color(gp.color, 0.9), 2.0)
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(cross + d * (hr - 8), cross + d * (hr + 7), gp.color, 2.0)
		var tn := _target_name()
		if tn != "":
			Art.text(self, cross + Vector2(-60, hr + 18), tn, 13, gp.color, HORIZONTAL_ALIGNMENT_CENTER, 120)


func _enemy_floor(room: Dictionary, corrupt: bool) -> Color:
	var base := Color("#2b2030") if corrupt else Color("#2e2622")
	var sname: String = room["system"]
	if enemy["sys"].has(sname) and enemy["sys"][sname]["damage"] > 0:
		base = base.lerp(Color("#6a2420"), 0.45)
	for f in flashes:
		if f["rect"] == room["rect"]:
			base = base.lerp(Color(1, 0.7, 0.3), f["life"])
	return base


func _draw_shots() -> void:
	for s in shots:
		if t < s["t0"]:
			continue
		var k := clampf((t - s["t0"]) / s["dur"], 0.0, 1.0)
		var a: Vector2 = s["from"]
		var b: Vector2 = s["to"]
		var mid := (a + b) / 2 + Vector2(0, -60)
		var p := a.bezier_interpolate(mid, mid, b, k)
		var col := Art.GOLD if s["owner"] == "player" else (Art.CORRUPT2 if s["weapon"] in ["spore", "tentacule"] else Art.DANGER)
		var size := 7.0 if s["dmg"] >= 2 else 4.5
		var p2 := a.bezier_interpolate(mid, mid, b, maxf(0.0, k - 0.06))
		draw_line(p2, p, Color(col, 0.5), size)
		draw_circle(p, size, col)


func _draw_weapon_panel() -> void:
	var r := Rect2(40, 648, 780, 54)
	var who := "automatique"
	if gunner != 0 and game.players.has(gunner):
		who = game.players[gunner].player_name
	Art.title(self, r.position + Vector2(0, 18), "Armes · %s" % who, 17, Art.GOLD)
	var x := r.position.x + 210
	var ws := _weapons_state()
	for w in ws:
		var bar := Rect2(x, r.position.y + 6, 120, 12)
		var col := Art.GOLD if w["ready"] else (Art.CELL if w["powered"] else Color(Art.IVORY, 0.2))
		Art.bar(self, bar, w["charge"], col)
		Art.text(self, Vector2(x, r.position.y + 36), w["name"] + ("" if w["powered"] else " (hors service)"), 13, Color(Art.IVORY, 0.75 if w["powered"] else 0.4))
		x += 150
	Art.icon(self, "bouclier", Vector2(x + 20, r.position.y + 12))
	Art.text(self, Vector2(x + 36, r.position.y + 18), "%d/%d" % [shield_layers, eff("boucliers")], 15)
	Art.text(self, Vector2(x, r.position.y + 40), "Esquive %d %%" % int(round(player_evasion() * 100)), 13, Color(Art.IVORY, 0.6))
	Art.text(self, Vector2(870, 668), "B : éteindre / réparer · A au poste d'armes : viser", 14, Color(Art.IVORY, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 380)
