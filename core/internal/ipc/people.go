package ipc

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/AvengeMedia/dankcalendar/core/ent"
	"github.com/AvengeMedia/dankcalendar/core/ent/account"
	"github.com/AvengeMedia/dankcalendar/core/internal/calendar"
	"github.com/AvengeMedia/dankcalendar/core/repo"
)

// maxScheduleRangeDays bounds a single people.schedule lookup so it never
// turns into an unbounded Google query.
const maxScheduleRangeDays = 62

func HandlePeople(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	switch req.Method {
	case "people.schedule":
		handlePeopleSchedule(ctx, w, req, deps)
	default:
		RespondError(w, req.ID, "unknown method: "+req.Method)
	}
}

// handlePeopleSchedule reads a colleague's availability for a range. Nothing
// it reads is persisted or logged; the result carries only what the provider
// returned for this one call.
func handlePeopleSchedule(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	email := strings.ToLower(strings.TrimSpace(ParamString(req.Params, "email")))
	if email == "" || strings.Count(email, "@") != 1 {
		RespondError(w, req.ID, "email must be a single address")
		return
	}

	from, err := time.Parse(time.RFC3339, ParamString(req.Params, "from"))
	if err != nil {
		RespondError(w, req.ID, "from must be RFC3339")
		return
	}
	to, err := time.Parse(time.RFC3339, ParamString(req.Params, "to"))
	if err != nil {
		RespondError(w, req.ID, "to must be RFC3339")
		return
	}
	switch {
	case !to.After(from):
		RespondError(w, req.ID, "to must be after from")
		return
	case to.Sub(from) > maxScheduleRangeDays*24*time.Hour:
		RespondError(w, req.ID, fmt.Sprintf("range must be at most %d days", maxScheduleRangeDays))
		return
	}

	if deps.Repo == nil || deps.Registry == nil {
		RespondError(w, req.ID, "people service unavailable")
		return
	}

	accounts, err := deps.Repo.ListAccounts(ctx)
	if err != nil {
		RespondError(w, req.ID, err.Error())
		return
	}
	acc, err := pickScheduleAccount(accounts, email, ParamString(req.Params, "accountId"))
	if err != nil {
		RespondError(w, req.ID, err.Error())
		return
	}

	provider, err := deps.Registry.Build(ctx, domainAccount(acc), deps.Secrets)
	if err != nil {
		RespondError(w, req.ID, err.Error())
		return
	}
	defer provider.Close()

	reader, ok := provider.(calendar.ScheduleReader)
	if !ok {
		RespondError(w, req.ID, "account does not support schedule lookups")
		return
	}

	result := map[string]any{
		"email":     email,
		"accountId": acc.ID,
		"name":      "",
		"events":    []any{},
		"busy":      []any{},
	}

	sched, err := reader.ReadSchedule(ctx, email, from, to)
	switch {
	case errors.Is(err, calendar.ErrScheduleScope), errors.Is(err, calendar.ErrReauthRequired):
		result["status"] = "reconnect"
		Respond(w, req.ID, result)
		return
	case err != nil:
		RespondError(w, req.ID, err.Error())
		return
	}

	result["status"] = string(sched.Access)
	result["name"] = sched.Name

	switch sched.Access {
	case calendar.ScheduleDetails:
		idx, err := newOwnerScheduleIndex(ctx, deps, email, from, to)
		if err != nil {
			RespondError(w, req.ID, err.Error())
			return
		}
		result["events"] = scheduleEventsJSON(sched.Events, idx)
	case calendar.ScheduleBusy:
		result["busy"] = busySpansJSON(sched.Busy)
	}

	Respond(w, req.ID, result)
}

// domainAccount converts a stored account into the domain shape a provider
// factory builds from, shared by anything that hands an account to
// deps.Registry.Build.
func domainAccount(acc *ent.Account) calendar.Account {
	return calendar.Account{ID: acc.ID, Kind: calendar.AccountKind(acc.Kind), DisplayName: acc.DisplayName, Settings: acc.Settings}
}

// pickScheduleAccount chooses which of the user's Google accounts reads a
// colleague's schedule: an explicit override, otherwise the first whose
// domain matches the looked-up address, otherwise the first Google account.
func pickScheduleAccount(accounts []*ent.Account, email, override string) (*ent.Account, error) {
	override = strings.ToLower(strings.TrimSpace(override))

	var googleAccounts []*ent.Account
	for _, a := range accounts {
		if a.Kind == account.KindGoogle {
			googleAccounts = append(googleAccounts, a)
		}
	}

	if override != "" {
		for _, a := range googleAccounts {
			if a.ID == override {
				return a, nil
			}
		}
		return nil, fmt.Errorf("accountId %q is not a connected Google account", override)
	}

	if len(googleAccounts) == 0 {
		return nil, errors.New("no Google account connected")
	}

	domain := emailDomain(email)
	for _, a := range googleAccounts {
		if emailDomain(a.ID) == domain {
			return a, nil
		}
	}
	return googleAccounts[0], nil
}

