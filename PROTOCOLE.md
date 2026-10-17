# Protocole manette ↔ PC

Messages JSON texte sur WebSocket (port 9080). Le champ `t` donne le type. La page manette est servie en HTTP sur le port 8080 (`/`), avec sa police (`/fonts/Federant-Regular.ttf`).

## Téléphone → PC

| `t` | Champs | Quand |
| --- | --- | --- |
| `hello` | `name` (12 car. max), `token`, `color` (0 à 7), `species` (`humain`, `automate`, `salamandrin`, `colosse`), `ornament` (`aucun`, `fleur`, `plume`, `couronne`) | À la connexion et à chaque reconnexion |
| `in` | `x`, `y` (joystick, -1 à 1, y vers le bas), `b` (4 booléens : Interagir, Action, Prendre, Changer) | 30 fois par seconde, état complet |
| `act` | `a` : `"fire"` (avec `w`, numéro de l'arme), `"quit"` | Boutons du poste d'armes |
| `act` | `a` : `"pick"` (avec `id` du membre), `"back"` | Écran Équipage : prendre un membre libre, ou revenir |
| `vote` | `id` de l'option choisie | Écrans de vote ; on peut changer d'avis tant que le vote est ouvert |
| `ping` | `ts` | Chaque seconde |
| `rtt` | `ms` | Après chaque `pong` |
| `dbg`, `dbg_tp`, `dbg_cmd` | voir `tests/` | Tests uniquement (`dbg_tp` et `dbg_cmd` exigent le mode `--test`) |

## PC → téléphone

| `t` | Champs | Effet |
| --- | --- | --- |
| `welcome` | `slot`, `color`, `name`, `species`, `ability` | Joueur accepté ; `slot` est la couleur réellement attribuée |
| `layout` | `mode` + champs du mode (voir ci-dessous) | La manette change d'interface |
| `controle` | `name`, `species`, `species_label`, `ability`, `color`, `ornament`, `own` | Le personnage que ce téléphone contrôle désormais |
| `hint` | `hints` {« 0 » à « 3 » : libellé} | Touches utiles à l'endroit où l'on se trouve : elles grossissent, pulsent et affichent l'action ; vide = aucune. À l'abordage, A « Frapper », B « Tirer ●●○ » (cartouches), X « Roulade », et seulement Y « Changer » quand on est à terre |
| `armes` | `weapons` : [{`name`, `charge` 0 à 1, `ready`, `powered`}], `target` | Mise à jour du poste d'armes (environ 6 fois par seconde) |
| `vote_state` | `counts` {option: nombre}, `mine`, `remaining` (s) | Avancement d'un vote |
| `vote_done` | `id`, `label`, `tie` | Résultat d'un vote |
| `toast` | `text` | Court message en bas de l'écran |
| `medal` | `text`, `medals` | Épreuve réussie à l'Académie |
| `buzz` | — | Bip et vibration courte |
| `pong` | `ts` | Réponse au `ping` |
| `full` | — | Vaisseau complet (8 joueurs) |

### Modes de `layout`

| `mode` | Champs | Écran |
| --- | --- | --- |
| `base` | — | Joystick et 4 boutons |
| `armes` | `title`, `weapons` | Viseur au joystick, un bouton par arme |
| `vote` | `title`, `text`, `options` [{`id`, `label`, `desc`, `disabled`}], `mine`, `counts`, `remaining`, `duration` | Liste d'options à voter, minuteur |
| `equipage` | `crew` : [{`id`, `name`, `species`, `species_label`, `ability`, `color`, `ornament`, `status` (`toi`, `libre` ou nom du joueur), `free`, `where`, `avatar`}] | Liste de l'équipage, ouverte avec Y |
| `info` | `title`, `text` | Message simple (« Regarde l'écran ») |

## Principes

- Le téléphone envoie toujours **l'état complet** de ses commandes : un message perdu est corrigé par le suivant.
- C'est **le PC qui décide** de l'interface affichée sur le téléphone. Ajouter un poste = un nouveau `mode` pour `layout`, et l'écran correspondant dans `web/index.html`.
- Le `token` et le profil sont gardés sur le téléphone : après une coupure, on revient avec le même personnage.
