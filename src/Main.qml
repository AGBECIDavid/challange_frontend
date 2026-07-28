import QtQuick
import QtQuick.Window

Window {
    id: root

    width: 1280
    height: 800
    visible: true
    color: "#12161c"
    title: qsTr("Navette 8 places — tableau de bord")

    // Sert uniquement à mesurer la cadence de rendu pour la vidéo de démo.
    // Aucune logique applicative ne doit dépendre de cet objet.
    FrameAnimation {
        id: frameClock

        running: true
    }

    Text {
        anchors.centerIn: parent
        text: qsTr("squelette OK")
        color: "#e6edf3"
        font.pixelSize: 32
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