func emailDomain(email string) string {
	i := strings.LastIndex(email, "@")
	if i < 0 {
		return ""
	}
	return email[i+1:]
}

// ownerMatch identifies the owner's own occurrence a colleague event shares.
type ownerMatch struct {
	eventID string
	uid     string
	start   time.Time
}

// ownerScheduleIndex looks up the owner's own occurrences by the identity a
// colleague's copy of the same event carries: the RFC 5545 pair UID +
// RECURRENCE-ID. Only the owner's own visible Google calendars are
// candidates: a hidden calendar's copy never suppresses a colleague chip
// behind an event the owner never draws, and a calendar merely subscribed
// from someone else's account never masquerades as the owner's own.
type ownerScheduleIndex struct {
	byUID      map[string]ownerMatch
	byUIDStart map[string]ownerMatch
}

func newOwnerScheduleIndex(ctx context.Context, deps Deps, email string, from, to time.Time) (*ownerScheduleIndex, error) {
	idx := &ownerScheduleIndex{byUID: map[string]ownerMatch{}, byUIDStart: map[string]ownerMatch{}}

	cals, err := deps.Repo.ListCalendars(ctx)
	if err != nil {
		return nil, err
	}

	var ownedGoogleIDs []string
	for _, c := range cals {
		switch {
		case c.Hidden || c.Edges.Account == nil || c.Edges.Account.Kind != account.KindGoogle:
			continue
		case c.RemoteID == email:
			// A calendar subscribed from the colleague's own account carries
			// their address as its RemoteID; it is never one the owner owns,
			// and matching against it would report the colleague's events
			// as the owner's own.
			continue
		case c.RemoteID != "primary" && c.RemoteID != c.Edges.Account.ID:
			// Only the owner's primary calendar is indexed: a calendar the
			// owner merely subscribes to (any other RemoteID) is not one of
			// their own occurrences.
			continue
		}
		ownedGoogleIDs = append(ownedGoogleIDs, c.ID)
	}
	if len(ownedGoogleIDs) == 0 {
		// No candidates: passing an empty CalendarIDs filter to ListEvents
		// would mean "every calendar", the opposite of what's intended here.
		return idx, nil
	}

	events, _, err := deps.Repo.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{CalendarIDs: ownedGoogleIDs, From: &from, To: &to, IncludeRecurring: true},
	})
	if err != nil {
		return nil, err
	}

	for _, ev := range events {
		m := ownerMatch{eventID: ev.ID, uid: ev.UID, start: ev.Start}
		if ev.RecurringID != ev.UID {
			// A generated recurrence copy shares the master's UID (and
			// RecurringID == UID), so indexing it here would let whichever
			// occurrence is visited last in this loop overwrite the real
			// single/exception match for that UID; byUIDStart is where
			// these copies are looked up instead.
			idx.byUID[ev.UID] = m
		}
		idx.byUIDStart[ev.UID+"|"+ev.Start.UTC().Format(time.RFC3339)] = m
	}
	return idx, nil
}

// match identifies the owner's own occurrence a colleague event shares:
// own.UID == theirs.UID covers single events and owner exception rows;
// own.UID == theirs.RecurringID with matching start covers owner occurrences
// expanded from a recurring master.
func (idx *ownerScheduleIndex) match(ev calendar.ScheduleEvent) (ownerMatch, bool) {
	if m, ok := idx.byUID[ev.UID]; ok {
		return m, true
	}
	if ev.RecurringID == "" {
		return ownerMatch{}, false
	}
	m, ok := idx.byUIDStart[ev.RecurringID+"|"+ev.OriginalStart.UTC().Format(time.RFC3339)]
	return m, ok
}

func scheduleEventsJSON(events []calendar.ScheduleEvent, idx *ownerScheduleIndex) []any {
	out := make([]any, 0, len(events))
	for _, ev := range events {
		keyStart := ev.OriginalStart
		if keyStart.IsZero() {
			keyStart = ev.Start
		}
		entry := map[string]any{
			"key":      ev.ICalUID + "|" + keyStart.UTC().Format(time.RFC3339),
			"summary":  ev.Summary,
			"location": ev.Location,
			"start":    ev.Start.UTC().Format(time.RFC3339),
			"end":      ev.End.UTC().Format(time.RFC3339),
			"allDay":   ev.AllDay,
			"status":   string(ev.Status),
			"private":  ev.Summary == "",
		}
		if m, ok := idx.match(ev); ok {
			entry["ownEventId"] = m.eventID
			entry["ownUid"] = m.uid
			entry["ownStart"] = m.start.UTC().Format(time.RFC3339)
		}
		out = append(out, entry)
	}
	return out
}

func busySpansJSON(spans []calendar.TimeSpan) []any {
	out := make([]any, 0, len(spans))
	for _, s := range spans {
		out = append(out, map[string]any{
			"start": s.Start.UTC().Format(time.RFC3339),
			"end":   s.End.UTC().Format(time.RFC3339),
		})
	}
	return out
}
