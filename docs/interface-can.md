# Interface CAN — proposition d'interface

> ## ⚠ Statut de ce document
>
> **Ceci est une proposition émise par l'équipe frontend, pas une
> spécification arrêtée.** Elle doit être validée — et selon toute
> vraisemblance corrigée — par l'équipe firmware (Groupe III) avant toute
> implémentation.
>
> Les identifiants, l'encodage octet par octet, les facteurs d'échelle et les
> périodes d'émission décrits ici **ont été inventés par l'équipe frontend**,
> faute de connaître le format de trames réellement produit par le VCU. Ils
> servent à montrer que l'architecture d'affichage est prête à recevoir un bus
> réel, et à donner une base de discussion chiffrée. **Aucun de ces choix n'a
> été convenu avec le Groupe III.**
>
> En cas de divergence, **le format du Groupe III prime sans discussion.**
>
> | Partie | Statut |
> |---|---|
> | Les cinq grandeurs attendues, leurs noms, unités et plages | **Fermé** — c'est le contrat que l'affichage lit déjà |
> | Le comportement attendu en cas de défaut de source | **Fermé** dans son principe, ouvert dans ses seuils |
> | Identifiants CAN, encodage, facteurs d'échelle, périodes | **Ouvert** — proposition à valider |
> | Présence de l'odomètre sur le bus | **Ouvert** — voir §7 |
> | Débit du bus, matériel d'adaptation | **Ouvert** — voir §7 |

Aucun code CAN n'existe dans ce dépôt et il n'est pas prévu d'en écrire ici :
le périmètre du projet est le frontend seul. Ce document décrit ce qu'il
faudrait faire, pas ce qui est fait.

---

## 1. Ce que l'affichage attend — la partie fermée

Ces cinq propriétés sont le **contrat de sortie**, repris à l'identique de la
section « Structure des données simulées » du [`README.md`](../README.md).
Mêmes noms, mêmes unités, mêmes plages.

| Champ | Type | Plage | Unité | Sens |
|---|---|---|---|---|
| `speedKph` | `real` | 0 à `maxSpeedKph` | km/h | lecture seule |
| `maxSpeedKph` | `real` | > 0 | km/h | lecture seule, constante pour une source donnée |
| `odometerKm` | `real` | ≥ 0 | km | lecture seule, monotone croissant |
| `throttlePercent` | `real` | 0 à 100 | % | lecture seule |
| `sourceValid` | `bool` | — | — | lecture seule, `false` si la source est défaillante |

**Cette partie n'est pas négociable** parce que c'est exactement ce que les
composants d'affichage lisent aujourd'hui, et que le but de l'exercice est
précisément qu'ils ne changent pas lors du passage au bus réel.

Une source CAN devra donc publier ces cinq propriétés, avec ces noms et ces
unités. Ce qu'elle fait en interne pour y parvenir — décodage, mise à
l'échelle, intégration — ne regarde qu'elle.

---

## 2. Trames proposées — synthèse

> Rappel : identifiants, périodes et longueurs ci-dessous sont **proposés**,
> pas convenus.

| Identifiant | Nom proposé | Longueur | Période proposée | Émetteur |
|---|---|---|---|---|
| `0x100` | `VEHICLE_DYNAMICS` | 8 octets | 50 ms (20 Hz) | VCU |
| `0x300` | `ODOMETER` | 4 octets | 1000 ms (1 Hz) | VCU |
| `0x500` | `VEHICLE_CONFIG` | 2 octets | 1000 ms (1 Hz) | VCU |

**Pourquoi ces identifiants.** Sur un bus CAN, l'arbitrage se fait par
l'identifiant : à émission simultanée, **le plus petit identifiant gagne** et
l'autre émetteur réessaie. L'ordre proposé traduit donc une hiérarchie de
priorité, pas une numérotation arbitraire :

- `0x100` pour la dynamique du véhicule, parce que c'est la seule des trois
  dont un retard se verrait à l'écran. Un cadran de vitesse qui saute est un
  défaut perceptible immédiatement.
- `0x300` pour l'odomètre : un retard de quelques dizaines de millisecondes
  sur un kilométrage cumulé est strictement invisible.
