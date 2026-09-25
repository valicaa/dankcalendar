import QtQuick
import qs.Common

// One colour bar per participant of a shared meeting, on the chip's trailing
// edge (the leading edge carries the busy bar). Hidden for fewer than two.
// The Theme.surface panel keeps a bar visible on a fill of the same colour;
// Theme.attendeeStripesWidth must match this sizing.
Item {
    id: root

    property var colors: []
    property bool compact: false

    readonly property real barWidth: compact ? 3 : 4
    readonly property real panelPadding: 2

    visible: colors.length > 1
    width: Theme.attendeeStripesWidth(colors.length, compact)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusXXS
        color: Theme.surface
    }

    Row {
        anchors.centerIn: parent
        spacing: 1

        Repeater {
            model: root.colors

            Rectangle {
                required property var modelData
                width: root.barWidth
                height: root.height - root.panelPadding * 2
                radius: 1
                color: Theme.toColor(modelData)
            }
        }
    }
}
