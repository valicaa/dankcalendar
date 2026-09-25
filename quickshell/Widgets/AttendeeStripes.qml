import QtQuick
import qs.Common

// One colour bar per participant of a merged meeting (PeopleService.stripesFor
// for a shared own event, or a colleague-colleague merge group's own
// `stripes`). Renders nothing for an unmerged item (0 or 1 colors) - a
// single-participant item carries no stripe at all, matching PeopleService's
// contract that stripes are only ever populated for an actual merge.
//
// Drawn on the chip's trailing (right) edge everywhere it's used, never the
// leading edge: PersonEventChip's own "busy" indicator bar already owns the
// left edge, and #22's RSVP treatment (fill/border/hatch/strikeout) reads
// evenly around the whole chip rather than favoring one edge, so the right
// edge is the only side free to carry a second signal.
//
// Bars sit on a Theme.surface backing panel so a same-colored bar against a
// same-colored chip fill still separates from it, rather than a bar drawn
// directly on the fill (Theme.attendeeStripesWidth mirrors this sizing for
// callers that reserve room for it in a chip's text layout).
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