- `0x500` pour la configuration : émise une fois par seconde, sans contrainte
  de latence.

Les trois valeurs sont espacées pour laisser de la place à des trames
intercalées sans renumérotation. Elles n'ont de sens que si elles ne
percutent pas le plan d'adressage existant du Groupe III — **c'est la
première chose à vérifier avec eux.**

**Charge de bus induite**, ordre de grandeur : environ 2,9 kbit/s au total en
tenant compte du bit stuffing, soit **moins de 1 % d'un bus à 500 kbit/s**. Le
choix des périodes n'est donc pas contraint par la bande passante.

---

## 3. Détail des trames

### 3.1 `0x100` — `VEHICLE_DYNAMICS`, 8 octets, 50 ms

| Octets | Signal | Type | Endianness | Facteur | Offset | Plage physique | Unité |
|---|---|---|---|---|---|---|---|
| 0–1 | `Speed` | uint16 | little-endian | 0,01 | 0 | 0 à 655,35 | km/h |
| 2 | `ThrottlePosition` | uint8 | — | 0,5 | 0 | 0 à 127,5 | % |
| 3 | `SequenceCounter` | uint8 | — | 1 | 0 | 0 à 255, rebouclant | — |
| 4 | `StatusFlags` | uint8 | — | — | — | champ de bits, réservé | — |
| 5–6 | *réservé* | — | — | — | — | — | — |
| 7 | `Checksum` | uint8 | — | — | — | 0 à 255 | — |

**Période de 50 ms.** Elle correspond exactement à la cadence de la source
simulée du projet. Ce n'est pas une coïncidence : `SimulatedDataSource` publie
à 20 Hz **précisément pour imiter une trame périodique réaliste**, de sorte
que l'affichage soit conçu dès le départ pour une source lente et discrète.
Le lissage par `Behavior` est déjà dimensionné pour cette période
(`durSpeed` = 60 ms, légèrement au-dessus pour absorber la gigue). Si le
Groupe III émet à une autre cadence, c'est `durSpeed` qu'il faudra ajuster —
une seule valeur, dans `src/Theme.js`.

**Facteur d'échelle de la vitesse : 0,01 km/h sur 16 bits.**

```
plage = 65535 × 0,01 = 655,35 km/h     couvre 50 km/h avec un facteur 13
résolution = 0,01 km/h
```

La marge est large, volontairement : elle absorbe sans changer le DBC une
variante de véhicule plus rapide, et l'encodage reste identique à celui de
`VEHICLE_CONFIG`, ce qui permet de comparer les deux signaux sans conversion.
La résolution, elle, est justifiée par la géométrie du cadran : l'arc de 270°
mesure environ 1192 px de long pour 50 km/h, soit **23,8 px par km/h**. Un pas
de 0,01 km/h vaut donc 0,24 px — sous le pixel, donc invisible. Un uint8 à
0,5 km/h aurait suffi en plage (0 à 127,5) et économisé un octet, mais aurait
produit des sauts de 12 px sur l'arc : rejeté.

**Facteur d'échelle de l'accélérateur : 0,5 % sur 8 bits.**

```
plage = 255 × 0,5 = 127,5 %            couvre 100 % avec 27,5 % de marge
résolution = 0,5 %
```

Un octet suffit, et la résolution se justifie là encore par le rendu : la
jauge fait 320 px de haut, donc 1 % vaut 3,2 px et 0,5 % vaut 1,6 px. Un
facteur de 1 % aurait produit des marches de 3 px visibles pendant un
mouvement lent de pédale.

**`SequenceCounter`** — voir §5, c'est un élément de détection de défaut et
non une donnée d'affichage.

**`StatusFlags` et octets 5–6** — réservés. Proposés vides plutôt que
supprimés : une trame de 8 octets coûte le même temps de bus qu'une trame de
5 dans la plupart des plans d'adressage, et laisser de la place évite d'avoir
à créer une seconde trame pour le premier drapeau qu'on voudra ajouter.

