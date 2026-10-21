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
	var card := Rect2(240, 80, 800, 560)
	var col := Art.GOLD if run.victory else Art.CORRUPT
	Art.panel(self, card, 1.1, col)
	Art.title(self, card.position + Vector2(0, 80), vote_title, 50, col, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	Art.rule(self, Vector2(card.get_center().x - 180, card.position.y + 104), 360, col)
	Art.paragraph(self, Vector2(card.position.x + 70, card.position.y + 150), _summary(run), card.size.x - 140, 20, Art.IVORY)
	var y := card.position.y + 260
	var rows := [
		["Vaisseau", "%s · %s" % [run.ship_name, run.diff.get("name", "")]],
		["Sauts effectués", str(run.stats["jumps"])],
		["Vaisseaux vaincus", str(run.stats["combats"])],
		["Événements", str(run.stats["events"])],
		["Ferraille récupérée", str(run.stats["scrap_earned"])],
		["Coque restante", "%d / %d" % [run.hull, run.hull_max]],
		["Réputation", "%s (%+d)" % [RunState.renown_title(run.renown), run.renown]],
		["Colons sauvés", Art.num(saved(run))],
	]
	for r in rows:
		Art.text(self, Vector2(card.position.x + 180, y), r[0], 18, Color(Art.IVORY, 0.6))
		Art.title(self, Vector2(card.position.x + 470, y), r[1], 22, Art.IVORY)
		y += 36
	draw_vote_footer(674)
