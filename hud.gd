class_name Hud
## Bandeau des ressources de l'expédition, partagé par la carte, le combat, les événements et la boutique.


static func draw(ci: CanvasItem, run: RunState, y := 18.0, x := 40.0) -> void:
	if run == null:
		return
	Art.title(ci, Vector2(x, y + 26), run.ship_name, 26)
	var cx := x + 20 + Art.title_font().get_string_size(run.ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	Art.icon(ci, "coque", Vector2(cx + 10, y + 16))
	var frac := float(run.hull) / float(run.hull_max)
	Art.bar(ci, Rect2(cx + 26, y + 9, 150, 14), frac, Art.SAGE if frac > 0.5 else (Art.GOLD if frac > 0.25 else Art.DANGER))
	Art.text(ci, Vector2(cx + 184, y + 22), "%d/%d" % [run.hull, run.hull_max], 15)
	cx += 250
	for item in [["carburant", run.fuel], ["ferraille", run.scrap], ["colons", run.colons]]:
		Art.icon(ci, item[0], Vector2(cx + 10, y + 16))
		var s := Art.num(item[1])
		var col := Art.DANGER if item[0] == "carburant" and run.fuel == 0 else Art.IVORY
		Art.text(ci, Vector2(cx + 26, y + 22), s, 17, col)
		cx += 44 + Art.font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	Art.icon(ci, "reputation", Vector2(cx + 10, y + 16))
	Art.text(ci, Vector2(cx + 26, y + 22), RunState.renown_title(run.renown), 15, RunState.renown_color(run.renown))
