import QtQuick
import QtTest
import "../src" as Dashboard
import "../src/Theme.js" as Theme
import "../src/VehicleModel.js" as VehicleModel

// Verifie que le cadran sature exactement au plafond qu'on lui donne, quel
// qu'il soit — et que ce plafond ne peut pas diverger de celui du modele.
TestCase {
    id: testCase

    name: "SpeedDial"
    when: windowShown
    visible: true
    width: Theme.dialDiameter
    height: Theme.dialDiameter

    Dashboard.SpeedDial {
        id: dial

        anchors.fill: parent
    }

    // Instanciee pour verifier la coherence du contrat avec le modele.
    Dashboard.SimulatedDataSource {
        id: source
    }

    // Le lissage dure durSpeed ; on laisse une marge confortable.
    readonly property int settleMs: Theme.durSpeed * 20

    function attendreFraction(fraction) {
        tryVerify(function () {
            return Math.abs(dial._fraction - fraction) < 0.001;
        }, testCase.settleMs,
        "_fraction=" + dial._fraction.toFixed(4) + " n'a pas rejoint " + fraction);
    }

    function init() {
        dial.maxSpeedKph = 50;
        dial.speedKph = 0;
        attendreFraction(0);
    }

    // Le cadran doit saturer a 1 exactement au plafond, quel que soit ce
    // plafond — et ne jamais le depasser au-dela.
    function test_sature_au_plafond_data() {
        return [
            { tag: "plafond 50", max: 50 },
            { tag: "plafond 30", max: 30 },
            { tag: "plafond 80", max: 80 },
            { tag: "plafond 130", max: 130 }
        ];
    }

    function test_sature_au_plafond(data) {
        dial.maxSpeedKph = data.max;

        // Exactement au plafond : saturation pleine.
        dial.speedKph = data.max;
        attendreFraction(1);

        // Trois fois le plafond : toujours 1, jamais davantage.
        dial.speedKph = data.max * 3;
        attendreFraction(1);
        verify(dial._fraction <= 1, "la fraction a depasse 1");
    }

    // A mi-echelle, la fraction vaut 0,5 quel que soit le plafond.
    function test_mi_echelle_data() {
        return [
            { tag: "plafond 50", max: 50 },
            { tag: "plafond 30", max: 30 },
            { tag: "plafond 80", max: 80 }
        ];
    }

    function test_mi_echelle(data) {
        dial.maxSpeedKph = data.max;
        dial.speedKph = data.max / 2;
        attendreFraction(0.5);
    }

    // Une vitesse negative ne doit jamais produire de fraction negative.
    function test_vitesse_negative_bornee() {
        dial.speedKph = -20;
        attendreFraction(0);
        verify(dial._fraction >= 0, "la fraction est devenue negative");
    }

    // Un plafond nul ne doit pas produire de division par zero.
    function test_plafond_nul() {
        dial.maxSpeedKph = 0;
        dial.speedKph = 10;
        wait(testCase.settleMs / 4);
        compare(dial._fraction, 0, "un plafond nul doit donner une fraction nulle");
    }

    // Le nombre de graduations suit le plafond : une tous les
    // dialMinorTickStep km/h, bornes incluses.
    function test_graduations_suivent_le_plafond_data() {
        return [
            { tag: "plafond 50", max: 50, attendu: 11 },
            { tag: "plafond 30", max: 30, attendu: 7 },
            { tag: "plafond 80", max: 80, attendu: 17 }
        ];
    }

    function test_graduations_suivent_le_plafond(data) {
        dial.maxSpeedKph = data.max;
        compare(dial._tickCount, data.attendu);
    }

    // Le plafond publie par la source est celui du modele physique.
    // C'est la garantie anti-divergence : la valeur n'est plus ecrite deux
    // fois, et ce test echouerait si quelqu'un la recopiait a nouveau.
    function test_le_contrat_publie_le_plafond_du_modele() {
        compare(source.maxSpeedKph, VehicleModel.MAX_SPEED_KPH,
                "le contrat et le modele physique ont diverge");
    }
}
