extends RefCounted
class_name ShipLayout
## Plan d'un vaisseau construit à partir d'une description en cases :
## salles, portes calculées sur les murs communs, zones où l'on peut marcher.

const WALL_T := 10.0

var rooms: Array = []   # [{id, name, system, rect: Rect2}]
var doors: Array = []   # [{a, b, pos: Vector2, vertical: bool}] ; vertical = le mur est vertical
var bounds := Rect2()
var cell := 64.0
var door_w := 60.0


## def = {"rooms": [{"id","name","system","x","y","w","h"}], "doors": [["a","b"], …]}
static func build(def: Dictionary, area: Rect2, cell_size: float) -> ShipLayout:
	var l := ShipLayout.new()
	l.cell = cell_size
	l.door_w = cell_size * 0.92
	var minx := 999
	var miny := 999
	var maxx := -999
	var maxy := -999
	for r in def["rooms"]:
		minx = mini(minx, r["x"])
		miny = mini(miny, r["y"])
		maxx = maxi(maxx, r["x"] + r["w"])
		maxy = maxi(maxy, r["y"] + r["h"])
	var size := Vector2(maxx - minx, maxy - miny) * cell_size
	var origin := (area.get_center() - size / 2).round() - Vector2(minx, miny) * cell_size
	for r in def["rooms"]:
		l.rooms.append({
			"id": r["id"], "name": r.get("name", ""), "system": r.get("system", ""),
			"rect": Rect2(origin + Vector2(r["x"], r["y"]) * cell_size, Vector2(r["w"], r["h"]) * cell_size),
		})
	l.bounds = Rect2(origin + Vector2(minx, miny) * cell_size, size)
	for pair in def.get("doors", []):
		var d := l._door_between(l.room(pair[0]), l.room(pair[1]))
		if not d.is_empty():
			l.doors.append(d)
	return l


func room(id: String) -> Dictionary:
	for r in rooms:
		if r["id"] == id:
			return r
	return {}


func room_with_system(system: String) -> Dictionary:
	for r in rooms:
		if r["system"] == system:
			return r
	return {}


func room_at(p: Vector2) -> Dictionary:
	for r in rooms:
		if (r["rect"] as Rect2).has_point(p):
			return r
	return {}


func neighbors(id: String) -> Array:
	var out: Array = []
	for d in doors:
		if d["a"] == id:
			out.append(d["b"])
		elif d["b"] == id:
			out.append(d["a"])
	return out


func random_point(r: Dictionary, margin := 26.0) -> Vector2:
	var rr: Rect2 = (r["rect"] as Rect2).grow(-margin)
	return Vector2(randf_range(rr.position.x, rr.end.x), randf_range(rr.position.y, rr.end.y))


