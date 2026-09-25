import QtQuick
import qs.Common
import qs.DankCommon.Widgets

// A colleague's busy time on a time grid: a tint in their colour drawn
// behind every chip. It takes no clicks; hover over its uncovered part only
// reports entered/exited for a tooltip.
Item {
    id: root

    property string personColor: Theme.primary
    property string label: ""

    signal entered
    signal exited

    readonly property color resolvedColor: Theme.toColor(personColor)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusXS
        color: Theme.withAlpha(root.resolvedColor, 0.16)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 2
        color: Theme.withAlpha(root.resolvedColor, 0.8)
    }

    StyledText {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 5
        anchors.rightMargin: 2
        anchors.topMargin: 2
        visible: root.height >= 14
        text: root.label
        font.pixelSize: 10
        color: Theme.surfaceVariantText
        maximumLineCount: 1
        elide: Text.ElideRight
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onEntered: root.entered()
        onExited: root.exited()
    }
}
