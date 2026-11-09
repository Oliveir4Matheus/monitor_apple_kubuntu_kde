import QtQuick

Item {
    id: root

    property real value: 0
    property color color: "#BF5AF2"
    property color trackColor: Qt.rgba(1, 1, 1, 0.10)
    implicitHeight: 4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
    }

    Rectangle {
        height: parent.height
        radius: height / 2
        color: root.color
        width: root.value <= 0
            ? 0
            : Math.max(parent.height, parent.width * Math.min(100, Math.max(0, root.value)) / 100)
        Behavior on width {
            NumberAnimation { duration: 550; easing.type: Easing.OutCubic }
        }
    }
}
