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
		"hull": 30, "shields": 1, "engines": 2, "weapons": ["canon", "canon"], "crew": 4,
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
		"hull": 38, "shields": 2, "engines": 1, "weapons": ["canon", "torpille"], "crew": 5,
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
		"hull": 22, "shields": 1, "engines": 3, "weapons": ["canon_rapide", "canon_rapide"], "crew": 3,
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

## Niveaux de difficulté. Multiplicateurs appliqués aux ennemis et ressources de départ.
const DIFFICULTIES := {
	"decouverte": {"name": "Découverte", "desc": "Court et facile : 3 sauts, ennemis fragiles et lents",
		"jumps": 3, "enemy_hull": 0.5, "enemy_charge": 1.6, "fire": 0.5, "fuel": 2, "scrap": 15},
	"normal": {"name": "Normal", "desc": "6 sauts, l'expérience prévue",
		"jumps": 6, "enemy_hull": 1.0, "enemy_charge": 1.0, "fire": 1.0, "fuel": 0, "scrap": 0},
	"difficile": {"name": "Difficile", "desc": "6 sauts, ennemis robustes et rapides, plus d'incendies",
		"jumps": 6, "enemy_hull": 1.3, "enemy_charge": 0.85, "fire": 1.4, "fuel": 0, "scrap": 0},
}
const DIFFICULTY_ORDER := ["decouverte", "normal", "difficile"]

const SYSTEM_NAMES := {
	"armes": "Armes", "boucliers": "Boucliers", "moteurs": "Moteurs", "pilotage": "Pilotage", "coeur": "Cœur",
}


## Ennemis des abordages (un coup les tue, sauf le capitaine).
const BOARDING_FOES := {
	"marin": {"name": "Marin", "hp": 1, "speed": 105.0, "reach": 76.0, "windup": 0.5, "cooldown": 1.3, "radius": 15.0},
	"fusilier": {"name": "Fusilier", "hp": 1, "speed": 70.0, "windup": 0.7, "cooldown": 2.4, "radius": 15.0, "bullet": 320.0},
	"capitaine": {"name": "Capitaine", "hp": 4, "speed": 112.0, "reach": 92.0, "windup": 0.42, "cooldown": 1.0, "radius": 21.0,
		"bullet": 300.0, "fan_every": 3.6},
}

## Niveaux d'abordage : un navire marchand et une île au trésor. Les salles sont en cases de 80 px.
## Le niveau dépasse la largeur de l'écran : la caméra suit le groupe, mais seulement s'il reste uni.
const BOARDINGS := {
	"galion": {
		"name": "Navire marchand", "tag": "Un galion lourdement chargé",
		"start": "passerelle", "boss": "capitaine",
		"palette": {"floor": Color("#3b2c22"), "alt": Color("#33261e"), "wall": Color("#6b4a30"), "back": Color("#120d12")},
		"floors": {"capitaine": Color("#3d2433"), "tresor": Color("#3a3320"), "cale": Color("#2b2420")},
		"layout": {
			"rooms": [
				{"id": "passerelle", "name": "Passerelle", "x": 0, "y": 1, "w": 4, "h": 5},
				{"id": "coursive", "name": "Coursive", "x": 4, "y": 2, "w": 6, "h": 3},
				{"id": "cabines", "name": "Cabines", "x": 4, "y": 0, "w": 6, "h": 2},
				{"id": "cale", "name": "Cale", "x": 4, "y": 5, "w": 6, "h": 2},
				{"id": "carre", "name": "Carré", "x": 10, "y": 1, "w": 6, "h": 5},
				{"id": "capitaine", "name": "Quartiers du capitaine", "x": 16, "y": 1, "w": 5, "h": 5},
				{"id": "tresor", "name": "Soute au trésor", "x": 21, "y": 2, "w": 4, "h": 3},
			],
			"doors": [["passerelle", "coursive"], ["coursive", "cabines"], ["coursive", "cale"], ["coursive", "carre"],
				["carre", "capitaine"], ["capitaine", "tresor"]],
		},
		"spawns": [
			{"room": "coursive", "type": "marin", "n": 2},
			{"room": "cabines", "type": "fusilier", "n": 1},
			{"room": "cale", "type": "marin", "n": 1}, {"room": "cale", "type": "fusilier", "n": 1},
			{"room": "carre", "type": "marin", "n": 3}, {"room": "carre", "type": "fusilier", "n": 2},
			{"room": "capitaine", "type": "capitaine", "n": 1}, {"room": "capitaine", "type": "fusilier", "n": 1},
		],
		"chests": [
			{"room": "cabines", "at": [0.3, 0.6], "scrap": [4, 6]},
			{"room": "cale", "at": [0.7, 0.5], "scrap": [4, 7]},
			{"room": "capitaine", "at": [0.8, 0.25], "scrap": [6, 9]},
			{"room": "tresor", "at": [0.5, 0.5], "scrap": [14, 20], "big": true},
		],
	},
	"ile": {
		"name": "Île au trésor", "tag": "Des ruines, des naufragés et un coffre",
		"start": "plage", "boss": "temple",
		"palette": {"floor": Color("#2f3a2b"), "alt": Color("#283325"), "wall": Color("#58634a"), "back": Color("#0d140f")},
		"floors": {"plage": Color("#4a4332"), "temple": Color("#2c3138"), "crypte": Color("#252630"), "caveau": Color("#3a3320")},
		"layout": {
			"rooms": [
				{"id": "plage", "name": "Plage", "x": 0, "y": 2, "w": 5, "h": 4},
				{"id": "sentier", "name": "Sentier", "x": 5, "y": 3, "w": 4, "h": 2},
				{"id": "clairiere", "name": "Clairière", "x": 9, "y": 1, "w": 6, "h": 5},
				{"id": "ruines", "name": "Ruines", "x": 15, "y": 0, "w": 5, "h": 3},
				{"id": "crypte", "name": "Crypte", "x": 15, "y": 4, "w": 5, "h": 3},
				{"id": "temple", "name": "Temple", "x": 20, "y": 2, "w": 5, "h": 4},
				{"id": "caveau", "name": "Caveau", "x": 25, "y": 3, "w": 3, "h": 2},
			],
			"doors": [["plage", "sentier"], ["sentier", "clairiere"], ["clairiere", "ruines"], ["clairiere", "crypte"],
				["ruines", "temple"], ["crypte", "temple"], ["temple", "caveau"]],
		},
		"spawns": [
			{"room": "sentier", "type": "marin", "n": 1},
			{"room": "clairiere", "type": "marin", "n": 2}, {"room": "clairiere", "type": "fusilier", "n": 2},
			{"room": "ruines", "type": "fusilier", "n": 2},
			{"room": "crypte", "type": "marin", "n": 2}, {"room": "crypte", "type": "fusilier", "n": 1},
			{"room": "temple", "type": "capitaine", "n": 1}, {"room": "temple", "type": "marin", "n": 2},
		],
		"chests": [
			{"room": "clairiere", "at": [0.5, 0.5], "scrap": [4, 6]},
			{"room": "ruines", "at": [0.7, 0.4], "scrap": [5, 8]},
			{"room": "crypte", "at": [0.5, 0.6], "scrap": [5, 8]},
			{"room": "caveau", "at": [0.5, 0.5], "scrap": [16, 24], "big": true},
		],
	},
}


## Ennemi tiré au sort selon la profondeur dans le secteur (1 = début).
static func enemy_for_depth(depth: int) -> String:
	if depth <= 1:
		return "eclaireur"
	if depth == 2:
		return ["eclaireur", "corsaire"].pick_random()
	return ["corsaire", "corrompu"].pick_random()
