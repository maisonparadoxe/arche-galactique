extends GameScene
class_name VoteScene
## Scène dont les décisions se prennent par un vote sur les téléphones.
## Majorité simple ; égalité tirée au sort ; abstentions ignorées ;
## sans aucun vote à la fin du minuteur, l'option par défaut est retenue.

const CLOSE_DELAY := 1.2   # pause après le dernier vote, pour voir le résultat

var vote_active := false
var vote_title := ""
var vote_text := ""
var options: Array = []      # [{id, label, desc, disabled}]
var votes: Dictionary = {}   # peer_id -> id d'option
var deadline := 0.0
var duration := 20.0
var default_id := ""
var closing_at := 0.0
var _last_broadcast := 0.0
var last_result := ""


func start_vote(title: String, text: String, opts: Array, seconds: float, default_option := "") -> void:
	vote_active = true
	vote_title = title
	vote_text = text
	options = opts
	votes = {}
	duration = seconds
	deadline = t + seconds
	default_id = default_option
	closing_at = 0.0
	last_result = ""
	send_layouts()


func layout_for(p: Player) -> Dictionary:
	if not vote_active:
		return {"t": "layout", "mode": "info", "title": vote_title, "text": "Regarde l'écran"}
	return {"t": "layout", "mode": "vote", "title": vote_title, "text": vote_text, "options": options,
		"mine": votes.get(p.peer_id, ""), "counts": counts(), "remaining": remaining(), "duration": duration}


func remaining() -> int:
	return int(ceil(max(0.0, deadline - t)))


func counts() -> Dictionary:
	var c := {}
	for id in votes.values():
		c[id] = int(c.get(id, 0)) + 1
	return c


func option(id: String) -> Dictionary:
	for o in options:
		if o["id"] == id:
			return o
	return {}


func on_vote(p: Player, id: String) -> void:
	if not vote_active:
		return
	var o := option(id)
	if o.is_empty() or o.get("disabled", false):
		return
	votes[p.peer_id] = id
	_broadcast_state()


func on_leave(p: Player) -> void:
	votes.erase(p.peer_id)


func _broadcast_state() -> void:
	_last_broadcast = t
	var c := counts()
	for pl: Player in game.players.values():
		game.net.send(pl.peer_id, {"t": "vote_state", "counts": c, "mine": votes.get(pl.peer_id, ""), "remaining": remaining()})


func update(_delta: float) -> void:
	if not vote_active:
		return
	var everyone: bool = not game.players.is_empty()
	for id in game.players:
		if not votes.has(id):
			everyone = false
	if everyone and closing_at == 0.0:
		closing_at = t + CLOSE_DELAY
	if t - _last_broadcast >= 1.0:
		_broadcast_state()
	if t >= deadline or (closing_at > 0.0 and t >= closing_at):
		_resolve()


func _resolve() -> void:
	vote_active = false
	var c := counts()
	var best: Array = []
	var top := 0
	for o in options:
		if o.get("disabled", false):
			continue
		var n: int = c.get(o["id"], 0)
		if n > top:
			top = n
			best = [o["id"]]
		elif n == top and n > 0:
			best.append(o["id"])
	var chosen := ""
	if best.size() > 0:
		chosen = best.pick_random()
	elif default_id != "":
		chosen = default_id
	else:
		var enabled := options.filter(func(o): return not o.get("disabled", false))
		if enabled.size() > 0:
			chosen = enabled.pick_random()["id"]
	last_result = chosen
	var label: String = option(chosen).get("label", "")
	for pl: Player in game.players.values():
		game.net.send(pl.peer_id, {"t": "vote_done", "id": chosen, "label": label, "tie": best.size() > 1})
	on_vote_result(chosen)


## À redéfinir : que faire de l'option retenue.
func on_vote_result(_id: String) -> void:
	pass


func debug_info(p: Player) -> Dictionary:
	return {"vote_active": vote_active, "options": options.map(func(o): return o["id"]), "mine": votes.get(p.peer_id, "")}


# ---------------------------------------------------------------- dessin commun

## Bandeau du bas à la TV : minuteur et état des votes de chaque joueur.
func draw_vote_footer(y := 672.0) -> void:
	if not vote_active:
		return
	var frac := clampf((deadline - t) / duration, 0.0, 1.0)
	Art.bar(self, Rect2(40, y, 520, 10), frac, Art.GOLD if frac > 0.25 else Art.DANGER)
	Art.text(self, Vector2(40, y + 32), "Votez sur vos téléphones · %d s" % remaining(), 16, Color(Art.IVORY, 0.7))
	var x := 600.0
	for p: Player in game.players.values():
		var voted := votes.has(p.peer_id)
		draw_circle(Vector2(x, y + 6), 9, p.color if voted else Color(p.color, 0.25))
		if voted:
			draw_arc(Vector2(x, y + 6), 12, 0, TAU, 24, Art.GOLD, 1.5)
		Art.text(self, Vector2(x + 16, y + 11), p.player_name, 14, Art.IVORY if voted else Color(Art.IVORY, 0.4))
		x += 30 + Art.font().get_string_size(p.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16
		if x > 1240:
			break


## Pastilles de votes à côté d'une option (une par votant, à sa couleur).
func draw_voters(option_id: String, at: Vector2) -> void:
	var x := at.x
	for id in votes:
		if votes[id] == option_id and game.players.has(id):
			var p: Player = game.players[id]
			draw_circle(Vector2(x, at.y), 8, p.color)
			draw_arc(Vector2(x, at.y), 9, 0, TAU, 20, Art.GOLD, 1.2)
			x += 20