**`Checksum`** — proposition d'un CRC-8 sur les octets 0 à 6. À valider :
beaucoup de bus s'en passent, le CAN ayant déjà son propre CRC au niveau
trame. Il ne protège que contre une corruption *applicative*, en amont du
contrôleur.

### 3.2 `0x300` — `ODOMETER`, 4 octets, 1000 ms

| Octets | Signal | Type | Endianness | Facteur | Offset | Plage physique | Unité |
|---|---|---|---|---|---|---|---|
| 0–2 | `TotalDistance` | uint24 | little-endian | 0,1 | 0 | 0 à 1 677 721,5 | km |
| 3 | `SequenceCounter` | uint8 | — | 1 | 0 | 0 à 255, rebouclant | — |

**Période de 1 Hz.** À 50 km/h, le véhicule parcourt 13,9 m par seconde, soit
un pas d'affichage de 0,014 km — en dessous de la décimale affichée par
`Odometer.qml`. Émettre plus souvent n'apporterait rien de visible.

**Facteur d'échelle : 0,1 km sur 24 bits.**

```
plage = 16777215 × 0,1 = 1 677 721,5 km
```

Pour une durée de vie plausible de 500 000 km, cela laisse un facteur 3,4. La
résolution de 0,1 km correspond exactement à la décimale affichée : ni plus
fine, donc pas de bits gaspillés, ni plus grossière, donc pas de saut visible.
Un uint32 aurait été plus simple à décoder et byte-aligné, au prix d'un octet
pour une plage de 429 millions de kilomètres dont personne n'a l'usage. **Le
choix uint24 est discutable et à arbitrer avec le Groupe III** : si leur
outillage manipule mal les entiers 24 bits, uint32 est un compromis
raisonnable.

### 3.3 `0x500` — `VEHICLE_CONFIG`, 2 octets, 1000 ms

| Octets | Signal | Type | Endianness | Facteur | Offset | Plage physique | Unité |
|---|---|---|---|---|---|---|---|
| 0–1 | `MaxSpeed` | uint16 | little-endian | 0,01 | 0 | 0 à 655,35 | km/h |

Encodage volontairement **identique** à celui de `Speed` dans `0x100`, pour que
la comparaison entre vitesse courante et plafond ne demande aucune conversion.

### 3.4 Le cas de `maxSpeedKph` — une constante, pas une mesure

`maxSpeedKph` est la seule des cinq sorties qui ne varie pas. La transmettre
comme une grandeur périodique est une possibilité parmi d'autres, et le choix
mérite d'être posé explicitement.

| Option | Coût | Risque |
|---|---|---|
| **A — Déclarée dans le fichier DBC** | Nul sur le bus. La valeur vit dans la base de signaux, avec les définitions d'échelle. | L'IHM doit embarquer le DBC ou une valeur qui en dérive. Une modification impose de redéployer les deux côtés en cohérence. Réintroduit un risque de divergence. |
| **B — Émise dans une trame de configuration** (proposée ci-dessus) | Une trame de 2 octets à 1 Hz, soit ~0,02 % d'un bus à 500 kbit/s. | L'IHM doit gérer l'état « pas encore reçue » au démarrage, pendant au plus une période. |
| **C — Fixée par la configuration du véhicule**, compilée dans l'IHM | Nul. | Réintroduit exactement la duplication supprimée à l'étape 6 : la valeur serait écrite à la fois dans le firmware et dans l'IHM, sans rien pour garantir qu'elles restent d'accord. |

**Recommandation : l'option B.** Elle est la seule qui préserve la propriété
sur laquelle repose toute l'architecture — **c'est la source qui publie
l'échelle de ses propres signaux**, pas l'afficheur qui la devine. C'est
littéralement la raison pour laquelle `maxSpeedKph` a été ajouté au contrat
plutôt que laissé en constante du cadran. Le choix d'une émission
**périodique** plutôt qu'au seul démarrage est délibéré : il permet de
redémarrer l'IHM sans redémarrer le VCU, ce qui arrivera constamment en
intégration.

En attendant la première réception, la proposition est que la source publie la
valeur par défaut du cadran et lève `sourceValid` à faux — le comportement est
alors le même que pour toute autre trame manquante, sans cas particulier.

