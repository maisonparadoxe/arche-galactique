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
Académie (hub) → choix du vaisseau → carte du secteur ⇄ combat · abordage · île · événement · halte · boutique → boss → bilan → Académie
```

1. **Académie galactique** : on rejoint, on crée son personnage, on s'entraîne aux épreuves. Pour partir, un joueur appuie sur **A** à la **table de commandement** (Pont central). Sur le PC, la touche **Entrée** fait la même chose.
2. **Choix du vaisseau** : vote sur les téléphones entre trois vaisseaux, puis **vote de la difficulté** :

   | Difficulté | Sauts avant le boss | Ennemis | Départ |
   | --- | --- | --- | --- |
   | Découverte | 3 | coque ×0,5, tirent ~40 % moins vite, 2 fois moins d'incendies | +2 carburant, +15 ferraille |
   | Normal | 6 | tels que prévus | — |
   | Difficile | 6 | coque ×1,3, tirent ~18 % plus vite, 40 % d'incendies en plus | — |

   Les réglages sont dans `ShipData.DIFFICULTIES` (`ship_data.gd`). Le jeu propose par défaut la dernière difficulté choisie.
3. **Carte du secteur** : 6 sauts jusqu'à l'Indicible. On vote chaque destination. Un saut coûte 1 carburant ; sans carburant, la coque perd 3 points.
4. **Nœuds** : combat de vaisseaux, **navire marchand** et **île au trésor** (abordages à pied), événement (« Inconnu »), halte, boutique, et le boss au bout.
5. **Bilan** : victoire ou défaite, colons sauvés, puis retour à l'Académie.

### L'équipage et le changement de personnage

Chaque téléphone contrôle **un** membre d'équipage ; les autres membres sont **libres** et travaillent tout seuls, à mi-vitesse, là où ils se trouvent : ils éteignent les feux et réparent le système de leur salle, et tiennent un levier si on les y laisse.

- **Y (Changer)** ouvre la liste de l'équipage sur le téléphone : portrait, espèce, capacité, salle où se trouve chaque membre. On touche un membre **libre** pour en prendre le contrôle, ou **Retour** pour revenir à la manette. Le personnage qu'on lâche reste sur place et passe en automatique.
- Ton personnage créé sur le téléphone est marqué d'une ★. Après une déconnexion, tu le retrouves.
- À l'Académie, trois **recrues** attendent avec les joueurs. Exemple en solo : laisse ton personnage sur un levier du réacteur, prends une recrue et va sur l'autre levier.
- En expédition, l'équipage est complété par des recrues d'espèces différentes : Païkan 4 membres, Nautile 5, Libellule 3. Les recrues commencent à leurs postes (armes, boucliers, moteurs, pilotage), les joueurs dans la coursive.
- À la TV, un anneau à ta couleur entoure le personnage que tu contrôles ; les membres libres sont marqués « auto » et un engrenage tourne quand ils travaillent.
- On ne peut pas changer de personnage pendant qu'on est au poste d'armes : il faut d'abord le quitter.

### Les touches qui se mettent en avant

Quand ton personnage se trouve près de quelque chose d'utile, la bonne touche du téléphone grossit, pulse et affiche l'action : **A « Lancer »** sur la table de départ, **A « Levier »**, **A « S'installer »** ou **A « Armes »** devant un poste, **B « Éteindre »** près d'un feu, **B « Réparer »** dans une salle endommagée, **X « Prendre / Poser / Brancher »** pour les cellules. Les autres touches s'estompent. Au poste d'armes, une arme chargée pulse aussi.

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
| Piloter | **A** devant la console du Pont : bouton « Virer ! » = 2,5 s d'esquive +32 % (délai 9 s). Un pilote à la barre ajoute aussi +8 % d'esquive en permanence. |
| Machines | **A** devant la console de la coursive : on envoie l'énergie aux armes (charge ×1,5), aux boucliers (recharge ×2) ou aux moteurs (+8 % d'esquive). Le bouton « Cloisons » empêche le feu de se propager. Sans ingénieur : rien de tout ça. |
| Éteindre un feu | Maintenir **B** près des flammes (Salamandrin ×2). Un feu abîme le système de la salle, la coque, et peut se propager. Un membre libre éteint seul les feux de sa salle. |
| Réparer | Maintenir **B** dans une salle dont le système est endommagé (Humain ×2). Un membre libre répare seul le système de sa salle. |
| Changer de personnage | **Y**, puis toucher un membre libre dans la liste. |
| Se déplacer | Joystick ; on glisse tout seul vers les portes quand on pousse contre un mur à côté. |

- **Boucliers** : chaque couche arrête un tir, puis se recharge (2,5 s).
- **Moteurs** : chance d'esquive (6 % par niveau), seulement si le **pilotage** fonctionne.
- **Armes** : chaque arme a besoin d'un niveau du système d'armes ; un système endommagé coupe des armes.
- Viser une salle ennemie endommage son système : les **boucliers** pour ouvrir une brèche, les **armes** pour le faire taire, le **cœur** de l'Indicible pour doubler les dégâts.

### L'abordage (navire marchand, île au trésor)

Tout l'équipage descend du vaisseau et nettoie un niveau à pied, vu de dessus, salle après salle, façon Hotline Miami : **un coup tue**, les ennemis comme les joueurs, et chaque attaque ennemie est **annoncée** (zone rose, ligne de tir) pour qu'on puisse l'éviter.

| Touche | Action |
| --- | --- |
| Joystick | Se déplacer |
| **A** « Frapper » | Coup d'épée devant soi : tue tout ce qu'il touche et dévie les balles. Se tourne seul vers l'ennemi proche |
| **B** « Tirer ●●● » | Pistolet, **visée automatique** (3 cartouches qui se rechargent). Les Automates visent dans un cône plus large |
| **X** « Roulade » | Esquive : invulnérable un instant. Les Salamandrins la relancent plus vite |
| **Y** | Changer de personnage, comme partout (utile quand on est à terre) |

- **Rester ensemble.** Le niveau est plus large que l'écran. Personne ne peut sortir de l'image : celui qui court en avant attend au bord, et la caméra ne progresse que si le groupe reste uni. Quand quelqu'un traîne trop, son personnage est entouré d'or et l'écran affiche « Attendez … ! ». Au bout de 18 s (6 s pour un membre libre), le retardataire est ramené auprès du groupe.
- **À terre.** Touché, on tombe. Il suffit qu'un équipier reste près de soi pour vous relever (3 s ; deux fois plus vite par un Humain, plus vite à plusieurs). Sans aide, on se relève au bout de 14 s auprès d'un équipier. Si tout l'équipage est à terre, c'est le **repli** : -3 coque, pas de butin.
- **Membres libres.** Ils suivent un joueur, se défendent contre les ennemis éveillés et relèvent les blessés, un peu moins bien qu'un joueur. Ils ne chassent pas les ennemis endormis.
- **Portes verrouillées.** Une porte reste fermée tant que la salle qui la précède (côté départ) contient des ennemis, même endormis. On peut toujours revenir en arrière. Les verrous sont roses, avec un compte des ennemis restants.
- **Niveaux.** Navire marchand (galion), caravelle de commerce, île au trésor, et **épave corrompue** (ombres rapides, sporeurs qui tirent des spores, gardien du Nid). L'épave se trouve dans la dernière partie du secteur.
- **Butin.** Coffres dans les salles (traversés = ouverts), gros coffre au fond, bonus du capitaine. Enchaîner des kills (×2, ×3…) fait grimper le score ; un enchaînement de 5 et un équipage sans chute donnent chacun +3 ferraille.
- **Équilibrage.** Le nombre d'ennemis suit la taille de l'équipage et la difficulté ; leurs préavis s'allongent en Découverte. Niveaux, ennemis et coffres sont dans `ShipData.BOARDINGS` et `BOARDING_FOES` : ajouter une île ou un galion, c'est ajouter des salles à cet endroit.

### Réputation et dilemmes

L'équipage a une **réputation** de -10 (« Fléau des mers ») à +10 (« Corsaire exemplaire »), affichée dans le bandeau du haut.
- Boutique : prix de -4 % par point de réputation (de 0,7 à 1,3).
- Abordages : une mauvaise réputation rapporte plus de butin (+4 % par point négatif).
- Colons sauvés : +2 % par point de réputation.
- Événements : certains n'apparaissent qu'à partir d'une réputation donnée (`when`), certains choix exigent un titre (`requires`).

Le nœud « Navire marchand » ouvre un dilemme (`convoi_*` dans `data/events.json`) : piller, escorter, négocier… Les effets `rep` et `abordage` s'y ajoutent aux effets habituels. Commande de debug : `rep`.

### Répliques de l'équipage

De temps en temps, un membre d'équipage lâche une réplique drôle dans une bulle au-dessus de sa tête (écran TV). Elles sont rares : probabilité par situation, 22 s minimum entre deux répliques, 80 s entre deux de la même situation. Situations : série d'ennemis, chute, relève, coffre, porte, victoire, repli, boutique, combat, coque touchée, événement. Les références littéraires sont des clins d'œil, jamais des citations. Banque de répliques : `quips.gd`. Commande de debug : `quip`.

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
| `boarding.gd` | L'abordage à pied : niveaux défilants, caméra solidaire, ennemis, relève |
| `run_state.gd` | État d'une expédition et génération de la carte |
| `ship_data.gd` | Vaisseaux, armes, ennemis : **tout l'équilibrage est ici** |
| `ship_layout.gd` | Plans des vaisseaux : salles, portes, déplacements |
| `art.gd`, `hud.gd` | Palette et ornements Art nouveau, bandeau des ressources |
| `player.gd` | Un membre d'équipage (contrôlé ou libre) et son dessin |
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
node tests/equipage.mjs                   # en solo : changement de personnage, équipage automatique
node tests/abordage.mjs                   # trois téléphones à l'abordage : caméra solidaire, relève, coups, repli
```

