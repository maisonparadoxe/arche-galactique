class_name ShipData
## Données de jeu : vaisseaux jouables, armes, vaisseaux ennemis.
## Tout est décrit ici pour pouvoir équilibrer sans toucher au code.

const WEAPONS := {
	"canon": {"name": "Canon", "dmg": 1, "charge": 8.0},
	"canon_rapide": {"name": "Canon rapide", "dmg": 1, "charge": 5.5},
	"canon_lourd": {"name": "Canon lourd", "dmg": 2, "charge": 11.0},
	"torpille": {"name": "Torpille", "dmg": 2, "charge": 14.0, "pierce": true},
	"spore": {"name": "Spore", "dmg": 1, "charge": 7.0},
	"tentacule": {"name": "Tentacule", "dmg": 2, "charge": 10.0},
}

const PLAYER_SHIPS := {
	"paikan": {
		"name": "Païkan", "the": "le Païkan", "fem": false,
		"tag": "L'escorte équilibrée",
		"desc": "Le vaisseau qui veille sur Éléa. Deux canons, un bouclier, une coque solide.",
		"hull": 30, "shields": 1, "engines": 2, "weapons": ["canon", "canon"],
		"hull_color": Color("#3a2f45"),
		"layout": {
			"rooms": [
				{"id": "moteurs", "name": "Moteurs", "system": "moteurs", "x": 0, "y": 2, "w": 2, "h": 2},
				{"id": "soute", "name": "Soute", "x": 2, "y": 0, "w": 3, "h": 2},
				{"id": "coursive", "name": "Coursive", "x": 2, "y": 2, "w": 5, "h": 2},
				{"id": "abri", "name": "L'Abri", "x": 2, "y": 4, "w": 3, "h": 2},
				{"id": "armes", "name": "Armes", "system": "armes", "x": 5, "y": 0, "w": 3, "h": 2},
				{"id": "boucliers", "name": "Boucliers", "system": "boucliers", "x": 5, "y": 4, "w": 3, "h": 2},
				{"id": "pont", "name": "Pont", "system": "pilotage", "x": 7, "y": 2, "w": 2, "h": 2},
			],
			"doors": [["moteurs", "coursive"], ["soute", "coursive"], ["abri", "coursive"], ["armes", "coursive"],
				["boucliers", "coursive"], ["pont", "coursive"], ["soute", "armes"], ["abri", "boucliers"]],
		},
	},
	"nautile": {
		"name": "Nautile", "the": "le Nautile", "fem": false,
		"tag": "Le cuirassé",
		"desc": "Long et lent, mais deux boucliers et une torpille qui les traverse.",
		"hull": 38, "shields": 2, "engines": 1, "weapons": ["canon", "torpille"],
		"hull_color": Color("#2c3a3d"),
		"layout": {
			"rooms": [
				{"id": "moteurs", "name": "Moteurs", "system": "moteurs", "x": 0, "y": 1, "w": 2, "h": 4},
				{"id": "soute", "name": "Soute", "x": 2, "y": 0, "w": 3, "h": 2},
				{"id": "coursive", "name": "Coursive", "x": 2, "y": 2, "w": 7, "h": 2},
				{"id": "abri", "name": "L'Abri", "x": 2, "y": 4, "w": 3, "h": 2},
				{"id": "armes", "name": "Armes", "system": "armes", "x": 5, "y": 0, "w": 3, "h": 2},
				{"id": "boucliers", "name": "Boucliers", "system": "boucliers", "x": 5, "y": 4, "w": 3, "h": 2},
				{"id": "observatoire", "name": "Observatoire", "x": 8, "y": 0, "w": 3, "h": 2},
				{"id": "pont", "name": "Pont", "system": "pilotage", "x": 9, "y": 2, "w": 2, "h": 2},
			],
			"doors": [["moteurs", "coursive"], ["soute", "coursive"], ["abri", "coursive"], ["armes", "coursive"],
				["boucliers", "coursive"], ["pont", "coursive"], ["armes", "observatoire"], ["observatoire", "pont"]],
		},
	},
	"libellule": {
		"name": "Libellule", "the": "la Libellule", "fem": true,
		"tag": "L'éclaireuse",
		"desc": "Petite et fragile, mais très agile : deux canons rapides et de gros moteurs.",
		"hull": 22, "shields": 1, "engines": 3, "weapons": ["canon_rapide", "canon_rapide"],
		"hull_color": Color("#2f3d2c"),
		"layout": {
			"rooms": [
				{"id": "moteurs", "name": "Moteurs", "system": "moteurs", "x": 0, "y": 2, "w": 2, "h": 2},
				{"id": "armes", "name": "Armes", "system": "armes", "x": 2, "y": 0, "w": 3, "h": 2},
				{"id": "coursive", "name": "Coursive", "x": 2, "y": 2, "w": 3, "h": 2},
				{"id": "boucliers", "name": "Boucliers", "system": "boucliers", "x": 2, "y": 4, "w": 3, "h": 2},
				{"id": "pont", "name": "Pont", "system": "pilotage", "x": 5, "y": 2, "w": 2, "h": 2},
			],
			"doors": [["moteurs", "coursive"], ["armes", "coursive"], ["boucliers", "coursive"], ["pont", "coursive"]],
		},
	},
}

