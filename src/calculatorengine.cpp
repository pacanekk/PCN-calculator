#include "calculatorengine.h"

#include <cmath>
#include <limits>
#include <stdexcept>
#include <QSettings>
#include <QStringList>

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kE  = 2.71828182845904523536;
}

CalculatorEngine::CalculatorEngine(QObject *parent) : QObject(parent)
{
    Q_ASSERT(selfTest());
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

QVector<CalculatorEngine::Token> CalculatorEngine::tokenize(const QString &expr)
{
    QVector<Token> tokens;
    int i = 0;

    while (i < expr.length()) {
        const QChar c = expr[i];

        if (c.isSpace()) { ++i; continue; }

        if (c.isDigit() || c == '.') {
            const int start = i;
            while (i < expr.length() && (expr[i].isDigit() || expr[i] == '.'))
                ++i;
            // scientific notation: 1e5, 2.5e-3
            if (i < expr.length() && (expr[i] == 'e' || expr[i] == 'E')) {
                int j = i + 1;
                if (j < expr.length() && (expr[j] == '+' || expr[j] == '-'))
                    ++j;
                if (j < expr.length() && expr[j].isDigit()) {
                    i = j;
                    while (i < expr.length() && expr[i].isDigit())
                        ++i;
                }
            }
            const QString text = expr.mid(start, i - start);
            bool ok = false;
            const double value = text.toDouble(&ok);
            // lexer only produces well-formed numbers, so !ok means out of range
            if (!ok)
                throw std::runtime_error("Liczba poza zakresem: " + text.toStdString());
            tokens.append({TokenType::Number, value, text});
            continue;
        }

        switch (c.unicode()) {
        case '+': tokens.append({TokenType::Plus, 0, "+"}); ++i; continue;
        case '-': case 0x2212: tokens.append({TokenType::Minus, 0, "-"}); ++i; continue;
        case '*': case 0x00D7: tokens.append({TokenType::Star, 0, "*"}); ++i; continue;
        case '/': case 0x00F7: tokens.append({TokenType::Slash, 0, "/"}); ++i; continue;
        case '^': tokens.append({TokenType::Caret, 0, "^"}); ++i; continue;
        case '%': tokens.append({TokenType::Percent, 0, "%"}); ++i; continue;
        case '(': tokens.append({TokenType::LParen, 0, "("}); ++i; continue;
        case ')': tokens.append({TokenType::RParen, 0, ")"}); ++i; continue;
        default: break;
        }

        if (c.isLetter() || c.unicode() == 0x03C0) { // a-z or π
            const int start = i;
            ++i;
            while (i < expr.length() && expr[i].isLetterOrNumber())
                ++i;
            tokens.append({TokenType::Identifier, 0, expr.mid(start, i - start)});
            continue;
        }

        throw std::runtime_error(QStringLiteral("Nieoczekiwany znak: %1").arg(c).toStdString());
    }

    tokens.append({TokenType::End, 0, {}});
    return tokens;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const CalculatorEngine::Token &CalculatorEngine::Parser::peek() const
{
    return m_tokens[m_pos];
}

CalculatorEngine::Token CalculatorEngine::Parser::consume()
{
    return m_tokens[m_pos++];
}

bool CalculatorEngine::Parser::match(TokenType t)
{
    if (peek().type == t) { consume(); return true; }
    return false;
}

double CalculatorEngine::Parser::parse()
{
    if (peek().type == TokenType::End)
        throw std::runtime_error("Puste wyrażenie");
    const double result = parseAdditive();
    if (peek().type != TokenType::End)
        throw std::runtime_error("Niekompletne wyrażenie");
    return result;
}

double CalculatorEngine::Parser::parseAdditive()
{
    double result = parseMultiplicative();
    while (peek().type == TokenType::Plus || peek().type == TokenType::Minus) {
        const bool subtract = consume().type == TokenType::Minus;
        const double rhs = parseMultiplicative();
        result = subtract ? result - rhs : result + rhs;
    }
    return result;
}

double CalculatorEngine::Parser::parseMultiplicative()
{
    double result = parseUnary();
    while (true) {
        const TokenType t = peek().type;
        if (t != TokenType::Star && t != TokenType::Slash)
            break;
        consume();
        const double rhs = parseUnary();
        if (t == TokenType::Star) {
            result *= rhs;
        } else {
            if (rhs == 0.0)
                throw std::runtime_error("Dzielenie przez zero");
            result /= rhs;
        }
    }
    return result;
}

double CalculatorEngine::Parser::parseUnary()
{
    if (++m_depth > kMaxParseDepth) {
        --m_depth;
        throw std::runtime_error("Za głębokie wyrażenie");
    }
    double value;
    if (match(TokenType::Minus))
        value = -parseUnary();
    else if (match(TokenType::Plus))
        value = parseUnary();
    else
        value = parsePower();
    --m_depth;
    return value;
}

double CalculatorEngine::Parser::parsePower()
{
    const double base = parsePrimary();
    if (match(TokenType::Caret))
        return std::pow(base, parseUnary()); // right-associative
    return base;
}

double CalculatorEngine::Parser::parsePrimary()
{
    double value;

    if (peek().type == TokenType::Number) {
        value = consume().value;
    } else if (match(TokenType::LParen)) {
        if (++m_depth > kMaxParseDepth) {
            --m_depth;
            throw std::runtime_error("Za głębokie wyrażenie");
        }
        value = parseAdditive();
        --m_depth;
        if (!match(TokenType::RParen))
            throw std::runtime_error("Brakuje zamykającego nawiasu");
    } else if (peek().type == TokenType::Identifier) {
        const QString name = consume().text;
        if (m_engine->isFunction(name)) {
            if (!match(TokenType::LParen))
                throw std::runtime_error("Po funkcji oczekiwano nawiasu");
            if (++m_depth > kMaxParseDepth) {
                --m_depth;
                throw std::runtime_error("Za głębokie wyrażenie");
            }
            const double arg = parseAdditive();
            --m_depth;
            if (!match(TokenType::RParen))
                throw std::runtime_error("Brakuje zamykającego nawiasu");
            value = m_engine->callFunction(name, arg);
        } else {
            const double c = m_engine->constant(name);
            if (std::isnan(c))
                throw std::runtime_error("Nieznany identyfikator: " + name.toStdString());
            value = c;
        }
    } else {
        throw std::runtime_error("Nieoczekiwany token");
    }

    if (match(TokenType::Percent))          // postfix percent: 50% == 0.5
        value /= 100.0;
    return value;
}

// ---------------------------------------------------------------------------
// Functions and constants
// ---------------------------------------------------------------------------

bool CalculatorEngine::isFunction(const QString &name) const
{
    static const QStringList funcs = {
        "sin", "cos", "tan", "asin", "acos", "atan",
        "log", "ln", "sqrt", "abs", "floor", "ceil", "exp"
    };
    return funcs.contains(name);
}

double CalculatorEngine::callFunction(const QString &name, double arg) const
{
    if (name == "sqrt") {
        if (arg < 0)
            throw std::runtime_error("sqrt z liczby ujemnej");
        return std::sqrt(arg);
    }
    if (name == "log") {
        if (arg <= 0)
            throw std::runtime_error("log wymaga argumentu dodatniego");
        return std::log10(arg);
    }
    if (name == "ln") {
        if (arg <= 0)
            throw std::runtime_error("ln wymaga argumentu dodatniego");
        return std::log(arg);
    }
    if (name == "sin")   return std::sin(arg);
    if (name == "cos")   return std::cos(arg);
    if (name == "tan")   return std::tan(arg);
    if (name == "asin")  return std::asin(arg);
    if (name == "acos")  return std::acos(arg);
    if (name == "atan")  return std::atan(arg);
    if (name == "abs")   return std::fabs(arg);
    if (name == "floor") return std::floor(arg);
    if (name == "ceil")  return std::ceil(arg);
    if (name == "exp")   return std::exp(arg);
    throw std::runtime_error("Nieznana funkcja: " + name.toStdString());
}

double CalculatorEngine::constant(const QString &name) const
{
    if (name == "pi" || name == QStringLiteral("π"))
        return kPi;
    if (name == "e")
        return kE;
    return std::numeric_limits<double>::quiet_NaN();
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

QVariantMap CalculatorEngine::evaluate(const QString &expression)
{
    QVariantMap out;
    try {
        const QVector<Token> tokens = tokenize(expression);
        Parser parser(tokens, this);
        const double value = parser.parse();
        if (std::isnan(value)) {
            out[QStringLiteral("ok")] = false;
            out[QStringLiteral("error")] = QStringLiteral("Błąd: niezdefiniowany wynik");
        } else if (std::isinf(value)) {
            out[QStringLiteral("ok")] = false;
            out[QStringLiteral("error")] = QStringLiteral("Błąd: przepełnienie");
        } else {
            out[QStringLiteral("ok")] = true;
            out[QStringLiteral("text")] = format(value);
            out[QStringLiteral("raw")] = QString::number(value, 'g', 17);
        }
    } catch (const std::exception &e) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Błąd: %1").arg(QString::fromStdString(e.what()));
    }
    return out;
}

QString CalculatorEngine::format(double value) const
{
    if (std::isnan(value))
        return QStringLiteral("Błąd: niezdefiniowany wynik");
    if (std::isinf(value))
        return QStringLiteral("Błąd: przepełnienie");
    // normalize -0 to 0
    if (value == 0.0)
        value = 0.0;
    return QString::number(value, 'g', 10);
}

// ---------------------------------------------------------------------------
// History persistence
// ---------------------------------------------------------------------------

void CalculatorEngine::saveHistory(const QString &json)
{
    QSettings settings;
    settings.setValue(QStringLiteral("history"), json);
}

QString CalculatorEngine::loadHistory() const
{
    const QSettings settings;
    return settings.value(QStringLiteral("history")).toString();
}

// ---------------------------------------------------------------------------

bool CalculatorEngine::selfTest()
{
    struct Case { const char *expr; double expected; };
    const Case cases[] = {
        {"2+3*4",        14.0},
        {"(2+3)*4",      20.0},
        {"2^3^2",        512.0},   // right-associative: 2^(3^2)
        {"-2^2",         -4.0},    // unary minus below power
        {"2^-3",         0.125},
        {"50%",          0.5},     // postfix percent
        {"200+50%",      200.5},
        {"2e3",          2000.0},  // scientific notation
        {"sqrt(16)+4",   8.0},
        {"10%3",         std::numeric_limits<double>::quiet_NaN()}, // % is postfix, not binary mod → error
        {"2(3+4)",       std::numeric_limits<double>::quiet_NaN()}, // unsupported implicit mult → error
    };
    for (const Case &c : cases) {
        const double expected = c.expected;
        if (std::isnan(expected)) {
            if (evaluate(QString::fromLatin1(c.expr)).value(QStringLiteral("ok")).toBool())
                return false;
            continue;
        }
        const QVector<Token> tokens = tokenize(QString::fromLatin1(c.expr));
        Parser parser(tokens, this);
        const double got = parser.parse();
        if (std::fabs(got - expected) > 1e-9)
            return false;
    }
    return true;
}
