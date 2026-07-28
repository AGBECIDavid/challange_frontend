import QtQuick
import QtQuick.Window

Window {
    id: root

    width: 1280
    height: 800
    visible: true
    color: "#12161c"
    title: qsTr("Navette 8 places — tableau de bord")

    SimulatedDataSource {
        id: source
    }

    // =====================================================================
    // HARNAIS TEMPORAIRE — A JETER A L'ETAPE 4
    //
    // Tout ce qui suit, hormis le compteur de FPS, est un echafaudage de
    // mise au point : affichage brut des sorties et pilotage clavier.
    // La commande definitive est la jauge interactive de l'etape 4, et
    // l'affichage definitif ses cadrans. Rien ici n'est destine a survivre.
    // =====================================================================

    // Pilotage clavier provisoire : fleche haut maintenue = throttleInput
    // monte vers 100, relachee = redescend vers 0.
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
        // Evite un echelon brutal qui ne dirait rien du comportement du
        // modele physique.
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

    // Affichage BRUT des quatre sorties du contrat. Aucune mise en forme :
    // on veut lire les nombres, pas les contempler.
    Column {
        anchors.centerIn: parent
        spacing: 8

        Text {
            color: "#e6edf3"
            font.family: "monospace"
            font.pixelSize: 24
            text: "speedKph        = " + source.speedKph.toFixed(3)
        }

        Text {
            color: "#e6edf3"
            font.family: "monospace"
            font.pixelSize: 24
            text: "odometerKm      = " + source.odometerKm.toFixed(6)
        }

        Text {
            color: "#e6edf3"
            font.family: "monospace"
            font.pixelSize: 24
            text: "throttlePercent = " + source.throttlePercent.toFixed(1)
        }

        Text {
            color: source.sourceValid ? "#7ee787" : "#ff7b72"
            font.family: "monospace"
            font.pixelSize: 24
            text: "sourceValid     = " + source.sourceValid
        }

        Text {
            color: "#6e7681"
            font.family: "monospace"
            font.pixelSize: 16
            text: qsTr("[harnais provisoire] fleche haut = accelerer")
        }
    }

    // Sert uniquement à mesurer la cadence de rendu pour la vidéo de démo.
    // Aucune logique applicative ne doit dépendre de cet objet.
    FrameAnimation {
        id: frameClock

        running: true
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        color: "#7ee787"
        font.pixelSize: 18
        text: frameClock.smoothFrameTime > 0
            ? Math.round(1 / frameClock.smoothFrameTime) + " FPS"
            : qsTr("— FPS")
    }
}
