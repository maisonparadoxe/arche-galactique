extends Node2D
## Contrôleur de L'Arche galactique : réseau, joueurs, enchaînement des scènes.
##
## Académie (hub) → choix du vaisseau → carte du secteur ⇄ combat / événement / halte / boutique
## → boss → bilan → Académie.

const PALETTE := [
	Color("#e8a33d"), Color("#3fb0a8"), Color("#d0603f"), Color("#9bc07a"),
	Color("#e08fae"), Color("#7d97e0"), Color("#f2e8d5"), Color("#62c6e6"),
]
const SPECIES := {
	"humain": "Répare deux fois plus vite",
	"automate": "Visée assistée (cible plus large)",
	"salamandrin": "Éteint les feux deux fois plus vite",
	"colosse": "Porte les charges sans ralentir",
}
const SPECIES_NAMES := {"humain": "Humain", "automate": "Automate", "salamandrin": "Salamandrin", "colosse": "Colosse"}
const ORNAMENTS := ["aucun", "fleur", "plume", "couronne"]
# Recrues : des noms empruntés aux romans de Jules Verne et H. G. Wells (domaine public)
const RECRUIT_NAMES := ["Aronnax", "Conseil", "Ned", "Passepartout", "Ardan", "Barbicane", "Nicholl", "Weena", "Fogg", "Lidenbrock"]
const RECRUIT_COLORS := [Color("#a88f6a"), Color("#7f9a8c"), Color("#a07a86"), Color("#8c8aa8"), Color("#9a9a6e"), Color("#6f8fa0")]
const ACADEMY_RECRUITS := 3   # recrues présentes à l'Académie, en plus des avatars des joueurs
const MAX_PLAYERS := 8
const INPUT_STALE_MS := 500

const SfxScript := preload("res://sfx.gd")
const ColonyScript := preload("res://colony.gd")
const QuipsScript := preload("res://quips.gd")

const SCENES := {
	"academie": preload("res://academy.gd"),
	"choix": preload("res://ship_select.gd"),
	"carte": preload("res://sector_map.gd"),
	"combat": preload("res://combat.gd"),
	"abordage": preload("res://boarding.gd"),
	"evenement": preload("res://event_scene.gd"),
	"boutique": preload("res://shop.gd"),
	"bilan": preload("res://results.gd"),
}

var net: NetServer
var sfx                               # sons et musique (sfx.gd)
var players: Dictionary = {}           # peer_id -> membre d'équipage contrôlé par ce téléphone
var people: Dictionary = {}            # peer_id -> {name, color, slot, token, medals, choosing}
var last_colony: Dictionary = {}    # bilan de colonie de la dernière expédition
var colony                           # la colonie de l'arche (colony.gd), conservée d'une expédition à l'autre
var quips                            # répliques humoristiques (quips.gd)
var crew: Array = []                   # tous les membres d'équipage présents (contrôlés ou libres)
var profiles_by_token: Dictionary = {} # token -> emplacement de couleur
var _next_crew_id := 1
var last_difficulty := "normal"        # proposée par défaut au vote suivant
var run: RunState
var scene: GameScene
var scene_name := ""
var join_url := ""
var qr_texture: Texture2D
var stars: Array = []
var test_mode := false
var t := 0.0
var _pending: Array = []               # changement de scène demandé pendant une mise à jour


