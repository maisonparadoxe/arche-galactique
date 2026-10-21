extends RefCounted
class_name RunState
## État d'une expédition (une « run ») : vaisseau, ressources, carte du secteur.

const START_FUEL := 4
const START_SCRAP := 10
const START_COLONS := 10000
const MAP_LAYERS := 7          # longueur par défaut : 0 = départ, 6 = boss
const DRIFT_DAMAGE := 3        # sauter sans carburant abîme la coque

var difficulty := "normal"
var diff: Dictionary = {}      # entrée de ShipData.DIFFICULTIES
var layers := MAP_LAYERS       # nombre de couches de la carte (départ et boss compris)
var ship_id := ""
var ship_name := ""
var hull := 0
var hull_max := 0
var shields := 1
var engines := 1
var weapons: Array = []        # identifiants d'armes (ShipData.WEAPONS)
var fuel := START_FUEL
var scrap := START_SCRAP
var colons := START_COLONS
var nodes: Array = []          # [{id, layer, type, pos: Vector2, next: [ids], visited}]
var current := 0
var seen_events: Array = []
var stats := {"jumps": 0, "combats": 0, "events": 0, "scrap_earned": 0}
var victory := false
var ended := false


static func create(id: String, difficulty_id := "normal") -> RunState:
	var r := RunState.new()
	var def: Dictionary = ShipData.PLAYER_SHIPS[id]
	r.difficulty = difficulty_id if ShipData.DIFFICULTIES.has(difficulty_id) else "normal"
	r.diff = ShipData.DIFFICULTIES[r.difficulty]
	r.layers = int(r.diff["jumps"]) + 1
	r.fuel += int(r.diff["fuel"])
	r.scrap += int(r.diff["scrap"])
	r.ship_id = id
	r.ship_name = def["name"]
	r.hull = def["hull"]
	r.hull_max = def["hull"]
	r.shields = def["shields"]
	r.engines = def["engines"]
	r.weapons = (def["weapons"] as Array).duplicate()
	r.generate_map()
	return r


func node(id: int) -> Dictionary:
	return nodes[id]


func depth() -> int:
	return int(nodes[current]["layer"])


func choices() -> Array:
	return (nodes[current]["next"] as Array).map(func(i): return nodes[i])


func add_scrap(n: int) -> void:
	scrap = maxi(0, scrap + n)
	if n > 0:
		stats["scrap_earned"] += n


## Applique les effets d'un événement ou d'une récompense. Retourne une ligne de résumé.
func apply(effects: Dictionary) -> String:
	var parts: Array = []
	if effects.has("scrap"):
		add_scrap(int(effects["scrap"]))
		parts.append("%+d ferraille" % int(effects["scrap"]))
	if effects.has("fuel"):
		fuel = maxi(0, fuel + int(effects["fuel"]))
		parts.append("%+d carburant" % int(effects["fuel"]))
	if effects.has("hull"):
		var before := hull
		hull = clampi(hull + int(effects["hull"]), 0, hull_max)
		parts.append("%+d coque" % (hull - before))
	if effects.has("colons"):
		colons = maxi(0, colons + int(effects["colons"]))
		parts.append("%+d colons" % int(effects["colons"]))
	if effects.has("engines"):
		if engines < 4:
			engines += 1
			parts.append("moteurs améliorés")
		else:
			add_scrap(10)
			parts.append("+10 ferraille")
	if effects.has("shields"):
		if shields < 3:
			shields += 1
			parts.append("boucliers renforcés")
		else:
			add_scrap(15)
			parts.append("+15 ferraille")
	if effects.has("weapon"):
		if weapons.size() < 3:
			weapons.append(effects["weapon"])
			parts.append("nouvelle arme : %s" % ShipData.WEAPONS[effects["weapon"]]["name"])
		else:
			add_scrap(20)
			parts.append("+20 ferraille")
	return ", ".join(parts)


