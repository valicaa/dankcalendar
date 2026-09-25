import QtQuick
import qs.Common

// Shared RSVP-styled event chip/card background: fill, border, tentative hatch,
// and hover/selection state, driven by response, calendarColor, selected and
// hovered. Content (text, icons, lane layout, drag ghost, now-line) stays with
// the caller; this only owns what every chip site repeated. See Theme.rsvp* for
// the color rules this follows.
Rectangle {
    id: root

    property string response: ""
    property color calendarColor: Theme.primary
    property bool selected: false
    property bool hovered: false
    property real hatchOpacity: 0.55

    readonly property color fillColor: Theme.rsvpFillColor(response, calendarColor)
    readonly property color textColor: Theme.rsvpTextColor(response, calendarColor)
    readonly property color mutedTextColor: Theme.rsvpMutedTextColor(response, calendarColor)
    readonly property color dotColor: Theme.rsvpDotColor(response, calendarColor)
    readonly property bool strikeout: Theme.rsvpStrikeout(response)

    radius: Theme.cornerRadiusS
    color: fillColor
    border.color: selected ? Theme.primary : Theme.rsvpBorderColor(response, calendarColor)
    border.width: selected ? 2 : Theme.rsvpBorderWidth(response)

    // Selection ring: a surface-colored gap between the RSVP fill and the primary
    // outline, so selection reads even when calendarColor is close to Theme.primary.
    Rectangle {
        visible: root.selected
        anchors.fill: parent
        anchors.margins: root.border.width
        radius: Math.max(0, root.radius - root.border.width)
        color: "transparent"
        border.color: Theme.surfaceContainerHighest
        border.width: 2
    }

    // Hover as a state-layer overlay so the RSVP fill is never swapped away.
    Rectangle {
        visible: root.hovered
        anchors.fill: parent
        radius: parent.radius
        color: Theme.withAlpha(root.textColor, Theme.stateLayerHover)
    }

    TentativeHatch {
        visible: Theme.rsvpHatchVisible(root.response)
        stripeColor: root.calendarColor
        opacity: root.hatchOpacity
    }
}
