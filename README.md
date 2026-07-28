# navette-dashboard

Tableau de bord de navette électrique 8 places, en Qt 6 / QML.

## Contexte et périmètre

Interface de conduite pour une navette électrique 8 places, destinée à un
Raspberry Pi 4 équipé d'un écran 10 pouces en 1280x800. Le projet couvre le
frontend seul : aucun backend, aucune lecture matérielle, aucun code CAN.

## Prérequis

Qt 6.8.3 LTS pour le développement, Qt 6.5 minimum à l'exécution ; CMake 3.21+
et Ninja pour la compilation.

Qt 6.8.3 est installé hors système, dans `$HOME/Qt`, via `aqtinstall` — le Qt
de la distribution n'est pas utilisé. `CMAKE_PREFIX_PATH` doit donc désigner
cette installation.

## Lancement

Deux modes sont supportés en permanence.

**Mode 1 — build CMake**, le mode de production :

```sh
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="$HOME/Qt/6.8.3/gcc_64"
cmake --build build
./build/dashboard
```

**Mode 2 — runtime QML**, pour itérer sans compiler :

```sh
"$HOME/Qt/6.8.3/gcc_64/bin/qml" src/Main.qml
```

Sur une machine sans affichage, préfixer par `QT_QPA_PLATFORM=offscreen`.

## Architecture

Découpage entre la couche de données simulées et la couche d'affichage, cette
dernière ne faisant que lire et lisser des propriétés.

| Fichier | Rôle |
|---|---|
| `src/VehicleModel.js` | Modèle physique pur, sans état ni effet de bord. Testable seul. |
| `src/SimulatedDataSource.qml` | Source de données. Publie le contrat, intègre le modèle à 20 Hz. |
| `src/OdometerStorage.qml` | Persistance de l'odomètre, isolée derrière un `Loader`. |
| `src/Main.qml` | Fenêtre principale. **Contient actuellement un harnais de mise au point temporaire.** |

L'affichage ne calcule jamais de physique : il lit les sorties de la source et
les lisse via `Behavior`. Cette règle est ce qui rend l'affichage indépendant
de la cadence — et donc interchangeable entre source simulée et source réelle.

## Structure des données simulées

Le contrat se lit en **deux parties distinctes**. C'est le point central de la
conception, et ce qui rend le passage au CAN réel indolore.

### Sorties — communes à toute source

Seules propriétés que l'affichage a le droit de lire. Toute source, simulée ou
réelle, doit les fournir.

| Champ | Type | Plage | Unité | Sens |
|---|---|---|---|---|
| `speedKph` | `real` | 0 à 50 | km/h | lecture seule |
| `odometerKm` | `real` | ≥ 0 | km | lecture seule, monotone croissant |
| `throttlePercent` | `real` | 0 à 100 | % | lecture seule |
| `sourceValid` | `bool` | — | — | lecture seule, `false` si la source est défaillante |

### Entrée de simulation — propre au simulateur

| Champ | Type | Plage | Unité | Sens |
|---|---|---|---|---|
| `throttleInput` | `real` | 0 à 100 | % | **écriture** par l'IHM |

Sur véhicule réel, la position de pédale provient du VCU via le bus CAN :
l'IHM ne la produit pas, elle la subit. `throttleInput` est donc le point
d'injection propre au simulateur. Il **disparaît** au passage au CAN, sans que
l'affichage change d'une ligne — puisque l'affichage ne lit que les sorties.

### Champ réservé, non implémenté

| Champ | Type | Plage | Unité | Statut |
|---|---|---|---|---|
| `brakePercent` | `real` | 0 à 100 | % | **réservé, non implémenté** |

Le freinage actif relève du Groupe III. L'énoncé ne demande que la
décélération en roue libre, qui est modélisée par `COAST_DECEL_MS2`.

### Cadence : 20 Hz

La source publie toutes les **50 ms**, soit 20 Hz.

Ce choix est structurel, pas esthétique. Une trame CAN périodique de vitesse
tourne typiquement entre 10 et 100 Hz ; 20 Hz est réaliste pour ce type de
véhicule. En publiant dès maintenant à cette cadence, on garantit que
l'affichage est conçu pour une source **lente et discrète**, et non pour une
animation continue. Le rendu tourne à 60 Hz avec une source à 20 Hz : c'est
`Behavior`, côté affichage, qui interpole entre deux trames. La démonstration
que le rendu ne dépend pas de la cadence de la source est ainsi faite par
construction.

L'écriture de l'odomètre sur disque est délibérément découplée : **0,2 Hz**
(toutes les 5 s) au lieu de 20 Hz, pour ménager la carte SD du Raspberry Pi.
Le compromis est qu'une coupure brutale peut perdre jusqu'à 5 s de trajet, ce
qui est sans conséquence sur un odomètre.

## Modèle physique

Tout est dans `src/VehicleModel.js`. Le modèle travaille en m/s en interne et
n'expose que des km/h, pour que les constantes restent lisibles en SI.

