import QtQuick
import qs.Common
import qs.DankCommon.Widgets

// One colleague-schedule overlay item, drawn on top of the owner's faded own
// chips in Week/Month (PeopleService.overlayForDay). Read-only: no
// EventMouseArea, so it cannot be clicked, dragged, selected or opened;
// hovering only shows a tooltip via the entered/exited signals.
Item {
    id: root

    property string kind: "event" // "event" | "busy"
    property string title: ""
    property string location: ""
    property string personColor: Theme.primary
    // Set for a detail event whose title the source didn't disclose (a
    // private event under reader access); it reads the same as a
    // free/busy-only block.
    property bool isPrivate: false
    property bool compact: false
    property int titleLines: 1

    signal entered
    signal exited

    readonly property color resolvedColor: Theme.toColor(personColor)
    readonly property bool busyLook: kind !== "event" || isPrivate
    readonly property color fillColor: busyLook ? Theme.withAlpha(resolvedColor, 0.18) : Theme.rsvpFillColor("", resolvedColor)
    readonly property color textColor: busyLook ? Theme.surfaceText : Theme.rsvpTextColor("", resolvedColor)

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

        Column {
            anchors.fill: parent
            anchors.leftMargin: root.busyLook ? 7 : 4
            anchors.rightMargin: 4
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            spacing: 2

            StyledText {
                width: parent.width
                text: root.busyLook ? I18n.tr("Busy", "overlay label for a colleague's free/busy-only or private time block") : root.title
                font.pixelSize: 11
                font.weight: Theme.fontWeightMedium
                color: root.textColor
                wrapMode: Text.WordWrap
                maximumLineCount: root.titleLines
                elide: Text.ElideRight
            }

            StyledText {
                visible: !root.busyLook && !root.compact && text !== ""
                text: root.location
                font.pixelSize: 10
                color: Theme.withAlpha(root.textColor, 0.75)
                width: parent.width
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    HoverHandler {
        onHoveredChanged: hovered ? root.entered() : root.exited()
    }
}
