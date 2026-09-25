import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DankCommon.Widgets

Item {
    id: root

    property var events: []
    property date day: new Date()
    property var selectedEventKeys: []

    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)

    readonly property int rowHeight: 38
    readonly property int headerHeight: 40
    readonly property int maxBodyHeight: 320
    readonly property int popoverWidth: 300

    function isEventSelected(event) {
        return selectedEventKeys.indexOf(DankCalService.eventKey(event)) !== -1;
    }

    function show(forDay, dayEvents, item) {
        if (!item)
            return;

        let contentItem = item.Window?.window?.contentItem;
        if (!contentItem) {
            let current = item;
            while (current) {
                if (current.Window?.window?.contentItem) {
                    contentItem = current.Window.window.contentItem;
                    break;
                }
                current = current.parent;
            }
        }
        if (!contentItem)
            return;

        root.day = forDay;
        root.events = dayEvents;
        popup.parent = contentItem;

        const bodyHeight = Math.min(maxBodyHeight, Math.max(rowHeight, dayEvents.length * rowHeight));
        const popoverHeight = headerHeight + bodyHeight + popup.topPadding + popup.bottomPadding;

        const itemPos = item.mapToItem(contentItem, 0, 0);
        const parentWidth = contentItem.width;
        const parentHeight = contentItem.height;
        const side = _bestSide(itemPos, item, parentWidth, parentHeight, popoverHeight);

        let targetX = 0;
        let targetY = 0;
        switch (side) {
        case "left":
            targetX = itemPos.x - popoverWidth - 8;
            targetY = itemPos.y;
            break;
        case "right":
            targetX = itemPos.x + item.width + 8;
            targetY = itemPos.y;
            break;
        case "top":
            targetX = itemPos.x + (item.width - popoverWidth) / 2;
            targetY = itemPos.y - popoverHeight - 8;
            break;
        case "bottom":
        default:
            targetX = itemPos.x + (item.width - popoverWidth) / 2;
            targetY = itemPos.y + item.height + 8;
            break;
        }

        popup.width = popoverWidth;
        popup.height = popoverHeight;
        popup.x = Math.max(4, Math.min(parentWidth - popoverWidth - 4, targetX));
        popup.y = Math.max(4, Math.min(parentHeight - popoverHeight - 4, targetY));
        popup.open();
    }

    function _bestSide(itemPos, item, parentWidth, parentHeight, popoverHeight) {
        if (parentWidth - (itemPos.x + item.width) >= popoverWidth + 16)
            return "right";
        if (itemPos.x >= popoverWidth + 16)
            return "left";
        if (parentHeight - (itemPos.y + item.height) >= popoverHeight + 16)
            return "bottom";
        return "top";
    }

    function hide() {
        popup.close();
    }

    Popup {
        id: popup

        padding: Theme.spacingS
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnReleaseOutside
        modal: false
        dim: false

        background: Rectangle {
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadiusM
        }

        contentItem: Column {
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                height: root.headerHeight - Theme.spacingXS
                text: SettingsData.formatDate(root.day, "dddd, MMMM d")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                verticalAlignment: Text.AlignVCenter
            }

            DankListView {
                width: parent.width
                height: popup.height - root.headerHeight - popup.topPadding - popup.bottomPadding
                clip: true
                spacing: 2
                model: ScriptModel {
                    values: root.events
                }
                // model rows are {isOverlay, event} wrappers (MonthView.mergeDayItems):
                // an own event row stays fully interactive; a colleague row
                // (PersonEventChip) is read-only, matching the month cells.
                delegate: Item {
                    id: rowDelegate
                    required property var modelData
                    readonly property bool isOverlay: modelData.isOverlay
                    readonly property var ev: modelData.event
                    readonly property var stripeColors: !isOverlay && PeopleService.active ? PeopleService.stripesFor(ev) : []
                    width: ListView.view.width
                    height: root.rowHeight - Theme.groupedListGap

                    EventChipBackground {
                        id: eventRow
                        visible: !rowDelegate.isOverlay
                        anchors.fill: parent
                        radius: Theme.cornerRadiusXS
                        response: rowDelegate.isOverlay ? "" : rowDelegate.ev.myResponse
                        calendarColor: rowDelegate.isOverlay ? Theme.primary : rowDelegate.ev.color
                        selected: !rowDelegate.isOverlay && root.isEventSelected(rowDelegate.ev)
                        dimmed: !rowDelegate.isOverlay && PeopleService.active && rowDelegate.stripeColors.length === 0
                        hovered: !rowDelegate.isOverlay && rowHover.containsMouse

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingXS
                            anchors.rightMargin: rowDelegate.stripeColors.length > 0 ? rowDelegate.stripeColors.length * 3 + Theme.spacingXS + 4 : Theme.spacingXS
                            spacing: Theme.spacingS

                            Rectangle {
                                width: 3
                                height: 22
                                radius: Theme.fullRadius(width, height)
                                color: eventRow.dotColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 64
                                text: rowDelegate.isOverlay ? "" : (rowDelegate.ev.allDay ? I18n.tr("All day", "all-day marker in the month day-detail popover") : SettingsData.formatTime(rowDelegate.ev.start))
                                font.pixelSize: Theme.fontSizeSmall
                                color: eventRow.mutedTextColor
                                isMonospace: true
                                elide: Text.ElideRight
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 3 - 64 - Theme.spacingS * 2
                                text: rowDelegate.isOverlay ? "" : rowDelegate.ev.title
                                font.pixelSize: Theme.fontSizeSmall
                                color: eventRow.textColor
                                font.strikeout: eventRow.strikeout
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        AttendeeStripes {
                            visible: rowDelegate.stripeColors.length > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 3
                            anchors.topMargin: 3
                            anchors.bottomMargin: 3
                            compact: true
                            colors: rowDelegate.stripeColors
                        }

                        MouseArea {
                            id: rowHover
                            enabled: !rowDelegate.isOverlay
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    root.eventContextRequested(rowDelegate.ev, eventRow, mouse.x, mouse.y);
                                    return;
                                }
                                root.eventClicked(rowDelegate.ev, mouse.modifiers);
                                if ((mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier)) === 0)
                                    popup.close();
                            }
                        }
                    }

                    Row {
                        visible: rowDelegate.isOverlay
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingXS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            text: rowDelegate.isOverlay ? (rowDelegate.ev.allDay ? I18n.tr("All day", "all-day marker in the month day-detail popover") : SettingsData.formatTime(rowDelegate.ev.start)) : ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            isMonospace: true
                            elide: Text.ElideRight
                        }

                        PersonEventChip {
                            id: colleagueRow
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 64 - Theme.spacingS
                            height: parent.height
                            kind: rowDelegate.isOverlay ? rowDelegate.ev.kind : "event"
                            title: rowDelegate.isOverlay ? rowDelegate.ev.title : ""
                            location: rowDelegate.isOverlay ? rowDelegate.ev.location : ""
                            personColor: rowDelegate.isOverlay ? rowDelegate.ev.color : Theme.primary
                            isPrivate: rowDelegate.isOverlay && !!rowDelegate.ev.private
                            stripes: rowDelegate.isOverlay ? (rowDelegate.ev.stripes || []) : []
                            compact: true
                            titleLines: 1
                        }
                    }
                }
            }
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: Theme.shorterDuration
                easing.type: Theme.standardEasing
            }
        }
    }
}
