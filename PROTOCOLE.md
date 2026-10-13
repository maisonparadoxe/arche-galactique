# Protocole manette ↔ PC

Messages JSON texte sur WebSocket (port 9080). Le champ `t` donne le type. La page manette est servie en HTTP sur le port 8080 (`/`), avec sa police (`/fonts/Federant-Regular.ttf`).

## Téléphone → PC

| `t` | Champs | Quand |
| --- | --- | --- |
| `hello` | `name` (12 car. max), `token`, `color` (0 à 7), `species` (`humain`, `automate`, `salamandrin`, `colosse`), `ornament` (`aucun`, `fleur`, `plume`, `couronne`) | À la connexion et à chaque reconnexion |
| `in` | `x`, `y` (joystick, -1 à 1, y vers le bas), `b` (4 booléens : Interagir, Action, Prendre, Changer) | 30 fois par seconde, état complet |
| `act` | `a` : `"fire"`, `"quit"` | Boutons des postes |
| `ping` | `ts` | Chaque seconde |
| `rtt` | `ms` | Après chaque `pong` |
| `dbg`, `dbg_tp` | `x`, `y` pour `dbg_tp` | Tests uniquement (`dbg_tp` exige le mode `--test`) |

## PC → téléphone

| `t` | Champs | Effet |
| --- | --- | --- |
| `welcome` | `slot`, `color`, `name`, `species`, `ability` | Joueur accepté ; `slot` est la couleur réellement attribuée |
| `layout` | `mode` (`"base"`, `"tir"`), `title` | La manette change d'interface |
| `toast` | `text` | Court message en bas de l'écran |
| `medal` | `text`, `medals` | Épreuve réussie : message, carillon, vibration, compteur |
| `buzz` | — | Bip et vibration courte |
| `pong` | `ts` | Réponse au `ping` |
| `full` | — | Vaisseau complet (8 joueurs) |

## Principes

- Le téléphone envoie toujours **l'état complet** de ses commandes : un message perdu est corrigé par le suivant.
- C'est **le PC qui décide** de l'interface affichée sur le téléphone. Ajouter un poste = un nouveau `mode` pour `layout`, et l'écran correspondant dans `web/index.html`.
- Le `token` et le profil sont gardés sur le téléphone : après une coupure, on revient avec le même personnage.