func _ready() -> void:
	test_mode = "--test" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if test_mode and a.begins_with("--speed="):
			Engine.time_scale = float(a.trim_prefix("--speed="))  # tests d'équilibrage accélérés
	RenderingServer.set_default_clear_color(Art.BG)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		stars.append([Vector2(rng.randf() * 1280, rng.randf() * 720), rng.randf_range(0.6, 1.8), rng.randf()])
	sfx = SfxScript.new()
	add_child(sfx)
	quips = QuipsScript.new(self)
	colony = ColonyScript.new()
	colony.persist = not test_mode
	colony.load_from_disk()
	net = NetServer.new()
	add_child(net)
	net.player_joined.connect(_on_joined)
	net.player_left.connect(_on_left)
	net.player_input.connect(_on_input)
	net.player_action.connect(_on_action)
	net.player_vote.connect(_on_vote)
	net.player_rtt.connect(func(id, ms): if players.has(id): players[id].rtt = ms)
	net.debug_requested.connect(_on_debug)
	join_url = "http://%s:%d" % [_local_ip(), NetServer.HTTP_PORT]
	var matrix := QR.encode(join_url)
	if not matrix.is_empty():
		qr_texture = ImageTexture.create_from_image(QR.to_image(matrix, 4, Color("#1a1420"), Art.IVORY))
	print("[game] Les téléphones rejoignent sur ", join_url)
	_switch("academie", {})


# ---------------------------------------------------------------- scènes

## Demande un changement de scène ; il s'applique à la fin de l'image en cours.
func goto(name: String, args := {}) -> void:
	_pending = [name, args]


func _switch(name: String, args: Dictionary) -> void:
	if scene:
		scene.exit()
		scene.queue_free()
	for p: Player in crew:
		p.reset_state()
		p.clone_gen = int(run.clones.get(p.crew_id, 0)) if run else 0
	for who in people.values():
		who["choosing"] = false
		who["hint_key"] = "?"
	if name == "academie":
		rebuild_crew(0, ACADEMY_RECRUITS)
	scene_name = name
	sfx.set_music("action" if name == "abordage" else "calme")
	scene = SCENES[name].new()
	scene.game = self
	add_child(scene)
	move_child(scene, 0)  # les personnages se dessinent par-dessus la scène
	scene.enter(args)
	_refresh_players()
	scene.send_layouts()
	print("[game] scène : ", name)


func _refresh_players() -> void:
	var visible_now := scene.shows_players()
	for p: Player in crew:
		p.visible = visible_now


## Démarre une expédition avec le vaisseau choisi.
func start_run(ship_id: String, difficulty := "normal") -> void:
	run = RunState.create(ship_id, difficulty)
	colony.apply_to(run)
	rebuild_crew(maxi(int(ShipData.PLAYER_SHIPS[ship_id].get("crew", 4)), people.size()))
	goto("carte")


## Fin de l'expédition : victoire ou défaite.
func end_run(victory: bool) -> void:
	run.victory = victory
	run.ended = true
	last_colony = colony.register(run)
	goto("bilan")


## Après un nœud de la carte (combat gagné, événement terminé…).
func node_done() -> void:
	if run.hull <= 0:
		end_run(false)
	elif run.node(run.current)["type"] == "boss":
		end_run(true)
	else:
		goto("carte")


func toast_all(text: String) -> void:
	for p: Player in players.values():
		net.send(p.peer_id, {"t": "toast", "text": text})


# ---------------------------------------------------------------- joueurs

func _on_joined(id: int, profile: Dictionary) -> void:
	if people.size() >= MAX_PLAYERS:
		net.kick(id, {"t": "full"})
		return
	var used := {}
	for who in people.values():
		used[who["slot"]] = true
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
	var species: String = profile["species"] if SPECIES.has(profile["species"]) else "humain"
	var ornament: String = profile["ornament"] if profile["ornament"] in ORNAMENTS else "aucun"
	people[id] = {"name": profile["name"], "color": PALETTE[slot], "slot": slot, "token": profile["token"],
		"species": species, "ornament": ornament, "medals": 0, "choosing": false}
	net.send(id, {"t": "welcome", "slot": slot, "color": "#" + PALETTE[slot].to_html(false), "name": profile["name"],
		"species": species, "ability": SPECIES[species]})
	if slot != wanted and wanted >= 0:
		net.send(id, {"t": "toast", "text": "Couleur déjà prise : on t'en a donné une autre."})
	# Reprendre son avatar s'il est encore à bord (reconnexion), sinon en créer un
	var body: Player = null
	for c: Player in crew:
		if c.owner_token != "" and c.owner_token == profile["token"]:
			body = c
	if body == null:
		body = _new_crew_member(profile["name"], species, ornament, PALETTE[slot], profile["token"])
		scene.on_join(body)
	else:
		body.player_name = profile["name"]
		body.species = species
		body.ornament = ornament
		body.color = PALETTE[slot]
	if not body.is_free():
		body = _first_free()
	if body == null:
		body = _new_crew_member(profile["name"], species, ornament, PALETTE[slot], profile["token"])
		scene.on_join(body)
	body.visible = scene.shows_players()
	_take_control(id, body)
	print("[game] %s (%s) a rejoint" % [profile["name"], species])


