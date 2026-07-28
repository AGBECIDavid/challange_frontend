import QtQuick
import "VehicleModel.js" as VehicleModel

// Source de donnees simulee.
//
// QtObject et non Item : cette source n'a aucune existence visuelle. Elle
// publie le contrat de donnees et rien d'autre.
//
// Le contrat se lit en deux parties, et c'est le point central de la
// conception :
//
//   * les SORTIES (speedKph, odometerKm, throttlePercent, sourceValid) sont
//     communes a toute source. Ce sont les seules proprietes que l'affichage
//     a le droit de lire.
//   * l'ENTREE DE SIMULATION (throttleInput) n'existe QUE dans cette source.
//     Sur vehicule reel, la position de pedale provient du VCU via le bus
//     CAN : l'IHM ne la produit pas, elle la subit. throttleInput est donc le
//     point d'injection propre au simulateur, et il disparait au passage au
//     CAN sans que l'affichage ait a changer d'une ligne.
QtObject {
    id: root

    // ----------------------------------------------------------------------
    // ENTREE DE SIMULATION — absente de toute source reelle
    // ----------------------------------------------------------------------

    // Position de pedale demandee, en %. Ecrite par l'IHM.
    // Bornee a [0, 100] a la lecture via throttlePercent : on ne fait pas
    // confiance a l'appelant.
    property real throttleInput: 0

    // ----------------------------------------------------------------------
    // SORTIES — contrat commun a toute source
    // ----------------------------------------------------------------------

    // Vitesse instantanee, en km/h, dans [0, MAX_SPEED_KPH].
    readonly property real speedKph: _private.speedKph

    // Kilometrage total, en km, monotone croissant.
    readonly property real odometerKm: _private.odometerKm

    // Position de pedale effective, en %, dans [0, 100].
    readonly property real throttlePercent: Math.max(0, Math.min(100, throttleInput))

    // false des que la source cesse de publier des donnees exploitables.
    // La detection de panne elle-meme (watchdog sur l'age de la derniere
    // trame, compteur de sequence, CRC...) n'est PAS implementee a ce stade :
    // _private.faulted est le point d'accroche prevu pour elle, de sorte que
    // l'ajouter plus tard ne touchera ni cette propriete ni l'affichage.
    readonly property bool sourceValid: _tick.running && !_private.faulted

    // ----------------------------------------------------------------------
    // Interne
    // ----------------------------------------------------------------------

    // Etat mutable, encapsule pour que les sorties restent readonly.
    //
    // Declare comme composant en ligne plutot que comme QtObject anonyme :
    // un `property QtObject` masquerait les membres aux yeux de qmllint, qui
    // signalerait alors « Member not found on type QObject » a chaque acces.
    // Le composant en ligne leur donne un type nomme et verifiable.
    component PrivateState: QtObject {
        property real speedKph: 0
        property real odometerKm: 0

        // Point d'accroche prevu pour la future detection de panne.
        property bool faulted: false
    }

    readonly property PrivateState _private: PrivateState {}

    // Cadence de publication : 50 ms, soit 20 Hz.
    //
    // Ce choix n'est pas esthetique, il est structurel. Une trame CAN
    // periodique de vitesse tourne typiquement entre 10 et 100 Hz ; 20 Hz est
    // une valeur realiste pour ce type de vehicule. En publiant deja a cette
    // cadence, on garantit que l'affichage est concu pour une source lente et
    // discrete, pas pour une animation continue : c'est Behavior, cote
    // affichage, qui lisse entre deux trames. Le rendu tourne ainsi a 60 Hz
    // avec une source a 20 Hz, ce qui prouve que le rendu ne depend pas de la
    // cadence de la source.
    readonly property Timer _tick: Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: root._advance(interval / 1000)
    }

    // Ecriture de l'odometre sur disque, volontairement decorrelee de la
    // simulation : 0.2 Hz au lieu de 20 Hz. Ecrire a chaque pas userait
    // inutilement la carte SD du Raspberry Pi. Le compromis est qu'une
    // coupure brutale peut perdre jusqu'a 5 s de trajet, ce qui est sans
    // consequence sur un odometre.
    readonly property Timer _persistTick: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root._persistOdometer()
    }

    // Chargement de la persistance via Loader : son echec degrade l'odometre
    // a 0 au lieu de faire echouer l'application. Voir OdometerStorage.qml.
    readonly property Loader _storage: Loader {
        source: "OdometerStorage.qml"
    }

    function _advance(dt: real) {
        const next = VehicleModel.step({
            speedKph: _private.speedKph,
            odometerKm: _private.odometerKm,
            throttlePercent: root.throttlePercent
        }, dt);

        _private.speedKph = next.speedKph;
        _private.odometerKm = next.odometerKm;
    }

    // Note sur les deux `qmllint disable` ci-dessous.
    //
    // Loader.item est type QObject : qmllint ne peut pas savoir qu'il s'agit
    // d'un OdometerStorage, et c'est VOULU. Nommer le type ici pour satisfaire
    // le linter recreerait une dependance de compilation vers OdometerStorage,
    // donc vers QtCore — exactement ce que le Loader sert a eviter. Si QtCore
    // manquait, la resolution du type ferait echouer la compilation de ce
    // fichier, et le repli a 0 ne fonctionnerait plus.
    // L'acces est protege a l'execution par le test status/item qui precede.

    function _persistOdometer() {
        if (_storage.status === Loader.Ready && _storage.item) {
            // qmllint disable missing-property
            _storage.item.odometerKm = _private.odometerKm;
            // qmllint enable missing-property
        }
    }

    // Reprise du kilometrage persiste. Si le Loader a echoue, on part de 0.
    Component.onCompleted: {
        if (_storage.status === Loader.Ready && _storage.item) {
            // qmllint disable missing-property
            _private.odometerKm = _storage.item.odometerKm;
            // qmllint enable missing-property
        }
    }

    // Derniere ecriture avant extinction, pour ne pas perdre le dernier
    // intervalle de persistance.
    Component.onDestruction: root._persistOdometer()
}
