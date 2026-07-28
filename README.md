# navette-dashboard

Tableau de bord de navette électrique 8 places, en Qt 6 / QML.

## Contexte et périmètre

Interface de conduite pour une navette électrique 8 places, destinée à un
Raspberry Pi 4 équipé d'un écran 10 pouces en 1280x800. Le projet couvre le
frontend seul : aucun backend, aucune lecture matérielle, aucun code CAN.

## Prérequis

Qt 6.8.3 LTS pour le développement, Qt 6.5 minimum à l'exécution ; CMake 3.21+
et Ninja pour la compilation.

## Lancement

Deux modes sont supportés en permanence : un build CMake pour la production et
le runtime `qml` pour l'itération rapide.

## Architecture

Découpage entre la couche de données simulées et la couche d'affichage, cette
dernière ne faisant que lire et lisser des propriétés.

## Structure des données simulées

> **À REMPLIR à l'étape 3.** Section explicitement exigée par l'énoncé du
> challenge : elle devra décrire chaque grandeur publiée, son unité, sa plage
> de valeurs et sa cadence de rafraîchissement.

## Modèle physique

Description à venir des équations de simulation de la navette (vitesse,
consommation, état de charge).

## Passage aux données CAN réelles

Description à venir du point de substitution permettant de remplacer la source
simulée par de vraies trames, sans modifier l'affichage.

## Tests

Tests QML exécutés par `qmltestrunner`, complétés par le lint `qmllint` qui
doit passer sans aucun avertissement.

## Limites connues

À compléter au fil du développement.
