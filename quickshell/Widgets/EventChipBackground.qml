import QtQuick
import qs.Common

// Shared RSVP-styled event chip/card background. See Theme.rsvp* for the color rules.
Rectangle {
    id: root

    property string response: ""
    property color calendarColor: Theme.primary
    property bool selected: false
    property bool hovered: false
    property real hatchOpacity: 0.55
    // Faded under a colleague overlay: fill, border and hatch are scaled to
    // Theme.overlayDimOpacity; text stays opaque, with its colour picked
    // against the dimmed fill so it stays legible.
    property bool dimmed: false

    readonly property real backgroundOpacity: dimmed ? Theme.overlayDimOpacity : 1
    readonly property color _contrastBg: dimmed ? Theme.overlayDimComposite(calendarColor) : Theme.toColor(calendarColor)

    readonly property color fillColor: Theme.blendAlpha(Theme.rsvpFillColor(response, calendarColor), backgroundOpacity)
    readonly property color textColor: dimmed ? Theme.rsvpTextColorAgainst(response, _contrastBg) : Theme.rsvpTextColor(response, calendarColor)
    readonly property color mutedTextColor: dimmed ? Theme.rsvpMutedTextColorAgainst(response, _contrastBg) : Theme.rsvpMutedTextColor(response, calendarColor)
    readonly property color dotColor: dimmed ? Theme.rsvpDotColorAgainst(response, _contrastBg, calendarColor) : Theme.rsvpDotColor(response, calendarColor)
    readonly property bool strikeout: Theme.rsvpStrikeout(response)
    // Short chips (month/all-day, ~18-32px) get a 1px ring so it doesn't crowd the text.
    property bool compact: height < 24
    readonly property int ringWidth: compact ? 1 : 2

    radius: Theme.cornerRadiusS
    color: fillColor
    border.color: Theme.blendAlpha(selected ? Theme.primary : Theme.rsvpBorderColor(response, calendarColor), backgroundOpacity)
    border.width: selected ? ringWidth : 1

    TentativeHatch {
        visible: Theme.rsvpHatchVisible(root.response)
        anchors.fill: parent
        anchors.margins: Math.max(root.border.width, root.radius * 0.3)
        stripeColor: root.calendarColor
        opacity: root.hatchOpacity * root.backgroundOpacity
    }

    // Selection ring: a surface-colored gap between the RSVP fill and the primary
    // outline, so selection reads even when calendarColor is close to Theme.primary.
    Rectangle {
        visible: root.selected
        anchors.fill: parent
        anchors.margins: root.border.width
        radius: Math.max(0, root.radius - root.border.width)
        color: "transparent"
        border.color: Theme.surfaceContainerHighest
        border.width: root.ringWidth
    }

    // Hover as a state-layer overlay so the RSVP fill is never swapped away.
    Rectangle {
        visible: root.hovered
        anchors.fill: parent
        radius: parent.radius
        color: Theme.withAlpha(root.textColor, Theme.stateLayerHover)
    }
}
