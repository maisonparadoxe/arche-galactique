extends VoteScene
## Boutique : on vote un achat à la fois, jusqu'à voter « Reprendre la route ».

const VOTE_SECONDS := 25.0

var items: Array = []     # [{id, label, desc, price, effects, stock}]
var last_bought := ""
var rounds := 0


func enter(_args: Dictionary) -> void:
	items = [
		{"id": "carburant", "label": "Carburant ×3", "desc": "Trois sauts de plus", "price": 6, "effects": {"fuel": 3}, "stock": 3},
		{"id": "reparation", "label": "Réparer la coque (+8)", "desc": "Soudure et rivets", "price": 8, "effects": {"hull": 8}, "stock": 3},
	]
	var specials := [
		{"id": "bouclier", "label": "Bouclier renforcé", "desc": "+1 couche de bouclier (max 3)", "price": 30, "effects": {"shields": 1}, "stock": 1},
		{"id": "moteurs", "label": "Moteurs améliorés", "desc": "+1 moteurs : esquive accrue", "price": 20, "effects": {"engines": 1}, "stock": 1},
		{"id": "canon_lourd", "label": "Canon lourd", "desc": "2 dégâts, charge lente (3 armes max)", "price": 28, "effects": {"weapon": "canon_lourd"}, "stock": 1},
		{"id": "torpille", "label": "Torpille", "desc": "2 dégâts, traverse les boucliers", "price": 32, "effects": {"weapon": "torpille"}, "stock": 1},
	]
	specials.shuffle()
	items.append_array(specials.slice(0, 2))
	# la réputation change les prix
	var mult: float = game.run.price_mult()
	for it in items:
		it["price"] = maxi(1, int(round(float(it["price"]) * mult)))
	_new_round()


func _new_round() -> void:
	var run: RunState = game.run
	var opts: Array = []
	for it in items:
		if it["stock"] <= 0:
			continue
		var full: bool = (it["id"] == "reparation" and run.hull >= run.hull_max) \
			or (it["id"] == "bouclier" and run.shields >= 3) \
			or (it["id"] in ["canon_lourd", "torpille"] and run.weapons.size() >= 3) \
			or (it["id"] == "moteurs" and run.engines >= 4)
		var too_dear: bool = run.scrap < it["price"]
		opts.append({"id": it["id"], "label": "%s · %d ferraille" % [it["label"], it["price"]], "desc": it["desc"],
			"disabled": too_dear or full})
	opts.append({"id": "partir", "label": "Reprendre la route", "desc": "Quitter la boutique"})
	var text := "Ferraille disponible : %d" % run.scrap
	if run.renown >= 3:
		text += " · le colporteur vous fait un prix, « %s »" % RunState.renown_title(run.renown).to_lower()
	elif run.renown <= -3:
		text += " · le colporteur majore ses prix, « %s »" % RunState.renown_title(run.renown).to_lower()
	if last_bought != "":
		text = "Acheté : %s. " % last_bought + text
	start_vote("Boutique du Colporteur", text, opts, VOTE_SECONDS, "partir")


func _item(id: String) -> Dictionary:
	for it in items:
		if it["id"] == id:
			return it
	return {}


func on_vote_result(id: String) -> void:
	rounds += 1
	if id == "partir" or rounds > 8:
		game.node_done()
		return
	var it := _item(id)
	var run: RunState = game.run
	if not it.is_empty() and run.scrap >= it["price"]:
		run.add_scrap(-it["price"])
		run.apply(it["effects"])
		it["stock"] -= 1
		last_bought = it["label"]
		game.toast_all("Acheté : %s" % it["label"])
	_new_round()


func debug_info(p: Player) -> Dictionary:
	var d := super.debug_info(p)
	d["items"] = items.map(func(i): return i["id"])
	return d


func _draw() -> void:
	var run: RunState = game.run
	Hud.draw(self, run)
	game.draw_small_qr(self, Vector2(1190, 22), 64)
	var card := Rect2(140, 100, 1000, 550)
	Art.panel(self, card, 1.0)
	Art.title(self, card.position + Vector2(0, 62), "Boutique du Colporteur", 40, Art.GOLD, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	Art.rule(self, Vector2(card.get_center().x - 160, card.position.y + 84), 320)
	Art.text(self, card.position + Vector2(0, 116), "Lanternes, écharpes et pièces détachées. Votez un achat à la fois.", 17, Color(Art.IVORY, 0.6), HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	var y := card.position.y + 168
	for o in options:
		var dis: bool = o.get("disabled", false)
		var row := Rect2(card.position.x + 90, y - 28, card.size.x - 180, 48)
		draw_rect(row, Color(1, 1, 1, 0.03 if not dis else 0.0))
		draw_rect(row, Art.GOLD_DIM if not dis else Color(Art.GOLD_DIM, 0.3), false, 1.0)
		var ic := Vector2(row.position.x + 26, y - 4)
		match o["id"]:
			"carburant": Art.icon(self, "carburant", ic)
			"reparation": Art.icon(self, "coque", ic)
			"bouclier": Art.icon(self, "bouclier", ic)
			"moteurs": Art.system_glyph(self, "moteurs", ic, 0.7)
			"canon_lourd", "torpille": Art.system_glyph(self, "armes", ic, 0.7)
		Art.title(self, Vector2(row.position.x + 50, y), o["label"], 20, Art.IVORY if not dis else Color(Art.IVORY, 0.35))
		Art.text(self, Vector2(row.position.x + 50, y + 16), o.get("desc", ""), 12, Color(Art.IVORY, 0.45 if not dis else 0.25))
		draw_voters(o["id"], Vector2(row.end.x - 20 - 20 * counts().get(o["id"], 0), y - 4))
		y += 60
	if last_bought != "":
		Art.title(self, Vector2(card.position.x, card.end.y - 24), "Acheté : %s" % last_bought, 20, Art.SAGE, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	draw_vote_footer(674)
