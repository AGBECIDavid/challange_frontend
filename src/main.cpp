#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // Identite d'application requise par QSettings, sur lequel repose
    // OdometerStorage. Sans ces deux lignes, QSettings refuse de s'initialiser
    // et l'odometre n'est jamais persiste en mode compile. Ce n'est pas de la
    // logique applicative : c'est la configuration minimale du processus.
    QGuiApplication::setOrganizationName(QStringLiteral("navette"));
    QGuiApplication::setApplicationName(QStringLiteral("dashboard"));

    QQmlApplicationEngine engine;
    engine.loadFromModule("Dashboard", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;
    return app.exec();
}
