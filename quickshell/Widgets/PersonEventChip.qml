import QtQuick
import qs.Common
import qs.DankCommon.Widgets

// A colleague-schedule overlay item (PeopleService). Read-only: it swallows
// presses so nothing under it is clicked or created, and only reports hover.
Item {
    id: root

    property string kind: "event" // "event" | "busy"
    property string title: ""
    property string location: ""
    property string personColor: Theme.primary
    // A detail event whose title the source withheld; drawn like busy time.
    property bool isPrivate: false
    property bool compact: false
    property int titleLines: 1
    property real titleFontSize: 11
    property real locationFontSize: 10
    // Every participant's colour when this item merges a shared meeting.
    property var stripes: []

    signal entered
    signal exited

    readonly property color resolvedColor: Theme.toColor(personColor)
    readonly property bool busyLook: kind !== "event" || isPrivate
    // Busy time is an opaque tint so an own chip underneath never shows its
    // title through; the dimmed own chip still shows wherever it is not covered.
    readonly property color fillColor: busyLook ? Qt.tint(Theme.surface, Theme.withAlpha(resolvedColor, 0.18)) : Theme.rsvpFillColor("", resolvedColor)
    readonly property color textColor: busyLook ? Theme.surfaceText : Theme.rsvpTextColor("", resolvedColor)
    readonly property real stripesWidth: Theme.attendeeStripesWidth(stripes.length, compact)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusS
        color: root.fillColor
        border.color: root.resolvedColor
        border.width: 1
        clip: true

        Rectangle {
            visible: root.busyLook
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3
            color: root.resolvedColor
        }

        AttendeeStripes {
            visible: root.stripes.length > 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.rightMargin: 3
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            colors: root.stripes
            compact: root.compact
        }

        Column {
            anchors.fill: parent
            anchors.leftMargin: root.busyLook ? 7 : 4
            anchors.rightMargin: root.stripes.length > 1 ? root.stripesWidth + 7 : 4
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            spacing: 2

            StyledText {
                width: parent.width
                text: root.title
                font.pixelSize: root.titleFontSize
                font.weight: Theme.fontWeightMedium
                color: root.textColor
                wrapMode: Text.WordWrap
                maximumLineCount: root.titleLines
                elide: Text.ElideRight
            }

            StyledText {
                visible: !root.busyLook && !root.compact && text !== ""
                text: root.location
                font.pixelSize: root.locationFontSize
                color: Theme.withAlpha(root.textColor, 0.75)
                width: parent.width
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onEntered: root.entered()
        onExited: root.exited()
    }
}
