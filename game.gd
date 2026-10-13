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
const ORNAMENTS := ["aucun", "fleur", "plume", "couronne"]
const MAX_PLAYERS := 8
const INPUT_STALE_MS := 500

const SCENES := {
	"academie": preload("res://academy.gd"),
	"choix": preload("res://ship_select.gd"),
	"carte": preload("res://sector_map.gd"),
	"combat": preload("res://combat.gd"),
	"evenement": preload("res://event_scene.gd"),
	"boutique": preload("res://shop.gd"),
	"bilan": preload("res://results.gd"),
}

var net: NetServer
var players: Dictionary = {}           # peer_id -> Player
var profiles_by_token: Dictionary = {} # token -> emplacement de couleur
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
	for p: Player in players.values():
		p.reset_state()
	scene_name = name
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
	for p: Player in players.values():
		p.visible = visible_now


## Démarre une expédition avec le vaisseau choisi.
func start_run(ship_id: String) -> void:
	run = RunState.create(ship_id)
	goto("carte")


## Fin de l'expédition : victoire ou défaite.
func end_run(victory: bool) -> void:
	run.victory = victory
	run.ended = true
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
	p.last_input_ms = Time.get_ticks_msec()
	players[id] = p
	add_child(p)
	net.send(id, {"t": "welcome", "slot": slot, "color": "#" + p.color.to_html(false), "name": p.player_name,
		"species": p.species, "ability": SPECIES[p.species]})
	if slot != wanted and wanted >= 0:
		net.send(id, {"t": "toast", "text": "Couleur déjà prise : on t'en a donné une autre."})
	scene.on_join(p)
	p.visible = scene.shows_players()
	net.send(id, scene.layout_for(p))
	print("[game] %s (%s) a rejoint" % [p.player_name, p.species])


func _on_left(id: int) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	scene.on_leave(p)
	print("[game] %s est parti" % p.player_name)
	players.erase(id)
	p.queue_free()


func _on_input(id: int, axis: Vector2, buttons: Array) -> void:
	if not players.has(id):
		return
	var p: Player = players[id]
	p.axis = axis
	p.buttons = buttons
	p.last_input_ms = Time.get_ticks_msec()


func _on_action(id: int, action: String, msg: Dictionary) -> void:
	if players.has(id):
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
	if test_mode and msg.get("t") == "dbg_cmd":
		match str(msg.get("cmd", "")):
			"shot": _shot(str(msg.get("path", "user://shot.png")))
			"goto": goto(str(msg.get("scene", "academie")), msg.get("args", {}))
			_: scene.debug_command(p, msg)
	var info := {"t": "dbg", "scene": scene_name, "x": p.position.x, "y": p.position.y, "seated": p.seated,
		"carrying": p.carrying, "medals": p.medals}
	if run:
		info["run"] = {"ship": run.ship_id, "hull": run.hull, "hull_max": run.hull_max, "fuel": run.fuel, "scrap": run.scrap,
			"colons": run.colons, "node": run.current, "layer": run.depth(), "type": run.node(run.current)["type"],
			"weapons": run.weapons, "shields": run.shields, "engines": run.engines, "victory": run.victory, "ended": run.ended}
	info.merge(scene.debug_info(p), true)
	net.send(id, info)


# ---------------------------------------------------------------- boucle

func _process(delta: float) -> void:
	t += delta
	_maybe_screenshot()
	var now := Time.get_ticks_msec()
	for p: Player in players.values():
		if now - p.last_input_ms > INPUT_STALE_MS:
			p.axis = Vector2.ZERO
	scene.update(delta)
	for p: Player in players.values():
		p.prev_buttons = p.buttons.duplicate()
	if not _pending.is_empty():
		var next: Array = _pending
		_pending = []
		_switch(next[0], next[1])
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
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
