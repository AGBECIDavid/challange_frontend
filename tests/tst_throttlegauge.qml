import QtQuick
import QtTest
import "../src" as Dashboard
import "../src/Theme.js" as Theme

// Verifie que la jauge suit sa propriete `value`, quelle que soit l'origine
// de la commande. C'est le chemin qui va de la source jusqu'au remplissage
// affiche : une rupture de liaison ou un lissage bloque le ferait echouer.
TestCase {
    id: testCase

    name: "ThrottleGauge"
    when: windowShown
    visible: true
    width: 200
    height: Theme.gaugeHeight + 80

    Dashboard.ThrottleGauge {
        id: gauge
    }

    // Le lissage dure durThrottle ; on laisse une marge confortable.
    readonly property int settleMs: Theme.durThrottle * 10

    function attendre(fraction) {
        tryVerify(function () {
            return Math.abs(gauge._smoothedFraction - fraction) < 0.01;
        }, testCase.settleMs,
        "_smoothedFraction=" + gauge._smoothedFraction.toFixed(3)
            + " n'a pas rejoint " + fraction);
    }

    function init() {
        gauge.value = 0;
        attendre(0);
    }

    // Le cas nominal : la jauge doit suivre chaque variation de value.
    function test_suit_sa_valeur_data() {
        return [
            { tag: "25 %", value: 25, fraction: 0.25 },
            { tag: "50 %", value: 50, fraction: 0.5 },
            { tag: "75 %", value: 75, fraction: 0.75 },
            { tag: "100 %", value: 100, fraction: 1 }
        ];
    }

    function test_suit_sa_valeur(data) {
        gauge.value = data.value;
        compare(gauge._fraction, data.fraction, "fraction immediate incorrecte");
        attendre(data.fraction);
    }

    // Une montee puis une descente, sans repasser par init entre les deux :
    // c'est la sequence reelle d'un appui suivi d'un relachement.
    function test_montee_puis_retour_a_zero() {
        gauge.value = 80;
        attendre(0.8);

        gauge.value = 0;
        attendre(0);
    }

    // Plusieurs variations rapprochees, comme pendant un glisser : chaque
    // nouvelle valeur doit reprendre la main sur l'animation en cours.
    function test_variations_rapprochees() {
        const etapes = [30, 60, 40, 90, 10];
        for (const v of etapes) {
            gauge.value = v;
            wait(Theme.durThrottle / 4);
        }
        attendre(0.1);
    }

    // La jauge borne son entree : on ne fait pas confiance a l'appelant.
    function test_valeurs_hors_bornes() {
        gauge.value = 150;
        compare(gauge._fraction, 1, "au-dela de 100 % doit etre borne a 1");
        attendre(1);

        gauge.value = -20;
        compare(gauge._fraction, 0, "en dessous de 0 % doit etre borne a 0");
        attendre(0);
    }
}