func _on_left(id: int) -> void:
	if not people.has(id):
		return
	if players.has(id):
		var p: Player = players[id]
		scene.on_leave(p)
		p.seated = false
		p.release()
		players.erase(id)
	print("[game] %s est parti" % people[id]["name"])
	people.erase(id)


# ---------------------------------------------------------------- équipage

func _new_crew_member(member_name: String, species: String, ornament: String, col: Color, token: String) -> Player:
	var p := Player.new()
	p.crew_id = _next_crew_id
	_next_crew_id += 1
	p.player_name = member_name
	p.species = species
	p.ornament = ornament
	p.color = col
	p.owner_token = token
	p.slot = crew.size()
	p.last_input_ms = Time.get_ticks_msec()
	crew.append(p)
	add_child(p)
	return p


func _first_free() -> Player:
	for c: Player in crew:
		if c.is_free():
			return c
	return null


## Recompose l'équipage : les avatars des joueurs présents, complétés par des recrues
## d'espèces encore absentes. Chaque joueur reprend son avatar.
func rebuild_crew(size: int, min_recruits := 0) -> void:
	for peer in players.keys():
		var p: Player = players[peer]
		p.seated = false
		p.release()
	players.clear()
	for c: Player in crew:
		c.queue_free()
	crew.clear()
	var avatars := {}
	for peer in people:
		var who: Dictionary = people[peer]
		avatars[peer] = _new_crew_member(who["name"], who["species"], who["ornament"], who["color"], who["token"])
	var names := RECRUIT_NAMES.duplicate()
	names.shuffle()
	var i := 0
	while crew.size() < size or i < min_recruits:
		var present := crew.map(func(c): return c.species)
		var missing := SPECIES.keys().filter(func(sp): return not (sp in present))
		var sp: String = missing.pick_random() if not missing.is_empty() else SPECIES.keys().pick_random()
		_new_crew_member(names[i % names.size()], sp, ["aucun", "plume", "fleur"].pick_random(), RECRUIT_COLORS[i % RECRUIT_COLORS.size()], "")
		i += 1
	for peer in avatars:
		_take_control(peer, avatars[peer], false)
		net.send(peer, _controlled_msg(avatars[peer], peer))


func _take_control(peer: int, body: Player, notify := true) -> void:
	var who: Dictionary = people[peer]
	if players.has(peer) and players[peer] != body:
		var old: Player = players[peer]
		scene.on_release(old)
		old.seated = false
		old.release()
	players[peer] = body
	body.peer_id = peer
	body.controller_name = who["name"]
	body.controller_color = who["color"]
	body.axis = Vector2.ZERO
	body.last_input_ms = Time.get_ticks_msec()
	who["choosing"] = false
	who["hint_key"] = "?"
	if notify:
		net.send(peer, _controlled_msg(body, peer))
		net.send(peer, scene.layout_for(body))


