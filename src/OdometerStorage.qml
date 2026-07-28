import QtCore

// Persistance isolee de l'odometre.
//
// Ce composant n'est JAMAIS instancie directement : SimulatedDataSource le
// charge via un Loader. C'est deliberé — si l'import QtCore echoue (Qt < 6.5,
// ou module QtCore absent du deploiement sur la cible), le Loader passe en
// status Error, son `item` reste null, et l'odometre repart simplement de 0
// au lieu de faire echouer le chargement de toute l'application.
//
// `Settings` vient de QtCore depuis Qt 6.5. L'ancien module Qt.labs.settings
// est deprecie et ne doit pas etre utilise.
Settings {
    // Regroupe la cle sous une section dediee du fichier de configuration,
    // pour ne pas polluer la racine quand d'autres reglages s'ajouteront.
    category: "odometer"

    // Kilometrage total, en km. Monotone croissant.
    property real odometerKm: 0
}
