extends VoteScene
## Choix du vaisseau d'escorte, voté sur les téléphones.

const VOTE_SECONDS := 30.0
const ORDER := ["paikan", "nautile", "libellule"]

var previews: Dictionary = {}   # id -> ShipLayout miniature
var chosen := ""
var launch_at := 0.0


func enter(_args: Dictionary) -> void:
	var opts: Array = []
	for i in ORDER.size():
		var id: String = ORDER[i]
		var def: Dictionary = ShipData.PLAYER_SHIPS[id]
		previews[id] = ShipLayout.build(def["layout"], _card(i).grow_individual(-16, -70, -16, -190), 22.0)
		opts.append({"id": id, "label": def["name"], "desc": "%s · coque %d · bouclier %d · moteurs %d" % [def["tag"], def["hull"], def["shields"], def["engines"]]})
	start_vote("Choisissez votre vaisseau", "Il escortera l'arche Éléa à travers le secteur.", opts, VOTE_SECONDS, "paikan")


func _card(i: int) -> Rect2:
	return Rect2(60 + i * 400, 150, 360, 470)


func on_vote_result(id: String) -> void:
	chosen = id
	launch_at = t + 1.8
	var the: String = ShipData.PLAYER_SHIPS[id]["the"]
	game.toast_all("%s appareille !" % (the.left(1).to_upper() + the.substr(1)))


func update(delta: float) -> void:
	super.update(delta)
	if chosen != "" and t >= launch_at:
		game.start_run(chosen)
		chosen = "*"  # une seule fois


func debug_command(p: Player, msg: Dictionary) -> void:
	if msg.get("cmd") == "vote_now":
		deadline = t


func _draw() -> void:
	Art.title(self, Vector2(60, 70), "Choisissez votre vaisseau", 40)
	Art.title(self, Vector2(62, 104), "Il escortera l'arche Éléa à travers le secteur", 19, Color(Art.IVORY, 0.65))
	Art.rule(self, Vector2(62, 118), 420)
	game.draw_small_qr(self, Vector2(1190, 22), 64)
	for i in ORDER.size():
		var id: String = ORDER[i]
		var def: Dictionary = ShipData.PLAYER_SHIPS[id]
		var r := _card(i)
		var picked: bool = last_result == id
		var lit: bool = picked or (vote_active and counts().get(id, 0) > 0)
		draw_rect(r, Color("#1a1522") if not picked else Color("#241c2c"))
		Art.frame(self, r, 0.8, Art.GOLD if lit else Art.GOLD_DIM)
		Art.title(self, r.position + Vector2(0, 46), def["name"], 34, Art.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		Art.title(self, r.position + Vector2(0, 72), def["tag"], 17, Color(Art.IVORY, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var lay: ShipLayout = previews[id]
		var hull_col: Color = def["hull_color"]
		lay.draw(self, func(room): return hull_col.lightened(0.08) if room["system"] != "" else hull_col, false, Art.WALL, Art.GOLD_DIM)
		for room in lay.rooms:
			if room["system"] != "":
				_system_glyph(room["system"], (room["rect"] as Rect2).get_center(), 0.8)
		draw_rect(lay.bounds.grow(8), Color(Art.GOLD, 0.5), false, 1.0)
		var y := r.end.y - 172
		for row in [["coque", "Coque", str(def["hull"])], ["bouclier", "Boucliers", str(def["shields"])],
				["", "Moteurs", str(def["engines"])], ["", "Armes", _weapons_text(def["weapons"])]]:
			if row[0] != "":
				Art.icon(self, row[0], Vector2(r.position.x + 30, y - 5), 0.9)
			else:
				draw_circle(Vector2(r.position.x + 30, y - 5), 4, Art.GOLD_DIM)
			Art.text(self, Vector2(r.position.x + 48, y), row[1], 15, Color(Art.IVORY, 0.6))
			Art.text(self, Vector2(r.position.x + 140, y), row[2], 15, Art.IVORY, HORIZONTAL_ALIGNMENT_LEFT, 200)
			y += 24
		Art.paragraph(self, Vector2(r.position.x + 24, y + 4), def["desc"], r.size.x - 48, 14, Color(Art.IVORY, 0.55))
		draw_voters(id, Vector2(r.get_center().x - 30, r.end.y + 22))
		if picked:
			Art.title(self, Vector2(r.position.x, r.end.y + 30), "Choisi !", 24, Art.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	draw_vote_footer()


func _weapons_text(list: Array) -> String:
	var counts := {}
	for w in list:
		counts[w] = int(counts.get(w, 0)) + 1
	var parts: Array = []
	for w in counts:
		parts.append(("%d× " % counts[w] if counts[w] > 1 else "") + ShipData.WEAPONS[w]["name"])
	return ", ".join(parts)


## Petit pictogramme de système, réutilisé par la carte et le combat.
func _system_glyph(system: String, c: Vector2, s := 1.0) -> void:
	Art.system_glyph(self, system, c, s)
