import QtQuick
import "Theme.js" as Theme

// Jauge d'accelerateur — l'organe de commande du tableau de bord.
//
// Contrairement au cadran, ce composant est BIDIRECTIONNEL :
//   * en entree, `value` : la position de pedale effectivement appliquee,
//     telle que la source la publie ;
//   * en sortie, le signal `valueRequested` : ce que l'utilisateur demande.
//
// Il n'ecrit JAMAIS dans la source. Il emet, et c'est l'appelant qui cable.
// Un composant d'affichage ne connait pas sa source.
//
// Pas de Shape ici : un Rectangle suffit et coute moins cher au GPU.
Item {
    id: root

    // ----------------------------------------------------------------------
    // Interface
    // ----------------------------------------------------------------------

    // Position affichee, en %. Vient de la source, pas de l'interaction.
    property real value: 0

    // Emis quand l'utilisateur agit. L'appelant decide quoi en faire.
    signal valueRequested(requested: real)

    // Vrai tant que l'utilisateur agit sur la jauge. Permet a l'appelant
    // d'arbitrer entre plusieurs organes de commande — ici, de suspendre le
    // pilotage clavier pendant un glisser. Lecture seule : ce n'est pas une
    // commande, c'est un etat.
    readonly property alias pressed: dragArea.pressed

    // La zone de saisie est plus large que la barre : le doigt d'un
    // conducteur n'est pas une souris.
    implicitWidth: Theme.gaugeTouchWidth
    implicitHeight: Theme.gaugeHeight + Theme.space16 + Theme.sizeLabel

    // ----------------------------------------------------------------------
    // Interne
    // ----------------------------------------------------------------------

    // Fraction remplie, bornee. Lissee pour absorber la cadence de la source,
    // comme la vitesse sur le cadran.
    readonly property real _fraction: Math.max(0, Math.min(1, value / 100))

    property real _smoothedFraction: _fraction

    Behavior on _smoothedFraction {
        NumberAnimation {
            duration: Theme.durThrottle
            easing.type: Easing.Linear
        }
    }

    // Convertit une ordonnee dans la barre en pourcentage : origine en bas.
    function _percentAt(y: real): real {
        const clamped = Math.max(0, Math.min(Theme.gaugeHeight, y));
        return (1 - clamped / Theme.gaugeHeight) * 100;
    }

    // ----------------------------------------------------------------------
    // Barre
    // ----------------------------------------------------------------------

    Item {
        id: bar

        width: Theme.gaugeBarWidth
        height: Theme.gaugeHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        // Piste inactive. track est ici a sa place : ce n'est pas une
        // information, c'est la course disponible.
        Rectangle {
            anchors.fill: parent
            color: Theme.track
        }

        // Remplissage par le bas.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * root._smoothedFraction
            color: Theme.accent
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: bar.bottom
        anchors.topMargin: Theme.space16

        text: qsTr("ACCÉLÉRATEUR")
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sizeLabel
        font.weight: Theme.weightLabel
        font.letterSpacing: Theme.sizeLabel * Theme.trackingUnit
    }

    // ----------------------------------------------------------------------
    // Interaction
    //
    // MouseArea couvre la souris ET le tactile : Qt synthetise les evenements
    // souris a partir des evenements tactiles. La zone deborde la barre en
    // largeur pour rester atteignable au doigt.
    // ----------------------------------------------------------------------

    MouseArea {
        id: dragArea

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.gaugeHeight

        // L'appui ouvre la commande, le glisser la suit. Un appui relache
        // aussitot ne produit qu'une impulsion : c'est voulu, la pedale ne
        // reste pas enfoncee toute seule.
        onPressed: (mouse) => root.valueRequested(root._percentAt(mouse.y))
        onPositionChanged: (mouse) => {
            if (pressed)
                root.valueRequested(root._percentAt(mouse.y));
        }

        // Le relachement ramene a zero, comme une vraie pedale : c'est le
        // comportement « deceleration au relachement » attendu du vehicule.
        onReleased: root.valueRequested(0)
        onCanceled: root.valueRequested(0)
    }
}
