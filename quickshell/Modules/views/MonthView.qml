import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DankCommon.Widgets

Item {
    id: root

    property date displayDate: new Date()
    property date today: new Date()
    property date selectedDate: new Date()
    property int eventsVersion: 0
    property var selectedEventKeys: []

    signal daySelected(date day)
    signal dayActivated(date day)
    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)
    signal dayContextRequested(date day, var anchorItem, real x, real y)
    signal eventDropRequested(var event, date targetDay)
    signal viewDayRequested(date day)
    signal previousRequested
    signal nextRequested
    signal createRangeRequested(date startDay, date endDay)

    property bool dragSelecting: false
    property real dragAnchorTime: 0
    property real dragRangeStart: 0
    property real dragRangeEnd: 0
    property real keyRangeStart: 0
    property real keyRangeEnd: 0
    property bool eventPointerDown: false
    property bool eventDragging: false
    property var draggedEvent: null
    property real dragTargetTime: 0
    property point dragPosition: Qt.point(0, 0)

    readonly property bool previewActive: dragSelecting || keyRangeStart > 0
    readonly property real previewStart: dragSelecting ? dragRangeStart : keyRangeStart
    readonly property real previewEnd: dragSelecting ? dragRangeEnd : keyRangeEnd

    function isEventSelected(event) {
        return selectedEventKeys.indexOf(DankCalService.eventKey(event)) !== -1;
    }

    function updateEventDrag(pointerItem, x, y) {
        const gridPosition = pointerItem.mapToItem(grid, x, y);
        const rootPosition = pointerItem.mapToItem(root, x, y);
        dragPosition = Qt.point(rootPosition.x, rootPosition.y);
        if (gridPosition.x < 0 || gridPosition.x >= grid.width || gridPosition.y < 0 || gridPosition.y >= grid.height) {
            dragTargetTime = 0;
            return;
        }
        const target = rangeDrag.dateAt(gridPosition);
        dragTargetTime = target ? target.getTime() : 0;
    }

    function finishEventDrag(event) {
        const targetTime = dragTargetTime;
        eventPointerDown = false;
        eventDragging = false;
        draggedEvent = null;
        dragTargetTime = 0;
        if (targetTime > 0)
            eventDropRequested(event, new Date(targetTime));
    }

    Timer {
        id: scrollCooldown
        interval: 100
        onTriggered: wheelHandler.scrollInProgress = false
    }

    WheelHandler {
        id: wheelHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        // Touchpad reports large continuous angleDelta, so it needs a much
        // higher threshold than a mouse wheel's discrete 120-unit notches.
        readonly property int touchpadThreshold: 500
        readonly property int mouseThreshold: 120
        property real touchpadAccumulator: 0
        property real mouseAccumulator: 0
        property bool scrollInProgress: false

        function step(direction) {
            if (direction < 0)
                root.previousRequested();
            else
                root.nextRequested();
            scrollInProgress = true;
            scrollCooldown.restart();
        }

        onWheel: event => {
            if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)) {
                event.accepted = false;
                return;
            }

            event.accepted = true;

            if (scrollInProgress)
                return;

            const delta = event.angleDelta.y;
            const isTouchpad = event.pixelDelta && event.pixelDelta.y !== 0;

            if (isTouchpad) {
                touchpadAccumulator += delta;
                if (Math.abs(touchpadAccumulator) < touchpadThreshold)
                    return;
                step(touchpadAccumulator > 0 ? -1 : 1);
                touchpadAccumulator = 0;
                return;
            }

            mouseAccumulator += delta;
            if (Math.abs(mouseAccumulator) < mouseThreshold)
                return;
            step(mouseAccumulator > 0 ? -1 : 1);
            mouseAccumulator = 0;
        }
    }

    Connections {
        target: DankCalService
        function onEventsUpdated() {
            root.eventsVersion++;
        }
    }

    DankTooltipV2 {
        id: chipTooltip
    }

    MonthDayPopover {
        id: dayPopover
        selectedEventKeys: root.selectedEventKeys
        onEventClicked: (ev, modifiers) => root.eventClicked(ev, modifiers)
        onEventContextRequested: (ev, anchorItem, x, y) => root.eventContextRequested(ev, anchorItem, x, y)
    }

    function eventTooltip(ev) {
        if (ev.allDay)
            return ev.title + " · " + I18n.tr("All day", "all-day marker in event tooltip") + (ev.calendar ? " · " + ev.calendar : "");
        return ev.title + " · " + SettingsData.formatTime(ev.start) + " – " + SettingsData.formatTime(ev.end) + (ev.calendar ? " · " + ev.calendar : "");
    }

    function overlayPersonLabel(item) {
        const person = PeopleService.people.find(p => p.email === item.email);
        return (person && (person.name || person.email)) || item.email;
    }

    function overlayTooltip(item) {
        const title = item.title || I18n.tr("Busy", "overlay label for a colleague's free/busy-only or private time block");
        const suffix = " · " + root.overlayPersonLabel(item);
        if (item.allDay)
            return title + " · " + I18n.tr("All day", "all-day marker in event tooltip") + suffix;
        return title + " · " + SettingsData.formatTime(item.start) + " – " + SettingsData.formatTime(item.end) + suffix;
    }

    // Colleague-schedule overlay for one cell, drawn on top of the (faded)
    // own chips rather than pushed below them.
    function overlayEventsFor(day) {
        if (!PeopleService.active)
            return [];
        return PeopleService.overlayForDay(day);
    }

    // A Month cell is a list, not a time grid, so "colleague on top" means
    // ordering, not overlap: one merged list of {isOverlay, event} wrappers,
    // all-day first, then timed items interleaved by start time (colleague
    // first on a tie). A shared meeting is never listed twice: the colleague
    // copy of an event that matches one of the owner's own occurrences is
    // already dropped by PeopleService.overlayForDay (section 4), so
    // ownEvents is drawn in full here, undimmed and carrying stripes via
    // PeopleService.stripesFor where it's shared.
    function mergeDayItems(ownEvents, overlayEvents) {
        const own = ownEvents.map(ev => ({
                    "isOverlay": false,
                    "event": ev
                }));
        const colleague = overlayEvents.map(ev => ({
                    "isOverlay": true,
                    "event": ev
                }));
        const allDayItems = own.filter(i => i.event.allDay).concat(colleague.filter(i => i.event.allDay));
        const timed = own.filter(i => !i.event.allDay).concat(colleague.filter(i => !i.event.allDay));
        timed.sort((a, b) => {
            const dt = a.event.start.getTime() - b.event.start.getTime();
            if (dt !== 0)
                return dt;
            if (a.isOverlay === b.isOverlay)
                return 0;
            return a.isOverlay ? -1 : 1;
        });
        return allDayItems.concat(timed);
    }

    readonly property int firstDayOfWeek: SettingsData.effectiveFirstDayOfWeek
    readonly property real weekGutter: SettingsData.showWeekNumbers ? 28 : 0
    readonly property real eventChipHeight: Math.max(18, SettingsData.monthEventTitleLines * 14 + 4)

    function isoWeekNumber(d) {
        const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const dayNum = date.getUTCDay() || 7;
        date.setUTCDate(date.getUTCDate() + 4 - dayNum);
        const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
        return Math.ceil(((date - yearStart) / 86400000 + 1) / 7);
    }

    readonly property int gridYear: displayDate.getFullYear()
    readonly property int gridMonth: displayDate.getMonth()

    readonly property date firstOfMonth: {
        const d = new Date(gridYear, gridMonth, 1);
        return d;
    }

    readonly property int leadingDays: {
        const offset = firstOfMonth.getDay() - firstDayOfWeek;
        return offset < 0 ? offset + 7 : offset;
    }

    function isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function cellDate(index) {
        return new Date(gridYear, gridMonth, 1 + index - leadingDays);
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Row {
            width: parent.width
            height: 32

            Item {
                width: root.weekGutter
                height: parent.height
            }

            Repeater {
                model: 7
                Item {
                    required property int index
                    width: (parent.width - root.weekGutter) / 7
                    height: parent.height

                    StyledText {
                        anchors.centerIn: parent
                        text: SettingsData.dayName((index + root.firstDayOfWeek) % 7)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: parent.height - 32

            Column {
                visible: SettingsData.showWeekNumbers
                width: root.weekGutter

                Repeater {
                    model: 6

                    Item {
                        required property int index
                        width: parent.width
                        height: grid.cellHeight

                        StyledText {
                            anchors.centerIn: parent
                            // ISO weeks are Monday-based; the row's 4th day avoids
                            // ambiguity when the grid starts on another day
                            text: root.isoWeekNumber(root.cellDate(index * 7 + 3))
                            font.pixelSize: 10
                            color: Theme.surfaceVariantText
                            isMonospace: true
                        }
                    }
                }
            }

            Grid {
                id: grid
                width: parent.width - root.weekGutter
                height: parent.height
                columns: 7
                rows: 6

                readonly property real cellWidth: width / columns
                readonly property real cellHeight: height / rows

                DragHandler {
                    id: rangeDrag
                    enabled: !root.eventPointerDown && !root.eventDragging

                    function dateAt(pos) {
                        const x = Math.min(Math.max(pos.x, 0), grid.width - 1);
                        const y = Math.min(Math.max(pos.y, 0), grid.height - 1);
                        const cell = grid.childAt(x, y);
                        if (!cell || cell.cellDate === undefined)
                            return null;
                        return cell.cellDate;
                    }

                    target: null

                    onActiveChanged: {
                        if (active) {
                            const anchor = dateAt(centroid.pressPosition);
                            if (!anchor)
                                return;
                            root.dragAnchorTime = anchor.getTime();
                            root.dragRangeStart = root.dragAnchorTime;
                            root.dragRangeEnd = root.dragAnchorTime;
                            root.dragSelecting = true;
                            return;
                        }
                        if (!root.dragSelecting)
                            return;
                        root.dragSelecting = false;
                        root.createRangeRequested(new Date(root.dragRangeStart), new Date(root.dragRangeEnd));
                    }
                    onTranslationChanged: {
                        if (!active || !root.dragSelecting)
                            return;
                        const hover = dateAt(centroid.position);
                        if (!hover)
                            return;
                        root.dragRangeStart = Math.min(root.dragAnchorTime, hover.getTime());
                        root.dragRangeEnd = Math.max(root.dragAnchorTime, hover.getTime());
                    }
                }

                Repeater {
                    model: 42

                    Item {
                        id: dayCell
                        required property int index

                        readonly property date cellDate: root.cellDate(index)
                        readonly property bool inCurrentMonth: cellDate.getMonth() === root.gridMonth
                        readonly property bool isToday: root.isSameDay(cellDate, root.today)
                        readonly property bool isSelected: root.isSameDay(cellDate, root.selectedDate)
                        readonly property bool inPreviewRange: root.previewActive && cellDate.getTime() >= root.previewStart && cellDate.getTime() <= root.previewEnd
                        readonly property bool isDropTarget: root.eventDragging && cellDate.getTime() === root.dragTargetTime
                        readonly property bool previewLeading: inPreviewRange && cellDate.getTime() === (I18n.isRtl ? root.previewEnd : root.previewStart)
                        readonly property bool previewTrailing: inPreviewRange && cellDate.getTime() === (I18n.isRtl ? root.previewStart : root.previewEnd)
                        readonly property var cellEvents: {
                            root.eventsVersion;
                            return DankCalService.eventsForDay(cellDate);
                        }
                        readonly property var cellOverlayEvents: {
                            root.eventsVersion;
                            PeopleService.version;
                            return root.overlayEventsFor(cellDate);
                        }

                        readonly property var mergedItems: root.mergeDayItems(cellEvents, cellOverlayEvents)

                        // On today, items that have already ended yield their
                        // chip slots to ones still upcoming; they fall into the
                        // "+N more" overflow rather than being shown first.
                        readonly property var displayItems: {
                            if (!isToday)
                                return mergedItems;
                            const now = root.today.getTime();
                            const upcoming = [];
                            const ended = [];
                            for (let i = 0; i < mergedItems.length; i++) {
                                const item = mergedItems[i];
                                if (item.event.allDay || item.event.end.getTime() > now)
                                    upcoming.push(item);
                                else
                                    ended.push(item);
                            }
                            return upcoming.concat(ended);
                        }

                        // When showing all events, chips fill whatever space is available
                        // below the day badge; otherwise fall back to a 3-chip cap anchored
                        // at the bottom, matching the classic "+N more" layout.
                        readonly property int maxChips: SettingsData.monthShowAllEvents ? Math.max(0, Math.floor((height - 36 - Theme.spacingXS * 2 - 14) / (root.eventChipHeight + 2))) : Math.max(0, Math.min(3, Math.floor((height - 50) / (root.eventChipHeight + 2))))

                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.gridLine
                        }

                        Rectangle {
                            visible: parent.isSelected
                            anchors.fill: parent
                            anchors.margins: 1
                            color: Theme.primaryBackground
                            border.color: Theme.primary
                            border.width: 1
                            radius: Theme.cornerRadiusXXS
                        }

                        Rectangle {
                            visible: dayCell.isDropTarget
                            anchors.fill: parent
                            anchors.margins: 2
                            color: Theme.withAlpha(Theme.primary, 0.12)
                            border.color: Theme.primary
                            border.width: 2
                            radius: Theme.cornerRadiusXXS
                            z: 4
                        }

                        Rectangle {
                            visible: dayCell.inPreviewRange
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 38
                            anchors.leftMargin: dayCell.previewLeading ? 2 : 0
                            anchors.rightMargin: dayCell.previewTrailing ? 2 : 0
                            height: root.eventChipHeight
                            color: Theme.primary
                            topLeftRadius: dayCell.previewLeading ? Theme.cornerRadiusXXS : 0
                            bottomLeftRadius: dayCell.previewLeading ? Theme.cornerRadiusXXS : 0
                            topRightRadius: dayCell.previewTrailing ? Theme.cornerRadiusXXS : 0
                            bottomRightRadius: dayCell.previewTrailing ? Theme.cornerRadiusXXS : 0
                            z: 3

                            StyledText {
                                visible: dayCell.cellDate.getTime() === root.previewStart
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("New event", "placeholder label on the event span shown while selecting days in the month grid")
                                font.pixelSize: 11
                                color: Theme.primaryText
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - 12)
                            }
                        }

                        Item {
                            id: dayBadge
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.topMargin: Theme.spacingS
                            anchors.leftMargin: Theme.spacingS
                            width: 28
                            height: 28
                            z: 2

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.fullRadius(width, height)
                                color: Theme.primary
                                visible: parent.parent.isToday
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: parent.parent.cellDate.getDate()
                                font.pixelSize: parent.parent.isToday ? Theme.fontSizeMedium : Theme.fontSizeSmall
                                font.weight: parent.parent.isToday ? Theme.fontWeightMedium : Theme.fontWeight
                                color: {
                                    if (parent.parent.isToday)
                                        return Theme.primaryText;
                                    if (!parent.parent.inCurrentMonth)
                                        return Theme.surfaceVariantText;
                                    return Theme.surfaceText;
                                }
                                opacity: parent.parent.inCurrentMonth ? 1.0 : 0.5
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    mouse.accepted = true;
                                    root.viewDayRequested(dayCell.cellDate);
                                }
                            }
                        }

                        // One merged list per cell (mergedItems/displayItems):
                        // colleague items (full colour) and remaining own
                        // items (dimmed), interleaved by start time. Each
                        // delegate carries both chip kinds and shows only the
                        // one that matches its item.
                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: SettingsData.monthShowAllEvents ? dayBadge.bottom : undefined
                            anchors.bottom: SettingsData.monthShowAllEvents ? undefined : parent.bottom
                            anchors.margins: Theme.spacingXS
                            spacing: 2
                            clip: true
                            // Above the cell's day-select MouseArea so chip clicks win.
                            z: 1

                            Repeater {
                                model: ScriptModel {
                                    values: dayCell.displayItems.slice(0, dayCell.maxChips)
                                }

                                Item {
                                    id: chipDelegate
                                    required property var modelData
                                    readonly property bool isOverlay: modelData.isOverlay
                                    readonly property var ev: modelData.event
                                    readonly property var stripeColors: !isOverlay && PeopleService.active ? PeopleService.stripesFor(ev) : []
                                    width: parent.width
                                    height: root.eventChipHeight

                                    EventChipBackground {
                                        id: ownChip
                                        visible: !chipDelegate.isOverlay
                                        anchors.fill: parent
                                        radius: Theme.cornerRadiusXS
                                        clip: true
                                        compact: true
                                        response: chipDelegate.isOverlay ? "" : chipDelegate.ev.myResponse
                                        calendarColor: chipDelegate.isOverlay ? Theme.primary : chipDelegate.ev.color
                                        selected: !chipDelegate.isOverlay && root.isEventSelected(chipDelegate.ev)
                                        dimmed: !chipDelegate.isOverlay && PeopleService.active && chipDelegate.stripeColors.length === 0
                                        hovered: !chipDelegate.isOverlay && chipMouseArea.containsMouse

                                        Row {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: chipDelegate.stripeColors.length > 0 ? chipDelegate.stripeColors.length * 3 + 6 : 4
                                            spacing: 4

                                            Rectangle {
                                                width: 3
                                                height: 12
                                                radius: Theme.fullRadius(width, height)
                                                color: parent.parent.dotColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: chipDelegate.isOverlay ? "" : chipDelegate.ev.title
                                                font.pixelSize: 11
                                                color: parent.parent.textColor
                                                font.strikeout: parent.parent.strikeout
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: SettingsData.monthEventTitleLines
                                                elide: Text.ElideRight
                                                width: parent.width - 10
                                            }
                                        }

                                        AttendeeStripes {
                                            visible: chipDelegate.stripeColors.length > 0
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: 3
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 2
                                            compact: true
                                            colors: chipDelegate.stripeColors
                                        }

                                        EventMouseArea {
                                            id: chipMouseArea
                                            enabled: !chipDelegate.isOverlay
                                            anchors.fill: parent
                                            eventData: chipDelegate.ev
                                            dragEnabled: !chipDelegate.isOverlay && !chipDelegate.ev.readOnly
                                            onEntered: chipTooltip.show(root.eventTooltip(chipDelegate.ev), ownChip)
                                            onExited: chipTooltip.hide()
                                            onActivated: (event, modifiers) => {
                                                chipTooltip.hide();
                                                root.eventClicked(event, modifiers);
                                            }
                                            onContextRequested: (event, anchorItem, x, y) => root.eventContextRequested(event, anchorItem, x, y)
                                            onDragPressed: root.eventPointerDown = true
                                            onDragStarted: (event, pointerItem, x, y) => {
                                                chipTooltip.hide();
                                                root.draggedEvent = event;
                                                root.eventDragging = true;
                                                root.updateEventDrag(pointerItem, x, y);
                                            }
                                            onDragMoved: (event, pointerItem, x, y) => root.updateEventDrag(pointerItem, x, y)
                                            onDropped: (event, pointerItem, x, y) => {
                                                root.updateEventDrag(pointerItem, x, y);
                                                root.finishEventDrag(event);
                                            }
                                            onDragReleased: {
                                                root.eventPointerDown = false;
                                                if (root.eventDragging)
                                                    root.finishEventDrag(chipDelegate.ev);
                                            }
                                        }
                                    }

                                    PersonEventChip {
                                        id: colleagueChip
                                        visible: chipDelegate.isOverlay
                                        anchors.fill: parent
                                        kind: chipDelegate.isOverlay ? chipDelegate.ev.kind : "event"
                                        title: chipDelegate.isOverlay ? chipDelegate.ev.title : ""
                                        location: chipDelegate.isOverlay ? chipDelegate.ev.location : ""
                                        personColor: chipDelegate.isOverlay ? chipDelegate.ev.color : Theme.primary
                                        isPrivate: chipDelegate.isOverlay && !!chipDelegate.ev.private
                                        stripes: chipDelegate.isOverlay ? (chipDelegate.ev.stripes || []) : []
                                        compact: true
                                        titleLines: SettingsData.monthEventTitleLines
                                        onEntered: chipTooltip.show(root.overlayTooltip(chipDelegate.ev), colleagueChip)
                                        onExited: chipTooltip.hide()
                                    }
                                }
                            }

                            StyledText {
                                id: moreLabel
                                visible: dayCell.displayItems.length > dayCell.maxChips
                                text: I18n.tr("+%1 more", "overflow label in month grid day cell, %1 is the number of hidden events").arg(dayCell.displayItems.length - dayCell.maxChips)
                                font.pixelSize: 10
                                color: Theme.surfaceVariantText
                                width: parent.width

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                        dayPopover.show(dayCell.cellDate, dayCell.displayItems, moreLabel);
                                    }
                                }
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (eventPoint, button) => {
                                if (button === Qt.RightButton) {
                                    root.dayContextRequested(dayCell.cellDate, dayCell, eventPoint.position.x, eventPoint.position.y);
                                    return;
                                }
                                root.daySelected(dayCell.cellDate);
                            }
                            onDoubleTapped: root.dayActivated(dayCell.cellDate)
                        }
                    }
                }
            }
        }
    }

    DankSlideArea {
        id: slidePager
        anchors.fill: parent
        continuous: false
        dragEnabled: false
        onStepped: direction => wheelHandler.step((I18n.isRtl ? 1 : -1) * direction)
    }

    EventDragGhost {
        dragging: root.eventDragging
        draggedEvent: root.draggedEvent
        dragPosition: root.dragPosition
        selectedKeys: root.selectedEventKeys
    }
}
