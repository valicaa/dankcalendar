import QtQuick
import qs.Common
import qs.DankCommon.Widgets

// One colleague-lookup chip in the sidebar People search (PeopleService).
// Shows the lookup status; clicking an "error" chip retries it.
StyledRect {
    id: root

    required property var person

    signal removed
    signal retried

    readonly property bool isError: person.status === "error"
    readonly property bool isUnavailable: person.status === "unavailable"
    readonly property bool isReconnect: person.status === "reconnect"
    readonly property bool isLoading: person.status === "loading"
    readonly property string label: person.name || person.email

    color: Theme.surfaceContainerHigh
    radius: Theme.cornerRadiusL
    implicitWidth: chipRow.implicitWidth + Theme.spacingM * 2
    implicitHeight: Theme.buttonHeightXS

    DankTooltipV2 {
        id: tooltip
    }

    MouseArea {
        id: retryArea
        anchors.fill: parent
        enabled: root.isError
        cursorShape: root.isError ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: true
        onClicked: root.retried()
        onEntered: tooltip.show(root.isError ? root.person.error : root.person.email, root)
        onExited: tooltip.hide()
    }

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: Theme.spacingXS

        Rectangle {
            width: Theme.spacingS
            height: Theme.spacingS
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.isUnavailable ? Theme.surfaceVariantText : Theme.toColor(root.person.color)
        }

        DankSpinner {
            visible: root.isLoading
            size: Theme.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }

        DankIcon {
            visible: root.isUnavailable
            name: "block"
            size: Theme.iconSizeSmall
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        DankIcon {
            visible: root.isError
            name: "warning"
            size: Theme.iconSizeSmall
            color: Theme.error
            anchors.verticalCenter: parent.verticalCenter
        }

        DankIcon {
            visible: root.isReconnect
            name: "sync_problem"
            size: Theme.iconSizeSmall
            color: Theme.error
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.isUnavailable ? I18n.tr("Unavailable", "person chip status label when a colleague's schedule cannot be read") : root.label
            font.pixelSize: Theme.fontSizeSmall
            color: root.isUnavailable ? Theme.surfaceVariantText : Theme.surfaceText
            elide: Text.ElideRight
            maximumLineCount: 1
            width: Math.min(implicitWidth, 140)
        }

        DankActionButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.iconSizeMedium
            iconSize: Theme.iconSizeSmall
            iconName: "close"
            tooltipText: I18n.tr("Remove", "person chip button to remove a colleague from the schedule search")
            onClicked: root.removed()
        }
    }
}
