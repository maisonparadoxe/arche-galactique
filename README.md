# L'Arche galactique — Prototype : l'Académie galactique

Une salle d'entraînement dans un vaisseau immobile. Les joueurs scannent le QR code, créent leur membre d'équipage sur leur téléphone, puis passent cinq épreuves dans six salles.

## Lancer

1. Installer **Godot 4.5** (version standard).
2. Dans Godot, « Importer » et choisir `project.godot`, puis lancer avec F5.
3. Sur chaque téléphone, **connecté au même Wi-Fi que le PC**, scanner le QR code affiché en haut à droite (ou taper l'adresse indiquée).
4. Créer son personnage et appuyer sur « Embarquer ».

Au premier lancement, autorise Godot dans le pare-feu pour les réseaux privés. Ports utilisés : **8080** (page manette) et **9080** (WebSocket).

## Création du personnage

Sur le téléphone : nom, couleur (8 au choix ; si elle est prise, le jeu en attribue une autre), ornement (aucun, fleur, plume, couronne) et espèce. Le profil est mémorisé sur le téléphone pour les prochaines parties.

| Espèce | Capacité provisoire | Épreuve où elle brille |
| --- | --- | --- |
| Humain | Répare deux fois plus vite | Atelier |
| Automate | Visée assistée (cible deux fois plus large) | Stand de tir |
| Salamandrin | Éteint les feux deux fois plus vite | Salle des machines |
| Colosse | Porte les charges sans ralentir | Cellule d'énergie |

## Les épreuves

| Salle | Épreuve | Comment |
| --- | --- | --- |
| Salle des machines | Feu | Maintenir **B** près du feu. Le feu reprend doucement si on s'arrête ; il réapparaît ailleurs après 6 s. |
| Atelier | Réparation | Maintenir **B** près de la console. Elle retombe en panne après 8 s. |
| Soute → Réacteur | Cellule d'énergie | **X** près de la pile de cellules, porter (on ralentit, sauf le Colosse), **X** sur le socle du réacteur. **X** ailleurs pose la cellule par terre. |
| Réacteur | Redémarrage à deux | Deux joueurs maintiennent **A** chacun sur un levier pendant 2 s. Impossible seul pour l'instant. |
| Stand de tir | Tir | **A** devant la console : la manette devient un poste de tir. Le joystick déplace le viseur, « Tirer » tire. Trois cibles à abattre. |

Chaque épreuve réussie donne une médaille à ceux qui y ont participé : le téléphone joue un petit carillon et vibre, la TV affiche « +1 médaille » et met à jour le tableau.

**Y (Changer)** affiche pour l'instant « à la prochaine étape » : le changement de personnage arrive avec l'équipage complet.

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `main.gd` | L'Académie : plan du vaisseau, murs, épreuves, tableau, décor Art nouveau |
| `player.gd` | Un membre d'équipage et son dessin (espèce, ornement, couleur) |
| `net_server.gd` | Serveur HTTP (page manette, police) et WebSocket (manettes) |
| `qr.gd` | Générateur de QR code |
| `web/index.html` | La manette : création du personnage, manette de base, poste de tir |
| `fonts/` | Police de titre Federant (licence SIL OFL, voir `OFL-Federant.txt`) |
| `PROTOCOLE.md` | Les messages échangés entre téléphones et PC |

La page `web/index.html` est relue à chaque chargement : modifie-la, puis recharge simplement la page sur le téléphone.

## Mode test

`godot --path . -- --test` active deux commandes de développement : la téléportation d'un joueur (`dbg_tp`) et la capture d'écran automatique (`--shot=chemin.png --shot-at=5`). Elles ne servent qu'aux tests automatiques.

## Limites connues

- Le changement de personnage (Y) n'est pas encore là.
- Pas de personnages non contrôlés : le réacteur à deux demande deux joueurs.
- L'écran du téléphone peut se mettre en veille : règle la veille sur un délai long pendant les tests.
- Sur iPhone, pas de plein écran dans Safari, pas de vibration, et le mode silencieux coupe les sons.
- Pour **exporter** le jeu, ajoute `web/*` et `fonts/*.ttf` aux « Filtres pour exporter des fichiers non-ressources ».
