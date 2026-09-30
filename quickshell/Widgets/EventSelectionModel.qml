import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/EventUtils.js" as EventUtils

Item {
    id: root

    property var selectedKeys: []
    property string anchorKey: ""
    property bool busy: false

    readonly property int count: selectedKeys.length
    readonly property bool hasSelection: count > 0
    readonly property var clipboardEvents: EventUtils.clipboardEvents(Quickshell.clipboardText)
    readonly property int clipboardCount: clipboardEvents.length
    readonly property bool clipboardIsCut: clipboardCount > 0 && clipboardEvents.every(event => event._dankCut)

    visible: false
    width: 0
    height: 0

    function contains(event) {
        return selectedKeys.indexOf(DankCalService.eventKey(event)) !== -1;
    }

    function clear() {
        selectedKeys = [];
        anchorKey = "";
    }

    function replace(events) {
        selectedKeys = events.map(event => DankCalService.eventKey(event));
        anchorKey = selectedKeys.length > 0 ? selectedKeys[selectedKeys.length - 1] : "";
    }

    function ensureSelected(event) {
        if (contains(event))
            return;
        replace([event]);
    }

    function selectRange(event, additive) {
        const events = DankCalService.visibleEvents();
        const targetKey = DankCalService.eventKey(event);
        let anchorIndex = -1;
        let targetIndex = -1;
        for (let i = 0; i < events.length; i++) {
            const key = DankCalService.eventKey(events[i]);
            if (key === anchorKey)
                anchorIndex = i;
            if (key === targetKey)
                targetIndex = i;
        }
        if (anchorIndex < 0 || targetIndex < 0) {
            replace([event]);
            return;
        }

        const start = Math.min(anchorIndex, targetIndex);
        const end = Math.max(anchorIndex, targetIndex);
        const rangeKeys = events.slice(start, end + 1).map(item => DankCalService.eventKey(item));
        if (!additive) {
            selectedKeys = rangeKeys;
            return;
        }

        const merged = selectedKeys.slice();
        for (let i = 0; i < rangeKeys.length; i++) {
            if (merged.indexOf(rangeKeys[i]) === -1)
                merged.push(rangeKeys[i]);
        }
        selectedKeys = merged;
    }

    function select(event, modifiers) {
        const toggle = (modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0;
        const extend = (modifiers & Qt.ShiftModifier) !== 0;
        const key = DankCalService.eventKey(event);

        if (extend && anchorKey !== "") {
            selectRange(event, toggle);
            return;
        }
        if (toggle) {
            const keys = selectedKeys.slice();
            const index = keys.indexOf(key);
            if (index === -1)
                keys.push(key);
            else
                keys.splice(index, 1);
            selectedKeys = keys;
            anchorKey = key;
            return;
        }
        selectedKeys = [key];
        anchorKey = key;
    }

    function selectDay(day) {
        replace(DankCalService.eventsForDay(day));
    }

    function events(fallback) {
        const resolved = DankCalService.eventsByKeys(selectedKeys);
        if (resolved.length > 0)
            return resolved;
        return fallback ? [fallback] : [];
    }

    function allWritable(fallback) {
        const selected = events(fallback);
        return selected.length > 0 && selected.every(event => !event.readOnly);
    }

    function writableCalendarId(preferredId) {
        const writable = DankCalService.writableCalendars();
        for (let i = 0; i < writable.length; i++) {
            if (writable[i].id === preferredId)
                return preferredId;
        }
        const fallback = DankCalService.defaultCalendar();
        return fallback ? fallback.id : "";
    }

    function operationToast(action, completed, total) {
        switch (action) {
        case "paste":
            if (completed !== total)
                return I18n.tr("Pasted %1 of %2 events", "toast when only some events pasted; %1 is completed count, %2 is total count").arg(completed).arg(total);
            return total === 1 ? I18n.tr("Pasted 1 event", "toast after pasting one event") : I18n.tr("Pasted %1 events", "toast after pasting multiple events; %1 is event count").arg(total);
        case "move":
            if (completed !== total)
                return I18n.tr("Moved %1 of %2 events", "toast when only some events moved; %1 is completed count, %2 is total count").arg(completed).arg(total);
            return total === 1 ? I18n.tr("Moved 1 event", "toast after moving one event") : I18n.tr("Moved %1 events", "toast after moving multiple events; %1 is event count").arg(total);
        case "create":
            if (completed !== total)
                return I18n.tr("Created %1 of %2 events", "toast when only some events created; %1 is completed count, %2 is total count").arg(completed).arg(total);
            return total === 1 ? I18n.tr("Created 1 event", "toast after creating one event") : I18n.tr("Created %1 events", "toast after creating multiple events; %1 is event count").arg(total);
        case "delete":
            if (completed !== total)
                return I18n.tr("Deleted %1 of %2 events", "toast when only some events deleted; %1 is completed count, %2 is total count").arg(completed).arg(total);
            return total === 1 ? I18n.tr("Deleted 1 event", "toast after deleting one event") : I18n.tr("Deleted %1 events", "toast after deleting multiple events; %1 is event count").arg(total);
        }
        return "";
    }

    function failureSummary(action, count, total) {
        switch (action) {
        case "paste":
            return I18n.tr("%1 of %2 events couldn't be pasted.", "toast when some events failed to paste; %1 is failed count, %2 is total count").arg(count).arg(total);
        case "move":
            return I18n.tr("%1 of %2 events couldn't be moved.", "toast when some events failed to move; %1 is failed count, %2 is total count").arg(count).arg(total);
        case "create":
            return I18n.tr("%1 of %2 events couldn't be created.", "toast when some events failed to create; %1 is failed count, %2 is total count").arg(count).arg(total);
        }
        return I18n.tr("%1 of %2 events couldn't be deleted.", "toast when some events failed to delete; %1 is failed count, %2 is total count").arg(count).arg(total);
    }

    // finishOperation reports a batch that ended. A failure toast states how many
    // items failed and why (the raw error only goes to the log) and offers Try
    // again for the retryable ones only. retry = {method, done, resume}: the IPC
    // method to resend with, how many items succeeded before this reply, and what
    // to call with the retry's reply (default: report it here again).
    function finishOperation(action, total, response, retry) {
        busy = false;
        const done = (retry && retry.done) || 0;
        const completed = done + (response.results || []).length;
        if (!response.error) {
            ToastService.info(operationToast(action, completed, total));
            return;
        }
        const method = retry.method;
        const resume = retry.resume || ((next, nextDone) => root.finishOperation(action, total, next, {
                    "method": method,
                    "done": nextDone
                }));
        const failed = DankCalService.batchFailure(response, action === "delete" ? "delete" : "save");
        let message = failed.reason;
        if (total > 1 || message === "") {
            message = total > 1 ? failureSummary(action, failed.count, total) : (action === "delete" ? I18n.tr("Couldn't delete the event.", "event delete error for an unclassified failure") : I18n.tr("Couldn't save the event.", "event save error for an unclassified failure"));
            if (total > 1 && failed.reason !== "")
                message += " " + failed.reason;
        }
        const opts = {};
        if (failed.retry.length > 0) {
            opts.actionLabel = I18n.tr("Try again", "toast action to resend a failed event change");
            opts.action = () => {
                root.busy = true;
                DankCalService.retryBatch(method, failed.retry, next => resume(next, completed));
            };
        } else if (failed.account) {
            opts.actionLabel = I18n.tr("Reconnect", "toast action to sign in to an account again");
            opts.action = () => DankCalService.reconnectAccount(failed.account);
        }
        ToastService.show(message, opts);
    }

    // Reports the create half of a paste. A cut only deletes its sources once
    // every copy exists, so a partly failed paste (or its retry) never loses one.
    function finishPasteCreate(fields, cutSources, response, done) {
        if (response.error || cutSources.length !== fields.length) {
            root.finishOperation("paste", fields.length, response, {
                "method": "events.create",
                "done": done,
                "resume": (next, nextDone) => root.finishPasteCreate(fields, cutSources, next, nextDone)
            });
            root.clear();
            return;
        }
        DankCalService.deleteEvents(cutSources, deleteResponse => {
            root.finishOperation("move", fields.length, deleteResponse, {
                "method": "events.delete"
            });
            if (!deleteResponse.error)
                Quickshell.clipboardText = EventUtils.clipboardTextFromFields(fields);
            root.clear();
        });
    }

    function copy(fallback) {
        if (fallback)
            ensureSelected(fallback);
        const selected = events(fallback);
        if (selected.length === 0)
            return;
        Quickshell.clipboardText = EventUtils.clipboardText(selected, false);
        ToastService.info(selected.length === 1 ? I18n.tr("Copied 1 event", "clipboard confirmation for one event") : I18n.tr("Copied %1 events", "clipboard confirmation for multiple events; %1 is event count").arg(selected.length));
    }

    function cut(fallback) {
        if (fallback)
            ensureSelected(fallback);
        const selected = events(fallback);
        if (selected.length === 0)
            return;
        if (!allWritable(fallback)) {
            ToastService.info(I18n.tr("Read-only events can't be cut", "event cut error for a read-only calendar"));
            return;
        }
        Quickshell.clipboardText = EventUtils.clipboardText(selected, true);
        ToastService.info(selected.length === 1 ? I18n.tr("Cut 1 event", "clipboard confirmation for one event") : I18n.tr("Cut %1 events", "clipboard confirmation for multiple events; %1 is event count").arg(selected.length));
    }

    function paste(targetDay) {
        const copied = EventUtils.clipboardEvents(Quickshell.clipboardText);
        if (copied.length === 0 || busy)
            return;
        const fallbackId = writableCalendarId("");
        if (fallbackId === "") {
            ToastService.info(I18n.tr("No writable calendar available", "event paste error when no calendar allows creating events"));
            return;
        }
        const fields = EventUtils.pasteFields(copied, targetDay, fallbackId);
        const cutSources = [];
        for (let i = 0; i < fields.length; i++) {
            if (fields[i]._dankCut)
                cutSources.push(fields[i]._dankCut);
            delete fields[i]._dankCut;
            fields[i].calendarId = writableCalendarId(fields[i].calendarId);
        }
        busy = true;
        DankCalService.createEvents(fields, response => root.finishPasteCreate(fields, cutSources, response, 0));
    }

    function duplicate(dayOffset, fallback) {
        if (busy)
            return;
        if (fallback)
            ensureSelected(fallback);
        const selected = events(fallback);
        const fields = [];
        for (let i = 0; i < selected.length; i++) {
            const calendarId = writableCalendarId(selected[i].calendarId);
            if (calendarId !== "")
                fields.push(EventUtils.createFields(selected[i], dayOffset, calendarId, false));
        }
        if (fields.length === 0) {
            ToastService.info(I18n.tr("No writable calendar available", "event duplicate error when no calendar allows creating events"));
            return;
        }
        busy = true;
        DankCalService.createEvents(fields, response => root.finishOperation("create", fields.length, response, {
                "method": "events.create"
            }));
    }

    function moveTo(anchorEvent, targetDay) {
        moveBy(anchorEvent, EventUtils.daysBetween(anchorEvent.start, targetDay), 0);
    }

    function moveBy(anchorEvent, dayOffset, minuteOffset) {
        if (busy)
            return;
        ensureSelected(anchorEvent);
        const selected = events(anchorEvent);
        if (!allWritable(anchorEvent)) {
            ToastService.info(I18n.tr("Read-only events can't be moved", "event move error for a read-only calendar"));
            return;
        }
        if (dayOffset === 0 && minuteOffset === 0)
            return;
        busy = true;
        DankCalService.moveEvents(selected, dayOffset, minuteOffset, response => {
            root.finishOperation("move", selected.length, response, {
                "method": "events.update"
            });
            root.clear();
        });
    }

    function remove(fallback) {
        if (busy)
            return;
        if (fallback)
            ensureSelected(fallback);
        const selected = events(fallback);
        if (selected.length === 0)
            return;
        if (!allWritable(fallback)) {
            ToastService.info(I18n.tr("Read-only events can't be deleted", "event delete error for a read-only calendar"));
            return;
        }
        busy = true;
        DankCalService.deleteEvents(selected, response => {
            root.finishOperation("delete", selected.length, response, {
                "method": "events.delete"
            });
            root.clear();
        });
    }

    Connections {
        target: DankCalService
        function onEventsUpdated() {
            if (root.selectedKeys.length === 0)
                return;
            const available = {};
            const events = DankCalService.visibleEvents();
            for (let i = 0; i < events.length; i++)
                available[DankCalService.eventKey(events[i])] = true;
            const next = root.selectedKeys.filter(key => available[key]);
            if (next.length !== root.selectedKeys.length)
                root.selectedKeys = next;
            if (root.anchorKey !== "" && !available[root.anchorKey])
                root.anchorKey = next.length > 0 ? next[next.length - 1] : "";
        }
    }
}
