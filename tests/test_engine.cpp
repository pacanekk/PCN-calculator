#include "calculatorengine.h"

#include <QVariantMap>
#include <cstdio>
#include <cstring>

static int failures = 0;

static void expectText(CalculatorEngine &e, const char *expr, const char *want)
{
    const QVariantMap r = e.evaluate(QString::fromUtf8(expr));
    const bool ok = r.value(QStringLiteral("ok")).toBool();
    const QString got = ok ? r.value(QStringLiteral("text")).toString()
                           : r.value(QStringLiteral("error")).toString();
    if (!ok || got != QLatin1String(want)) {
        ++failures;
        std::printf("FAIL: %-28s want %-14s got %s\n", expr, want, qPrintable(got));
    }
}

static void expectErr(CalculatorEngine &e, const QString &expr)
{
    const QVariantMap r = e.evaluate(expr);
    if (r.value(QStringLiteral("ok")).toBool()) {
        ++failures;
        std::printf("FAIL: %-28s expected error, got %s\n",
                    qPrintable(expr), qPrintable(r.value(QStringLiteral("text")).toString()));
    }
}

int main()
{
    CalculatorEngine e;

    // precedence & associativity
    expectText(e, "2+3*4",       "14");
    expectText(e, "(2+3)*4",     "20");
    expectText(e, "2^3^2",       "512");   // right-associative
    expectText(e, "-2^2",        "-4");    // unary below power
    expectText(e, "2^-3",        "0.125");
    expectText(e, "2+-3",        "-1");

    // postfix percent
    expectText(e, "50%",         "0.5");
    expectText(e, "200+50%",     "200.5");
    expectErr(e, "10%3");                  // % is postfix, not binary mod

    // scientific notation
    expectText(e, "2e3",         "2000");
    expectText(e, "2.5e-3",      "0.0025");
    expectErr(e,  "1e400");                // out of range

    // functions & constants
    expectText(e, "sqrt(16)+4",  "8");
    expectText(e, "ln(e)",       "1");
    expectText(e, "abs(-7)",     "7");
    expectText(e, "0.1+0.2",     "0.3");
    expectText(e, "pi",          "3.141592654");

    // errors
    expectErr(e, "1/0");
    expectErr(e, "sqrt(-1)");
    expectErr(e, "2(3+4)");                // no implicit multiplication
    expectErr(e, "foo(3)");
    expectErr(e, "()");
    expectErr(e, "5+");

    // deep nesting -> error, not crash
    {
        QString deep;
        deep.reserve(401);
        for (int i = 0; i < 400; ++i) deep += QLatin1Char('(');
        deep += QLatin1Char('1');
        expectErr(e, deep);
    }

    // round-trip: raw (17 digits) must re-evaluate at full precision
    {
        const QVariantMap r1 = e.evaluate(QStringLiteral("1/3"));
        const QVariantMap r2 = e.evaluate(r1.value(QStringLiteral("raw")).toString() + "*3");
        const bool ok2 = r2.value(QStringLiteral("ok")).toBool();
        if (!ok2 || r2.value(QStringLiteral("text")).toString() != QLatin1String("1")) {
            ++failures;
            std::printf("FAIL: round-trip 1/3*3 want 1 got %s\n",
                        qPrintable(r2.value(ok2 ? QStringLiteral("text") : QStringLiteral("error")).toString()));
        }
    }

    if (failures == 0) std::printf("ALL TESTS PASSED\n");
    return failures ? 1 : 0;
}
