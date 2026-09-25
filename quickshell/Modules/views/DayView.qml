import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DankCommon.Widgets
import "../../Common/EventUtils.js" as EventUtils

Item {
    id: root

    property date displayDate: new Date()
    property date today: new Date()
    property string selectedEventKey: ""
    property var selectedEventKeys: []
    property int eventsVersion: 0

    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)
    signal dayContextRequested(date day, var anchorItem, real x, real y)
    signal previousRequested
    signal nextRequested
    signal createTimedRequested(date start, date end)

    function isEventSelected(event) {
        const key = DankCalService.eventKey(event);
        return selectedEventKey === key || selectedEventKeys.indexOf(key) !== -1;
    }

    function revealHours(start, duration) {
        const top = start * hourHeight;
        const bottom = top + duration * hourHeight;
        if (top < dayFlickable.contentY) {
            dayFlickable.contentY = Math.max(0, top - hourHeight / 2);
            return;
        }
        if (bottom > dayFlickable.contentY + dayFlickable.height)
            dayFlickable.contentY = Math.max(0, Math.min(dayFlickable.contentHeight - dayFlickable.height, bottom - dayFlickable.height + hourHeight / 2));
    }

    readonly property real startHour: SettingsData.effectiveHourStart
    readonly property real endHour: SettingsData.effectiveHourEnd
    readonly property real hourCount: endHour - startHour
    readonly property var hourTicks: EventUtils.hourTicks(startHour, endHour)
    readonly property real hourHeight: 56
    readonly property real timeColumnWidth: 72

    // Per-person lanes while PeopleService.active: the owner first (null),
    // then each colleague with a schedule in chip order. A colleague still
    // "loading"/"error"/"unavailable"/"reconnect" gets no column (matches
    // PeopleService.lanes). With no people, laneOwners is [null] and every
    // lane* helper below is the identity, so the layout is unchanged.
    readonly property var laneOwners: PeopleService.lanes.length > 0 ? [null].concat(PeopleService.lanes) : [null]
    readonly property int laneCount: laneOwners.length
    readonly property real laneGap: 6

    function laneWidth(totalWidth) {
        return (totalWidth - (laneCount - 1) * laneGap) / laneCount;
    }

    function laneX(totalWidth, index) {
        return index * (laneWidth(totalWidth) + laneGap);
    }

    function overlayPersonLabel(item) {
        const person = PeopleService.people.find(p => p.email === item.email);
        return (person && (person.name || person.email)) || item.email;
    }

    function overlayTooltip(item) {
        const title = item.title || I18n.tr("Busy", "overlay label for a colleague's free/busy-only or private time block");
        const suffix = (item.location ? " · " + item.location : "") + " · " + root.overlayPersonLabel(item);
        if (item.allDay)
            return title + " · " + I18n.tr("All day", "all-day marker in event tooltip") + suffix;
        return title + " · " + SettingsData.formatTime(item.start) + " – " + SettingsData.formatTime(item.end) + suffix;
    }

    // One colleague lane's timed items, laid out through the same overlap
    // logic as the owner's own lane, but independently: a lane's columns
    // never depend on another lane's events.
    function laneTimedEvents(index) {
        const person = laneOwners[index];
        if (!person)
            return [];
        const out = [];
        const items = PeopleService.personItemsForDay(person.email, displayDate);
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (item.allDay)
                continue;
            const slot = EventUtils.timedSlot(item, displayDate, root.startHour, root.endHour);
            if (!slot)
                continue;
            out.push(Object.assign({}, item, slot));
        }
        return DankCalService.layoutTimedEvents(out).map(ev => Object.assign({}, ev, {
                    "lane": index
                }));
    }

    // Flattened across every colleague lane (index >= 1); each item still
    // carries its own lane index plus that lane's own column/columns.
    readonly property var colleagueTimedEvents: {
        eventsVersion;
        PeopleService.version;
        let out = [];
        for (let i = 1; i < laneCount; i++)
            out = out.concat(laneTimedEvents(i));
        return out;
    }

    function laneAllDayEvents(index) {
        const person = laneOwners[index];
        if (!person)
            return root.allDayEvents;
        return PeopleService.personItemsForDay(person.email, displayDate).filter(item => item.allDay);
    }

    readonly property bool colleagueHasAllDay: {
        eventsVersion;
        PeopleService.version;
        for (let i = 1; i < laneCount; i++)
            if (laneAllDayEvents(i).length > 0)
                return true;
        return false;
    }

    readonly property bool showsNow: today.getFullYear() === displayDate.getFullYear() && today.getMonth() === displayDate.getMonth() && today.getDate() === displayDate.getDate()
    readonly property real nowHour: today.getHours() + today.getMinutes() / 60

    property bool initialScrollDone: false

    function applyInitialScroll() {
        const viewport = dayFlickable.height;
        const contentSpan = hourHeight * hourCount;
        if (initialScrollDone || viewport <= 0 || contentSpan <= viewport)
            return;
        initialScrollDone = true;
        const coreTop = (SettingsData.coreHoursStart - startHour) * hourHeight;
        const coreSpan = (SettingsData.coreHoursEnd - SettingsData.coreHoursStart) * hourHeight;
        const nowInCore = nowHour >= SettingsData.coreHoursStart && nowHour < SettingsData.coreHoursEnd;
        const center = SettingsData.coreHoursValid && nowInCore && coreSpan <= viewport ? coreTop + coreSpan / 2 : (nowHour - startHour) * hourHeight;
        dayFlickable.contentY = Math.max(0, Math.min(contentSpan - viewport, center - viewport / 2));
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

    function eventTooltip(ev) {
        const suffix = (ev.location ? " · " + ev.location : "") + (ev.calendar ? " · " + ev.calendar : "");
        if (ev.allDay)
            return ev.title + " · " + I18n.tr("All day", "all-day marker in event tooltip") + suffix;
        return ev.title + " · " + SettingsData.formatTime(ev.start) + " – " + SettingsData.formatTime(ev.end) + suffix;
    }

    function hourLabel(hour) {
        if (hour === 24)
            return SettingsData.use24HourTime ? "24:00" : SettingsData.formatTime(new Date(2000, 0, 2));
        if (hour % 1 !== 0)
            return SettingsData.formatTime(new Date(2000, 0, 1, 0, Math.round(hour * 60)));
        if (hour === 0)
            return "";
        if (SettingsData.use24HourTime)
            return (hour < 10 ? "0" + hour : hour) + ":00";
        const h = hour % 12 === 0 ? 12 : hour % 12;
        return hour < 12 ? I18n.tr("%1 AM", "morning hour label in time gutter").arg(h) : I18n.tr("%1 PM", "afternoon hour label in time gutter").arg(h);
    }

    readonly property var dayEvents: {
        eventsVersion;
        return DankCalService.eventsForDay(displayDate);
    }

    readonly property var allDayEvents: dayEvents.filter(ev => ev.allDay)

    readonly property var timedEvents: {
        const out = [];
        for (let i = 0; i < dayEvents.length; i++) {
            const ev = dayEvents[i];
            if (ev.allDay)
                continue;
            const slot = EventUtils.timedSlot(ev, displayDate, root.startHour, root.endHour);
            if (!slot)
                continue;
            out.push(Object.assign({}, ev, slot));
        }
        return DankCalService.layoutTimedEvents(out);
    }

    readonly property var hiddenInfo: {
        eventsVersion;
        let count = 0;
        let before = false;
        let after = false;
        for (let i = 0; i < dayEvents.length; i++) {
            const ev = dayEvents[i];
            if (ev.allDay)
                continue;
            const sides = EventUtils.hiddenSides(ev, displayDate, root.startHour, root.endHour);
            if (!sides)
                continue;
            before = before || sides.before;
            after = after || sides.after;
            if (sides.before || sides.after)
                count++;
        }
        return {
            count: count,
            before: before,
            after: after
        };
    }

    readonly property int hiddenEventCount: hiddenInfo.count

    Rectangle {
        id: coreHoursWarning
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 36 : 0
        visible: root.hiddenEventCount > 0
        color: Theme.withAlpha(Theme.warning, 0.18)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "warning"
                size: Theme.iconSizeSmall
                color: Theme.warning
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hiddenEventCount === 1 ? I18n.tr("1 appointment falls outside core hours", "core hours warning banner, singular") : I18n.tr("%1 appointments fall outside core hours", "core hours warning banner, plural").arg(root.hiddenEventCount)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
        }

        DankButton {
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Disable core hours", "core hours warning banner disable action")
            backgroundColor: "transparent"
            textColor: Theme.warning
            buttonHeight: Theme.buttonHeightXS
            focusPolicy: Qt.NoFocus
            onClicked: SettingsData.coreHoursEnabled = false
        }
    }

    // Lane header (colour dot + name), shown only with a colleague-schedule
    // overlay so a bare Day view (no people) is unchanged.
    Row {
        id: laneHeader
        anchors.top: coreHoursWarning.visible ? coreHoursWarning.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.timeColumnWidth
        height: root.laneCount > 1 ? 20 : 0
        visible: root.laneCount > 1
        spacing: root.laneGap

        Repeater {
            model: root.laneCount

            Row {
                id: laneHeaderCell
                required property int index
                width: root.laneWidth(laneHeader.width)
                height: laneHeader.height
                spacing: Theme.spacingXS

                Rectangle {
                    width: 8
                    height: 8
                    radius: Theme.fullRadius(width, height)
                    anchors.verticalCenter: parent.verticalCenter
                    color: laneHeaderCell.index === 0 ? Theme.primary : Theme.toColor(root.laneOwners[laneHeaderCell.index].color)
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: laneHeaderCell.width - 12
                    text: laneHeaderCell.index === 0 ? I18n.tr("Me", "day-view lane header label for the owner's own column") : (root.laneOwners[laneHeaderCell.index].name || root.laneOwners[laneHeaderCell.index].email)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }
        }
    }

    // All-day strip: one lane column per person while PeopleService.active,
    // laid out with the same laneWidth/laneX geometry as the timed grid
    // below. With no people, laneCount is 1 and this is a single column,
    // identical to before.
    Row {
        id: allDayStrip
        anchors.top: laneHeader.visible ? laneHeader.bottom : (coreHoursWarning.visible ? coreHoursWarning.bottom : parent.top)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.timeColumnWidth
        spacing: root.laneGap
        visible: root.allDayEvents.length > 0 || root.colleagueHasAllDay

        Repeater {
            model: root.laneCount

            Column {
                id: allDayLane
                required property int index
                readonly property bool isOwn: index === 0
                readonly property var laneEvents: {
                    root.eventsVersion;
                    PeopleService.version;
                    return root.laneAllDayEvents(index);
                }
                width: root.laneWidth(allDayStrip.width)
                spacing: 2

                Repeater {
                    model: ScriptModel {
                        values: allDayLane.laneEvents
                    }

                    Item {
                        id: allDayItemDelegate
                        required property var modelData
                        width: allDayLane.width
                        height: 22

                        EventChipBackground {
                            id: ownAllDayDayChip
                            visible: allDayLane.isOwn
                            readonly property bool isSelected: root.isEventSelected(allDayItemDelegate.modelData)
                            readonly property var stripeColors: PeopleService.active ? PeopleService.stripesFor(allDayItemDelegate.modelData) : []
                            anchors.fill: parent
                            radius: Theme.cornerRadiusXS
                            clip: true
                            response: allDayItemDelegate.modelData.myResponse
                            calendarColor: allDayItemDelegate.modelData.color
                            selected: isSelected
                            dimmed: PeopleService.active && PeopleService.sharedWith(allDayItemDelegate.modelData).length === 0
                            hovered: allDayMouseArea.containsMouse

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: ownAllDayDayChip.stripeColors.length > 0 ? ownAllDayDayChip.stripeColors.length * 3 + Theme.spacingS + 4 : Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: allDayItemDelegate.modelData.title + "  ·  " + I18n.tr("all day", "suffix on all-day event chip in day view")
                                font.pixelSize: Theme.fontSizeSmall
                                color: parent.textColor
                                font.strikeout: parent.strikeout
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }

                            AttendeeStripes {
                                visible: ownAllDayDayChip.stripeColors.length > 0
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 3
                                anchors.topMargin: 3
                                anchors.bottomMargin: 3
                                compact: true
                                colors: ownAllDayDayChip.stripeColors
                            }

                            EventMouseArea {
                                id: allDayMouseArea
                                anchors.fill: parent
                                eventData: allDayItemDelegate.modelData
                                onEntered: chipTooltip.show(root.eventTooltip(allDayItemDelegate.modelData), ownAllDayDayChip)
                                onExited: chipTooltip.hide()
                                onActivated: (event, modifiers) => {
                                    chipTooltip.hide();
                                    root.eventClicked(event, modifiers);
                                }
                                onContextRequested: (event, anchorItem, x, y) => root.eventContextRequested(event, anchorItem, x, y)
                            }
                        }

                        PersonEventChip {
                            id: colleagueAllDayDayChip
                            visible: !allDayLane.isOwn
                            anchors.fill: parent
                            kind: allDayItemDelegate.modelData.kind
                            title: allDayItemDelegate.modelData.title
                            location: allDayItemDelegate.modelData.location
                            personColor: allDayItemDelegate.modelData.color
                            isPrivate: !!allDayItemDelegate.modelData.private
                            stripes: allDayItemDelegate.modelData.stripes || []
                            compact: true
                            titleLines: 1
                            onEntered: chipTooltip.show(root.overlayTooltip(allDayItemDelegate.modelData), colleagueAllDayDayChip)
                            onExited: chipTooltip.hide()
                        }
                    }
                }
            }
        }
    }

    Item {
        id: hiddenBeforeStrip
        anchors.top: allDayStrip.visible ? allDayStrip.bottom : (laneHeader.visible ? laneHeader.bottom : (coreHoursWarning.visible ? coreHoursWarning.bottom : parent.top))
        anchors.topMargin: allDayStrip.visible ? Theme.spacingS : (coreHoursWarning.visible ? Theme.spacingS : 0)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.timeColumnWidth
        height: root.hiddenInfo.before ? 16 : 0
        visible: root.hiddenInfo.before

        DankIcon {
            anchors.centerIn: parent
            name: "keyboard_arrow_up"
            size: Theme.iconSizeSmall
            color: Theme.warning
        }
    }

    DankFlickable {
        id: dayFlickable
        anchors.top: hiddenBeforeStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: root.hourHeight * root.hourCount
        clip: true
        onHeightChanged: root.applyInitialScroll()

        DankSlideDragHandler {
            slideArea: slidePager
        }

        Item {
            width: parent.width
            height: root.hourHeight * root.hourCount

            Item {
                anchors.left: parent.left
                width: root.timeColumnWidth
                height: parent.height

                Repeater {
                    model: root.hourTicks.length

                    StyledText {
                        required property int index
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        readonly property real tickY: (root.hourTicks[index] - root.startHour) * root.hourHeight
                        visible: index === 0 || (tickY >= height + Theme.spacingXS && (index === root.hourTicks.length - 1 || parent.height - tickY >= height + Theme.spacingXS))
                        y: Math.max(0, Math.min(parent.height - height, tickY - height / 2))
                        text: root.hourLabel(root.hourTicks[index])
                        font.pixelSize: 11
                        color: Theme.surfaceVariantText
                        isMonospace: true
                    }
                }
            }

            Item {
                id: timedArea
                anchors.right: parent.right
                width: parent.width - root.timeColumnWidth
                height: parent.height

                Repeater {
                    model: root.hourTicks.length

                    Rectangle {
                        required property int index
                        y: (root.hourTicks[index] - root.startHour) * root.hourHeight
                        width: parent.width
                        height: 1
                        color: Theme.gridLine
                    }
                }

                // Lane separators, one per boundary between adjacent
                // per-person columns; absent (no repeated items) when
                // laneCount is 1.
                Repeater {
                    model: Math.max(0, root.laneCount - 1)

                    Rectangle {
                        required property int index
                        x: root.laneX(timedArea.width, index + 1) - root.laneGap / 2
                        width: 1
                        height: parent.height
                        color: Theme.gridLine
                    }
                }

                TimeGridCreateArea {
                    anchors.fill: parent
                    day: root.displayDate
                    startHour: root.startHour
                    hourCount: root.hourCount
                    hourHeight: root.hourHeight
                    flickable: dayFlickable
                    onCreateRequested: (start, end) => root.createTimedRequested(start, end)
                }

                DankIcon {
                    visible: root.hiddenInfo.after
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.hourCount * root.hourHeight + 2
                    name: "keyboard_arrow_down"
                    size: Theme.iconSizeSmall
                    color: Theme.warning
                }

                Item {
                    visible: root.showsNow && root.nowHour >= root.startHour && root.nowHour < root.endHour
                    y: (root.nowHour - root.startHour) * root.hourHeight
                    width: parent.width
                    z: 10

                    Rectangle {
                        id: nowDot
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.top
                        width: Theme.spacingS + Theme.spacingXXS
                        height: width
                        radius: Theme.fullRadius(width, height)
                        color: Theme.error
                    }

                    Rectangle {
                        anchors.left: nowDot.right
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.top
                        height: 2
                        color: Theme.error
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.timedEvents
                    }

                    EventChipBackground {
                        id: ownDayTimedChip
                        required property var modelData
                        readonly property bool isSelected: root.isEventSelected(modelData)
                        readonly property var stripeColors: PeopleService.active ? PeopleService.stripesFor(modelData) : []
                        onIsSelectedChanged: {
                            if (isSelected)
                                root.revealHours(modelData.startHour, modelData.durationHours);
                        }
                        readonly property real ownLaneGap: 3
                        readonly property real ownLaneWidth: root.laneWidth(timedArea.width)
                        readonly property real usableWidth: ownLaneWidth - 16
                        readonly property real laneWidth: (usableWidth - (modelData.columns - 1) * ownLaneGap) / modelData.columns
                        x: root.laneX(timedArea.width, 0) + 8 + modelData.column * (laneWidth + ownLaneGap)
                        y: modelData.startHour * root.hourHeight
                        width: laneWidth
                        height: modelData.durationHours * root.hourHeight - 4
                        clip: true
                        response: modelData.myResponse
                        calendarColor: modelData.color
                        selected: isSelected
                        dimmed: PeopleService.active && stripeColors.length === 0
                        hovered: timedMouseArea.containsMouse

                        AttendeeStripes {
                            visible: ownDayTimedChip.stripeColors.length > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 3
                            anchors.topMargin: 3
                            anchors.bottomMargin: 3
                            colors: ownDayTimedChip.stripeColors
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            anchors.rightMargin: ownDayTimedChip.stripeColors.length > 0 ? ownDayTimedChip.stripeColors.length * 3 + Theme.spacingS + 4 : Theme.spacingS
                            spacing: Theme.spacingS

                            Rectangle {
                                width: 3
                                height: parent.height - 4
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.fullRadius(width, height)
                                color: parent.parent.dotColor
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 12

                                StyledText {
                                    text: parent.parent.parent.modelData.title
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: parent.parent.parent.textColor
                                    font.strikeout: parent.parent.parent.strikeout
                                    width: parent.width
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: parent.parent.parent.modelData.durationHours >= 0.75
                                    text: parent.parent.parent.modelData.calendar
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: parent.parent.parent.mutedTextColor
                                    width: parent.width
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: text !== "" && parent.parent.parent.modelData.durationHours >= 1.25
                                    text: parent.parent.parent.modelData.location
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: parent.parent.parent.mutedTextColor
                                    width: parent.width
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: text !== "" && parent.parent.parent.modelData.durationHours >= 2
                                    text: DankCalService.descriptionPreview(parent.parent.parent.modelData)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: parent.parent.parent.mutedTextColor
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        EventMouseArea {
                            id: timedMouseArea
                            anchors.fill: parent
                            eventData: parent.modelData
                            onEntered: chipTooltip.show(root.eventTooltip(parent.modelData), parent)
                            onExited: chipTooltip.hide()
                            onActivated: (event, modifiers) => {
                                chipTooltip.hide();
                                root.eventClicked(event, modifiers);
                            }
                            onContextRequested: (event, anchorItem, x, y) => root.eventContextRequested(event, anchorItem, x, y)
                        }
                    }
                }

                // One PersonEventChip per colleague lane's timed item,
                // laid out independently per lane (root.laneTimedEvents);
                // read-only, matching Week/Month.
                Repeater {
                    model: ScriptModel {
                        values: root.colleagueTimedEvents
                    }

                    PersonEventChip {
                        id: colleagueDayTimedChip
                        required property var modelData
                        readonly property real colLaneWidth: root.laneWidth(timedArea.width)
                        readonly property real colGap: 3
                        readonly property real usableWidth: colLaneWidth - 8
                        readonly property real colWidth: (usableWidth - (modelData.columns - 1) * colGap) / modelData.columns
                        x: root.laneX(timedArea.width, modelData.lane) + 4 + modelData.column * (colWidth + colGap)
                        y: modelData.startHour * root.hourHeight
                        z: 1
                        width: colWidth
                        height: modelData.durationHours * root.hourHeight - 4
                        kind: modelData.kind
                        title: modelData.title
                        location: modelData.location
                        personColor: modelData.color
                        isPrivate: !!modelData.private
                        stripes: modelData.stripes || []
                        compact: modelData.durationHours < 1
                        titleLines: Math.max(1, Math.floor(height / 14))
                        onEntered: chipTooltip.show(root.overlayTooltip(modelData), colleagueDayTimedChip)
                        onExited: chipTooltip.hide()
                    }
                }
            }
        }
    }

    DankSlideArea {
        id: slidePager
        anchors.fill: parent
        z: 50
        continuous: false
        onStepped: direction => {
            const forward = (I18n.isRtl ? 1 : -1) * direction;
            if (forward < 0)
                root.previousRequested();
            else
                root.nextRequested();
        }
    }

    DankSlideDragHandler {
        slideArea: slidePager
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => root.dayContextRequested(root.displayDate, root, eventPoint.position.x, eventPoint.position.y)
    }
}
