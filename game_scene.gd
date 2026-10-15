extends Node2D
class_name GameScene
## Base des scènes du jeu (Académie, choix du vaisseau, carte, combat…).
## Le contrôleur (game.gd) appelle ces méthodes ; chaque scène redéfinit ce qui la concerne.

var game  # référence vers le contrôleur (game.gd) ; non typée pour éviter une dépendance circulaire
var t := 0.0


## La scène devient active. Elle place les joueurs et envoie les interfaces.
func enter(_args: Dictionary) -> void:
	pass


func exit() -> void:
	pass


## Les personnages sont-ils visibles et contrôlables dans cette scène ?
func shows_players() -> bool:
	return false


## Interface à afficher sur le téléphone d'un joueur (message « layout »).
func layout_for(_p: Player) -> Dictionary:
	return {"t": "layout", "mode": "info", "title": "L'Arche galactique", "text": "Regarde l'écran"}


func on_join(_p: Player) -> void:
	pass


func on_leave(_p: Player) -> void:
	pass


## Un téléphone lâche ce personnage pour en prendre un autre (il quitte son poste, etc.).
func on_release(_p: Player) -> void:
	pass


## Où se trouve ce personnage (affiché dans la liste de l'équipage).
func location_name(_p: Player) -> String:
	return ""


## Vitesse de travail : un membre contrôlé travaille à plein régime quand il maintient le bouton,
## un membre libre travaille seul à mi-vitesse là où il se trouve.
func work_rate(p: Player, button := 1) -> float:
	if p.seated:
		return 0.0
	if not p.is_free():
		return 1.0 if p.held(button) else 0.0
	return 0.5


## Touches utiles là où se trouve le personnage : {numéro de bouton: libellé}.
## 0 = A, 1 = B, 2 = X, 3 = Y. Le téléphone fait grossir et pulser ces boutons.
func hints_for(_p: Player) -> Dictionary:
	return {}


func on_action(_p: Player, _action: String, _msg: Dictionary) -> void:
	pass


func on_vote(_p: Player, _option: String) -> void:
	pass


## Appelée à chaque image, après la mise à jour des entrées.
func update(_delta: float) -> void:
	pass


## Informations renvoyées aux tests automatiques (mode --test).
func debug_info(_p: Player) -> Dictionary:
	return {}


func debug_command(_p: Player, _msg: Dictionary) -> void:
	pass


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func send_layouts() -> void:
	for p: Player in game.players.values():
		game.net.send(p.peer_id, layout_for(p))