## Saute vers un nœud voisin. Retourne les dégâts de dérive (0 si du carburant restait).
func jump_to(id: int) -> int:
	current = id
	nodes[id]["visited"] = true
	stats["jumps"] += 1
	if fuel > 0:
		fuel -= 1
		return 0
	hull = maxi(0, hull - DRIFT_DAMAGE)
	return DRIFT_DAMAGE


# ---------------------------------------------------------------- carte

func generate_map() -> void:
	nodes = []
	var by_layer: Array = []
	# Couches du milieu : la version longue en a 5 ; une run courte en garde 3, dont une boutique.
	var middle: Array = [
		func(): return ["combat", "evenement"],
		func(): return _shuffle(["combat", "evenement", "halte"]),
		func(): return _shuffle(["boutique", "abordage", "combat"]),
		func(): return _shuffle(["combat", "ile", ["evenement", "halte"].pick_random()]),
		func(): return _shuffle(["boutique", "combat", "epave"]),
	]
	if layers - 2 < middle.size():
		middle = [middle[0], middle[2], middle[4]].slice(0, maxi(layers - 2, 1))
	for layer in layers:
		var types: Array
		if layer == 0:
			types = ["depart"]
		elif layer == layers - 1:
			types = ["boss"]
		else:
			types = middle[mini(layer - 1, middle.size() - 1)].call()
		var ids: Array = []
		for i in types.size():
			var y := 0.5 if types.size() == 1 else float(i) / (types.size() - 1)
			var jitter := Vector2(randf_range(-0.2, 0.2), randf_range(-0.06, 0.06)) if layer not in [0, layers - 1] else Vector2.ZERO
			nodes.append({"id": nodes.size(), "layer": layer, "type": types[i], "next": [], "visited": layer == 0,
				"pos": Vector2(layer + jitter.x, clampf(0.04 + y * 0.92 + jitter.y, 0.0, 1.0))})
			ids.append(nodes.size() - 1)
		by_layer.append(ids)
	# Liens sans croisement : chaque nœud vise une plage contiguë de la couche suivante.
	for layer in layers - 1:
		var a: Array = by_layer[layer]
		var b: Array = by_layer[layer + 1]
		var main: Array = []
		for i in a.size():
			main.append(0 if a.size() == 1 else int(round(float(i) * (b.size() - 1) / (a.size() - 1))))
		var lo: Array = main.duplicate()
		var hi: Array = main.duplicate()
		for i in a.size():
			if randf() < 0.5:
				# un lien de plus, vers le haut ou le bas, seulement s'il ne croise rien
				if randf() < 0.5 and main[i] + 1 < b.size() and (i == a.size() - 1 or main[i + 1] >= main[i] + 1):
					hi[i] = main[i] + 1
				elif main[i] - 1 >= 0 and (i == 0 or hi[i - 1] <= main[i] - 1):
					lo[i] = main[i] - 1
		for j in b.size():  # chaque nœud doit rester atteignable
			var reached := false
			for i in a.size():
				if j >= lo[i] and j <= hi[i]:
					reached = true
			if not reached:
				var src := 0
				for i in a.size():
					if hi[i] < j:
						src = i
				lo[src] = mini(lo[src], j)
				hi[src] = maxi(hi[src], j)
		for i in a.size():
			for j in range(lo[i], hi[i] + 1):
				_link(a[i], b[j])
	current = 0


func _link(a: int, b: int) -> void:
	if not (b in nodes[a]["next"]):
		nodes[a]["next"].append(b)
		nodes[a]["next"].sort_custom(func(x, y): return nodes[x]["pos"].y < nodes[y]["pos"].y)


func _shuffle(a: Array) -> Array:
	var c := a.duplicate()
	c.shuffle()
	return c


static func type_label(type: String) -> String:
	match type:
		"combat": return "Combat"
		"evenement": return "Inconnu"
		"halte": return "Halte"
		"boutique": return "Boutique"
		"abordage": return "Navire marchand"
		"ile": return "Île au trésor"
		"epave": return "Épave corrompue"
		"boss": return "L'Indicible"
		"depart": return "Départ"
	return type
