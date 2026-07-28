# navette-dashboard — instructions projet

## Contexte

Tableau de bord de navette électrique 8 places, écrit en Qt 6 / QML.

| | |
|---|---|
| Cible | Raspberry Pi 4, Linux, écran 10 pouces, 1280x800 |
| Qt de développement | 6.8.3 LTS (aligné sur Raspberry Pi OS Trixie, qui livre Qt 6.8.2) |
| Version minimale supportée | **Qt 6.7** — maximum de deux contraintes : `Settings` dans le module `QtCore` (6.5) et `font.features` pour les chiffres tabulaires (6.7) |

## Périmètre

**Frontend seul.** Le projet se limite à l'affichage et à la simulation des
données qui l'alimentent.

Sont hors périmètre, sans exception :

- tout backend, tout service, tout démon ;
- toute lecture matérielle ;
- tout code CAN / SocketCAN ;
- toute pile HTTP ou réseau.

## Règles Git

Ces commandes ne doivent **jamais** être exécutées par un agent :

- `git push`
- `git merge`
- `git rebase`
- toute réécriture d'historique (`git commit --amend`, `git reset --hard`,
  `git filter-branch`, `git push --force`, …)

Git est géré manuellement par le propriétaire du dépôt. Un agent peut créer et
modifier des fichiers, puis signaler que les modifications sont prêtes à être
commitées — il ne commite pas de lui-même.

## Conventions de code

### Répartition C++ / QML

Toute la logique vit en **QML/JS**. Le C++ se limite strictement à
`src/main.cpp`, qui ne fait qu'instancier le moteur et charger le module.
Aucun type C++ exposé à QML, aucun modèle C++.

### Disposition des fichiers

`src/` reste **plat** : pas de sous-dossiers, pas de singleton QML.

Raison : les fichiers `.qml` frères se résolvent sans `import`, ce qui permet
de lancer le projet des deux façons (voir « Modes de lancement »). Un
sous-dossier ou un singleton casserait le mode `qml src/Main.qml`, qui ne
dispose pas des métadonnées du module CMake.

Ne pas réorganiser cette structure sans validation explicite.

### Qualité

`qmllint` doit passer **sans aucun avertissement**. Pas de seuil toléré, pas
d'exception : zéro.

### Interdits pour la cible embarquée

Le Raspberry Pi 4 rend via GPU avec une bande passante mémoire limitée. Sont
proscrits :

- `Canvas` — rendu logiciel, coûteux ; utiliser **`QtQuick.Shapes`** ;
- `Qt5Compat.GraphicalEffects` — non garanti sur la cible, coûteux ;
- `layer.enabled` superflu — chaque couche force une passe de rendu hors
  écran supplémentaire.

### Séparation affichage / calcul

**L'affichage ne calcule jamais de physique.** Un composant visuel se contente
de lire des propriétés et de les lisser via `Behavior`. Toute intégration,
tout filtrage, toute dérivation appartient à la couche de données.

### Cadence des données

La source de données publie à **20 Hz**, comme une trame CAN périodique. Cette
cadence est un choix d'architecture : elle prépare le remplacement ultérieur de
la simulation par de vraies trames, sans toucher à l'affichage.

## Modes de lancement

Les deux doivent fonctionner en permanence.

1. **Build CMake** — le mode de production :

   ```sh
   cmake -S . -B build -G Ninja
   cmake --build build
   ./build/dashboard
   ```

2. **Runtime QML** — itération rapide, sans compilation :

   ```sh
   qml src/Main.qml
   ```

Toute modification qui casse l'un des deux modes est à rejeter.

## Ne pas faire

- Pas de code CAN / SocketCAN.
- Pas de HTTP, pas de réseau, pas de socket.
- Pas de lecture matérielle (GPIO, I2C, SPI, `/sys`, `/dev`).
- Pas de `git push` / `merge` / `rebase` ni de réécriture d'historique.
- Pas de sous-dossiers dans `src/`, pas de singleton QML.
- Pas de `Canvas`, pas de `Qt5Compat.GraphicalEffects`.
- Pas de calcul physique dans les composants d'affichage.
