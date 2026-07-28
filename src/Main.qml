import QtQuick
import QtQuick.Window
import "Theme.js" as Theme

Window {
    id: root

    width: 1280
    height: 800
    visible: true
    color: Theme.bg
    title: qsTr("Navette 8 places — tableau de bord")

    // Polices bundlees. Chargees ici une seule fois : FontLoader enregistre la
    // famille pour toute l'application. Les deux fichiers statiques
    // s'enregistrent sous la meme famille « Inter », differenciee par le poids.
    //
    // Le chemin relatif fonctionne dans les DEUX modes de lancement : en mode
    // compile, qt_add_qml_module conserve la hierarchie sous la racine du
    // module ; en mode qml, il est resolu sur le systeme de fichiers.
    FontLoader { source: "../assets/fonts/Inter-Light.ttf" }
    FontLoader { source: "../assets/fonts/Inter-Regular.ttf" }

    SimulatedDataSource {
        id: source
    }

    SpeedDial {
        id: speedDial

        x: root.width * Theme.dialCenterXRatio - width / 2
        y: (root.height - height) / 2

        // Le cadran ne lit que le contrat de sortie de la source.
        speedKph: source.speedKph
    }

    // =====================================================================
    // HARNAIS TEMPORAIRE — A JETER A L'ETAPE 5
    //
    // Le pilotage clavier ci-dessous est un echafaudage : l'organe de
    // commande exige par l'enonce est la jauge d'accelerateur interactive,
    // qui arrive a l'etape 5. Le clavier n'est qu'un appoint pour pouvoir
    // exercer le cadran d'ici la.
    // =====================================================================

    Item {
        id: keyboardHarness

        anchors.fill: parent
        focus: true

        property bool accelerating: false

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Up && !event.isAutoRepeat) {
                keyboardHarness.accelerating = true;
                event.accepted = true;
            }
        }

        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Up && !event.isAutoRepeat) {
                keyboardHarness.accelerating = false;
                event.accepted = true;
            }
        }

        // Rampe de pedale : 100 % en 400 ms, dans un sens comme dans l'autre.
        // Evite un echelon brutal qui ne dirait rien du comportement du modele.
        Timer {
            interval: 50
            running: true
            repeat: true

            onTriggered: {
                const target = keyboardHarness.accelerating ? 100 : 0;
                const stepPercent = 100 * (interval / 400);
                const delta = target - source.throttleInput;

                if (Math.abs(delta) <= stepPercent)
                    source.throttleInput = target;
                else
                    source.throttleInput += Math.sign(delta) * stepPercent;
            }
        }
    }

    // Rappel discret que la commande clavier est provisoire.
    Text {
        anchors.horizontalCenter: speedDial.horizontalCenter
        anchors.top: speedDial.bottom
        anchors.topMargin: Theme.space48

        text: qsTr("commande clavier provisoire — flèche haut pour accélérer")
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sizeLabel
        font.weight: Theme.weightLabel
    }

    // Sert uniquement a demontrer la fluidite dans la video de demo.
    // Aucune logique applicative ne doit dependre de cet objet.
    FrameAnimation {
        id: frameClock

        running: true
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.layoutMargin

        text: frameClock.smoothFrameTime > 0
            ? Math.round(1 / frameClock.smoothFrameTime) + qsTr(" FPS")
            : qsTr("— FPS")
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sizeLabel
        font.weight: Theme.weightLabel
        font.features: ({ "tnum": 1 })
    }
}
