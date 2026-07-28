cmake_minimum_required(VERSION 3.21)
project(navette-dashboard VERSION 0.1 LANGUAGES CXX)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick)
qt_standard_project_setup(REQUIRES 6.5)

# Main.qml vit dans src/, pas a la racine du module.
# NEW genere un qmldir secondaire dans src/ ; le qmldir racine declare
# toujours "Main 1.0 src/Main.qml", donc loadFromModule("Dashboard", "Main")
# reste valide et l'espace de noms reste plat.
# OLD fonctionne aussi mais emet un avertissement de depreciation.
qt_policy(SET QTP0004 NEW)

# Génère .qmlls.ini pour l'autocomplétion QML dans l'éditeur
set(QT_QML_GENERATE_QMLLS_INI ON)

qt_add_executable(dashboard src/main.cpp)

qt_add_qml_module(dashboard
    URI Dashboard
    VERSION 1.0
    QML_FILES
        src/Main.qml
        src/SimulatedDataSource.qml
        src/OdometerStorage.qml
        src/VehicleModel.js
)

target_link_libraries(dashboard PRIVATE Qt6::Quick)
