import QtQuick

Item {
    id: root

    property string text: ""
    property color bg: "#26262f"
    property color bgHover: "#33333f"
    property color bgPressed: "#454552"
    property color fg: "#ffffff"
    property int fontSize: 22
    property bool bold: false

    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) * 0.24
        color: mouseArea.pressed ? root.bgPressed
             : mouseArea.containsMouse ? root.bgHover
             : root.bg
        border.width: 1
        border.color: "#0dffffff"
        scale: mouseArea.pressed ? 0.94 : 1.0

        Behavior on color { ColorAnimation { duration: 80 } }
        Behavior on scale { NumberAnimation { duration: 60; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: root.text
            color: root.fg
            font.pixelSize: root.fontSize
            font.bold: root.bold
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