`--test` active des commandes réservées aux tests (téléportation, changement de scène, captures d'écran). `--speed=8` accélère le jeu pour `tests/equilibrage.mjs`, qui mesure des combats laissés en automatique total.

### Sons

Tous les sons sont **générés par le jeu** (aucun fichier audio) : coups, tirs, relève, coffres, portes, fanfares, et deux musiques. Une musique calme accompagne la gestion ; à l'abordage, une musique à couches (basse, batterie, arpège) s'allume quand les ennemis s'éveillent et qu'on enchaîne les victimes. La touche **M** coupe ou rétablit le son du PC. Les téléphones jouent leurs propres petits sons (appui sur une touche, chute, relève, coffre).

## Limites connues

- À l'Académie et en combat de vaisseaux, les membres libres ne se déplacent pas d'eux-mêmes : c'est à toi de les placer (à l'abordage, ils suivent le groupe).
- Abordage : quatre niveaux seulement (galion, caravelle, île, épave) ; les sons n'ont été vérifiés que sur le papier (je n'ai pas d'oreilles), à régler à l'usage.
- Pas encore de poste ingénieur (énergie, portes) ni de poste pilote actif.
- Pas de méta-progression sur l'arche ni de mode narratif.
- Sur iPhone, pas de plein écran dans Safari, pas de vibration, et le mode silencieux coupe les sons.
- Pour **exporter** le jeu, ajoute `web/*`, `fonts/*.ttf` et `data/*.json` aux « Filtres pour exporter des fichiers non-ressources ».
