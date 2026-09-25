import QtQuick
import qs.Common

// One colour bar per participant of a merged meeting (PeopleService.stripesFor
// for a shared own event, or a colleague-colleague merge group's own
// `stripes`). The caller anchors this Row to a chip's trailing edge and
// binds its height; it renders nothing when colors is empty.
Row {
    id: root

    property var colors: []
    property bool compact: false

    readonly property real barWidth: compact ? 2 : 3

    spacing: 1

    Repeater {
        model: root.colors

        Rectangle {
            required property var modelData
            width: root.barWidth
            height: root.height
            color: Theme.toColor(modelData)
        }
    }
}
