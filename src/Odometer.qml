import QtQuick
import "Theme.js" as Theme

// Kilometrage cumulatif.
//
// Une seule entree, en km. Aucun lissage : l'odometre progresse lentement et
// monotonement, l'interpoler n'apporterait rien.
Row {
    id: root

    // Valeur affichee, en km.
    property real odometerKm: 0

    spacing: Theme.space12

    Text {
        anchors.baseline: unit.baseline

        // Une decimale : au-dela, les chiffres de droite defileraient en
        // permanence sans rien apprendre au conducteur.
        text: root.odometerKm.toFixed(1)
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sizeOdometer
        font.weight: Theme.weightOdometer

        // Chiffres tabulaires : la valeur change, elle ne doit pas sauter
        // lateralement.
        font.features: ({ "tnum": 1 })
    }

    Text {
        id: unit

        text: qsTr("KM")
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sizeUnit
        font.weight: Theme.weightUnit
        font.letterSpacing: Theme.sizeUnit * Theme.trackingUnit
    }
}
