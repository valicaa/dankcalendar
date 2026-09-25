pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/EventUtils.js" as EventUtils

// Colleague-schedule lookups for the sidebar People search and the view
// overlay. Held in memory only: nothing is written to ui-settings.json or
// the database.
Singleton {
    id: root

    readonly property var log: Log.scoped("PeopleService")

    // Each entry: {email, name, color, status, accountId, events, busy, error, window}.
    // status is the outcome of the last lookup: pending (none yet) | details |
    // busy | unavailable | reconnect | error. A refetch keeps status and data,
    // so the overlay stays up while paging; `loading` marks it for the chips.
    property var people: []
    // email -> true while a lookup is in flight. Read by the chips only.
    property var loading: ({})
    // Bumped once per rebuild of the overlay index; the one signal views
    // depend on. The lookups below read it so their callers re-evaluate.
    property int version: 0
    // The people with a Day lane. Reassigned only when that list changes.
    property var lanes: []

    readonly property bool active: people.length > 0
    readonly property bool hasGoogleAccount: DankCalService.accounts.some(a => a.kind === "google")
    readonly property var reconnectPerson: people.find(p => p.status === "reconnect") || null
    readonly property string busyLabel: I18n.tr("Busy", "overlay label for a colleague's free/busy-only or private time block")

    property int _seq: 0
    property string _windowKey: ""
    // Mutated in place, so it notifies nothing: index, latest seq per email,
    // the window being fetched and the window each person's fetch asked for.
    readonly property var _store: ({
            "index": {
                "shared": {},
                "byDay": {},
                "lanes": {}
            },
            "seqs": {},
            "window": null,
            "fetchWindows": {}
        })

    Connections {
        target: DankCalService
        function onFocusDateChanged() {
            refetchTimer.restart();
        }
    }

    Timer {
        id: refetchTimer
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

    function _setWindow() {
        _windowKey = _monthKey(DankCalService.focusDate);
        _store.window = _windowFor(DankCalService.focusDate);
    }

    function _maybeRefetchAll() {
        const key = _monthKey(DankCalService.focusDate);
        if (key === _windowKey || people.length === 0)
            return;
        _setWindow();
        for (const p of people)
            _fetch(p.email);
    }

    function _laneKey(list) {
        return list.map(p => p.email + "|" + p.status + "|" + p.name + "|" + p.color).join(",");
    }

    // Every change to people goes through here: one index rebuild, one
    // version bump.
    function _commit(next) {
        _store.index = _buildIndex(next);
        people = next;
        const nextLanes = next.filter(p => p.status === "details" || p.status === "busy");
        if (_laneKey(nextLanes) !== _laneKey(lanes))
            lanes = nextLanes;
        version++;
    }

    function _setLoading(email, value) {
        const next = Object.assign({}, loading);
        if (value)
            next[email] = true;
        else
            delete next[email];
        loading = next;
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

        if (people.length === 0)
            _setWindow();
        _commit(people.concat([{
                    "email": trimmed,
                    "name": "",
                    "color": _nextColor(),
                    "status": "pending",
                    "accountId": "",
                    "events": [],
                    "busy": [],
                    "error": "",
                    "window": null
                }]));
        _fetch(trimmed);
        return "";
    }

    function _forget(email) {
        delete _store.seqs[email];
        delete _store.fetchWindows[email];
        _setLoading(email, false);
    }

    function remove(email) {
        const next = people.filter(p => p.email !== email);
        if (next.length === people.length)
            return;
        _forget(email);
        _commit(next);
        if (next.length === 0)
            _windowKey = "";
    }

    function clear() {
        if (people.length === 0)
            return;
        for (const p of people)
            _forget(p.email);
        _commit([]);
        _windowKey = "";
    }

    function retry(email) {
        if (people.some(p => p.email === email))
            _fetch(email);
    }

    // Refetches every person showing "reconnect", after a successful
    // DankCalService.reconnectAccount(...).
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
        _commit(next);
    }

    // Fetches the current window. Only the first add and a month change move
    // the window, so an add or retry during the refetch debounce cannot make
    // the debounced refetch skip everyone else.
    function _fetch(email) {
        if (!people.some(p => p.email === email))
            return;
        const seq = ++_seq;
        const win = _store.window;
        _store.seqs[email] = seq;
        _store.fetchWindows[email] = win;
        _setLoading(email, true);
        DankCalService.sendRequest("people.schedule", {
            "email": email,
            "from": win.from.toISOString(),
            "to": win.to.toISOString()
        }, response => root.ingest(email, response, seq));
    }

    // The people.schedule reply for the fetch numbered seq. A reply for a
    // superseded fetch, or for a person removed since, is dropped.
    function ingest(email, response, seq) {
        if (_store.seqs[email] !== seq || !people.some(p => p.email === email))
            return;
        _setLoading(email, false);
        if (response.error) {
            log.warn("colleague lookup failed");
            _setPerson(email, {
                "status": "error",
                "error": response.error
            });
            return;
        }
        const result = response.result || {};
        _setPerson(email, {
            "status": result.status || "error",
            "window": _store.fetchWindows[email],
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

    // All-day boundaries arrive as UTC-midnight ISO strings, the convention
    // DankCalService.normalizeEvent uses for own events.
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
            // EventUtils.eventKey of the owner's occurrence this event matched.
            "ownKey": (ownEventId && ownStart) ? (ownEventId + "|" + ownUid + "|" + ownStart.getTime()) : ""
        });
    }

    function _dayKeyOf(d) {
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate();
    }

    // Local day keys an item overlaps (start < dayEnd && end > dayStart, the
    // rule DankCalService.eventsForRange applies to own events), clamped to
    // the window it was fetched for.
    function _daysOf(start, end, win) {
        const keys = [];
        let lo = start;
        let hi = end;
        if (win) {
            lo = new Date(Math.max(lo.getTime(), win.from.getTime()));
            hi = new Date(Math.min(hi.getTime(), win.to.getTime()));
        }
        for (let day = new Date(lo.getFullYear(), lo.getMonth(), lo.getDate()); day < hi; day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1))
            keys.push(_dayKeyOf(day));
        return keys;
    }

    function _overlayItem(p, kind, source, isPrivate) {
        const hidesTitle = kind === "busy" || isPrivate;
        return {
            "overlay": true,
            "kind": kind,
            "title": hidesTitle ? busyLabel : source.title,
            "location": hidesTitle ? "" : (source.location || ""),
            "start": source.start,
            "end": source.end,
            "allDay": !!source.allDay,
            "key": source.key || "",
            "color": p.color,
            "stripes": [],
            "email": p.email,
            "emails": [p.email],
            "private": isPrivate
        };
    }

    function _push(map, key, item) {
        if (map[key])
            map[key].push(item);
        else
            map[key] = [item];
    }

    // One pass over every person's events, per change of `people`:
    //  - shared: own event key -> colours of the colleagues who share it
    //  - byDay: day key -> merged overlay items for Week/Month. An event that
    //    matches an own occurrence is carried by the own chip's stripes
    //    instead. The rest are grouped by `key` (iCalUID + start), so a
    //    meeting several colleagues share is one item in the first person's
    //    colour, striped with every participant. Busy spans and private
    //    events never merge: each person keeps their own band.
    //  - lanes: email -> day key -> that person's own items, unmerged, for
    //    the Day view.
    function _buildIndex(list) {
        const shared = {};
        const groups = {};
        const busyByDay = {};
        const lanes = {};
        for (const p of list) {
            const lane = {};
            lanes[p.email] = lane;
            if (p.status === "details") {
                for (const ev of p.events) {
                    const item = _overlayItem(p, "event", ev, ev.private);
                    const days = _daysOf(ev.start, ev.end, p.window);
                    for (const day of days)
                        _push(lane, day, item);
                    if (ev.ownKey) {
                        const colors = shared[ev.ownKey] || (shared[ev.ownKey] = []);
                        if (colors.indexOf(p.color) === -1)
                            colors.push(p.color);
                        continue;
                    }
                    if (ev.private) {
                        for (const day of days)
                            _push(busyByDay, day, item);
                        continue;
                    }
                    // Without an iCalUID an event merges with nobody.
                    const mergeKey = ev.key || ("_" + p.email + "_" + ev.start.getTime());
                    for (const day of days) {
                        const dayGroups = groups[day] || (groups[day] = {
                                "order": [],
                                "byKey": {}
                            });
                        const existing = dayGroups.byKey[mergeKey];
                        if (existing) {
                            if (existing.emails.indexOf(p.email) === -1) {
                                existing.stripes.push(p.color);
                                existing.emails.push(p.email);
                            }
                            continue;
                        }
                        const merged = Object.assign({}, item, {
                            "stripes": [p.color],
                            "emails": [p.email]
                        });
                        dayGroups.byKey[mergeKey] = merged;
                        dayGroups.order.push(merged);
                    }
                }
            } else if (p.status === "busy") {
                for (const b of p.busy) {
                    const item = _overlayItem(p, "busy", b, false);
                    for (const day of _daysOf(b.start, b.end, p.window)) {
                        _push(lane, day, item);
                        _push(busyByDay, day, item);
                    }
                }
            }
        }

        const byDay = {};
        for (const day in groups) {
            // A single colour means nobody merged with it: no stripe.
            byDay[day] = groups[day].order.map(g => g.stripes.length > 1 ? g : Object.assign({}, g, {
                        "stripes": []
                    }));
        }
        for (const day in busyByDay)
            byDay[day] = (byDay[day] || []).concat(busyByDay[day]);

        return {
            "shared": shared,
            "byDay": byDay,
            "lanes": lanes
        };
    }

    // Merged overlay items overlapping a day, for Week and Month.
    function overlayForDay(day) {
        version;
        return _store.index.byDay[_dayKeyOf(day)] || [];
    }

    // One person's own items overlapping a day, unmerged, for a Day lane.
    function personItemsForDay(email, day) {
        version;
        const lane = _store.index.lanes[email];
        return (lane && lane[_dayKeyOf(day)]) || [];
    }

    // Colours of the colleagues who share an own event, in chip order.
    function sharedWith(ev) {
        version;
        return (ev && _store.index.shared[EventUtils.eventKey(ev)]) || [];
    }

    function _byStart(items) {
        return items.map((item, i) => ({
                    "item": item,
                    "i": i
                })).sort((a, b) => (a.item.start - b.item.start) || (a.i - b.i)).map(e => e.item);
    }

    // Own events (in their eventsForDay order) and overlay items as one list
    // of {key, isOverlay, event}: all-day items first, then timed, each by
    // start with a colleague first on a tie. With no overlay items the own
    // events keep their order. `key` is stable across rebuilds, so a
    // ScriptModel with objectProp "key" keeps each delegate (and a drag in
    // progress on it) when the lists are recomputed.
    function mergeWithOwn(ownEvents, overlayItems) {
        const wrap = (isOverlay, ev) => ({
                "key": isOverlay ? ("colleague|" + ev.email + "|" + ev.key + "|" + ev.start.getTime() + "|" + ev.end.getTime()) : ("own|" + EventUtils.eventKey(ev)),
                "isOverlay": isOverlay,
                "event": ev
            });
        if (overlayItems.length === 0)
            return ownEvents.map(ev => wrap(false, ev));
        const merge = (own, overlay) => {
            const out = [];
            let i = 0;
            let j = 0;
            while (i < own.length || j < overlay.length) {
                if (j < overlay.length && (i >= own.length || overlay[j].start <= own[i].start))
                    out.push(wrap(true, overlay[j++]));
                else
                    out.push(wrap(false, own[i++]));
            }
            return out;
        };
        const overlay = _byStart(overlayItems);
        return merge(ownEvents.filter(ev => ev.allDay), overlay.filter(ev => ev.allDay)).concat(merge(ownEvents.filter(ev => !ev.allDay), overlay.filter(ev => !ev.allDay)));
    }

    // Stripe colours for an own chip: its own colour, then every colleague
    // who shares it. Empty when nobody does.
    function stripesFor(ev) {
        const shared = sharedWith(ev);
        return shared.length === 0 ? [] : [ev.color].concat(shared);
    }

    function personLabel(email) {
        const person = people.find(p => p.email === email);
        return (person && person.name) || email;
    }

    // Busy time and private events carry no title; the time grid draws them
    // as a background band rather than a chip.
    function isBusyTime(item) {
        return item.kind === "busy" || !!item.private;
    }

    function bandLabel(item) {
        return busyLabel + " · " + personLabel(item.email);
    }

    // Tooltip text for an overlay item: title, time, location, then every
    // person who has it.
    function tooltipFor(item) {
        const when = item.allDay ? I18n.tr("All day", "all-day marker in event tooltip") : SettingsData.formatTime(item.start) + " – " + SettingsData.formatTime(item.end);
        const parts = [item.title, when];
        if (item.location)
            parts.push(item.location);
        parts.push((item.emails || [item.email]).map(email => personLabel(email)).join(", "));
        return parts.join(" · ");
    }
}
