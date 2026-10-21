extends RefCounted
class_name Quips
## Répliques humoristiques de l'équipage. Rares par construction : une probabilité par situation,
## un délai global entre deux répliques et un délai propre à chaque situation.
## Les références littéraires sont des clins d'œil, jamais des citations.

const GLOBAL_COOLDOWN := 22.0
const SITUATION_COOLDOWN := 80.0
const SHOW_TIME := 3.6

# situation → [probabilité, répliques]
const BANK := {
	"serie": [0.35, [
		"Capitaine Nemo n'aurait pas fait mieux. Il aurait fait plus silencieux.",
		"Ça fait dix à la suite. Je compte, c'est mon seul passe-temps.",
		"Le tour du monde en quatre-vingts coups de feu !",
		"Je ne suis pas violent, je suis rythmé.",
		"On dirait que j'ai pris des cours chez le Syndicat.",
	]],
	"tombe": [0.5, [
		"Je me repose. Les yeux ouverts. Par terre.",
		"Quelqu'un a vu d'où venait ce plomb ?",
		"Dites à ma mère que j'ai fait une belle roulade.",
		"Ce n'était pas dans le contrat, ça.",
		"Ça pique, mais avec élégance.",
	]],
	"releve": [0.5, [
		"Merci. Je vous dois un verre. Ou deux.",
		"Retour des morts. C'est devenu une habitude à bord.",
		"Je n'ai rien vu de l'au-delà, c'était mal éclairé.",
		"Ma dette envers vous est considérable. Je la nierai demain.",
	]],
	"coffre": [0.4, [
		"Le trésor ! Et pas une seule carte au dos de la boîte.",
		"On partage en parts égales. Enfin, en parts proches.",
		"Ça brille. Ça doit être bon signe.",
		"Je sens qu'on va devoir acheter une plus grande poche.",
		"Mon cœur de corsaire fait des bonds.",
	]],
	"porte": [0.3, [
		"Elle s'ouvre toute seule. Je n'aime pas quand les portes sont aimables.",
		"Après vous. Non, vraiment, après vous.",
		"Une porte de moins entre nous et les ennuis.",
		"Ça sent le piège. Entrons.",
	]],
	"victoire": [0.6, [
		"Beau travail ! Personne n'a besoin de le répéter.",
		"On le raconte au retour ? Avec des détails inventés ?",
		"Le navire est à nous. Il nous reste à savoir quoi en faire.",
		"Un abordage propre, ou presque. Disons, vivant.",
	]],
	"defaite": [0.6, [
		"Repli stratégique. C'est écrit dans les manuels.",
		"On revient plus fort. Ou plus lent, mais plus prudent.",
		"Ce n'est pas une fuite, c'est un virage serré.",
		"Nous avons perdu une bataille, pas notre sens de l'humour.",
	]],
	"boutique": [0.5, [
		"Les prix, j'en connais un qui va pleurer.",
		"Tout est en vente ? Même les promesses ?",
		"Je regarde seulement. Je regarde toujours seulement.",
		"Le colporteur me regarde. Je n'aime pas qu'on lise dans mes poches.",
	]],
	"combat": [0.35, [
		"Visez le gros truc qui brille !",
		"Prévenez-moi si on perd. Ou si on gagne, d'ailleurs.",
		"Rien ne vaut un petit duel pour se dégourdir les canons.",
		"Si l'Indicible nous entend, qu'il sache que nous sommes occupés.",
	]],
	"coque": [0.4, [
		"La coque a fait un bruit que je n'aime pas.",
		"Ce n'est qu'une égratignure. Sur une coque. Qui coule.",
		"On avait dit : pas de trous. Qui a dit oui ?",
		"Un peu d'aération, ça ne fait jamais de mal.",
	]],
	"evenement": [0.35, [
		"Les ennuis ont une odeur. Là, c'est du cèdre et de la poudre.",
		"Ce signal me rappelle un roman où tout finissait mal.",
		"Je vote pour la sagesse. Pas pour l'ennui, pour la sagesse.",
		"Chaque fois qu'on décide vite, on y repense longtemps.",
	]],
}


var game
var cooldown := 8.0                  # pas de réplique dans les toutes premières secondes
var situation_cd: Dictionary = {}
var last_line := ""


func _init(g) -> void:
	game = g


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	for k in situation_cd.keys():
		situation_cd[k] = maxf(0.0, float(situation_cd[k]) - delta)


## Une situation se produit. Parfois (rarement) un membre d'équipage réagit.
## `who` : le personnage concerné, ou null pour en tirer un au hasard.
func react(situation: String, who: Player = null, force := false) -> bool:
	if not BANK.has(situation):
		return false
	if not force:
		if cooldown > 0.0 or float(situation_cd.get(situation, 0.0)) > 0.0:
			return false
		if randf() > float(BANK[situation][0]):
			return false
	var speaker: Player = who
	if speaker == null or speaker.downed and situation != "tombe":
		var pool: Array = game.crew.filter(func(p: Player): return not p.downed)
		if pool.is_empty():
			return false
		speaker = pool.pick_random()
	var lines: Array = (BANK[situation][1] as Array).duplicate()
	lines.erase(last_line)
	var line: String = lines.pick_random()
	last_line = line
	speaker.say(line, SHOW_TIME)
	cooldown = GLOBAL_COOLDOWN
	situation_cd[situation] = SITUATION_COOLDOWN
	return true
