pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/EventUtils.js" as EventUtils

// Colleague-schedule search: transient, in-memory UI state for the sidebar
// People search and the (future) Week/Month/Day overlay. Talks to the daemon
// only through DankCalService.sendRequest("people.schedule", ...). Nothing
// here is written to ui-settings.json or the database.
Singleton {
    id: root

    readonly property var log: Log.scoped("PeopleService")

    // Each entry: {email, name, color, status, accountId, events, busy, error, seq}.
    // status is one of loading | details | busy | unavailable | reconnect | error.
    property var people: []
    property int version: 0

    readonly property bool active: people.length > 0
    readonly property var lanes: people.filter(p => p.status === "details" || p.status === "busy")
    readonly property bool hasGoogleAccount: DankCalService.accounts.some(a => a.kind === "google")
    readonly property var reconnectPerson: people.find(p => p.status === "reconnect") || null

    property string _windowKey: ""

    Connections {
        target: DankCalService
        function onFocusDateChanged() {
            root._refetchTimer.restart();
        }
    }

    Timer {
        id: _refetchTimer
        interval: 250
        onTriggered: root._maybeRefetchAll()
    }

    function _monthKey(d) {
        return d.getFullYear() + "-" + d.getMonth();
    }

    function _windowFor(d) {
        const first = new Date(d.getFullYear(), d.getMonth(), 1);
        return {
            "from": new Date(first.getTime() - 7 * 86400000),
            "to": new Date(first.getTime() + 42 * 86400000)
        };
    }

    function _maybeRefetchAll() {
        const key = _monthKey(DankCalService.focusDate);
        if (key === _windowKey || people.length === 0)
            return;
        _windowKey = key;
        for (const p of people)
            _fetch(p.email);
    }

    function _nextColor() {
        const palette = DankCalService.fallbackPalette;
        const used = people.map(p => p.color);
        for (let i = 0; i < palette.length; i++) {
            if (used.indexOf(palette[i]) === -1)
                return palette[i];
        }
        return palette[people.length % palette.length];
    }

    // Adds a person and starts their fetch. Returns "" on success, or an
    // error string meant for the search field's supportingText.
    function add(email) {
        const trimmed = (email || "").trim().toLowerCase();
        if (!trimmed)
            return I18n.tr("Enter an email address", "people search validation error for an empty field");
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed))
            return I18n.tr("Enter a valid email address", "people search validation error for a malformed address");
        if (people.some(p => p.email === trimmed))
            return I18n.tr("Already added", "people search validation error for a duplicate address");
        if (DankCalService.accounts.some(a => (a.id || "").toLowerCase() === trimmed))
            return I18n.tr("That's your own account", "people search validation error when the address is one of the user's own accounts");

        people = people.concat([{
                "email": trimmed,
                "name": "",
                "color": _nextColor(),
                "status": "loading",
                "accountId": "",
                "events": [],
                "busy": [],
                "error": "",
                "seq": 0
            }]);
        version++;
        _fetch(trimmed);
        return "";
    }

    function remove(email) {
        const next = people.filter(p => p.email !== email);
        if (next.length === people.length)
            return;
        people = next;
        version++;
        if (people.length === 0)
            _windowKey = "";
    }

    function clear() {
        if (people.length === 0)
            return;
        people = [];
        version++;
        _windowKey = "";
    }

    function retry(email) {
        if (people.some(p => p.email === email))
            _fetch(email);
    }

    // Refetches every person currently showing "reconnect", called after a
    // successful DankCalService.reconnectAccount(...).
    function retryReconnect() {
        for (const p of people)
            if (p.status === "reconnect")
                _fetch(p.email);
    }

    function _setPerson(email, patch) {
        const idx = people.findIndex(p => p.email === email);
        if (idx < 0)
            return;
        const next = people.slice();
        next[idx] = Object.assign({}, next[idx], patch);
        people = next;
        version++;
    }

    function _fetch(email) {
        const idx = people.findIndex(p => p.email === email);
        if (idx < 0)
            return;
        const seq = (people[idx].seq || 0) + 1;
        _setPerson(email, {
            "status": "loading",
            "seq": seq,
            "error": ""
        });
        const win = _windowFor(DankCalService.focusDate);
        _windowKey = _monthKey(DankCalService.focusDate);
        DankCalService.sendRequest("people.schedule", {
            "email": email,
            "from": win.from.toISOString(),
            "to": win.to.toISOString()
        }, response => root.ingest(email, response, seq));
    }

    // The production IPC callback body. Also the entry point an offscreen
    // verification harness feeds fixture responses through. seq is omitted
    // by such a harness, which skips the stale-response guard.
    function ingest(email, response, seq) {
        const idx = people.findIndex(p => p.email === email);
        if (idx < 0)
            return;
        if (seq !== undefined && people[idx].seq !== seq)
            return;
        if (response && response.error) {
            log.warn("lookup failed", email, response.error);
            _setPerson(email, {
                "status": "error",
                "error": response.error
            });
            return;
        }
        const result = (response && response.result !== undefined) ? response.result : (response || {});
        _setPerson(email, {
            "status": result.status || "error",
            "name": result.name || "",
            "accountId": result.accountId || "",
            "events": (result.events || []).map(e => _normalizeEvent(e)),
            "busy": (result.busy || []).map(b => ({
                        "start": new Date(b.start),
                        "end": new Date(b.end)
                    })),
            "error": ""
        });
    }

    // Colleague all-day boundaries arrive as UTC-midnight ISO strings, the
    // same convention DankCalService.normalizeEvent uses for own events.
    function _dayBoundary(iso) {
        const d = new Date(iso);
        return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
    }

    function _normalizeEvent(raw) {
        const e = raw || {};
        const base = DankCalService.normalizeEvent(e);
        const ownStart = e.ownStart ? (base.allDay ? _dayBoundary(e.ownStart) : new Date(e.ownStart)) : null;
        const ownEventId = e.ownEventId || "";
        const ownUid = e.ownUid || "";
        return Object.assign({}, base, {
            "key": e.key || "",
            "private": !!e.private,
            "ownEventId": ownEventId,
            "ownUid": ownUid,
            "ownStart": ownStart,
            // Matches EventUtils.eventKey(ownEvent) for the owner occurrence
            // this colleague event was matched against (section 4 of the
            // design), used by sharedWith().
            "ownKey": (ownEventId && ownStart) ? (ownEventId + "|" + ownUid + "|" + ownStart.getTime()) : ""
        });
    }

    function _dayKeyOf(d) {
        const date = new Date(d);
        return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
    }

    // Merged overlay items for one day, for the Week/Month views (phase 3).
    // No colleague-colleague merge yet: every detail event is its own item.
    function overlayForDay(day) {
        const key = _dayKeyOf(day);
        const items = [];
        for (const p of people) {
            if (p.status === "details") {
                for (const ev of p.events) {
                    if (_dayKeyOf(ev.start) !== key)
                        continue;
                    items.push({
                        "overlay": true,
                        "kind": "event",
                        "title": ev.title,
                        "location": ev.location,
                        "start": ev.start,
                        "end": ev.end,
                        "allDay": ev.allDay,
                        "color": p.color,
                        "stripes": [],
                        "email": p.email
                    });
                }
            } else if (p.status === "busy") {
                for (const b of p.busy) {
                    if (_dayKeyOf(b.start) !== key)
                        continue;
                    items.push({
                        "overlay": true,
                        "kind": "busy",
                        "title": I18n.tr("Busy", "overlay label for a colleague's free/busy-only time block"),
                        "location": "",
                        "start": b.start,
                        "end": b.end,
                        "allDay": false,
                        "color": p.color,
                        "stripes": [],
                        "email": p.email
                    });
                }
            }
        }
        return items;
    }

    // One person's unmerged items for a day, for the Day-view lanes (phase 4).
    function personItemsForDay(email, day) {
        return overlayForDay(day).filter(item => item.email === email);
    }

    // Colleague colours who share the given own event, for the own chip's
    // attendee stripes (phase 4). Uses the daemon's own-event match, not a
    // QML-side merge.
    function sharedWith(ev) {
        if (!ev)
            return [];
        const key = EventUtils.eventKey(ev);
        const colors = [];
        for (const p of people) {
            if (p.status !== "details")
                continue;
            for (const pe of p.events) {
                if (pe.ownKey && pe.ownKey === key) {
                    colors.push(p.color);
                    break;
                }
            }
        }
        return colors;
    }
}
