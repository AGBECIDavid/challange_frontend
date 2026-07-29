#!/usr/bin/env bash
#
# setup.sh — diagnostic, configuration et compilation de navette-dashboard.
#
# CE SCRIPT N'INSTALLE RIEN.
#
# Il ne demande jamais les droits administrateur, ne télécharge rien, ne
# touche à aucun fichier hors de build/, et ne modifie aucun profil shell.
# Quand il manque quelque chose, il imprime la commande exacte à lancer et
# s'arrête : c'est à vous de décider ce qui est installé sur votre machine.
#
# Usage : ./scripts/setup.sh [--check|--run|--test] [--clean] [--help]

set -euo pipefail

# --- Racine du projet -------------------------------------------------------
# Résolue depuis le chemin du script, jamais depuis $PWD : le script doit
# fonctionner appelé depuis n'importe quel répertoire courant.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(dirname -- "$SCRIPT_DIR")
BUILD_DIR="$PROJECT_ROOT/build"

readonly QT_MIN="6.7"
readonly CMAKE_MIN="3.21"

# --- Sortie -----------------------------------------------------------------
# Une seule couleur, pour l'échec seulement, et uniquement si le terminal la
# gère. Pas d'art ASCII : ce script est lu autant qu'exécuté.
RED='' RESET=''
if [ -t 2 ] && command -v tput >/dev/null 2>&1; then
    if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        RED=$(tput setaf 1) RESET=$(tput sgr0)
    fi
fi

info() { printf '%s\n' "$*"; }

die() {
    printf '%sÉchec :%s %s\n' "$RED" "$RESET" "$1" >&2
    shift
    local line
    for line in "$@"; do printf '%s\n' "$line" >&2; done
    exit 1
}

# --- Garde-fou --------------------------------------------------------------
# Le script supprime build/ sur --clean. On vérifie donc que la racine déduite
# du chemin du script est bien celle du projet, et pas un répertoire arbitraire
# où le script aurait été recopié seul.
if [ ! -f "$PROJECT_ROOT/CMakeLists.txt" ] || [ ! -d "$PROJECT_ROOT/src" ]; then
    die "racine du projet introuvable : $PROJECT_ROOT" \
        "" \
        "CMakeLists.txt et src/ y sont attendus, et l'un des deux manque." \
        "Ce script se situe par rapport à sa propre position : il doit rester" \
        "dans scripts/, à la racine du dépôt. Ni une copie isolée ni un lien" \
        "symbolique posé ailleurs ne fonctionnent — appelez-le par son vrai" \
        "chemin, depuis le répertoire courant que vous voulez."
fi

