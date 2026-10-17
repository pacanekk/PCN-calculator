#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVector>

// Expression evaluator: lexer + recursive descent parser.
// Grammar (highest to lowest precedence):
//   expression := additive
//   additive   := multiplicative (('+' | '-') multiplicative)*
//   multiplicative := unary (('*' | '/') unary)*
//   unary      := '-' unary | '+' unary | power
//   power      := primary ('^' unary)?          // right-associative
//   primary    := NUMBER | CONSTANT | FUNCTION '(' expression ')'
//                | '(' expression ')'           // each may be followed by '%' => /100
//
// Note: unary minus has LOWER precedence than power, so -2^2 = -(2^2) = -4.
// '%' is a POSTFIX percent operator: 50% == 0.5.

class CalculatorEngine : public QObject
{
    Q_OBJECT

public:
    explicit CalculatorEngine(QObject *parent = nullptr);

    // Evaluates an expression. Returns a map:
    //   { ok: true,  text: "<display>", raw: "<full precision>" }
    //   { ok: false, error: "Błąd: ..." }
    Q_INVOKABLE QVariantMap evaluate(const QString &expression);

    // Used by QML to detect dangling function names like "sin" without a '('
    Q_INVOKABLE bool isFunction(const QString &name) const;

    // History persistence (QSettings -> ~/.config/PCN/pcn-calculator.conf)
    Q_INVOKABLE void saveHistory(const QString &json);
    Q_INVOKABLE QString loadHistory() const;

private:
    enum class TokenType {
        Number,
        Plus, Minus, Star, Slash, Caret, Percent,
        LParen, RParen,
        Identifier,
        End
    };

    struct Token {
        TokenType type;
        double value = 0.0;
        QString text;
    };

    QVector<Token> tokenize(const QString &expr);
    double callFunction(const QString &name, double arg) const;
    double constant(const QString &name) const;
    QString format(double value) const;
    bool selfTest();

    static constexpr int kMaxParseDepth = 256;

    class Parser {
    public:
        Parser(const QVector<Token> &tokens, CalculatorEngine *engine)
            : m_tokens(tokens), m_engine(engine) {}
        double parse();

    private:
        const Token &peek() const;
        Token consume();
        bool match(TokenType t);
        double parseAdditive();
        double parseMultiplicative();
        double parseUnary();
        double parsePower();
        double parsePrimary();

        const QVector<Token> &m_tokens;
        CalculatorEngine *m_engine;
        int m_pos = 0;
        int m_depth = 0;
    };
};