| Constante | Valeur | Unité | Origine |
|---|---|---|---|
| `MAX_SPEED_KPH` | 50 | km/h | Navette urbaine à carrosserie ouverte : vitesse bridée bien en dessous d'un véhicule routier, les passagers pouvant voyager debout. |
| `MAX_ACCEL_MS2` | 1,5 | m/s² | Véhicule 8 places chargé, annoncé à ~0-50 km/h en 12 s, soit une moyenne de (50/3,6)/12 ≈ 1,16 m/s². L'accélération décroissant avec la vitesse, la consigne à l'arrêt doit être supérieure à cette moyenne : 1,5 restitue les 12 s. |
| `COAST_DECEL_MS2` | 0,4 | m/s² | Résistance au roulement + traînée aérodynamique. Pas de frein moteur ni de récupération : la chaîne de traction est supposée en roue libre pédale relâchée. |

**Accélération** — approche asymptotique :

```
a = (throttle / 100) × MAX_ACCEL_MS2 × (1 − v / vMax)
```

L'accélération disponible décroît linéairement jusqu'à s'annuler à `vMax`. La
vitesse tend vers son plafond au lieu d'y buter brutalement, ce qui donne un
comportement de fin de course réaliste sur un cadran.

**Décélération** — pédale relâchée : `a = −COAST_DECEL_MS2`, constante jusqu'à
l'arrêt.

**Invariants garantis** : la vitesse n'est jamais négative et ne dépasse
jamais `MAX_SPEED_KPH` ; l'odomètre ne décroît jamais. L'odomètre est intégré
par la méthode des trapèzes, exacte lorsque l'accélération est constante.

`step(state, dt)` est **pure** : elle ne modifie pas son argument et retourne
un nouvel objet. `throttlePercent` est un champ de `state` plutôt qu'un
troisième paramètre, ce qui préserve la signature d'un intégrateur générique
et regroupe en un seul objet tout ce qui décrit l'instant courant.

## Passage aux données CAN réelles

Cette section est **de la documentation**. Aucun code CAN n'existe dans ce
dépôt et il n'est pas prévu d'en écrire ici.

### Ce qu'il y aurait à remplacer

Un seul fichier : `src/SimulatedDataSource.qml`, à substituer par un
`CanDataSource` qui publierait **les mêmes quatre sorties**.

| Élément actuel | Devient |
|---|---|
| `Timer` à 50 ms appelant `VehicleModel.step()` | Réception des trames CAN périodiques |
| `throttleInput` (écriture IHM) | **Disparaît** — la pédale vient du VCU |
| `throttlePercent` calculé depuis `throttleInput` | Décodé depuis la trame VCU |
| `speedKph` intégré localement | Décodé depuis la trame de vitesse |
| `odometerKm` intégré localement | Décodé, ou toujours intégré si le bus ne le publie pas |
| `sourceValid` = `_tick.running` | Watchdog sur l'âge de la dernière trame, compteur de séquence, CRC |

`_private.faulted` existe déjà dans `SimulatedDataSource` comme point
d'accroche pour cette détection de panne, précisément pour que l'ajouter plus
tard ne touche ni la propriété `sourceValid` ni l'affichage.

### Ce qu'il n'y aurait PAS à toucher

- **Tout l'affichage.** Il ne lit que les quatre sorties du contrat, jamais
  `throttleInput`. Aucun composant visuel ne change.
- **`VehicleModel.js`** — soit il devient inutile si le bus publie la vitesse,
  soit il reste tel quel pour intégrer l'odomètre. Dans les deux cas il n'est
  pas modifié.
- **`OdometerStorage.qml`** — la persistance est indépendante de l'origine des
  données.
- **`main.cpp`**, **`CMakeLists.txt`** (hors ajout du nouveau fichier), et la
  totalité des tests du modèle physique.

C'est la raison d'être de la séparation sorties / entrée de simulation : la
frontière de substitution est un fichier, pas une refonte.

## Tests

Tests QML exécutés par `qmltestrunner`, complétés par le lint `qmllint` qui
doit passer sans aucun avertissement.

```sh
"$HOME/Qt/6.8.3/gcc_64/bin/qmltestrunner" -input tests
cmake --build build --target all_qmllint
```

`tests/tst_vehiclemodel.qml` teste le **modèle physique seul**, jamais l'IHM :
saturation sous plein gaz, arrêt exact à zéro en roue libre, monotonie de
l'odomètre, indépendance au pas de temps et pureté de `step()`.

## Limites connues

- `src/Main.qml` contient un **harnais de mise au point temporaire** :
  affichage brut des sorties et pilotage clavier (flèche haut). Il sera
  remplacé à l'étape 4 par les cadrans et la jauge interactive.
- Le freinage actif (`brakePercent`) n'est pas implémenté.
- Aucune détection de panne de la source n'est implémentée ; `sourceValid`
  reflète seulement l'état du timer.
- L'intégration de la vitesse est un Euler explicite, d'erreur en O(dt).
  L'écart entre `dt = 0,05` et `dt = 0,01` sur 10 s est de 0,12 % — acceptable
  pour un affichage, à revoir si le modèle devait servir à autre chose.
