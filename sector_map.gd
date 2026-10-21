extends VoteScene
## Carte du secteur : on vote la prochaine destination.
## Chaque saut coûte une unité de carburant ; sans carburant, la coque souffre.

const VOTE_SECONDS := 20.0
const AREA := Rect2(110, 196, 1060, 420)
const TRAVEL_TIME := 1.6

var travel_from := Vector2.ZERO
var travel_to := Vector2.ZERO
var travel_start := -1.0
var target_id := -1


func enter(_args: Dictionary) -> void:
	var run: RunState = game.run
	var opts: Array = []
	var nexts := run.choices()
	for n in nexts:
		var label := RunState.type_label(n["type"])
		var same := nexts.filter(func(m): return m["type"] == n["type"]).size() > 1
		if same:
			label += " (haut)" if n["pos"].y < 0.5 else " (bas)"
		var desc := _describe(n["type"])
		if run.fuel == 0:
			desc += " · plus de carburant : -%d coque" % RunState.DRIFT_DAMAGE
		opts.append({"id": str(n["id"]), "label": label, "desc": desc})
	var title := "Prochaine destination"
	var text := "Carburant : %d. Chaque saut en consomme un." % run.fuel
	start_vote(title, text, opts, VOTE_SECONDS, "")


func _describe(type: String) -> String:
	match type:
		"combat": return "Un vaisseau hostile croise dans les parages"
		"evenement": return "Un signal inconnu, à vos risques et périls"
		"halte": return "Un lieu sûr pour souffler un peu"
		"boutique": return "Un marchand : carburant, réparations, armes"
		"abordage": return "Un navire marchand à aborder : butin, mais l'équipage se bat"
		"ile": return "Une île au trésor : des ruines, des gardiens, un coffre"
		"epave": return "Une épave que l'Indicible a fait sienne : dangereux, mais un reliquaire au fond"
		"boss": return "L'Indicible barre la route de l'arche"
	return ""


func node_pos(n: Dictionary) -> Vector2:
	var p: Vector2 = n["pos"]
	return Vector2(AREA.position.x + p.x / (game.run.layers - 1) * AREA.size.x, AREA.position.y + p.y * AREA.size.y)


func on_vote_result(id: String) -> void:
	var run: RunState = game.run
	target_id = int(id)
	travel_from = node_pos(run.node(run.current))
	travel_to = node_pos(run.node(target_id))
	travel_start = t
	var drift := run.jump_to(target_id)
	if drift > 0:
		game.toast_all("Plus de carburant : le vaisseau dérive (-%d coque)" % drift)


func update(delta: float) -> void:
	super.update(delta)
	if travel_start >= 0.0 and t - travel_start >= TRAVEL_TIME:
		travel_start = -1.0
		_arrive()


func _arrive() -> void:
	var run: RunState = game.run
	if run.hull <= 0:
		game.end_run(false)
		return
	var n := run.node(target_id)
	match n["type"]:
		"combat":
			game.goto("combat", {"enemy": ShipData.enemy_for_depth(int(n["layer"]))})
		"boss":
			game.goto("combat", {"enemy": "avatar"})
		"abordage":
			game.goto("abordage", {"layout": ["galion", "caravelle"].pick_random()})
		"ile":
			game.goto("abordage", {"layout": "ile"})
		"epave":
			game.goto("abordage", {"layout": "epave"})
		"evenement", "halte":
			game.goto("evenement", {"kind": n["type"]})
		"boutique":
			game.goto("boutique")
		_:
			game.goto("carte")


func debug_info(p: Player) -> Dictionary:
	var d := super.debug_info(p)
	d["choices"] = game.run.choices().map(func(n): return {"id": n["id"], "type": n["type"]})
	return d


# ---------------------------------------------------------------- dessin