func _controlled_msg(body: Player, peer: int) -> Dictionary:
	return {"t": "controle", "name": body.player_name, "species": body.species, "species_label": SPECIES_NAMES[body.species],
		"ability": SPECIES[body.species], "color": "#" + body.color.to_html(false), "ornament": body.ornament,
		"own": body.owner_token != "" and body.owner_token == people[peer]["token"]}


## Liste de l'équipage envoyée au téléphone (écran « Équipage »).
func roster_for(peer: int) -> Dictionary:
	var list: Array = []
	var mine: Player = players.get(peer)
	for c: Player in crew:
		var status := "libre"
		if c == mine:
			status = "toi"
		elif not c.is_free():
			status = people[c.peer_id]["name"] if people.has(c.peer_id) else "occupé"
		list.append({"id": c.crew_id, "name": c.player_name, "species": c.species, "species_label": SPECIES_NAMES[c.species],
			"ability": SPECIES[c.species], "color": "#" + c.color.to_html(false), "ornament": c.ornament,
			"status": status, "free": c.is_free(), "where": scene.location_name(c),
			"avatar": c.owner_token != "" and people.has(peer) and c.owner_token == people[peer]["token"]})
	# toi d'abord, puis les membres libres, puis ceux des autres joueurs
	var rank := func(e): return 0 if e["status"] == "toi" else (1 if e["free"] else 2)
	list.sort_custom(func(x, y): return rank.call(x) < rank.call(y))
	return {"t": "layout", "mode": "equipage", "crew": list}


func _open_roster(peer: int) -> void:
	people[peer]["choosing"] = true
	var p: Player = players[peer]
	p.axis = Vector2.ZERO
	net.send(peer, roster_for(peer))


func _refresh_rosters() -> void:
	for peer in people:
		if people[peer]["choosing"]:
			net.send(peer, roster_for(peer))


func _pick_crew(peer: int, crew_id: int) -> void:
	for c: Player in crew:
		if c.crew_id == crew_id:
			if c == players.get(peer):
				_close_roster(peer)
				return
			if not c.is_free():
				net.send(peer, {"t": "toast", "text": "%s est déjà contrôlé par un autre joueur" % c.player_name})
				net.send(peer, roster_for(peer))
				return
			_take_control(peer, c)
			net.send(peer, {"t": "toast", "text": "Tu contrôles maintenant %s" % c.player_name})
			_refresh_rosters()
			return


## Envoie à chaque téléphone les touches utiles du moment, seulement quand elles changent.
func _push_hints() -> void:
	for peer in players:
		var p: Player = players[peer]
		var h: Dictionary = {}
		if scene.shows_players() and not p.seated and not people[peer]["choosing"]:
			h = scene.hints_for(p)
		var key := JSON.stringify(h)
		if people[peer].get("hint_key", "") != key:
			people[peer]["hint_key"] = key
			var out := {}
			for b in h:
				out[str(b)] = h[b]
			net.send(peer, {"t": "hint", "hints": out})


func _close_roster(peer: int) -> void:
	people[peer]["choosing"] = false
	if players.has(peer):
		net.send(peer, scene.layout_for(players[peer]))


func _on_input(id: int, axis: Vector2, buttons: Array) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	p.axis = axis
	p.buttons = buttons
	p.last_input_ms = Time.get_ticks_msec()


func _on_action(id: int, action: String, msg: Dictionary) -> void:
	if not players.has(id):
		return
	match action:
		"equipage":
			if scene.shows_players():
				_open_roster(id)
		"pick":
			if scene.shows_players():
				_pick_crew(id, int(msg.get("id", 0)))
		"back":
			_close_roster(id)
		_:
			scene.on_action(players[id], action, msg)


func _on_vote(id: int, option: String) -> void:
	if players.has(id):
		scene.on_vote(players[id], option)


