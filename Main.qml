import QtQuick
import QtQuick.Layouts
import QtQml.Models

Window {
    id: root
    visible: true
    title: "PCN Calculator"
    width: 360
    height: 600
    minimumWidth: 320
    minimumHeight: 480
    color: "#0e0e12"

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    property string expression: ""
    property string preview: ""
    property string committedError: ""
    property bool scientific: false
    property bool historyVisible: false
    property bool justEvaluated: false
    // full-precision result kept for chaining (display string loses digits)
    property string lastResultRaw: ""

    // ------------------------------------------------------------------
    // Palette
    // ------------------------------------------------------------------
    readonly property color bg: "#0e0e12"
    readonly property color numBg: "#1c1c24"
    readonly property color numBgHover: "#282833"
    readonly property color numBgPressed: "#34343f"
    readonly property color utilBg: "#23232c"
    readonly property color utilBgHover: "#30303c"
    readonly property color utilFg: "#d8d8e0"
    readonly property color accent: "#5b8cff"
    readonly property color accentHover: "#7aa3ff"
    readonly property color accentPressed: "#3a63d4"
    readonly property color textPrimary: "#f2f2f5"
    readonly property color textSecondary: "#82828e"
    readonly property color errorColor: "#ff6b6b"

    // ------------------------------------------------------------------
    // Logic
    // ------------------------------------------------------------------
    function closeParens(e) {
        let depth = 0
        for (let i = 0; i < e.length; ++i) {
            if (e[i] === '(') ++depth
            else if (e[i] === ')') --depth
        }
        while (depth-- > 0) e += ')'
        return e
    }

    // Strip trailing ops, '(' and dangling function names:
    // "2÷−"→"2", "5×("→"5", "2×sin("→"2"
    function sanitizeForEval(e) {
        let prev
        do {
            prev = e
            e = e.replace(/[+−×÷^(]+$/, '')
            e = e.replace(/([\d.])[eE][+\-−]?$/, '$1')  // dangling exponent: "2e"→"2"
            // dangling function name: ask the engine instead of duplicating the list
            const fm = e.match(/[a-z]+$/i)
            if (fm && engine.isFunction(fm[0]))
                e = e.slice(0, -fm[0].length)
        } while (e !== prev && e.length)
        return e
    }

    function updatePreview() {
        committedError = ""
        const e = sanitizeForEval(expression)
        if (!e) { preview = ""; return }
        const r = engine.evaluate(closeParens(e))
        preview = r.ok ? r.text : ""
    }

    function append(s) {
        const ops = "+−×÷^"

        if (justEvaluated) {
            justEvaluated = false
            // ops/postfix chain on the raw result (full precision), values start fresh
            expression = (ops.includes(s) || s === '%' || s.startsWith('^'))
                       ? lastResultRaw : ""
        }

        if (expression.length >= 200) return      // guard parser recursion / sanity

        // exponent pending ("2e" / "2e-"): only digits, or a sign right after 'e'
        if (/[\d.][eE][+\-−]?$/.test(expression)) {
            if (/^\d$/.test(s)) expression += s
            else if ((s === '−' || s === '+') && expression.slice(-1) === 'e')
                expression += (s === '−' ? '-' : '+')
            else return
            updatePreview()
            return
        }

        const last = expression.slice(-1)
        const lastIsOp = ops.includes(last)

        if (ops.includes(s)) {
            if (!expression || last === '(') {
                // only unary minus may start an expression or follow '('
                if (s !== '−') return
            } else if (lastIsOp) {
                // operator after operator always replaces: "9×" + "−" → "9−"
                // (negative numbers are made with the ± button, like other calculators)
                while (ops.includes(expression.slice(-1)))
                    expression = expression.slice(0, -1)
                if (!expression && s !== '−') { updatePreview(); return }
                expression += s
            } else {
                expression += s
            }
        } else if (s === ')') {
            let depth = 0
            for (let i = 0; i < expression.length; ++i) {
                if (expression[i] === '(') ++depth
                else if (expression[i] === ')') --depth
            }
            if (depth <= 0 || lastIsOp || last === '(') return
            expression += s
        } else if (s === '%') {
            // postfix percent needs an operand: "50%" → 0.5
            if (!/[\d)πe%]/.test(last)) return
            expression += s
        } else if (s === '.') {
            if (/[\d.][eE][+\-−]?\d*$/.test(expression)) return  // no dot in exponent
            const run = expression.match(/[\d.]*$/)[0]
            if (run.includes('.')) return          // one dot per number
            if (last >= '0' && last <= '9') {
                expression += '.'
            } else {
                if (last === ')' || last === 'π' || last === 'e')
                    expression += '×'              // ")" + "." → ")×0."
                expression += '0.'
            }
        } else {
            // digit, '(', π, e, function token like "sin(", or "^..."
            const lastIsOperand = /[\d)πe]/.test(last)
            const sIsDigit = /^\d$/.test(s)
            if (s === 'e' && /[\d.]/.test(last) && !/[\d.][eE][+\-−]?\d*$/.test(expression)) {
                expression += 'e'                     // start exponent: "2e"
            } else if (s.startsWith('^')) {
                if (!lastIsOperand) return          // x²/xʸ need an operand
                expression += s
            } else {
                if ((sIsDigit && (last === ')' || last === 'π' || last === 'e'))
                    || (!sIsDigit && lastIsOperand)) {
                    // implicit multiplication: ")3"→")×3", "2sin("→"2×sin(", "πe"→"π×e"
                    expression += '×'
                }
                expression += s
            }
        }
        updatePreview()
    }

    function evaluateCommit() {
        const e = closeParens(sanitizeForEval(expression))
        if (!e) return
        const r = engine.evaluate(e)
        if (!r.ok) {
            committedError = r.error
            return
        }
        historyModel.insert(0, { expr: e, res: r.text, raw: r.raw })
        if (historyModel.count > 200)
            historyModel.remove(historyModel.count - 1)
        syncHistory()
        expression = r.text
        lastResultRaw = r.raw
        justEvaluated = true
        updatePreview()
    }

    function negate() {
        if (!expression) return                         // nothing to negate
        if (/[\d.][eE][+\-−]?$/.test(expression)) return // dangling exponent — no-op
        if (expression.endsWith(")")) {
            // negate whole group: "(3)"→"−(3)" ↔ "−(3)"→"(3)", "(−3)"→"(3)"
            let depth = 0, i = expression.length - 1
            for (; i >= 0; --i) {
                if (expression[i] === ')') ++depth
                else if (expression[i] === '(' && --depth === 0) break
            }
            if (i < 0) return
            if (i > 0 && expression[i-1] === '−') {
                expression = expression.slice(0, i-1) + expression.slice(i)
            } else if (expression[i+1] === '−') {
                expression = expression.slice(0, i+1) + expression.slice(i+2)
            } else {
                expression = expression.slice(0, i) + "−" + expression.slice(i)
            }
            updatePreview()
            return
        }
        const m = expression.match(/(\d+\.?\d*(?:[eE][+\-−]?\d*)?|[πe])$/)
        if (!m) return                                  // ends with operator/'(' — no-op
        const head = expression.slice(0, m.index)
        if (head === "" || head === "−") {
            expression = (head === "−" ? "" : "−") + m[0]        // "5"↔"−5"
        } else if (head.endsWith("+")) {
            expression = head.slice(0, -1) + "−" + m[0]          // "5+3"→"5−3"
        } else if (head.endsWith("−")) {
            const before = head.slice(-2, -1)
            if (/[\d)πe]/.test(before))
                expression = head.slice(0, -1) + "+" + m[0]      // "5−3"→"5+3"
            else
                expression = head.slice(0, -1) + m[0]            // "5×−3"→"5×3"
        } else {
            expression = head + "−" + m[0]                       // "5×3"→"5×−3", "5×e"→"5×−e"
        }
        updatePreview()
    }

    function wrapLast(pre, post) {
        if (justEvaluated) { justEvaluated = false; expression = lastResultRaw }
        if (!expression) return
        if (/[\d.][eE][+\-−]?$/.test(expression)) return // dangling exponent — no-op
        if (expression.endsWith(")")) {
            let depth = 0, i = expression.length - 1
            for (; i >= 0; --i) {
                if (expression[i] === ')') ++depth
                else if (expression[i] === '(' && --depth === 0) break
            }
            expression = expression.slice(0, i) + pre + expression.slice(i) + post
        } else {
            const m = expression.match(/(\d+\.?\d*(?:[eE][+\-−]?\d*)?|[πe])$/)
            if (!m) return                          // no operand to wrap — no-op
            expression = expression.slice(0, m.index) + pre + m[0] + post
        }
        updatePreview()
    }

    function press(k) {
        switch (k) {
        case 'C':  expression = ""; preview = ""; committedError = ""; justEvaluated = false; lastResultRaw = ""; break
        case 'CE': expression = ""; justEvaluated = false; updatePreview(); break
        case '⌫':  if (justEvaluated) break; expression = expression.slice(0, -1); updatePreview(); break
        case '±':  if (justEvaluated) { justEvaluated = false; expression = lastResultRaw } negate(); break
        case '=':  evaluateCommit(); break
        default:   append(k)
        }
    }

    // ------------------------------------------------------------------
    // Header: mode switch + history
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredHeight: 34
                Layout.preferredWidth: 190
                radius: 8
                color: "#1a1a21"

                Rectangle {
                    width: parent.width / 2 - 3
                    height: parent.height - 6
                    x: root.scientific ? parent.width / 2 + 1 : 2
                    y: 3
                    radius: 6
                    color: accent
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                Row {
                    anchors.fill: parent
                    Item {
                        width: parent.width / 2; height: parent.height
                        Text { anchors.centerIn: parent; text: "Standard"; font.pixelSize: 13
                               color: !root.scientific ? "#ffffff" : textSecondary }
                        MouseArea { anchors.fill: parent; onClicked: root.scientific = false }
                    }
                    Item {
                        width: parent.width / 2; height: parent.height
                        Text { anchors.centerIn: parent; text: "Scientific"; font.pixelSize: 13
                               color: root.scientific ? "#ffffff" : textSecondary }
                        MouseArea { anchors.fill: parent; onClicked: root.scientific = true }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            CalcButton {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 34
                text: "≡"
                fontSize: 18
                bg: "#1a1a21"
                bgHover: "#24242c"
                onClicked: root.historyVisible = !root.historyVisible
            }
        }

        // ------------------------------------------------------------------
        // Display
        // ------------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 108
            Layout.minimumHeight: 88
            Layout.maximumHeight: 130
            radius: 16
            color: "#15151b"
            border.width: 1
            border.color: "#0dffffff"

            Text {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                anchors.topMargin: 10
                height: 20
                horizontalAlignment: Text.AlignRight
                text: root.expression
                color: textSecondary
                font.pixelSize: 15
                elide: Text.ElideLeft
            }
            Text {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                anchors.bottomMargin: 8
                height: 44
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignBottom
                text: committedError ? committedError
                    : (preview !== "" ? preview
                    : (root.expression === "" ? "0" : "…"))
                color: committedError ? errorColor : textPrimary
                font.pixelSize: committedError ? 17 : 34
                font.bold: !committedError
                elide: Text.ElideLeft
            }
        }

        // ------------------------------------------------------------------
        // Scientific panel
        // ------------------------------------------------------------------
        GridLayout {
            visible: root.scientific
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumHeight: visible ? 220 : 0
            columns: 4
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: [
                    { t: "sin", ins: "sin(" }, { t: "cos", ins: "cos(" },
                    { t: "tan", ins: "tan(" }, { t: "(",   ins: "(" },
                    { t: "log", ins: "log(" }, { t: "ln",  ins: "ln(" },
                    { t: "√",   ins: "sqrt(" }, { t: ")",   ins: ")" },
                    { t: "x²",  ins: "^2" },  { t: "xʸ",  ins: "^" },
                    { t: "1/x", ins: "__recip__" }, { t: "%", ins: "%" },
                    { t: "π",   ins: "π" },   { t: "e",   ins: "e" },
                    { t: "|x|", ins: "abs(" }, { t: "eˣ", ins: "exp(" }
                ]
                CalcButton {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: modelData.t
                    fontSize: 15
                    bg: "#181820"
                    bgHover: "#24242e"
                    fg: "#9a9aa8"
                    onClicked: {
                        if (modelData.ins === "__recip__") wrapLast("1/(", ")")
                        else append(modelData.ins)
                    }
                }
            }
        }

        // ------------------------------------------------------------------
        // Standard keypad
        // ------------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: [
                    { t: "C",  k: "util" }, { t: "CE", k: "util" },
                    { t: "⌫",  k: "util" }, { t: "÷",  k: "op" },
                    { t: "7",  k: "num" }, { t: "8",   k: "num" },
                    { t: "9",  k: "num" }, { t: "×",   k: "op" },
                    { t: "4",  k: "num" }, { t: "5",   k: "num" },
                    { t: "6",  k: "num" }, { t: "−",   k: "op" },
                    { t: "1",  k: "num" }, { t: "2",   k: "num" },
                    { t: "3",  k: "num" }, { t: "+",   k: "op" },
                    { t: "±",  k: "num" }, { t: "0",   k: "num" },
                    { t: ".",  k: "num" }, { t: "=",   k: "eq" }
                ]
                CalcButton {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: modelData.t
                    fontSize: modelData.k === "eq" ? 26 : 22
                    bold: modelData.k === "eq"
                    bg: modelData.k === "op" ? "#2e2e3a"
                      : modelData.k === "util" ? utilBg
                      : modelData.k === "eq" ? accent
                      : numBg
                    bgHover: modelData.k === "eq" ? accentHover
                           : modelData.k === "util" ? utilBgHover : numBgHover
                    bgPressed: modelData.k === "eq" ? accentPressed : numBgPressed
                    fg: modelData.k === "op" ? accent
                      : modelData.k === "eq" ? "#151517" : textPrimary
                    onClicked: root.press(modelData.t)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // History drawer
    // ------------------------------------------------------------------
    Rectangle {  // dim overlay
        anchors.fill: parent
        color: "#000000"
        opacity: root.historyVisible ? 0.5 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MouseArea { anchors.fill: parent; onClicked: root.historyVisible = false }
    }

    Rectangle {
        id: drawer
        width: 300
        height: parent.height
        anchors.right: parent.right
        anchors.rightMargin: root.historyVisible ? 0 : -width
        color: "#15151b"
        Behavior on anchors.rightMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Historia"; color: textPrimary; font.pixelSize: 18; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Wyczyść"
                    color: textSecondary
                    font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { historyModel.clear(); root.syncHistory() }
                        hoverEnabled: true
                        onEntered: parent.color = textPrimary
                        onExited: parent.color = textSecondary
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: ListModel { id: historyModel }

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 54
                    radius: 8
                    color: entryArea.containsMouse ? "#22222c" : "transparent"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: expr
                            color: textSecondary
                            font.pixelSize: 13
                            elide: Text.ElideLeft
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: res
                            color: textPrimary
                            font.pixelSize: 18
                            font.bold: true
                            elide: Text.ElideLeft
                        }
                    }
                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.expression = res
                            root.lastResultRaw = raw
                            root.justEvaluated = true
                            root.updatePreview()
                            root.historyVisible = false
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: historyModel.count === 0
                    text: "Brak historii"
                    color: textSecondary
                    font.pixelSize: 14
                }
            }
        }
    }

    Component.onCompleted: {
        try {
            const saved = JSON.parse(engine.loadHistory() || "[]")
            for (const it of saved)
                if (it && it.expr !== undefined && it.res !== undefined)
                    historyModel.append({ expr: String(it.expr),
                                          res: String(it.res),
                                          raw: String(it.raw || it.res) })
        } catch (err) { /* corrupt settings → start empty */ }
    }

    // ------------------------------------------------------------------
    // Keyboard
    // ------------------------------------------------------------------
    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (root.historyVisible) { root.historyVisible = false; event.accepted = true; return }
            const t = event.text
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.press('='); return }
            if (event.key === Qt.Key_Backspace) { root.press('⌫'); return }
            if (event.key === Qt.Key_Delete)    { root.press('CE'); return }
            if (event.key === Qt.Key_Escape)    { root.press('C'); return }
            if (!t) return
            if (t >= '0' && t <= '9') append(t)
            else if (t === '+') append('+')
            else if (t === '-') append('−')
            else if (t === '*' || t === 'x') append('×')
            else if (t === '/') append('÷')
            else if (t === '^' || t === '%' || t === '.' || t === '(' || t === ')') append(t)
            else if (t === ',') append('.')
            else if (t === 'e') append('e')
            else if (t === 'p') append('π')
            else if (t === '=') root.press('=')
        }
    }
}
