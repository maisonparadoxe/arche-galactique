class_name Art
## Palette et ornements Art nouveau partagés par toutes les scènes.

const BG := Color("#0f0d16")
const PANEL := Color("#17131d")
const GOLD := Color("#d4a64a")
const GOLD_DIM := Color("#8a6a33")
const COPPER := Color("#b8734a")
const IVORY := Color("#f2e8d5")
const SAGE := Color("#9caf88")
const TEAL := Color("#2a6f73")
const CELL := Color("#5fd4c4")
const WALL := Color("#4a3d33")
const DANGER := Color("#e8452e")
const CORRUPT := Color("#b04cff")     # violet acide de l'Indicible
const CORRUPT2 := Color("#7dff6a")    # vert acide de l'Indicible
const SHIELD := Color("#62c6e6")
const NEON_PINK_ICON := Color("#ff4d9d")   # accent néon des abordages

static var _title_font: Font


static func title_font() -> Font:
	if _title_font == null:
		_title_font = load("res://fonts/Federant-Regular.ttf")
	return _title_font


## 10000 → « 10 000 »
static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func font() -> Font:
	return ThemeDB.fallback_font


static func title(ci: CanvasItem, pos: Vector2, text: String, size := 32, col := GOLD, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string(title_font(), pos, text, align, width, size, col)


static func text(ci: CanvasItem, pos: Vector2, s: String, size := 15, col := IVORY, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string(font(), pos, s, align, width, size, col)


## Texte sur plusieurs lignes, coupé à la largeur donnée. Retourne la hauteur utilisée.
static func paragraph(ci: CanvasItem, pos: Vector2, s: String, width: float, size := 16, col := IVORY, line_h := 0.0) -> float:
	var lh := line_h if line_h > 0 else size * 1.35
	ci.draw_multiline_string(font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, col)
	var lines := font().get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size).y
	return max(lines, lh)


static func frame(ci: CanvasItem, r: Rect2, s := 1.0, col := GOLD) -> void:
	ci.draw_rect(r, col, false, 2.5 * s)
	ci.draw_rect(r.grow(6 * s), Color(col, 0.45), false, 1.0)
	whiplash(ci, r.position, 1, 1, s, col)
	whiplash(ci, Vector2(r.end.x, r.position.y), -1, 1, s, col)
	whiplash(ci, Vector2(r.position.x, r.end.y), 1, -1, s, col)
	whiplash(ci, r.end, -1, -1, s, col)


static func panel(ci: CanvasItem, r: Rect2, s := 0.7, col := GOLD) -> void:
	ci.draw_rect(r, PANEL)
	frame(ci, r, s, col)


## Volute « coup de fouet » typique de l'Art nouveau, posée sur un angle.
static func whiplash(ci: CanvasItem, corner: Vector2, sx: float, sy: float, s := 1.0, col := GOLD) -> void:
	var pts := PackedVector2Array()
	var p0 := corner + Vector2(sx * 2, sy * 46) * s
	var p1 := corner + Vector2(sx * 4, sy * 10) * s
	var p2 := corner + Vector2(sx * 30, sy * 6) * s
	var p3 := corner + Vector2(sx * 22, sy * 22) * s
	for i in 17:
		pts.append(p0.bezier_interpolate(p1, p2, p3, i / 16.0))
	ci.draw_polyline(pts, col, 2.0 * s, true)
	ci.draw_circle(p3, 3.5 * s, col)
	var q := PackedVector2Array()
	var q0 := corner + Vector2(sx * 46, sy * 2) * s
	var q1 := corner + Vector2(sx * 14, sy * 3) * s
	var q2 := corner + Vector2(sx * 9, sy * 26) * s
	var q3 := corner + Vector2(sx * 18, sy * 16) * s
	for i in 17:
		q.append(q0.bezier_interpolate(q1, q2, q3, i / 16.0))
	ci.draw_polyline(q, Color(col, 0.7), 1.5 * s, true)


## Filet doré horizontal avec un losange au centre.
static func rule(ci: CanvasItem, from: Vector2, length: float, col := GOLD) -> void:
	ci.draw_line(from, from + Vector2(length, 0), Color(col, 0.7), 1.5)
	var c := from + Vector2(length / 2, 0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), col)


static func progress_arc(ci: CanvasItem, center: Vector2, r: float, frac: float, col := SAGE, width := 4.0) -> void:
	if frac <= 0.0:
		return
	ci.draw_arc(center, r, -PI / 2, -PI / 2 + TAU * clamp(frac, 0.0, 1.0), 48, col, width)