func _door_between(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty() or b.is_empty():
		return {}
	var ra: Rect2 = a["rect"]
	var rb: Rect2 = b["rect"]
	for pair in [[ra, rb], [rb, ra]]:
		var p: Rect2 = pair[0]
		var q: Rect2 = pair[1]
		if absf(p.end.x - q.position.x) < 1.0:
			var y0 := maxf(p.position.y, q.position.y)
			var y1 := minf(p.end.y, q.end.y)
			if y1 - y0 >= door_w:
				return {"a": a["id"], "b": b["id"], "pos": Vector2(q.position.x, (y0 + y1) / 2), "vertical": true}
		if absf(p.end.y - q.position.y) < 1.0:
			var x0 := maxf(p.position.x, q.position.x)
			var x1 := minf(p.end.x, q.end.x)
			if x1 - x0 >= door_w:
				return {"a": a["id"], "b": b["id"], "pos": Vector2((x0 + x1) / 2, q.position.y), "vertical": false}
	push_warning("Pas de mur commun assez long entre %s et %s" % [a["id"], b["id"]])
	return {}


# ---------------------------------------------------------------- déplacements

func _door_zone(d: Dictionary, r: float) -> Rect2:
	var half_len := r + WALL_T + 6.0
	var half_w := door_w / 2 - r
	var c: Vector2 = d["pos"]
	if d["vertical"]:
		return Rect2(c.x - half_len, c.y - half_w, half_len * 2, half_w * 2)
	return Rect2(c.x - half_w, c.y - half_len, half_w * 2, half_len * 2)


func is_walkable(p: Vector2, r: float) -> bool:
	for rm in rooms:
		if (rm["rect"] as Rect2).grow(-(r + WALL_T / 2 + 1)).has_point(p):
			return true
	for d in doors:
		if _door_zone(d, r).has_point(p):
			return true
	return false


## Déplace un personnage en respectant les murs. Aide à franchir les portes :
## si l'on pousse contre un mur près d'une porte, on glisse vers l'ouverture.
func move(pos: Vector2, step: Vector2, r: float) -> Vector2:
	var p := pos
	for axis in 2:
		var s := step.x if axis == 0 else step.y
		if s == 0.0:
			continue
		var cand := p + (Vector2(s, 0) if axis == 0 else Vector2(0, s))
		if is_walkable(cand, r):
			p = cand
			continue
		# Glissement vers une porte proche dans la direction poussée
		for d in doors:
			var c: Vector2 = d["pos"]
			var across_wall: bool = d["vertical"] == (axis == 0)
			if not across_wall:
				continue
			var dist_wall := absf((c.x - p.x) if axis == 0 else (c.y - p.y))
			var offset := (c.y - p.y) if axis == 0 else (c.x - p.x)
			if dist_wall < r + WALL_T + 14 and absf(offset) < door_w / 2 + r + 6 and signf((c.x - p.x) if axis == 0 else (c.y - p.y)) == signf(s):
				var slide := clampf(offset, -absf(s), absf(s))
				var side := p + (Vector2(0, slide) if axis == 0 else Vector2(slide, 0))
				if is_walkable(side, r):
					p = side
				break
	return p


# ---------------------------------------------------------------- dessin

func draw(ci: CanvasItem, floor_for: Callable, labels := true, wall_col := Art.WALL, trim := Art.GOLD_DIM) -> void:
	for r in rooms:
		ci.draw_rect(r["rect"], floor_for.call(r))
	for r in rooms:
		var rr: Rect2 = r["rect"]
		for x in range(int(rr.position.x) + int(cell / 2), int(rr.end.x), int(cell / 2)):
			ci.draw_line(Vector2(x, rr.position.y), Vector2(x, rr.end.y), Color(1, 1, 1, 0.025))
		for y in range(int(rr.position.y) + int(cell / 2), int(rr.end.y), int(cell / 2)):
			ci.draw_line(Vector2(rr.position.x, y), Vector2(rr.end.x, y), Color(1, 1, 1, 0.025))
	for r in rooms:
		ci.draw_rect(r["rect"], wall_col, false, WALL_T)
	for d in doors:
		var c: Vector2 = d["pos"]
		var gap := Rect2(c - Vector2(WALL_T, door_w / 2), Vector2(WALL_T * 2, door_w)) if d["vertical"] \
			else Rect2(c - Vector2(door_w / 2, WALL_T), Vector2(door_w, WALL_T * 2))
		ci.draw_rect(gap, floor_for.call(room(d["a"])).lerp(floor_for.call(room(d["b"])), 0.5))
		var ends := [c - Vector2(0, door_w / 2), c + Vector2(0, door_w / 2)] if d["vertical"] \
			else [c - Vector2(door_w / 2, 0), c + Vector2(door_w / 2, 0)]
		for e in ends:
			ci.draw_circle(e, 6.0 * cell / 64.0, trim)
			ci.draw_circle(e, 3.2 * cell / 64.0, Art.GOLD)
	if labels:
		for r in rooms:
			if r["name"] != "":
				Art.title(ci, (r["rect"] as Rect2).position + Vector2(12, 24), r["name"], 15, Color(Art.IVORY, 0.42))
