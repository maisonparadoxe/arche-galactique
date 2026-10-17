extends Node2D
class_name Player
## Un membre d'équipage. Il peut être contrôlé par un téléphone (peer_id ≠ 0)
## ou laissé libre : il travaille alors en automatique là où il se trouve.
## Le dessin suit la même description que l'aperçu de la manette (web/index.html).

const GOLD := Color("#d4a64a")
const IVORY := Color("#f2e8d5")
const CELL := Color("#5fd4c4")

var crew_id := 0
var peer_id := 0                 # téléphone qui le contrôle (0 = libre)
var slot := 0                    # rang dans l'équipage, pour placer les personnages
var owner_token := ""            # avatar d'un joueur : jeton de son téléphone ; vide pour une recrue
var player_name := ""            # nom du personnage
var color := Color.WHITE
var species := "humain"
var ornament := "aucun"
var controller_name := ""
var controller_color := Color.WHITE
var axis := Vector2.ZERO
var facing := Vector2.RIGHT
var buttons: Array = [false, false, false, false]
var prev_buttons: Array = [false, false, false, false]
var last_input_ms := 0
var rtt := -1
var seated := false
var carrying := false
var working := false             # remis à faux à chaque image ; vrai si le membre libre travaille
var medals := 0
var downed := false              # à terre (abordage) : ne peut plus agir tant qu'on ne l'a pas relevé
var revive_frac := 0.0           # progression de la relève, de 0 à 1
var blink := 0.0                 # invulnérabilité : le personnage clignote


func is_free() -> bool:
	return peer_id == 0


func radius() -> float:
	return 23.0 if species == "colosse" else 18.0


## Remet à zéro ce qui dépend de la scène (appelé à chaque changement de scène).
func reset_state() -> void:
	seated = false
	carrying = false
	downed = false
	revive_frac = 0.0
	blink = 0.0
	axis = Vector2.ZERO


## Le téléphone lâche ce personnage : il s'arrête et ses boutons sont relâchés.
func release() -> void:
	peer_id = 0
	controller_name = ""
	axis = Vector2.ZERO
	buttons = [false, false, false, false]
	prev_buttons = [false, false, false, false]
	rtt = -1


func pressed(i: int) -> bool:
	## Vrai uniquement à l'image où le bouton vient d'être enfoncé.
	return buttons[i] and not prev_buttons[i]


func held(i: int) -> bool:
	return buttons[i]


func _process(_delta: float) -> void:
	if axis.length() > 0.15:
		facing = axis.normalized()
	modulate.a = 0.4 if blink > 0.0 and int(Time.get_ticks_msec() / 70) % 2 == 0 else 1.0
	queue_redraw()


func _draw() -> void:
	var r := radius()
	var free := is_free()
	if downed:
		_draw_downed(r)
		return
	# ombre, et anneau à la couleur du joueur qui le contrôle
	draw_set_transform(Vector2(0, r * 0.9), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.35))
	if not free:
		draw_arc(Vector2.ZERO, r * 1.35, 0, TAU, 40, controller_color, 3.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if held(1) or working:
		draw_circle(Vector2.ZERO, r + 14, Color(color, 0.18))
	draw_body(self, species, ornament, color if not free else color.darkened(0.15), r, facing)
	if held(0):
		draw_arc(Vector2.ZERO, r + 6, 0, TAU, 32, IVORY, 2.0)
	if carrying:
		var c := Vector2(r + 8, -4)
		draw_rect(Rect2(c - Vector2(7, 10), Vector2(14, 20)), Color(CELL, 0.25))
		draw_rect(Rect2(c - Vector2(5, 8), Vector2(10, 16)), CELL)
		draw_rect(Rect2(c - Vector2(5, 8), Vector2(10, 16)), GOLD, false, 1.5)
	if free and working:
		# petit engrenage : le membre libre travaille tout seul
		var g := Vector2(r * 0.8, -r * 0.9)
		var a0 := Time.get_ticks_msec() / 400.0
		for i in 6:
			var a := a0 + TAU * i / 6.0
			draw_line(g, g + Vector2(cos(a), sin(a)) * 7, GOLD, 2.5)
		draw_circle(g, 4, GOLD)
		draw_circle(g, 1.8, Color("#1a1420"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-80, r + 24), player_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, IVORY if not free else Color(IVORY, 0.6))
	var info := ""
	if seated:
		info = "au poste"
	elif free:
		info = "auto"
	if not free and controller_name != player_name:
		draw_string(font, Vector2(-80, r + 39), controller_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, controller_color)
	elif info != "":
		draw_string(font, Vector2(-80, r + 39), info, HORIZONTAL_ALIGNMENT_CENTER, 160, 11, Color(IVORY, 0.5))


## À terre : grisé, avec une croix et l'arc de relève.
func _draw_downed(r: float) -> void:
	draw_set_transform(Vector2(0, r * 0.9), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_circle(Vector2.ZERO, r, Color(color.darkened(0.6), 0.85))
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(GOLD, 0.4), 2.0)
	var k := r * 0.45
	draw_line(Vector2(-k, -k), Vector2(k, k), Color("#e8452e"), 3.5)
	draw_line(Vector2(k, -k), Vector2(-k, k), Color("#e8452e"), 3.5)
	if revive_frac > 0.0:
		draw_arc(Vector2.ZERO, r + 9, -PI / 2, -PI / 2 + TAU * clampf(revive_frac, 0.0, 1.0), 40, Color("#9caf88"), 5.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-80, r + 24), player_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color(IVORY, 0.55))
	draw_string(font, Vector2(-80, r + 39), "à terre", HORIZONTAL_ALIGNMENT_CENTER, 160, 11, Color("#e8452e"))


