import QtQuick
import QtTest
import "../src/VehicleModel.js" as VehicleModel

// Teste le modele physique seul, jamais l'IHM. VehicleModel.js etant une
// `pragma library` de fonctions pures, aucun composant visuel n'est instancie.
TestCase {
    name: "VehicleModel"

    // Avance l'etat sur `seconds` secondes par pas de `dt`, a throttle constant.
    function integrate(state, throttlePercent, dt, seconds) {
        let current = { speedKph: state.speedKph, odometerKm: state.odometerKm };
        const steps = Math.round(seconds / dt);
        for (let i = 0; i < steps; ++i) {
            current = VehicleModel.step({
                speedKph: current.speedKph,
                odometerKm: current.odometerKm,
                throttlePercent: throttlePercent
            }, dt);
        }
        return current;
    }

    // Plein gaz depuis l'arret : la vitesse croit, puis sature sans jamais
    // depasser MAX_SPEED_KPH, y compris apres des milliers d'iterations.
    function test_full_throttle_saturates_below_max() {
        let state = { speedKph: 0, odometerKm: 0 };
        let previous = -1;

        for (let i = 0; i < 20000; ++i) {
            const next = VehicleModel.step({
                speedKph: state.speedKph,
                odometerKm: state.odometerKm,
                throttlePercent: 100
            }, 0.05);

            verify(next.speedKph <= VehicleModel.MAX_SPEED_KPH,
                   "iteration " + i + " : " + next.speedKph + " kph depasse le plafond");
            verify(next.speedKph >= previous,
                   "iteration " + i + " : la vitesse a decru sous plein gaz");

            previous = next.speedKph;
            state = next;
        }

        // Apres 1000 s de plein gaz, on doit etre colle au plafond.
        verify(state.speedKph > VehicleModel.MAX_SPEED_KPH - 0.01,
               "la vitesse n'a pas atteint le plafond : " + state.speedKph);
    }

    // Relachement depuis une vitesse etablie : decroissance monotone, arret
    // exact a 0, jamais de valeur negative.
    function test_coasting_stops_exactly_at_zero() {
        let state = { speedKph: 30, odometerKm: 0 };
        let previous = state.speedKph;

        for (let i = 0; i < 1000; ++i) {
            const next = VehicleModel.step({
                speedKph: state.speedKph,
                odometerKm: state.odometerKm,
                throttlePercent: 0
            }, 0.05);

            verify(next.speedKph >= 0, "vitesse negative a l'iteration " + i);
            verify(next.speedKph <= previous, "la vitesse a augmente en roue libre");

            previous = next.speedKph;
            state = next;
        }

        compare(state.speedKph, 0, "l'arret n'est pas exactement a 0");
    }

    // L'odometre ne decroit jamais, quelle que soit la sollicitation.
    function test_odometer_never_decreases() {
        let state = { speedKph: 0, odometerKm: 0 };
        let previous = 0;

        // Alterne plein gaz et roue libre pour balayer les deux regimes.
        for (let i = 0; i < 2000; ++i) {
            const throttle = (Math.floor(i / 100) % 2 === 0) ? 100 : 0;
            const next = VehicleModel.step({
                speedKph: state.speedKph,
                odometerKm: state.odometerKm,
                throttlePercent: throttle
            }, 0.05);

            verify(next.odometerKm >= previous,
                   "l'odometre a decru a l'iteration " + i);

            previous = next.odometerKm;
            state = next;
        }

        verify(state.odometerKm > 0, "l'odometre n'a pas progresse");
    }

    // Independance au pas de temps : 10 s de plein gaz simulees a dt=0.05 et
    // a dt=0.01 doivent converger.
    //
    // Tolerance de 1 % justifiee ainsi : l'integration de la vitesse est un
    // Euler explicite, dont l'erreur est en O(dt). L'ecart mesure entre les
    // deux pas est de 0.12 % sur la vitesse et 0.15 % sur l'odometre (la
    // solution analytique donne 33.0202 km/h a t=10 s). 1 % laisse donc un
    // facteur ~6 de marge, suffisant pour absorber les variations de calcul
    // flottant d'une plateforme a l'autre sans rendre le test complaisant.
    function test_timestep_independence() {
        const coarse = integrate({ speedKph: 0, odometerKm: 0 }, 100, 0.05, 10);
        const fine = integrate({ speedKph: 0, odometerKm: 0 }, 100, 0.01, 10);

        const speedError = Math.abs(coarse.speedKph - fine.speedKph) / fine.speedKph;
        const odometerError = Math.abs(coarse.odometerKm - fine.odometerKm) / fine.odometerKm;

        verify(speedError < 0.01,
               "ecart de vitesse de " + (speedError * 100).toFixed(3) + " %");
        verify(odometerError < 0.01,
               "ecart d'odometre de " + (odometerError * 100).toFixed(3) + " %");
    }

    // Purete : step() ne doit jamais modifier l'objet qu'on lui passe.
    function test_step_does_not_mutate_its_argument() {
        const state = { speedKph: 12.5, odometerKm: 3.25, throttlePercent: 60 };
        const result = VehicleModel.step(state, 0.05);

        compare(state.speedKph, 12.5, "step() a modifie speedKph");
        compare(state.odometerKm, 3.25, "step() a modifie odometerKm");
        compare(state.throttlePercent, 60, "step() a modifie throttlePercent");

        // Et le resultat est bien un nouvel objet.
        verify(result !== state, "step() a retourne son propre argument");
        verify(result.speedKph !== state.speedKph, "l'etat n'a pas avance");
    }

    // Un pas de temps nul ou negatif ne fait rien avancer.
    function test_non_positive_dt_is_a_no_op() {
        const state = { speedKph: 20, odometerKm: 5, throttlePercent: 100 };

        const zero = VehicleModel.step(state, 0);
        compare(zero.speedKph, 20);
        compare(zero.odometerKm, 5);

        const negative = VehicleModel.step(state, -1);
        compare(negative.speedKph, 20);
        compare(negative.odometerKm, 5);
    }
}
