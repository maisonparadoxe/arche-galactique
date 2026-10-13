extends VoteScene
## Événements et haltes : un texte, des choix votés, une conséquence.
## Les événements sont décrits dans data/events.json.

const EVENTS_PATH := "res://data/events.json"
const CHOICE_SECONDS := 25.0
const READ_SECONDS := 20.0

static var _events: Array = []

var event: Dictionary = {}
var phase := "choix"        # choix → resultat
var outcome_text := ""
var outcome_summary := ""
var pending_combat := ""


static func all_events() -> Array:
	if _events.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_PATH))
		if parsed is Array:
			_events = parsed
		else:
			push_error("data/events.json illisible")
	return _events


func enter(args: Dictionary) -> void:
	var run: RunState = game.run
	var kind: String = args.get("kind", "evenement")
	var forced: String = args.get("id", "")
	var pool := all_events().filter(func(e): return e["kind"] == kind and not (e["id"] in run.seen_events))
	if pool.is_empty():
		pool = all_events().filter(func(e): return e["kind"] == kind)
	event = pool.pick_random()
	for e in all_events():
		if e["id"] == forced:
			event = e
	run.seen_events.append(event["id"])
	run.stats["events"] += 1
	var opts: Array = []
	for i in event["choices"].size():
		var c: Dictionary = event["choices"][i]
		var ok := _affordable(c.get("cost", {}))
		opts.append({"id": str(i), "label": c["label"], "disabled": not ok,
			"desc": "" if ok else "Pas assez de ressources"})
	start_vote(event["title"], event["text"], opts, CHOICE_SECONDS, _first_enabled(opts))


func _affordable(cost: Dictionary) -> bool:
	var run: RunState = game.run
	return run.scrap >= int(cost.get("scrap", 0)) and run.fuel >= int(cost.get("fuel", 0))


func _first_enabled(opts: Array) -> String:
	for o in opts:
		if not o["disabled"]:
			return o["id"]
	return opts[0]["id"]


func on_vote_result(id: String) -> void:
	if phase == "choix":
		var choice: Dictionary = event["choices"][int(id)]
		var outcome := _pick_outcome(choice["outcomes"])
		var effects: Dictionary = (outcome.get("effects", {}) as Dictionary).duplicate()
		pending_combat = effects.get("combat", "")
		effects.erase("combat")
		outcome_text = outcome["text"]
		outcome_summary = game.run.apply(effects)
		phase = "resultat"
		var label := "Au combat !" if pending_combat != "" else "Continuer"
		var text := outcome_text + ("\n\n" + outcome_summary if outcome_summary != "" else "")
		start_vote(event["title"], text, [{"id": "ok", "label": label}], READ_SECONDS, "ok")
	else:
		if game.run.hull <= 0:
			game.end_run(false)
		elif pending_combat != "":
			game.goto("combat", {"enemy": pending_combat})
		else:
			game.node_done()


func _pick_outcome(outcomes: Array) -> Dictionary:
	var total := 0
	for o in outcomes:
		total += int(o.get("weight", 1))
	var roll := randi_range(1, maxi(total, 1))
	for o in outcomes:
		roll -= int(o.get("weight", 1))
		if roll <= 0:
			return o
	return outcomes[0]


func debug_info(p: Player) -> Dictionary:
	var d := super.debug_info(p)
	d["event"] = event.get("id", "")
	d["phase"] = phase
	return d


# ---------------------------------------------------------------- dessin

func _draw() -> void:
	Hud.draw(self, game.run)
	game.draw_small_qr(self, Vector2(1190, 22), 64)
	var halte: bool = event.get("kind", "") == "halte"
	var card := Rect2(140, 110, 1000, 540)
	Art.panel(self, card, 1.0, Art.SAGE if halte else Art.GOLD)
	Art.title(self, card.position + Vector2(0, 66), event.get("title", ""), 40, Art.SAGE if halte else Art.GOLD, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	Art.rule(self, Vector2(card.get_center().x - 160, card.position.y + 88), 320, Art.SAGE if halte else Art.GOLD)
	var y := card.position.y + 130
	if phase == "choix":
		y += Art.paragraph(self, Vector2(card.position.x + 70, y), event.get("text", ""), card.size.x - 140, 21, Art.IVORY) + 30
		for o in options:
			var dis: bool = o.get("disabled", false)
			var row := Rect2(card.position.x + 110, y - 26, card.size.x - 220, 44)
			draw_rect(row, Color(1, 1, 1, 0.03 if not dis else 0.0))
			draw_rect(row, Art.GOLD_DIM if not dis else Color(Art.GOLD_DIM, 0.3), false, 1.0)
			Art.title(self, Vector2(row.position.x + 20, y + 4), o["label"], 21, Art.IVORY if not dis else Color(Art.IVORY, 0.35))
			if dis:
				Art.text(self, Vector2(row.end.x - 230, y + 2), o.get("desc", ""), 14, Color(Art.DANGER, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 210)
			draw_voters(o["id"], Vector2(row.end.x - 20 - 20 * counts().get(o["id"], 0), y - 4))
			y += 56
	else:
		y += Art.paragraph(self, Vector2(card.position.x + 70, y), outcome_text, card.size.x - 140, 22, Art.IVORY) + 30
		if outcome_summary != "":
			Art.title(self, Vector2(card.position.x, y), outcome_summary, 24, Art.GOLD, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
		if pending_combat != "":
			Art.title(self, Vector2(card.position.x, y + 50), "Aux postes de combat !", 28, Art.DANGER, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	draw_vote_footer(674)
