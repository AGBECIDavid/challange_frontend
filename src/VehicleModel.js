.pragma library

// Modele physique de la navette : fonctions pures, sans etat ni effet de bord.
//
// Note sur la directive ci-dessus : le point initial est requis dans une
// ressource .js, et elle doit etre la toute PREMIERE chose du fichier — pas
// meme un commentaire avant elle, sinon la detection de qt_add_qml_module
// echoue et CMake avertit que le fichier sera re-evalue dans le contexte de
// chaque document QML importateur.
//
// Ce fichier est donc partage entre tous ses importateurs et n'a aucun acces
// au contexte QML. C'est precisement ce qui le rend testable isolement par
// tests/tst_vehiclemodel.qml, sans instancier d'IHM.

// Vitesse maximale, en km/h.
// Navette urbaine a carrosserie ouverte : la vitesse est bridee bien en
// dessous d'un vehicule routier, les passagers pouvant voyager debout.
var MAX_SPEED_KPH = 50;

// Acceleration de consigne a l'arret, en m/s^2.
// Vehicule 8 places charge, annonce a environ 0-50 km/h en 12 s, soit une
// moyenne de (50 / 3.6) / 12 ~= 1.16 m/s^2. Comme l'acceleration decroit avec
// la vitesse (voir step), la consigne a vitesse nulle doit etre superieure a
// cette moyenne : 1.5 m/s^2 restitue les 12 s a l'arrivee.
var MAX_ACCEL_MS2 = 1.5;

// Deceleration en roue libre, en m/s^2.
// Somme de la resistance au roulement et de la trainee aerodynamique. La
// chaine de traction electrique est supposee en roue libre des que la pedale
// est relachee : pas de frein moteur, pas de recuperation.
// Le freinage actif (brakePercent) releve du Groupe III et n'est PAS
// implemente ici — voir le champ reserve documente dans le README.
var COAST_DECEL_MS2 = 0.4;

// Facteurs de conversion. Le modele travaille en m/s en interne et n'expose
// que des km/h, pour que les constantes physiques restent lisibles en SI.
var _MS_PER_KPH = 1 / 3.6;
var _KPH_PER_MS = 3.6;

function _clamp(value, low, high) {
    if (value < low)
        return low;
    if (value > high)
        return high;
    return value;
}

// Avance l'etat du vehicule d'un pas de temps.
//
//   state : { speedKph, odometerKm, throttlePercent }
//   dt    : duree du pas, en secondes
//   -> retourne un NOUVEL objet { speedKph, odometerKm }
//
// Choix documente : throttlePercent est un CHAMP DE STATE et non un troisieme
// parametre. Cela garde la signature step(state, dt) — celle d'un integrateur
// generique — et regroupe en un seul objet tout ce qui decrit l'instant
// courant. La valeur de retour n'expose que les grandeurs integrees : le
// throttle est une entree, pas un resultat.
//
// La fonction est PURE : elle ne modifie jamais `state`.
function step(state, dt) {
    var speedKph = state.speedKph || 0;
    var odometerKm = state.odometerKm || 0;

    // Un pas nul ou negatif ne fait rien avancer. Garde-fou contre un timer
    // qui aurait derive ou une valeur aberrante.
    if (!(dt > 0))
        return { speedKph: speedKph, odometerKm: odometerKm };

    var throttle = _clamp(state.throttlePercent || 0, 0, 100);

    var vMax = MAX_SPEED_KPH * _MS_PER_KPH;
    var v = _clamp(speedKph * _MS_PER_KPH, 0, vMax);

    var a;
    if (throttle > 0) {
        // Approche asymptotique : l'acceleration disponible decroit
        // lineairement jusqu'a s'annuler a vMax. La vitesse tend vers son
        // plafond au lieu d'y buter brutalement, ce qui donne un
        // comportement de fin de course realiste sur un cadran.
        a = (throttle / 100) * MAX_ACCEL_MS2 * (1 - v / vMax);
    } else {
        // Roue libre : deceleration constante jusqu'a l'arret.
        a = -COAST_DECEL_MS2;
    }

    // La vitesse ne devient jamais negative et ne depasse jamais vMax.
    var vNext = _clamp(v + a * dt, 0, vMax);

    // Distance parcourue sur le pas, par integration trapezoidale : plus
    // precise que v * dt ou vNext * dt, et exacte lorsque l'acceleration est
    // constante — ce qui est le cas en roue libre.
    var distanceM = 0.5 * (v + vNext) * dt;

    return {
        speedKph: vNext * _KPH_PER_MS,
        // v et vNext sont positifs ou nuls, donc distanceM l'est aussi :
        // l'odometre est monotone croissant par construction.
        odometerKm: odometerKm + distanceM / 1000
    };
}