---

## 4. Correspondance trame → contrat

| Champ de trame | Propriété du contrat | Traitement |
|---|---|---|
| `0x100.Speed` | `speedKph` | Décodage direct, × 0,01 |
| `0x100.ThrottlePosition` | `throttlePercent` | Décodage direct, × 0,5, borné à 100 |
| `0x300.TotalDistance` | `odometerKm` | Décodage direct, × 0,1 |
| `0x500.MaxSpeed` | `maxSpeedKph` | Décodage direct, × 0,01 |
| `0x100.SequenceCounter`, `0x300.SequenceCounter`, âge des trames | `sourceValid` | **Calculé**, voir §5 |

**Champs du contrat qui ne viennent pas directement d'une trame :**

- **`sourceValid`** n'est transmis par personne. C'est une propriété
  *déduite* par la source à partir de l'âge des trames et de la progression
  des compteurs de séquence. Aucun émetteur ne peut signaler de manière fiable
  sa propre absence.
- **`odometerKm`**, si le Groupe III ne publie pas d'odomètre sur le bus. Il
  faudrait alors l'intégrer localement à partir de `speedKph`, comme le fait
  déjà `VehicleModel.js`, et le persister via `OdometerStorage.qml`. C'est une
  question ouverte, posée au §7.

---

## 5. Détection de défaut — alimentation de `sourceValid`

### 5.1 Chien de garde sur l'âge de la dernière trame

**Proposition : seuil à 3 périodes**, soit 150 ms pour `0x100` et 3 s pour
`0x300`.

Trois périodes tolèrent la perte de deux trames consécutives sans lever de
fausse alarme — ce qui arrive normalement lors d'un pic d'arbitrage ou d'une
erreur de bus isolée — tout en restant sous le seuil de perception : à 150 ms,
un cadran figé n'est pas encore lisible comme figé par un conducteur.
Descendre à 2 périodes rendrait l'indicateur nerveux ; monter à 5 laisserait
250 ms de données périmées affichées comme valides, ce qui est trop long sur
une information de vitesse.

Ce seuil est **à valider avec le Groupe III**, qui seul connaît le taux
d'erreur réel du bus et la gigue de son ordonnanceur.

### 5.2 Compteur de séquence

Le compteur de séquence répond à un défaut que le chien de garde ne voit pas.

Si le VCU cesse de mettre à jour ses données mais qu'un composant en aval —
passerelle, tampon, tâche bloquée sur un buffer figé — continue d'émettre la
dernière trame connue, alors les trames **arrivent bien à l'heure** et le
chien de garde reste silencieux. Le contenu, lui, est périmé.

Or **une donnée figée est indistinguable d'une donnée stable** : un véhicule à
l'arrêt et un véhicule dont le capteur de vitesse est mort publient tous deux
`speedKph = 0`, indéfiniment. Le compteur lève cette ambiguïté : il doit
progresser à chaque émission, quel que soit le contenu. S'il stagne entre deux
trames reçues, les données sont périmées même si elles arrivent.

Proposition : incrément de 1 à chaque émission, rebouclage de 255 à 0, et
`sourceValid` à faux après trois trames consécutives sans progression.

### 5.3 Ce que l'affichage doit faire quand `sourceValid` passe à faux

Le comportement actuel, déjà implémenté : un indicateur `SOURCE INVALIDE` en
`Theme.danger` apparaît en fondu, et **rien n'est affiché tant que tout va
bien** — c'est le seul usage prévu de cette couleur dans tout le projet.

**Point à trancher, et il est de sécurité** : que faire des valeurs
elles-mêmes ? Trois comportements possibles, avec une recommandation nette.

- **Les remettre à zéro** — à rejeter. Afficher « 0 km/h » sur un véhicule qui
  roule est le pire mode de défaillance imaginable : le conducteur lirait une
  information fausse et plausible.
- **Les figer sur la dernière valeur connue** — le comportement actuel. Une
  information périmée, mais signalée comme telle par l'indicateur.
- **Les masquer**, en remplaçant le chiffre par des tirets. Plus honnête :
  aucune valeur n'est affirmée. C'est la pratique de nombreux combinés
  automobiles.