func _on_debug(id: int, msg: Dictionary) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	if test_mode and msg.get("t") == "dbg_tp":
		p.position = Vector2(float(msg.get("x", 0)), float(msg.get("y", 0)))
		p.prev_buttons = p.buttons.duplicate()
	if test_mode and msg.get("t") == "dbg_cmd":
		match str(msg.get("cmd", "")):
			"shot": _shot(str(msg.get("path", "user://shot.png")))
			"goto": goto(str(msg.get("scene", "academie")), msg.get("args", {}))
			"quip": quips.react(str(msg.get("situation", "victoire")), null, true)
			"end_run": if run: end_run(bool(msg.get("win", true)))
			"colony": colony.pop = int(msg.get("value", 0))
			"madness": if run: run.madness = clampi(int(msg.get("value", 0)), 0, 3)
			"rep": if run: run.renown = clampi(int(msg.get("value", 0)), -10, 10)
			_: scene.debug_command(p, msg)
	var info := {"t": "dbg", "scene": scene_name, "x": p.position.x, "y": p.position.y, "seated": p.seated,
		"carrying": p.carrying, "medals": people[id]["medals"], "me": p.crew_id, "me_name": p.player_name,
		"crew": crew.map(func(c): return {"id": c.crew_id, "name": c.player_name, "species": c.species, "peer": c.peer_id,
			"x": c.position.x, "y": c.position.y, "avatar": c.owner_token != ""})}
	if run:
		info["colony"] = {"pop": colony.pop, "expeditions": colony.expeditions, "buildings": colony.unlocked().map(func(b): return b["id"])}
		info["quips"] = crew.filter(func(q): return q.bubble_t > 0.0).map(func(q): return q.bubble)
		info["run"] = {"ship": run.ship_id, "hull": run.hull, "hull_max": run.hull_max, "fuel": run.fuel, "scrap": run.scrap,
			"colons": run.colons, "renown": run.renown, "clones_total": run.clone_total(), "node": run.current, "difficulty": run.difficulty, "layers": run.layers, "layer": run.depth(), "type": run.node(run.current)["type"],
			"weapons": run.weapons, "shields": run.shields, "engines": run.engines, "victory": run.victory, "ended": run.ended}
	info.merge(scene.debug_info(p), true)
	net.send(id, info)


# ---------------------------------------------------------------- boucle

func _process(delta: float) -> void:
	t += delta
	quips.tick(delta)
	_maybe_screenshot()
	var now := Time.get_ticks_msec()
	for p: Player in crew:
		p.working = false
	for peer in players:
		var p: Player = players[peer]
		if now - p.last_input_ms > INPUT_STALE_MS or people[peer]["choosing"]:
			p.axis = Vector2.ZERO
		if p.pressed(3) and scene.shows_players() and not p.seated:
			_open_roster(peer)
	scene.update(delta)
	_push_hints()
	for p: Player in crew:
		p.prev_buttons = p.buttons.duplicate()
	if not _pending.is_empty():
		var next: Array = _pending
		_pending = []
		_switch(next[0], next[1])
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toast_all("Son coupé sur le PC" if sfx.toggle_mute() else "Son rétabli sur le PC")
	# Raccourci clavier sur le PC : Entrée lance une expédition depuis l'Académie.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and scene_name == "academie":
		goto("choix")


func _draw() -> void:
	Art.stars(self, stars, t, 1.0 if scene_name in ["carte", "combat"] else 0.0)


## Petit QR code dans un coin, pour que l'on puisse rejoindre à tout moment.
func draw_small_qr(ci: CanvasItem, pos: Vector2, size := 64.0) -> void:
	if qr_texture == null:
		return
	var r := Rect2(pos, Vector2(size, size))
	ci.draw_rect(r.grow(3), Color("#1a1420"))
	ci.draw_texture_rect(qr_texture, r, false)
	ci.draw_rect(r.grow(3), Art.GOLD_DIM, false, 1.0)


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


## Tests : capture d'écran demandée par un faux téléphone ({"t":"dbg_cmd","cmd":"shot","path":…}).
func _shot(path: String) -> void:
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
