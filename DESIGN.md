# Conception visuelle — tableau de bord de navette 8 places

Ce document est la référence unique pour tout ce qui se voit à l'écran :
couleurs, typographie, espacement, durées d'animation, géométrie des
composants et contraintes de rendu sur la cible embarquée. Il fait autorité
sur ces sujets pour l'ensemble du dépôt.

Aucune valeur visuelle (couleur, taille, durée, rayon) ne doit apparaître en
dur dans un composant : tout passe par `src/Theme.js`.

Chaque règle est donnée avec sa raison. Celles du §1 découlent du cahier des
charges du véhicule et priment sur toute préférence esthétique.

## 1. Le contexte impose le design

Ces quatre contraintes viennent du cahier des charges du véhicule, pas d'une
préférence esthétique. Elles priment sur toute considération de style.

| Contrainte | Conséquence de conception |
|---|---|
| **Carrosserie ouverte, climat chaud** | Lecture en plein soleil. Contraste texte/fond ≥ 7:1. Aucun trait de moins de 3 px. Aucun gris moyen sur fond sombre pour une information utile. |
| **Conducteur en mouvement** | L'information vitale doit se lire en moins d'une demi-seconde, sans accommodation. La vitesse est l'élément le plus grand de l'écran, de loin. |
| **Raspberry Pi 4, VideoCore VI** | Budget GPU serré. Voir §5, non négociable. |
| **Écran 10", 1280×800 fixe** | Pas de responsive. On compose pour cette taille exacte. |

## 2. Langage visuel

Registre : instrumentation automobile électrique haut de gamme. Sobriété
extrême, hiérarchie brutale, zéro décoration.

**Principes**

1. **Le fond est un vide, pas une surface.** Presque noir, uniforme. Pas de
   dégradé d'ambiance, pas de texture, pas de vignettage.
2. **Trois couleurs visibles au maximum** en fonctionnement normal : fond,
   texte, accent. Les couleurs fonctionnelles (alerte, défaut) n'apparaissent
   que lorsqu'elles signalent quelque chose.
3. **Aucune boîte.** Pas de cartes, pas de panneaux, pas de bordures, pas de
   coins arrondis décoratifs. L'espace sépare, pas les traits. Un tableau de
   bord n'est pas une page web.
4. **Aucune ombre.** Ni portée, ni interne, ni lueur. Elles coûtent cher au
   GPU et trahissent immédiatement le rendu « web ».
5. **La hiérarchie se fait par la taille, pas par la couleur.** Le rapport
   entre la vitesse et le libellé d'unité doit dépasser 6:1.
6. **Le mouvement est continu, jamais saccadé ni rebondissant.** Aucun easing
   élastique, aucun *overshoot* : une donnée physique ne dépasse pas sa valeur.