## Dessine un personnage : utilisable par n'importe quel CanvasItem.
static func draw_body(ci: CanvasItem, sp: String, orn: String, col: Color, r: float, face: Vector2) -> void:
	var dark := col.darkened(0.35)
	match sp:
		"automate":
			var rect := Rect2(-r, -r, r * 2, r * 2)
			ci.draw_rect(rect.grow(-4), col)
			for c in [Vector2(-r + 4, -r + 4), Vector2(r - 4, -r + 4), Vector2(-r + 4, r - 4), Vector2(r - 4, r - 4)]:
				ci.draw_circle(c, 4, col)
			ci.draw_rect(Rect2(-r + 4, -r, r * 2 - 8, r * 2), col)
			ci.draw_rect(Rect2(-r, -r + 4, r * 2, r * 2 - 8), col)
			ci.draw_line(Vector2(r * 0.55, -r), Vector2(r * 0.75, -r - 11), GOLD, 2.0)
			ci.draw_circle(Vector2(r * 0.75, -r - 12), 3.5, GOLD)
			ci.draw_rect(rect.grow(-1), GOLD, false, 2.0)
		"salamandrin":
			var tail := -face * (r + 12)
			var side := Vector2(-face.y, face.x) * r * 0.7
			ci.draw_colored_polygon(PackedVector2Array([side - face * r * 0.3, tail, -side - face * r * 0.3]), dark)
			ci.draw_circle(Vector2.ZERO, r, col)
			ci.draw_arc(Vector2.ZERO, r, 0, TAU, 40, GOLD, 2.0)
		"colosse":
			ci.draw_circle(Vector2.ZERO, r, col)
			ci.draw_arc(Vector2.ZERO, r * 0.62, PI * 0.15, PI * 0.85, 16, dark, 5.0)
			ci.draw_arc(Vector2.ZERO, r, 0, TAU, 40, GOLD, 2.5)
		_:  # humain
			ci.draw_circle(Vector2.ZERO, r, col)
			ci.draw_arc(Vector2.ZERO, r, 0, TAU, 40, GOLD, 2.0)
	# yeux, tournés vers la direction du regard
	var perp := Vector2(-face.y, face.x)
	for s: float in [-1.0, 1.0]:
		var e := face * r * 0.35 + perp * s * r * 0.3
		ci.draw_circle(e, r * 0.17, IVORY)
		ci.draw_circle(e + face * 1.2, r * 0.08, Color("#1a1420"))
	# ornement
	var top := Vector2(0, -r)
	match orn:
		"fleur":
			for i in 5:
				var a := TAU * i / 5.0 - PI / 2
				ci.draw_circle(top + Vector2(-6, -3) + Vector2(cos(a), sin(a)) * 5, 3.6, Color("#f0b8c8"))
			ci.draw_circle(top + Vector2(-6, -3), 2.6, GOLD)
		"plume":
			var pts := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				pts.append(top + Vector2(4 - 14 * t, -22 * t + 6 * t * t))
			ci.draw_polyline(pts, IVORY, 4.0, true)
			ci.draw_polyline(pts, GOLD, 1.2, true)
		"couronne":
			var c := PackedVector2Array([
				top + Vector2(-9, 3), top + Vector2(-9, -7), top + Vector2(-4.5, -2), top + Vector2(0, -11),
				top + Vector2(4.5, -2), top + Vector2(9, -7), top + Vector2(9, 3)])
			ci.draw_colored_polygon(c, GOLD)