# --- Comparaison de versions ------------------------------------------------
# Pure bash : ni sort -V, ni awk, ni python. « 6.8.3 » >= « 6.7 » -> vrai.
version_ge() {
    local -a have want
    IFS='.' read -r -a have <<<"${1%%[!0-9.]*}"
    IFS='.' read -r -a want <<<"${2%%[!0-9.]*}"
    local i x y
    for i in 0 1 2; do
        x=${have[i]-} y=${want[i]-}
        x=${x:-0} y=${y:-0}
        if ((10#$x > 10#$y)); then return 0; fi
        if ((10#$x < 10#$y)); then return 1; fi
    done
    return 0
}

# --- Aide -------------------------------------------------------------------
usage() {
    cat <<'EOF'
setup.sh — diagnostic, configuration et compilation de navette-dashboard.

  ./scripts/setup.sh [OPTION]... [-- ARGS...]

Sans option : détecte Qt et les outils de compilation, puis configure et
compile. Ne lance pas l'application — compiler et lancer sont deux intentions
différentes.

  --check      Diagnostic seul. Ne compile rien, n'écrit rien.
  --run        Compile puis lance. Tous les arguments qui suivent sont
               transmis à l'application :
                   ./scripts/setup.sh --run --windowed --fps
  --test       Compile, puis joue qmltestrunner et all_qmllint.
  --clean      Supprime build/ avant de reconfigurer. Se combine aux autres.
  --help       Cette aide.

Ce script n'installe rien et ne demande jamais les droits administrateur.
Quand il manque une dépendance, il affiche la commande à lancer et s'arrête.

Détection de Qt, par ordre de priorité :
  1. $QT_ROOT si la variable est définie
  2. $HOME/Qt/*/gcc_64          (voie aqtinstall, la plus récente)
  3. qmake6 dans le PATH, ou /usr/lib/qt6/bin/qmake6   (Qt de la distribution)

Documentation complète : README.md
EOF
}

# --- Commandes d'installation, affichées jamais exécutées -------------------
apt_hint_build() {
    info ""
    info "Pour les installer (commande à lancer vous-même) :"
    info ""
    info "    sudo apt install build-essential cmake ninja-build"
    info ""
}

apt_hint_qt() {
    info ""
    info "Deux voies, détaillées dans README.md § Prérequis."
    info ""
    info "  a) Qt de la distribution — si elle fournit Qt >= $QT_MIN"
    info "     (Debian 13 Trixie et Raspberry Pi OS Trixie fournissent 6.8.2) :"
    info ""
    info "    sudo apt install build-essential cmake ninja-build \\"
    info "        qt6-base-dev qt6-declarative-dev qt6-declarative-dev-tools \\"
    info "        qml-qt6 \\"
    info "        qml6-module-qtcore qml6-module-qtquick qml6-module-qtquick-shapes \\"
    info "        qml6-module-qtquick-window qml6-module-qttest"
    info ""
    info "  b) Installation isolée dans \$HOME, sans toucher au système —"
    info "     si la distribution est trop ancienne (Debian 12, Ubuntu 24.04) :"
    info ""
    info "    sudo apt install build-essential cmake ninja-build pipx"
    info "    pipx install aqtinstall"
    info "    aqt install-qt linux desktop 6.8.3 linux_gcc_64 \\"
    info "        -m qtshadertools --outputdir \"\$HOME/Qt\""
    info ""
    info "     Environ 195 Mo de téléchargement, 1,5 Go sur disque."
    info "     Ce script la détectera ensuite tout seul."
    info ""
}

# --- a) Détection de Qt -----------------------------------------------------
QT_PREFIX='' QT_BIN='' QT_VERSION='' QT_ORIGIN='' QT_NEEDS_PREFIX_PATH=0

detect_qt() {
    local candidate

    # 1. QT_ROOT, si l'utilisateur l'a définie : elle prime sur tout.
    if [ -n "${QT_ROOT:-}" ]; then
        if [ ! -x "$QT_ROOT/bin/qmake6" ]; then
            die "QT_ROOT est définie mais ne désigne pas une installation Qt 6." \
                "" \
                "    QT_ROOT = $QT_ROOT" \
                "" \
                "Le fichier attendu est \$QT_ROOT/bin/qmake6, et il est absent." \
                "QT_ROOT doit désigner le préfixe d'installation, pas son dossier bin :" \
                "" \
                "    QT_ROOT=\"\$HOME/Qt/6.8.3/gcc_64\"   et non   .../gcc_64/bin" \
                "" \
                "Pour laisser le script chercher tout seul, désactivez la variable :" \
                "" \
                "    unset QT_ROOT"
        fi
        QT_PREFIX=$QT_ROOT
        QT_ORIGIN="variable QT_ROOT"
        QT_NEEDS_PREFIX_PATH=1

    # 2. Voie aqtinstall : la plus récente des installations dans $HOME/Qt.
    else
        while IFS= read -r candidate; do
            if [ -x "$candidate/bin/qmake6" ]; then
                QT_PREFIX=$candidate
                QT_ORIGIN="aqtinstall"
                QT_NEEDS_PREFIX_PATH=1
                break
            fi
        done < <(printf '%s\n' "${HOME:-/nonexistent}"/Qt/*/gcc_64 | sort -Vr)

        # 3. Qt de la distribution. Sur Debian, /usr/lib/qt6/bin n'est pas
        #    dans le PATH : on l'essaie explicitement.
        if [ -z "$QT_PREFIX" ]; then
            if candidate=$(command -v qmake6 2>/dev/null); then
                QT_PREFIX=$(cd -- "$(dirname -- "$candidate")/.." && pwd -P)
                QT_ORIGIN="Qt de la distribution (PATH)"
            elif [ -x /usr/lib/qt6/bin/qmake6 ]; then
                QT_PREFIX=/usr/lib/qt6
                QT_ORIGIN="Qt de la distribution (/usr/lib/qt6)"
            fi
            QT_NEEDS_PREFIX_PATH=0
        fi
    fi

    if [ -z "$QT_PREFIX" ]; then
        printf '%sÉchec :%s aucune installation de Qt 6 trouvée.\n' "$RED" "$RESET" >&2
        info ""
        info "Cherché, dans cet ordre :"
        info "  1. \$QT_ROOT                    (variable non définie)"
        info "  2. \$HOME/Qt/*/gcc_64           (voie aqtinstall)"
        info "  3. qmake6 dans le PATH, puis /usr/lib/qt6/bin/qmake6"
        apt_hint_qt
        exit 1
    fi

    QT_BIN="$QT_PREFIX/bin"
    # 2>/dev/null : qmake6 se plaint sur stderr d'une locale non UTF-8, ce qui
    # n'a rien à voir avec la version qu'on lui demande.
    QT_VERSION=$("$QT_BIN/qmake6" -query QT_VERSION 2>/dev/null || true)
    if [ -z "$QT_VERSION" ]; then
        die "qmake6 trouvé mais inexploitable : $QT_BIN/qmake6" \
            "" \
            "Il n'a pas répondu à « qmake6 -query QT_VERSION ». L'installation" \
            "est probablement incomplète ou déplacée. Détail de l'erreur :" \
            "" \
            "    $QT_BIN/qmake6 -query QT_VERSION"
    fi
}

# --- b) Version de Qt -------------------------------------------------------
check_qt_version() {
    if version_ge "$QT_VERSION" "$QT_MIN"; then
        return 0
    fi

    printf '%sÉchec :%s Qt %s détecté, mais %s est le minimum.\n' \
        "$RED" "$RESET" "$QT_VERSION" "$QT_MIN" >&2
    info ""
    info "  Installation : $QT_PREFIX  ($QT_ORIGIN)"
    info ""
    info "Ce seuil n'est pas arbitraire. Il est le maximum de deux contraintes :"
    info "  - Settings dans le module QtCore                    -> Qt 6.5"
    info "  - font.features, pour les chiffres tabulaires       -> Qt 6.7"
    info ""
    info "font.features est ce qui donne aux chiffres une largeur constante."
    info "Sans lui, la valeur de vitesse se décale latéralement à chaque"
    info "rafraîchissement — 20 fois par seconde. Le défaut est visible et"
    info "rédhibitoire sur un combiné de conduite, d'où le refus de dégrader."
    info ""
    info "Votre distribution ne fournit pas un Qt assez récent : utilisez la"
    info "voie b), qui installe Qt dans \$HOME sans toucher au système."
    apt_hint_qt
    exit 1
}

# --- c) Outils de compilation ----------------------------------------------
CXX_FOUND='' CMAKE_VERSION='' NINJA_VERSION=''

check_build_tools() {
    local -a missing=()
    local path

    if path=$(command -v cmake 2>/dev/null); then
        CMAKE_VERSION=$(cmake --version | head -n 1)
        CMAKE_VERSION=${CMAKE_VERSION##* }
        if ! version_ge "$CMAKE_VERSION" "$CMAKE_MIN"; then
            printf '%sÉchec :%s CMake %s détecté, mais %s est le minimum.\n' \
                "$RED" "$RESET" "$CMAKE_VERSION" "$CMAKE_MIN" >&2
            info ""
            info "  Trouvé : $path"
            info ""
            info "CMakeLists.txt exige cmake_minimum_required(VERSION $CMAKE_MIN)."
            apt_hint_build
            exit 1
        fi
    else
        missing+=("cmake (>= $CMAKE_MIN)")
    fi

    if command -v ninja >/dev/null 2>&1; then
        NINJA_VERSION=$(ninja --version)
    else
        missing+=("ninja")
    fi

    local cxx
    for cxx in "${CXX:-}" c++ g++ clang++; do
        if [ -n "$cxx" ] && command -v "$cxx" >/dev/null 2>&1; then
            CXX_FOUND=$(command -v "$cxx")
            break
        fi
    done
    [ -n "$CXX_FOUND" ] || missing+=("un compilateur C++ (g++ ou clang++)")

    if [ ${#missing[@]} -gt 0 ]; then
        printf '%sÉchec :%s outils de compilation manquants.\n' "$RED" "$RESET" >&2
        info ""
        local m
        for m in "${missing[@]}"; do info "  - $m"; done
        apt_hint_build
        exit 1
    fi
}

# --- Diagnostic -------------------------------------------------------------
report() {
    info "Projet   : $PROJECT_ROOT"
    info "Qt       : $QT_VERSION  ($QT_ORIGIN)"
    info "           $QT_PREFIX"
    info "CMake    : $CMAKE_VERSION"
    info "Ninja    : $NINJA_VERSION"
    info "C++      : $CXX_FOUND"
}

# --- Configuration et compilation -------------------------------------------
# Idempotent : un cache CMake déjà correct est réutilisé, un cache devenu
# incohérent (projet déplacé, Qt changé) est supprimé et refait.
configure_and_build() {
    local -a cmake_args=(-S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja)
    local wanted_prefix=''

    if [ "$QT_NEEDS_PREFIX_PATH" -eq 1 ]; then
        wanted_prefix=$QT_PREFIX
        cmake_args+=(-DCMAKE_PREFIX_PATH="$QT_PREFIX")
    fi

    if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
        local cached_src cached_prefix
        cached_src=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' \
            "$BUILD_DIR/CMakeCache.txt" | head -n 1)
        cached_prefix=$(sed -n 's/^CMAKE_PREFIX_PATH:[^=]*=//p' \
            "$BUILD_DIR/CMakeCache.txt" | head -n 1)
        if [ "$cached_src" != "$PROJECT_ROOT" ] || \
           [ "${cached_prefix:-}" != "$wanted_prefix" ]; then
            info "Cache CMake incohérent avec cette configuration, on repart de zéro."
            rm -rf -- "$BUILD_DIR"
        fi
    fi

    info "Configuration…"
    cmake "${cmake_args[@]}"
    info "Compilation…"
    cmake --build "$BUILD_DIR"
}

# --- Plateforme graphique ---------------------------------------------------
# Sans serveur d'affichage, Qt échoue à s'initialiser et abandonne. Le cas se
# présente aussi bien pour l'application que pour qmltestrunner : en session
# SSH, en conteneur, ou sur une intégration continue. On bascule alors en
# offscreen — sauf si l'utilisateur a déjà choisi une plateforme lui-même.
ensure_qpa_platform() {
    if [ -n "${QT_QPA_PLATFORM:-}" ]; then return 0; fi
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then return 0; fi
    info "Aucun serveur d'affichage détecté : QT_QPA_PLATFORM=offscreen."
    export QT_QPA_PLATFORM=offscreen
}

# --- Tests ------------------------------------------------------------------
run_tests() {
    local runner="$QT_BIN/qmltestrunner"
    if [ ! -x "$runner" ]; then
        die "qmltestrunner introuvable dans $QT_BIN." \
            "" \
            "Avec le Qt de la distribution, il vient du paquet" \
            "qt6-declarative-dev-tools, et les tests QML exigent en plus" \
            "qml6-module-qttest. Voir README.md § Prérequis."
    fi

    info ""
    ensure_qpa_platform
    info "Tests QML — $runner"
    # cd indispensable : les tests importent « ../src » en relatif.
    (cd -- "$PROJECT_ROOT" && "$runner" -input tests)

    info ""
    info "Lint QML — cible all_qmllint"
    cmake --build "$BUILD_DIR" --target all_qmllint
}

# --- Comment lancer ---------------------------------------------------------
print_launch_help() {
    local qml_bin="$QT_BIN/qml"
    info ""
    info "Compilation terminée. Deux modes de lancement :"
    info ""
    info "  Mode 1 — build CMake, le mode de production"
    info "      $BUILD_DIR/dashboard"
    info "      $BUILD_DIR/dashboard --windowed --fps"
    info ""
    info "  Mode 2 — runtime QML, pour itérer sans compiler"
    info "      $qml_bin $PROJECT_ROOT/src/Main.qml"
    info "      $qml_bin $PROJECT_ROOT/src/Main.qml -- --windowed --fps"
    info ""
    info "  Ou par ce script :"
    info "      $SCRIPT_DIR/setup.sh --run --windowed --fps"
    info ""
    info "L'application démarre en plein écran sans décoration ; Échap en sort."
    info "--windowed démarre en fenêtre, --fps affiche le compteur d'images."
}

# --- Arguments --------------------------------------------------------------
# --run consomme tout ce qui suit et le transmet à l'application, ce qui rend
# « --run --windowed --fps » sans ambiguïté : le script n'a pas à connaître
# les options de l'application, ni l'inverse.
ACTION=build
CLEAN=0
APP_ARGS=()

set_action() {
    if [ "$ACTION" != build ]; then
        die "--check, --run et --test s'excluent : « --$1 » arrive après « --$ACTION »."
    fi
    ACTION=$1
}

while [ $# -gt 0 ]; do
    case $1 in
        --help|-h) usage; exit 0 ;;
        --check)   set_action check; shift ;;
        --test)    set_action test;  shift ;;
        --clean)   CLEAN=1; shift ;;
        --run)
            set_action run
            shift
            # « --run -- --windowed » accepté aussi, par symétrie avec le
            # mode 2 où le « -- » est obligatoire.
            if [ "${1:-}" = "--" ]; then shift; fi
            APP_ARGS=("$@")
            break
            ;;
        *)
            die "option inconnue : $1" \
                "" \
                "Les options de l'application (--windowed, --fps) se passent" \
                "après --run :" \
                "" \
                "    ./scripts/setup.sh --run $1" \
                "" \
                "« ./scripts/setup.sh --help » liste les options du script."
            ;;
    esac
done

# --- Enchaînement -----------------------------------------------------------
detect_qt
check_qt_version
check_build_tools
report

if [ "$ACTION" = check ]; then
    info ""
    info "Diagnostic seul : rien n'a été compilé."
    info "Lancez « $SCRIPT_DIR/setup.sh » pour configurer et compiler."
    exit 0
fi

if [ "$CLEAN" -eq 1 ] && [ -d "$BUILD_DIR" ]; then
    info ""
    info "Suppression de $BUILD_DIR"
    rm -rf -- "$BUILD_DIR"
fi

info ""
configure_and_build

case $ACTION in
    test)
        run_tests
        info ""
        info "Tests et lint terminés."
        ;;
    run)
        ensure_qpa_platform
        info ""
        info "Lancement : $BUILD_DIR/dashboard ${APP_ARGS[*]-}"
        info ""
        exec "$BUILD_DIR/dashboard" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
        ;;
    build)
        print_launch_help
        ;;
esac
