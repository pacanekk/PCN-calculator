#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>

#include "calculatorengine.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("pcn-calculator"));
    app.setApplicationDisplayName(QStringLiteral("PCN Calculator"));
    app.setOrganizationName(QStringLiteral("PCN"));

    app.setWindowIcon(QIcon(QStringLiteral(":/icon.png")));  // compiled-in resource

    CalculatorEngine engine;

    QQmlApplicationEngine qmlEngine;
    qmlEngine.rootContext()->setContextProperty(QStringLiteral("engine"), &engine);
    qmlEngine.loadFromModule(QStringLiteral("PCNCalculator"), QStringLiteral("Main"));

    if (qmlEngine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
