import QtQuick
import QtTest

TestCase {
    name: "Placeholder"

    // Valide uniquement que qmltestrunner s'exécute.
    // La vraie suite arrivera avec le modèle physique.
    function test_trivial() {
        compare(1 + 1, 2);
    }
}