**Recommandation : masquer**, avec l'indicateur. Ce n'est pas implémenté à ce
jour, et cela relève d'une décision produit autant que technique.

### 5.4 Le point d'accroche existe déjà

Aucun de ces mécanismes ne demande de toucher à l'affichage. Dans
`src/SimulatedDataSource.qml`, `sourceValid` est déjà déduite d'un état
interne prévu pour cela :

```qml
property bool faulted: false
readonly property bool sourceValid: _tick.running && !_private.faulted
```

Une source CAN alimenterait `faulted` depuis son chien de garde et son
compteur de séquence. La propriété publique, sa sémantique, et tout ce qui la
lit restent inchangés.

---

## 6. Procédure de substitution

### 6.1 Ce qu'il y a à faire, dans l'ordre

**Étape 1 — écrire `src/CanDataSource.qml`.**

Un composant non visuel publiant **exactement les cinq propriétés** du §1, avec
ces noms et ces unités. Il encapsule la réception, le décodage, la mise à
l'échelle et la détection de défaut. Il ne doit exposer **aucune** propriété
d'entrée : contrairement au simulateur, il n'y a rien à piloter — la pédale
est physique.

**Étape 2 — changer une déclaration dans `src/Main.qml`.**

```qml
SimulatedDataSource {      // devient : CanDataSource {
    id: source
}
```

L'`id: source` est conservé, ce qui laisse intactes toutes les liaisons qui
en dépendent : `source.speedKph`, `source.maxSpeedKph`, `source.odometerKm`,
`source.throttlePercent`, `source.sourceValid`.

**Étape 3 — supprimer le pilotage manuel dans `src/Main.qml`.**

Deux blocs perdent leur objet dès qu'une vraie pédale existe :

- le gestionnaire `onValueRequested` de `ThrottleGauge`, qui écrit dans
  `source.throttleInput` — propriété qui n'existe plus, puisqu'elle était
  l'entrée d'injection propre au simulateur ;
- l'`Item` `keyboardControl` en entier, avec son `Timer` de rampe : piloter
  l'accélérateur au clavier pendant que le conducteur appuie sur une pédale
  produirait deux commandes concurrentes pour un même organe.

Le composant `ThrottleGauge` lui-même, en revanche, **peut et devrait rester**
— en lecture seule. Il affiche `source.throttlePercent`, c'est-à-dire la
position réelle de la pédale, ce qui reste une information utile au
conducteur. Il faudrait alors neutraliser sa zone de saisie, faute de quoi un
appui sur l'écran émettrait un signal que plus personne n'écoute.

**Étape 4 — mettre à jour `CMakeLists.txt`.**

Dans le bloc `qt_add_qml_module`, remplacer une ligne de `QML_FILES` :

```cmake
src/SimulatedDataSource.qml   →   src/CanDataSource.qml
```

### 6.2 Ce qui ne change pas — l'argument principal du projet

| Fichier | Pourquoi il ne bouge pas |
|---|---|
| `src/SpeedDial.qml` | Lit `speedKph` et `maxSpeedKph`, deux propriétés du contrat. Il ignore d'où elles viennent, et n'importe aucune constante physique. |
| `src/Odometer.qml` | Lit `odometerKm`. Une seule entrée, aucune connaissance de la source. |
| `src/ThrottleGauge.qml` | Le composant expose une entrée `value` et un signal ; c'est `Main.qml` qui câble. Retirer le câblage n'impose aucune modification du composant. |
| `src/Theme.js` | Tokens de design. Sans rapport avec l'origine des données. |
| `src/OdometerStorage.qml` | La persistance est indépendante de la provenance du kilométrage. |
| `src/main.cpp` | 20 lignes, aucune logique applicative. Rien à y changer. |
| `src/VehicleModel.js` | Soit devient inutilisé si le bus publie la vitesse, soit reste tel quel pour intégrer l'odomètre. Dans les deux cas, **non modifié**. |
| `tests/tst_vehiclemodel.qml` | Teste le modèle physique pur, jamais l'IHM ni la source. |
| `tests/tst_throttlegauge.qml` | Pilote la jauge par sa propriété `value`, sans instancier de source. |
| [`DESIGN.md`](../DESIGN.md), [`CONVENTIONS.md`](../CONVENTIONS.md) | Le langage visuel et les conventions de code ne dépendent pas du bus. |