static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, back := Color(1, 1, 1, 0.08)) -> void:
	ci.draw_rect(r, back)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clamp(frac, 0.0, 1.0), r.size.y)), col)
	ci.draw_rect(r, GOLD_DIM, false, 1.0)


static func fire(ci: CanvasItem, pos: Vector2, intensity: float, t: float, scale := 1.0) -> void:
	var k: float = (0.35 + 0.65 * intensity / 100.0) * scale
	for i in 6:
		var a := t * 3.0 + i * 1.7 + pos.x * 0.01
		var off := Vector2(cos(a) * 9, sin(a * 1.3) * 6 - i * 3) * k
		var col: Color = [Color("#ffcf5a"), Color("#ff8a3d"), Color("#e8452e")][i % 3]
		ci.draw_circle(pos + off, (22 - i * 2.5) * k * (0.9 + 0.1 * sin(t * 9 + i)), Color(col, 0.75))


static func stars(ci: CanvasItem, list: Array, t: float, drift := 0.0) -> void:
	for s in list:
		var p: Vector2 = s[0]
		if drift != 0.0:
			p.x = fposmod(p.x - t * drift * s[1] * 20.0, 1280.0)
		ci.draw_circle(p, s[1], Color(IVORY, 0.25 + 0.25 * sin(t * 0.8 + s[2] * 10)))


## Pictogramme d'un système de vaisseau.
static func system_glyph(ci: CanvasItem, system: String, c: Vector2, s := 1.0, col := GOLD) -> void:
	match system:
		"armes":
			ci.draw_line(c + Vector2(-12, 6) * s, c + Vector2(12, -6) * s, col, 5.0 * s)
			ci.draw_circle(c + Vector2(-10, 7) * s, 6 * s, col)
		"boucliers":
			ci.draw_arc(c + Vector2(-4, 0) * s, 14 * s, -1.1, 1.1, 16, col, 3.0 * s)
			ci.draw_arc(c + Vector2(-4, 0) * s, 8 * s, -1.1, 1.1, 12, Color(col, 0.6), 2.0 * s)
		"moteurs":
			for i in 3:
				var x := (-10 + i * 8) * s
				ci.draw_polyline(PackedVector2Array([c + Vector2(x, -8 * s), c + Vector2(x + 6 * s, 0), c + Vector2(x, 8 * s)]), col, 2.5 * s)
		"pilotage":
			ci.draw_arc(c, 10 * s, 0, TAU, 24, col, 2.5 * s)
			for i in 6:
				var a := TAU * i / 6.0
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * 14 * s, col, 2.0 * s)
		"coeur":
			ci.draw_set_transform(c, 0, Vector2(1, 0.55))
			ci.draw_circle(Vector2.ZERO, 16 * s, Color(CORRUPT2, 0.8))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			ci.draw_circle(c, 6 * s, Color("#120a18"))


## Petite icône de ressource : « coque », « carburant », « ferraille », « colons ».
static func icon(ci: CanvasItem, kind: String, c: Vector2, s := 1.0) -> void:
	match kind:
		"coque":
			var pts := PackedVector2Array([c + Vector2(0, -9) * s, c + Vector2(8, -5) * s, c + Vector2(6, 6) * s,
				c + Vector2(0, 10) * s, c + Vector2(-6, 6) * s, c + Vector2(-8, -5) * s])
			ci.draw_colored_polygon(pts, Color("#d0603f"))
			pts.append(pts[0])
			ci.draw_polyline(pts, GOLD, 1.5)
		"carburant":
			ci.draw_rect(Rect2(c - Vector2(6, 9) * s, Vector2(12, 18) * s), CELL)
			ci.draw_rect(Rect2(c - Vector2(6, 9) * s, Vector2(12, 18) * s), GOLD, false, 1.5)
			ci.draw_rect(Rect2(c - Vector2(3, 12) * s, Vector2(6, 3) * s), GOLD)
		"ferraille":
			for i in 6:
				var a := TAU * i / 6.0
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * 9 * s, COPPER, 3.0 * s)
			ci.draw_circle(c, 5 * s, COPPER)
			ci.draw_circle(c, 2.2 * s, PANEL)
		"colons":
			ci.draw_circle(c + Vector2(0, -4) * s, 4 * s, IVORY)
			ci.draw_arc(c + Vector2(0, 8) * s, 7 * s, PI, TAU, 12, IVORY, 3.0 * s)
		"bouclier":
			ci.draw_arc(c, 8 * s, 0, TAU, 24, SHIELD, 2.5 * s)
			ci.draw_circle(c, 3 * s, Color(SHIELD, 0.6))