func _draw() -> void:
	var run: RunState = game.run
	Hud.draw(self, run)
	Art.title(self, Vector2(40, 110), "Secteur de la Nébuleuse d'Argent", 30)
	Art.text(self, Vector2(44, 136), "L'arche Éléa suit votre sillage. Choisissez la route.", 16, Color(Art.IVORY, 0.6))
	game.draw_small_qr(self, Vector2(1190, 22), 64)
	_draw_corruption(run)
	# Liens
	for n in run.nodes:
		for j in n["next"]:
			var m := run.node(j)
			var a := node_pos(n)
			var b := node_pos(m)
			var reachable: bool = n["id"] == run.current and travel_start < 0.0
			var col := Art.GOLD if reachable else Color(Art.GOLD_DIM, 0.55 if not m["visited"] or not n["visited"] else 0.9)
			var pts := PackedVector2Array()
			var mid := (a + b) / 2
			var c1 := Vector2(mid.x, a.y)
			var c2 := Vector2(mid.x, b.y)
			for i in 21:
				pts.append(a.bezier_interpolate(c1, c2, b, i / 20.0))
			draw_polyline(pts, col, 2.5 if reachable else 1.5, true)
	# Nœuds
	for n in run.nodes:
		var c := node_pos(n)
		var is_current: bool = n["id"] == run.current
		var selectable: bool = vote_active and str(n["id"]) in options.map(func(o): return o["id"])
		var r := 26.0 if n["type"] == "boss" else 20.0
		if selectable:
			draw_circle(c, r + 10 + 3 * sin(t * 3.0), Color(Art.GOLD, 0.12))
		draw_circle(c, r, Color("#1e1828") if not n["visited"] else Color("#2a3326"))
		draw_arc(c, r, 0, TAU, 40, Art.GOLD if selectable or is_current else Art.GOLD_DIM, 2.5 if selectable else 1.5)
		_node_icon(n["type"], c)
		if selectable:
			Art.text(self, c + Vector2(-70, r + 20), RunState.type_label(n["type"]), 14, Art.IVORY, HORIZONTAL_ALIGNMENT_CENTER, 140)
			draw_voters(str(n["id"]), c + Vector2(-8, -r - 16))
	# Vaisseau
	var ship_pos := node_pos(run.node(run.current))
	if travel_start >= 0.0:
		var k := clampf((t - travel_start) / TRAVEL_TIME, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		ship_pos = travel_from.lerp(travel_to, k)
	_draw_ship_marker(ship_pos + Vector2(0, -2))
	draw_vote_footer()


func _draw_ship_marker(c: Vector2) -> void:
	var pts := PackedVector2Array([c + Vector2(16, 0), c + Vector2(-10, -10), c + Vector2(-5, 0), c + Vector2(-10, 10)])
	draw_colored_polygon(pts, Art.IVORY)
	pts.append(pts[0])
	draw_polyline(pts, Art.GOLD, 2.0)
	draw_circle(c + Vector2(-14, 0), 4 + sin(t * 12.0), Color(Art.CELL, 0.8))


func _node_icon(type: String, c: Vector2) -> void:
	match type:
		"combat":
			draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), Art.DANGER, 3.0)
			draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), Art.DANGER, 3.0)
		"evenement":
			Art.title(self, c + Vector2(-20, 9), "?", 26, Art.IVORY, HORIZONTAL_ALIGNMENT_CENTER, 40)
		"halte":
			for i in 5:
				var a := TAU * i / 5.0 - PI / 2
				draw_line(c, c + Vector2(cos(a), sin(a)) * 10, Art.SAGE, 3.0)
		"boutique":
			Art.icon(self, "ferraille", c)
		"abordage":
			draw_line(c + Vector2(-10, 8), c + Vector2(10, -10), Art.NEON_PINK_ICON, 3.0)
			draw_line(c + Vector2(-4, -10), c + Vector2(10, 4), Art.NEON_PINK_ICON, 2.0)
		"epave":
			draw_arc(c + Vector2(0, 2), 10, 0.4, PI - 0.4, 12, Art.CORRUPT2, 3.0)
			draw_line(c + Vector2(-8, 4), c + Vector2(8, -6), Art.CORRUPT, 3.0)
			draw_line(c + Vector2(8, 4), c + Vector2(-8, -6), Art.CORRUPT, 3.0)
		"ile":
			draw_arc(c + Vector2(0, 6), 11, PI, TAU, 14, Art.SAGE, 3.0)
			draw_line(c + Vector2(0, 6), c + Vector2(0, -8), Art.SAGE, 3.0)
			draw_circle(c + Vector2(0, -10), 4, Art.GOLD)
		"boss":
			Art.system_glyph(self, "coeur", c, 1.0)
		"depart":
			draw_circle(c, 6, Art.GOLD)


## Le brouillard de l'Indicible gagne le secteur derrière le vaisseau.
func _draw_corruption(run: RunState) -> void:
	if run.depth() < 1:
		return
	var front := AREA.position.x + (float(run.depth()) - 0.6) / (run.layers - 1) * AREA.size.x
	for i in 14:
		var x := front * (i / 14.0)
		draw_rect(Rect2(x, 150, front / 14.0 + 1, 480), Color(Art.CORRUPT, 0.05 + 0.1 * i / 14.0))
	for k in 5:
		var y := 190.0 + k * 95
		var pts := PackedVector2Array()
		for i in 12:
			var u := i / 11.0
			pts.append(Vector2(front - 60 + u * 70 + sin(t * 1.5 + k) * 6, y + sin(u * 6 + t * 2 + k) * 12))
		draw_polyline(pts, Color(Art.CORRUPT2, 0.35), 2.0, true)
