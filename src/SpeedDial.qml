// Autorise les delegues de Repeater a referencer l'id du composant englobant
// (root). Sans cette directive, chaque acces depuis un delegue est signale
// « Unqualified access » par qmllint.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "Theme.js" as Theme

// Cadran de vitesse.
//
// Le composant ne connait NI la source de donnees, NI VehicleModel.js, NI
// aucune constante physique. Il expose une entree — la vitesse en km/h — et un
// plafond avec une valeur par defaut. C'est l'appelant qui cable les deux.
//
// Pas d'aiguille : l'arc EST l'indicateur (skill §6).
Item {
    id: root

    // ----------------------------------------------------------------------
    // Interface
    // ----------------------------------------------------------------------

    // Seule entree du composant. En km/h.
    property real speedKph: 0

    // Plafond du cadran. Propriete du composant avec valeur par defaut, et
    // surtout PAS un import de VehicleModel.js : un composant d'affichage n'a
    // pas a connaitre la physique du vehicule (skill §8.3).
    property real maxSpeedKph: 50

    implicitWidth: Theme.dialDiameter
    implicitHeight: Theme.dialDiameter

    // ----------------------------------------------------------------------
    // Lissage — point critique (skill §4)
    // ----------------------------------------------------------------------

    // UNE SEULE propriete lissee, dont derivent A LA FOIS l'angle de l'arc et
    // le chiffre central. Les lisser separement les desynchroniserait de
    // maniere visible : le chiffre annoncerait une vitesse que l'arc n'aurait
    // pas encore atteinte.
    //
    // L'affichage ne calcule aucune physique : il lit une propriete et
    // l'interpole entre deux echantillons de la source (20 Hz) pour alimenter
    // un rendu a 60 Hz.
    property real smoothedSpeedKph: speedKph

    Behavior on smoothedSpeedKph {
        NumberAnimation {
            duration: Theme.durSpeed
            // Lineaire imperativement. Un easing non lineaire ferait
            // « respirer » le cadran au rythme du timer de la source : c'est
            // l'artefact le plus courant sur ce type d'interface.
            easing.type: Easing.Linear
        }
    }

    // ----------------------------------------------------------------------
    // Geometrie
    // ----------------------------------------------------------------------

    readonly property real _cx: width / 2
    readonly property real _cy: height / 2

    // Rayon de l'axe des arcs : on retranche la demi-epaisseur du plus epais
    // pour que le trait reste entierement dans le composant.
    readonly property real _arcRadius:
        Math.min(width, height) / 2 - Theme.dialActiveWidth / 2

    // Les graduations vivent a l'interieur des arcs.
    readonly property real _tickRadius:
        _arcRadius - Theme.dialActiveWidth / 2 - Theme.space12

    // Les valeurs chiffrees a l'interieur des graduations.
    readonly property real _labelRadius:
        _tickRadius - Theme.dialMajorTickLength - Theme.space24

    // Fraction du balayage occupee par la vitesse courante, dans [0, 1].
    readonly property real _fraction: maxSpeedKph > 0
        ? Math.max(0, Math.min(1, smoothedSpeedKph / maxSpeedKph))
        : 0

    // Nombre de graduations, bornes incluses.
    readonly property int _tickCount:
        Math.floor(maxSpeedKph / Theme.dialMinorTickStep) + 1

    // Angle d'arc (convention PathAngleArc : 0° a 3 h, positif horaire)
    // correspondant a une fraction du balayage.
    function _angleAt(fraction: real): real {
        return Theme.dialStartAngle + Theme.dialSweepAngle * fraction;
    }

    // ----------------------------------------------------------------------
    // Arcs
    // ----------------------------------------------------------------------

    Shape {
        anchors.fill: parent

        // Antialiasing calcule par le GPU. Sans lui, les arcs sont creneles.
        preferredRendererType: Shape.CurveRenderer

        // Piste complete, inactive. Extremites carrees.
        ShapePath {
            strokeColor: Theme.track
            strokeWidth: Theme.dialTrackWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root._cx
                centerY: root._cy
                radiusX: root._arcRadius
                radiusY: root._arcRadius
                startAngle: Theme.dialStartAngle
                sweepAngle: Theme.dialSweepAngle
            }
        }

        // Arc actif. Seul sweepAngle est anime — jamais width/height, qui
        // forceraient la retessellation du chemin a chaque image.
        //
        // A sweepAngle nul, RoundCap ne laisse AUCUN point visible a l'origine
        // du cadran : verifie par comparaison de rendus offscreen, identiques
        // au pixel pres avec et sans masquage. Aucun seuil n'est donc
        // necessaire ici.
        ShapePath {
            strokeColor: Theme.accent
            strokeWidth: Theme.dialActiveWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root._cx
                centerY: root._cy
                radiusX: root._arcRadius
                radiusY: root._arcRadius
                startAngle: Theme.dialStartAngle
                sweepAngle: Theme.dialSweepAngle * root._fraction
            }
        }
    }

    // ----------------------------------------------------------------------
    // Graduations — Repeater de Rectangle avec transform Rotation.
    // Plus economique et plus net qu'un Shape contenant un chemin par trait
    // (skill §5).
    // ----------------------------------------------------------------------

    Repeater {
        model: root._tickCount

        delegate: Rectangle {
            id: tick

            required property int index

            readonly property real value: index * Theme.dialMinorTickStep
            readonly property bool major: (value % Theme.dialMajorTickStep) === 0

            width: major ? Theme.dialMajorTickWidth : Theme.dialMinorTickWidth
            height: major ? Theme.dialMajorTickLength : Theme.dialMinorTickLength

            // Les graduations portent une information : elles ne peuvent pas
            // utiliser track, invisible en plein soleil. Les majeures prennent
            // la couleur de leurs propres libelles chiffres.
            color: major ? Theme.textSecondary : Theme.tickMinor
            antialiasing: true

            // Positionne au sommet du cadran, puis pivote autour du centre.
            x: root._cx - width / 2
            y: root._cy - root._tickRadius

            transform: Rotation {
                origin.x: tick.width / 2
                origin.y: root._tickRadius
                // Le sommet du cadran correspond a l'angle d'arc 270°.
                angle: root._angleAt(tick.value / root.maxSpeedKph) - 270
            }
        }
    }

    // Valeurs chiffrees, une par graduation majeure. Non pivotees : le texte
    // reste horizontal, comme sur un combine automobile.
    Repeater {
        model: root._tickCount

        delegate: Text {
            id: tickLabel

            required property int index

            readonly property real value: index * Theme.dialMinorTickStep
            readonly property real angleRad:
                root._angleAt(value / root.maxSpeedKph) * Math.PI / 180

            visible: (value % Theme.dialMajorTickStep) === 0

            text: Math.round(value)
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sizeLabel
            font.weight: Theme.weightLabel

            x: root._cx + root._labelRadius * Math.cos(angleRad) - width / 2
            y: root._cy + root._labelRadius * Math.sin(angleRad) - height / 2
        }
    }

    // ----------------------------------------------------------------------
    // Chiffre central et unite
    // ----------------------------------------------------------------------

    Column {
        anchors.centerIn: parent
        spacing: Theme.space8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            // Arrondi a l'entier : un dixieme de km/h qui clignote est un
            // defaut, pas une precision.
            text: Math.round(root.smoothedSpeedKph)
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sizeSpeed
            font.weight: Theme.weightSpeed

            // Chiffres tabulaires : sans cela la largeur des chiffres varie et
            // le nombre « saute » lateralement a chaque rafraichissement.
            font.features: ({ "tnum": 1 })
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: qsTr("KM/H")
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sizeUnit
            font.weight: Theme.weightUnit
            font.letterSpacing: Theme.sizeUnit * Theme.trackingUnit
        }
    }
}
