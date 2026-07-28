import QtQuick
import QtQuick.Window
import "Theme.js" as Theme

Window {
    id: root

    width: 1280
    height: 800
    color: Theme.bg
    title: qsTr("Navette 8 places — tableau de bord")

    // Plein ecran par defaut.
    //
    // C'est le mode de deploiement reel : sur le Raspberry Pi il n'y a pas de
    // gestionnaire de fenetres, la fenetre doit occuper l'ecran sans
    // decoration. Le defaut correspond donc au produit, et c'est le
    // developpement qui demande une option — pas l'inverse.
    //
    //   --windowed  : demarrer en fenetre (developpement)
    //   Echap       : repasser en fenetre a chaud
    visibility: Qt.application.arguments.indexOf("--windowed") !== -1
        ? Window.Windowed
        : Window.FullScreen

    visible: true

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

    // ----------------------------------------------------------------------
    // Affichage
    // ----------------------------------------------------------------------

    SpeedDial {
        id: speedDial

        x: root.width * Theme.dialCenterXRatio - width / 2
        y: (root.height - height) / 2 - Theme.space48

        speedKph: source.speedKph

        // L'echelle vient du contrat, pas d'une constante recopiee : le
        // cadran ne peut pas diverger du plafond physique de la source.
        maxSpeedKph: source.maxSpeedKph
    }

    // Odometre sous le cadran, aligne sur son axe.
    Odometer {
        anchors.horizontalCenter: speedDial.horizontalCenter
        anchors.top: speedDial.bottom
        anchors.topMargin: Theme.space32

        odometerKm: source.odometerKm
    }

    // ----------------------------------------------------------------------
    // Commande
    // ----------------------------------------------------------------------

    ThrottleGauge {
        id: throttleGauge

        anchors.right: parent.right
        anchors.rightMargin: Theme.layoutMargin
        anchors.verticalCenter: parent.verticalCenter

        // Affiche ce que la source applique reellement, pas ce que
        // l'utilisateur demande : la jauge reflete l'etat du vehicule.
        value: source.throttlePercent

        // La jauge n'ecrit pas dans la source : elle emet, on cable ici.
        onValueRequested: (requested) => {
            keyboardControl.accelerating = false;
            source.throttleInput = requested;
        }
    }

    // Pilotage clavier — appoint. La jauge reste l'organe principal ; le
    // clavier permet de conduire d'une main pendant l'enregistrement de la
    // video de demonstration.
    Item {
        id: keyboardControl

        anchors.fill: parent
        focus: true

        property bool accelerating: false

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Up && !event.isAutoRepeat) {
                keyboardControl.accelerating = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.visibility = Window.Windowed;
                event.accepted = true;
            }
        }

        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Up && !event.isAutoRepeat) {
                keyboardControl.accelerating = false;
                event.accepted = true;
            }
        }

        // Rampe de pedale : 100 % en 400 ms, dans un sens comme dans l'autre.
        // Evite un echelon brutal, qui ne dirait rien du comportement du
        // modele physique.
        //
        // Suspendue pendant un glisser sur la jauge, pour que les deux organes
        // de commande ne se disputent pas throttleInput.
        Timer {
            interval: 50
            repeat: true
            running: keyboardControl.accelerating
                || (source.throttleInput > 0 && !throttleGauge.pressed)

            onTriggered: {
                const target = keyboardControl.accelerating ? 100 : 0;
                const stepPercent = 100 * (interval / 400);
                const delta = target - source.throttleInput;

                if (Math.abs(delta) <= stepPercent)
                    source.throttleInput = target;
                else
                    source.throttleInput += Math.sign(delta) * stepPercent;
            }
        }
    }

    // ----------------------------------------------------------------------
    // Indicateurs
    // ----------------------------------------------------------------------

    // Source defaillante. Seul usage prevu de Theme.danger : rien ne s'affiche
    // tant que tout va bien. Materialise le champ sourceValid du contrat, que
    // le watchdog CAN alimentera lors du passage aux donnees reelles.
    Text {
        anchors.horizontalCenter: speedDial.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.layoutMargin

        text: qsTr("SOURCE INVALIDE")
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sizeUnit
        font.weight: Theme.weightUnit
        font.letterSpacing: Theme.sizeUnit * Theme.trackingUnit

        opacity: source.sourceValid ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFade }
        }
    }

    // Compteur de FPS — instrument de mise au point, absent par defaut.
    //
    // Un affichage technique en surimpression n'a pas sa place sur un combine
    // de production : le produit est propre par defaut, et l'instrument reste
    // a un argument de distance pour mesurer sur la cible ou demontrer la
    // fluidite dans une video.
    //
    //   --fps  : afficher le compteur
    readonly property bool showFps:
        Qt.application.arguments.indexOf("--fps") !== -1

    FrameAnimation {
        id: frameClock

        // Ne tourne pas quand le compteur n'est pas affiche : inutile de
        // reveiller une animation par image pour une valeur que personne
        // ne lit.
        running: root.showFps
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.layoutMargin

        visible: root.showFps

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