const ENEMY_LAYOUTS := {
	"standard": {
		"rooms": [
			{"id": "armes", "system": "armes", "x": 0, "y": 0, "w": 2, "h": 2},
			{"id": "boucliers", "system": "boucliers", "x": 2, "y": 0, "w": 2, "h": 2},
			{"id": "pilotage", "system": "pilotage", "x": 0, "y": 2, "w": 2, "h": 2},
			{"id": "moteurs", "system": "moteurs", "x": 2, "y": 2, "w": 2, "h": 2},
		],
	},
	"boss": {
		"rooms": [
			{"id": "armes", "system": "armes", "x": 0, "y": 0, "w": 2, "h": 2},
			{"id": "coeur", "system": "coeur", "x": 2, "y": 0, "w": 2, "h": 4},
			{"id": "boucliers", "system": "boucliers", "x": 4, "y": 0, "w": 2, "h": 2},
			{"id": "pilotage", "system": "pilotage", "x": 0, "y": 2, "w": 2, "h": 2},
			{"id": "moteurs", "system": "moteurs", "x": 4, "y": 2, "w": 2, "h": 2},
		],
	},
}

const ENEMIES := {
	"eclaireur": {"name": "Éclaireur pirate", "hull": 8, "shields": 0, "engines": 1, "weapons": ["canon"],
		"layout": "standard", "corrupt": false, "scrap": [8, 12]},
	"corsaire": {"name": "Corsaire", "hull": 9, "shields": 1, "engines": 1, "weapons": ["canon", "canon"],
		"layout": "standard", "corrupt": false, "scrap": [12, 18]},
	"corrompu": {"name": "Vaisseau corrompu", "hull": 11, "shields": 1, "engines": 0, "weapons": ["spore", "canon"],
		"layout": "standard", "corrupt": true, "scrap": [12, 20]},
	"avatar": {"name": "Avatar de l'Indicible", "hull": 18, "shields": 1, "engines": 1, "weapons": ["tentacule", "spore", "spore"],
		"layout": "boss", "corrupt": true, "scrap": [0, 0], "boss": true},
}

const SYSTEM_NAMES := {
	"armes": "Armes", "boucliers": "Boucliers", "moteurs": "Moteurs", "pilotage": "Pilotage", "coeur": "Cœur",
}


## Ennemi tiré au sort selon la profondeur dans le secteur (1 = début).
static func enemy_for_depth(depth: int) -> String:
	if depth <= 1:
		return "eclaireur"
	if depth == 2:
		return ["eclaireur", "corsaire"].pick_random()
	return ["corsaire", "corrompu"].pick_random()