**Contre-modèle à connaître** : le cluster Tesla Model 3 n'a pas de cadran.
Le cahier des charges en exige un. On reprend le *langage* (fond noir, un
grand chiffre, typographie fine et large, absence totale d'ornement), pas la
composition. Le résultat visé est plus proche d'un Polestar 2 ou d'un Model S :
un cadran, mais dépouillé.

## 3. Tokens — `src/Theme.js`

Fichier `.pragma library`. **Première ligne du fichier**, avant tout
commentaire, sinon `qt_add_qml_module` ne le détecte pas comme bibliothèque.

### Couleurs

| Token | Valeur | Usage |
|---|---|---|
| `bg` | `#07090C` | Fond général. Presque noir, très légèrement bleuté. |
| `surface` | `#101318` | Zones très rarement nécessaires. Éviter. |
| `track` | `#1E242C` | Arcs et graduations inactifs. |
| `textPrimary` | `#EAF0F5` | Vitesse, odomètre. Contraste ~16:1 sur `bg`. |
| `textSecondary` | `#7A848F` | Unités, libellés. Jamais pour une valeur. |
| `accent` | `#5FD3B4` | Arc de vitesse actif, remplissage de la jauge. **Un seul accent dans tout le projet.** |
| `warn` | `#F5A524` | Réservé. |
| `danger` | `#F4483B` | Source invalide, défaut. |

`textSecondary` sur `bg` donne ~5,5:1 — suffisant pour un libellé statique,
**insuffisant pour une valeur lue en roulant**. Ne jamais y mettre un nombre.

### Typographie

Police bundlée, jamais une police système : le rendu doit être identique sur
le Pi et sur la machine de développement. **Inter** (licence OFL) ou **Roboto**
(Apache 2.0), variante Regular + Light, chargée par `FontLoader`.

| Token | Taille | Graisse | Usage |
|---|---|---|---|
| `sizeSpeed` | 180 | 300 (Light) | Le chiffre de vitesse. |
| `sizeOdometer` | 34 | 300 | Kilométrage. |
| `sizeUnit` | 22 | 400 | `km/h`, `km`. Capitales, interlettrage +8 %. |
| `sizeLabel` | 16 | 400 | Libellés secondaires. |

**Chiffres tabulaires obligatoires** sur toute valeur qui change :

```qml
font.features: { "tnum": 1 }   // Qt 6.7+
```

Sans cela, la largeur des chiffres varie et le nombre « saute » latéralement à
chaque rafraîchissement. C'est le défaut le plus visible et le plus fréquent
sur ce type d'interface. Sur Qt < 6.7, se rabattre sur un conteneur de largeur
fixe par chiffre.

### Espacement et durées

Échelle : `4, 8, 12, 16, 24, 32, 48, 64, 96`. Rien en dehors.

| Token | Valeur | Usage |
|---|---|---|
| `durSpeed` | 60 ms | Lissage de la vitesse. Voir §4. |
| `durThrottle` | 80 ms | Jauge d'accélérateur. |
| `durFade` | 160 ms | Apparition/disparition d'un indicateur. |

## 4. Le lissage, point critique

La source publie à **20 Hz** (50 ms). Le rendu tourne à **60 Hz**. C'est
`Behavior`, côté affichage, qui interpole entre deux échantillons — et c'est
la preuve visible que le rendu ne dépend pas de la cadence de la source.

```qml
property real displaySpeed: source.speedKph
Behavior on displaySpeed {
    NumberAnimation { duration: Theme.durSpeed; easing.type: Easing.Linear }
}
```

**Easing linéaire, impérativement.** Un `InOutQuad` sur une donnée continue
produit un mouvement qui ralentit puis accélère entre chaque échantillon : le
cadran « respire » au rythme du timer. C'est l'artefact le plus courant.

**Durée ≈ période de la source** (50 ms), légèrement au-dessus pour absorber
la gigue. Au-delà de 100 ms, l'aiguille traîne visiblement derrière la donnée.

**L'affichage ne calcule jamais de physique.** Il lit une propriété et
l'interpole. Toute formule d'accélération dans un composant visuel est un
défaut de conception, pas un raccourci.

## 5. Contraintes GPU — Raspberry Pi 4

**Obligatoire**

```qml
Shape {
    preferredRendererType: Shape.CurveRenderer   // Qt 6.6+
}
```

Antialiasing calculé par le GPU. Sans lui, les arcs sont crénelés ou baveux —
c'est le détail qui sépare visuellement un rendu professionnel d'un rendu
amateur, et il tient en une ligne.

**Interdits**

| Interdit | Raison |
|---|---|
| `Canvas` | Rendu CPU, repasse par une texture à chaque image. Inutilisable à 60 Hz sur VideoCore. |
| `Qt5Compat.GraphicalEffects` | Déprécié, coûteux, et le style n'en a aucun besoin. |
| `layer.enabled` | Alloue une texture hors écran par élément. Seulement si mesuré nécessaire, jamais par défaut. |
| `DropShadow`, `Glow`, `Blur` | Cumul des deux points ci-dessus. |
| Animer `width`/`height` d'un `Shape` | Force la retessellation du chemin à chaque image. Animer `PathAngleArc.sweepAngle`, `rotation` ou `opacity`. |
| Une `Image` sans `sourceSize` | Décodage à la taille native puis rééchantillonnage. |

**Graduations** : un `Repeater` de `Rectangle` avec `transform: Rotation` est
plus économique et plus net qu'un `Shape` contenant un chemin par trait.

**Vérification** : mesurer avec le compteur de FPS, disponible à la demande
via l'option de lancement `--fps` — il est absent par défaut, un affichage de
mise au point n'ayant pas sa place sur un combiné de production. Un
composant qui fait tomber la cadence sous 55 est à revoir immédiatement, pas
à la fin.

## 6. Spécification du cadran

- **Balayage 270°**, de 135° à 405° (angles `PathAngleArc`, sens horaire,
  origine à 3 h). Ouverture vers le bas, convention automobile.
- **Deux arcs superposés** : la piste complète en `track`, l'arc actif en
  `accent`, dont seul `sweepAngle` est animé.
- **Extrémités arrondies** sur l'arc actif (`capStyle: ShapePath.RoundCap`),
  carrées sur la piste.
- **Épaisseur** : 14 px pour l'arc actif, 10 px pour la piste. En dessous de
  10 px, illisible en plein soleil.
- **Graduations** tous les 5 km/h, majeures tous les 10 avec la valeur
  chiffrée en `textSecondary`, `sizeLabel`.
- **Chiffre de vitesse au centre du cadran**, `sizeSpeed`, `textPrimary`,
  arrondi à l'entier — un dixième de km/h qui clignote est un défaut, pas une
  précision.
- **`km/h` sous le chiffre**, `sizeUnit`, `textSecondary`, capitales.
- **Pas d'aiguille.** L'arc *est* l'indicateur. Une aiguille ajoute une pièce
  mobile à animer pour zéro gain de lisibilité.

## 7. Mise en page 1280×800

```
┌──────────────────────────────────────────────────────────┐
│                                                    [FPS] │
│                                                          │
│              ╭───────────────╮                  ┌──┐     │
│             ╱                 ╲                 │  │     │
│            │       4 2         │                │██│     │
│            │      KM/H         │                │██│     │
│             ╲                 ╱                 │██│     │
│              ╰───────────────╯                  └──┘     │
│                                              ACCÉLÉRATEUR│
│                  1 2 4 7 . 3  KM                         │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

- Cadran centré horizontalement à ~45 % de la largeur, diamètre ~520 px.
- Jauge d'accélérateur verticale à droite, barre de 64 px de large, remplie
  par le bas en `accent`. Interactive au tactile et à la souris — c'est
  l'organe de commande exigé par l'énoncé, le clavier n'est qu'un appoint.
- Odomètre sous le cadran, aligné sur son axe.
- Marge extérieure : 48 px partout.
- Compteur de FPS en haut à droite, `textSecondary`, `sizeLabel`. Absent par
  défaut, affiché avec l'option `--fps` : il sert à mesurer pendant le
  développement et à démontrer la fluidité dans la vidéo, pas à meubler un
  combiné de production.

## 8. Contrôle avant de considérer un composant terminé

1. Aucune valeur visuelle en dur : tout vient de `Theme.js`.
2. `qmllint` passe sans **aucun** avertissement.
3. Le composant ne lit que des propriétés du contrat, jamais `throttleInput`
   et jamais une constante de `VehicleModel.js`.
4. Aucune formule de physique dans le composant.
5. Le compteur de FPS (`--fps`) reste au-dessus de 55 en `xcb` plein écran.
6. `Shape.CurveRenderer` activé sur tout `Shape`.
7. Chiffres tabulaires sur toute valeur qui change.
8. Aucun élément de la liste des interdits du §5.
9. Le composant fonctionne dans les **deux** modes de lancement.
10. Testé une fois **sur un écran réel**, pas seulement en `offscreen`.

## 9. Tokens de géométrie

Les valeurs géométriques des §6 et §7 (diamètre, angles, épaisseurs, pas de
graduation, marges) vivent aussi dans `Theme.js`, préfixées par le composant
concerné : `dialDiameter`, `dialStartAngle`, `dialActiveWidth`… Le §8.1
s'applique à elles comme au reste. Les constantes purement mathématiques
(`Math.PI / 180`, `"transparent"`, l'origine 270° de `PathAngleArc`) restent
en dur : ce ne sont pas des choix de design.