**Une exception, à signaler honnêtement** : `tests/tst_speeddial.qml` instancie
`SimulatedDataSource` pour vérifier que le plafond publié par le contrat est
bien celui du modèle physique. Ce test devrait être adapté — soit en
conservant le simulateur à seule fin de test, soit en transposant la
vérification à `CanDataSource`. C'est le seul fichier de test concerné, et il
ne s'agit pas d'un composant d'affichage.

### 6.3 Liste de contrôle — comment savoir que la substitution est réussie

- [ ] `git diff --stat` ne fait apparaître, sous `src/`, que `Main.qml` et le
      nouveau `CanDataSource.qml`. **Aucun fichier d'affichage** —
      `SpeedDial.qml`, `Odometer.qml`, `ThrottleGauge.qml`, `Theme.js` — ne
      doit apparaître dans le diff. C'est le critère principal.
- [ ] `cmake --build build --target all_qmllint` passe sans **aucun**
      avertissement, comme avant.
- [ ] `qmltestrunner -input tests` passe, à l'adaptation près de
      `tst_speeddial.qml` documentée ci-dessus.
- [ ] Le mode 1 démarre en plein écran et affiche des valeurs cohérentes bus
      branché.
- [ ] Le mode 2 (`qml src/Main.qml`) reste fonctionnel — en notant qu'il exige
      désormais un bus accessible, là où le simulateur tournait partout. Prévoir
      une source de rejeu ou un bus virtuel pour continuer à itérer hors
      véhicule.
- [ ] Débrancher le bus fait apparaître `SOURCE INVALIDE` en moins de 200 ms,
      et le rebrancher le fait disparaître.
- [ ] Le cadran ne dépasse jamais le plafond publié, et l'odomètre ne décroît
      jamais — les deux invariants déjà couverts par les tests.

---

## 7. Points à trancher avec le Groupe III

Ces questions sont ouvertes. Aucune n'a de réponse arrêtée côté frontend.

1. **Quel est le format exact de vos trames ?** Identifiants, longueurs,
   endianness, facteurs d'échelle, périodes. Tout ce qui précède est une
   proposition destinée à être remplacée par votre plan d'adressage réel. Nos
   identifiants `0x100` / `0x300` / `0x500` entrent-ils en conflit avec des
   trames existantes ?

2. **L'odomètre est-il publié sur le bus, ou faut-il l'intégrer localement à
   partir de la vitesse ?** Les deux sont réalisables côté IHM. Le publier
   garantit la cohérence avec le compteur légal du véhicule ; l'intégrer
   localement évite une trame mais produit une valeur qui dérivera de la
   vôtre. Quelle est la source de vérité ?

3. **Quel seuil de chien de garde retenez-vous ?** Notre proposition de trois
   périodes repose sur une hypothèse de taux d'erreur que nous n'avons aucun
   moyen de vérifier. Quelle gigue observez-vous en pratique sur vos trames
   périodiques ?

4. **Quel est le débit du bus, et quelle référence matérielle d'adaptateur
   est prévue ?** Le débit conditionne les périodes acceptables ; la référence
   d'adaptateur conditionne la pile logicielle côté Pi.

5. **Utilisez-vous déjà une convention de compteur de séquence ou de
   checksum applicatif ?** Si oui, nous la reprendrons plutôt que d'en
   proposer une.

6. **Que publie le VCU entre sa mise sous tension et sa première trame
   valide ?** Cela détermine ce que l'IHM doit afficher au démarrage, et
   pendant combien de temps.

---

## Références

- [`README.md`](../README.md) — contrat de données, architecture, procédure de
  lancement.
- [`CONVENTIONS.md`](../CONVENTIONS.md) — règles de contribution et périmètre
  du projet.
- [`DESIGN.md`](../DESIGN.md) — langage visuel et contraintes de rendu.
