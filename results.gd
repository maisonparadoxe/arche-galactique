extends VoteScene
## Bilan de l'expédition, puis retour à l'Académie.

const VOTE_SECONDS := 40.0


func enter(_args: Dictionary) -> void:
	var run: RunState = game.run
	var def: Dictionary = ShipData.PLAYER_SHIPS[run.ship_id]
	var lost := "%s est perdue" if def["fem"] else "%s est perdu"
	var the: String = def["the"]
	var title := "Victoire !" if run.victory else lost % (the.left(1).to_upper() + the.substr(1))
	start_vote(title, _summary(run), [{"id": "retour", "label": "Retour à l'Académie"}], VOTE_SECONDS, "retour")


func _summary(run: RunState) -> String:
	if run.victory:
		return "L'arche Éléa a franchi le secteur. %s colons regardent déjà le prochain ciel." % Art.num(saved(run))
	return "Sans escorte, l'arche Éléa doit faire demi-tour et se cacher. Il faudra retenter la traversée."


static func saved(run: RunState) -> int:
	if not run.victory:
		return 0
	return int(run.colons * (0.7 + 0.3 * float(run.hull) / float(run.hull_max)) * run.colon_mult())


func on_vote_result(_id: String) -> void:
	game.run = null
	game.goto("academie")


func _draw() -> void:
	var run: RunState = game.run
	if run == null:
		return
	var card := Rect2(240, 56, 800, 604)
	var col := Art.GOLD if run.victory else Art.CORRUPT
	Art.panel(self, card, 1.1, col)
	Art.title(self, card.position + Vector2(0, 80), vote_title, 50, col, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	Art.rule(self, Vector2(card.get_center().x - 180, card.position.y + 104), 360, col)
	Art.paragraph(self, Vector2(card.position.x + 70, card.position.y + 150), _summary(run), card.size.x - 140, 20, Art.IVORY)
	var y := card.position.y + 236
	var rows := [
		["Vaisseau", "%s · %s" % [run.ship_name, run.diff.get("name", "")]],
		["Sauts effectués", str(run.stats["jumps"])],
		["Vaisseaux vaincus", str(run.stats["combats"])],
		["Événements", str(run.stats["events"])],
		["Ferraille récupérée", str(run.stats["scrap_earned"])],
		["Coque restante", "%d / %d" % [run.hull, run.hull_max]],
		["Réputation", "%s (%+d)" % [RunState.renown_title(run.renown), run.renown]],
		["Colons sauvés", Art.num(saved(run))],
		["Colonie", "%s âmes (+%s)" % [Art.num(game.colony.pop), Art.num(int(game.last_colony.get("gain", 0)))]],
	]
	var fresh: Array = game.last_colony.get("new", [])
	if not fresh.is_empty():
		rows.append(["Bâtiment construit", ", ".join(fresh)])
	for r in rows:
		Art.text(self, Vector2(card.position.x + 180, y), r[0], 18, Color(Art.IVORY, 0.6))
		Art.title(self, Vector2(card.position.x + 470, y), r[1], 22, Art.IVORY)
		y += 26
	# Chronique : les dernières expéditions de l'arche
	var chron: Array = game.colony.chronicle
	if not chron.is_empty():
		var cy := y + 22
		Art.rule(self, Vector2(card.get_center().x - 120, cy - 18), 240, Color(col, 0.6))
		Art.title(self, Vector2(card.position.x + 70, cy + 4), "Chronique de l'arche", 18, Color(col, 0.9))
		cy += 28
		for e in chron.slice(maxi(0, chron.size() - 2)).filter(func(_x): return true):
			cy += Art.paragraph(self, Vector2(card.position.x + 70, cy), "· " + str(e), card.size.x - 140, 12, Color(Art.IVORY, 0.75)) + 4
	draw_vote_footer(674)
