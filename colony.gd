extends RefCounted
## La colonie : ce que l'arche Éléa retient d'une expédition à l'autre.
## Chaque colon sauvé la peuple ; des bâtiments se construisent seuls et donnent des bonus de départ.
## Sauvegarde dans user://colony.json (pas en mode test).

const PATH := "user://colony.json"
const BUILDINGS := [
	{"id": "forge", "name": "Forge", "at": 8000, "desc": "+6 ferraille au départ"},
	{"id": "citerne", "name": "Citerne", "at": 20000, "desc": "+1 carburant au départ"},
	{"id": "chantier", "name": "Chantier naval", "at": 40000, "desc": "+4 coque au départ"},
	{"id": "conseil", "name": "Conseil des anciens", "at": 70000, "desc": "Réputation +2 au départ"},
	{"id": "cryo", "name": "Grande cryo", "at": 110000, "desc": "Clones moins fatigués (-4 % au lieu de -7 %)"},
]

var persist := true
var pop := 0                      # colons sauvés au total
var expeditions := 0
var victories := 0
var chronicle: Array = []         # dernières entrées de la chronique


func load_from_disk() -> void:
	if not persist or not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		pop = int(d.get("pop", 0))
		expeditions = int(d.get("expeditions", 0))
		victories = int(d.get("victories", 0))
		chronicle = d.get("chronicle", [])


func save() -> void:
	if not persist:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"pop": pop, "expeditions": expeditions, "victories": victories, "chronicle": chronicle}))


func unlocked() -> Array:
	return BUILDINGS.filter(func(b): return pop >= int(b["at"]))


func has(id: String) -> bool:
	return pop >= int((BUILDINGS.filter(func(b): return b["id"] == id)[0])["at"])


## Bonus de départ appliqués à une nouvelle expédition.
func apply_to(run: RunState) -> void:
	if has("forge"):
		run.scrap += 6
	if has("citerne"):
		run.fuel += 1
	if has("chantier"):
		run.hull += 4
		run.hull_max += 4
	if has("conseil"):
		run.renown = 2
	if has("cryo"):
		run.clone_malus = 0.04


## Colons gagnés : toute l'arche en cas de victoire, quelques rescapés sinon (selon le chemin parcouru).
const ResultsScript := preload("res://results.gd")


static func gain_for(run: RunState) -> int:
	if run.victory:
		return ResultsScript.saved(run)
	return int(run.colons * 0.1 * float(run.depth()) / float(maxi(run.layers - 1, 1)))


## Enregistre la fin d'une expédition. Retourne {gain, new (noms de bâtiments), entry}.
func register(run: RunState) -> Dictionary:
	var before := unlocked().size()
	var gain := gain_for(run)
	pop += gain
	expeditions += 1
	if run.victory:
		victories += 1
	var fresh: Array = unlocked().slice(before).map(func(b): return b["name"])
	var entry := "Expédition %d · %s : %s. %s, équipage %s%s. L'arche gagne %s âmes." % [
		expeditions, run.ship_name, "traversée réussie" if run.victory else "demi-tour forcé",
		RunState.renown_title(run.renown), RunState.madness_title(run.madness).to_lower(),
		(", %d clonage%s" % [run.clone_total(), "s" if run.clone_total() > 1 else ""]) if run.clone_total() > 0 else "", Art.num(gain)]
	chronicle.append(entry)
	chronicle = chronicle.slice(maxi(0, chronicle.size() - 8))
	save()
	return {"gain": gain, "new": fresh, "entry": entry}


## Journal de bord : une ligne de récit sur la carte, selon l'avancée et l'état de l'équipage.
static func narrative_line(run: RunState) -> String:
	var d := run.depth()
	if run.madness >= 2 and d > 1:
		return ["Les hublots reflètent des choses qui ne sont pas dehors.", "Quelqu'un a griffé un nom sur la cloison. Personne ne l'a écrit.",
			"Le sillage de l'arche chante, très bas, à la limite de l'ouïe."][d % 3]
	if run.renown <= -4 and d > 0:
		return ["Aux relais, les lanternes s'éteignent à votre approche.", "On dit que l'équipage de la %s ne paie jamais deux fois." % run.ship_name,
			"Les convois changent de route avant même de vous voir."][d % 3]
	if run.renown >= 4 and d > 0:
		return ["Sur les ondes, un pilote inconnu salue la %s." % run.ship_name, "On a rallumé une lanterne sur votre route.",
			"Dans les relais, on parle de vous comme d'une bonne nouvelle."][d % 3]
	var base := [
		"L'arche Éléa dort derrière vous ; ses colons rêvent d'un ciel à eux.",
		"Premier saut : le vide a l'air poli, ce qui ne dit rien de ses intentions.",
		"Le journal de bord note : cap maintenu, moral correct, soupe douteuse.",
		"Au loin, des voiles de métal : d'autres ont tenté la traversée avant vous.",
		"Barjavel aurait ri de nos cryo, Verne de nos hublots. Nous continuons.",
		"Le secteur se resserre. L'Indicible n'est plus une rumeur, c'est un poids.",
		"Dernière ligne droite : l'arche tout entière retient son souffle.",
	]
	return base[mini(d, base.size() - 1)]
