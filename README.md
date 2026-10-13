# L'Arche galactique — Prototype

Jeu coopératif de canapé (Godot 4.5) : le PC fait tourner le jeu sur la TV, chaque joueur se sert de son téléphone comme manette, sans rien installer. L'équipage escorte l'arche *Éléa* à travers un secteur hanté par l'Indicible.

## Lancer

1. Installer **Godot 4.5** (version standard).
2. Dans Godot, « Importer » et choisir `project.godot`, puis lancer avec F5.
3. Sur chaque téléphone, **connecté au même Wi-Fi que le PC**, scanner le QR code (ou taper l'adresse affichée).
4. Créer son personnage et appuyer sur « Embarquer ».

Au premier lancement, autorise Godot dans le pare-feu pour les réseaux privés. Ports utilisés : **8080** (page manette) et **9080** (WebSocket).

## Déroulement d'une partie

```
Académie (hub) → choix du vaisseau → carte du secteur ⇄ combat · événement · halte · boutique → boss → bilan → Académie
```

1. **Académie galactique** : on rejoint, on crée son personnage, on s'entraîne aux épreuves. Pour partir, un joueur appuie sur **A** à la **table de commandement** (Pont central). Sur le PC, la touche **Entrée** fait la même chose.
2. **Choix du vaisseau** : vote sur les téléphones entre trois vaisseaux.
3. **Carte du secteur** : 6 sauts jusqu'à l'Indicible. On vote chaque destination. Un saut coûte 1 carburant ; sans carburant, la coque perd 3 points.
4. **Nœuds** : combat, événement (« Inconnu »), halte, boutique, et le boss au bout.
5. **Bilan** : victoire ou défaite, colons sauvés, puis retour à l'Académie.

### Les votes

Tous les choix collectifs se font sur les téléphones : majorité simple, égalité tirée au sort, abstentions ignorées. Le vote se clôt dès que tout le monde a voté (ou à la fin du minuteur, avec une option par défaut). La TV montre qui a voté quoi.

### Les vaisseaux

| Vaisseau | Coque | Boucliers | Moteurs | Armes | Plan |
| --- | --- | --- | --- | --- | --- |
| Païkan | 30 | 1 | 2 | 2 canons | 7 salles en croix |
| Nautile | 38 | 2 | 1 | canon + torpille (traverse les boucliers) | 8 salles en longueur |
| Libellule | 22 | 1 | 3 | 2 canons rapides | 5 salles, compacte |

### Le combat

Règle de base : **tout fonctionne en automatique, un joueur fait toujours mieux.**

| Action | Comment |
| --- | --- |
| Viser et tirer | **A** devant le poste d'armes : la manette devient le poste d'armes. Le joystick déplace le viseur sur le vaisseau ennemi, un bouton par arme tire quand elle est chargée. Sans artilleur, les armes tirent seules, plus lentement et au hasard. |
| Éteindre un feu | Maintenir **B** près des flammes (Salamandrin ×2). Un feu abîme le système de la salle, la coque, et peut se propager. |
| Réparer | Maintenir **B** dans une salle dont le système est endommagé (Humain ×2). |
| Se déplacer | Joystick ; on glisse tout seul vers les portes quand on pousse contre un mur à côté. |

- **Boucliers** : chaque couche arrête un tir, puis se recharge (2,5 s).
- **Moteurs** : chance d'esquive (6 % par niveau), seulement si le **pilotage** fonctionne.
- **Armes** : chaque arme a besoin d'un niveau du système d'armes ; un système endommagé coupe des armes.
- Viser une salle ennemie endommage son système : les **boucliers** pour ouvrir une brèche, les **armes** pour le faire taire, le **cœur** de l'Indicible pour doubler les dégâts.

### Événements, haltes, boutique

- Les **événements** et **haltes** sont dans `data/events.json` : texte, choix, conséquences aléatoires pondérées (ferraille, carburant, coque, colons, améliorations, combat). On peut en ajouter sans toucher au code.
- La **boutique** vend carburant et réparations, plus deux objets tirés au hasard (bouclier, moteurs, canon lourd, torpille). On vote un achat à la fois.

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `game.gd` | Contrôleur : réseau, joueurs, enchaînement des scènes |
| `game_scene.gd`, `vote_scene.gd` | Bases des scènes et du système de vote |
| `academy.gd` | L'Académie (hub et épreuves) |
| `ship_select.gd`, `sector_map.gd`, `event_scene.gd`, `shop.gd`, `results.gd` | Scènes de vote |
| `combat.gd` | Le combat entre vaisseaux |
| `run_state.gd` | État d'une expédition et génération de la carte |
| `ship_data.gd` | Vaisseaux, armes, ennemis : **tout l'équilibrage est ici** |
| `ship_layout.gd` | Plans des vaisseaux : salles, portes, déplacements |
| `art.gd`, `hud.gd` | Palette et ornements Art nouveau, bandeau des ressources |
| `player.gd` | Un membre d'équipage et son dessin |
| `net_server.gd`, `qr.gd` | Serveur HTTP/WebSocket, QR code |
| `web/index.html` | La manette : création du personnage, manette, poste d'armes, votes |
| `data/events.json` | Événements et haltes |
| `tests/` | Faux téléphones pour les tests automatiques |

## Tests automatiques

Ils demandent Node.js 22 ou plus.

```
godot --path . -- --test                 # dans un premier terminal
node tests/academie.mjs                   # les cinq épreuves de l'Académie
node tests/expedition.mjs                 # une expédition gagnée, puis une perdue
```

`--test` active des commandes réservées aux tests (téléportation, changement de scène, captures d'écran). `--speed=8` accélère le jeu pour `tests/equilibrage.mjs`, qui mesure des combats laissés en automatique total.

## Limites connues

- Le changement de personnage (Y) et l'équipage non contrôlé ne sont pas encore là.
- Pas encore de poste ingénieur (énergie, portes) ni de poste pilote actif.
- Pas de méta-progression sur l'arche ni de mode narratif.
- Sur iPhone, pas de plein écran dans Safari, pas de vibration, et le mode silencieux coupe les sons.
- Pour **exporter** le jeu, ajoute `web/*`, `fonts/*.ttf` et `data/*.json` aux « Filtres pour exporter des fichiers non-ressources ».
