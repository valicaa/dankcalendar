package google

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"google.golang.org/api/calendar/v3"
	"google.golang.org/api/googleapi"

	cal "github.com/AvengeMedia/dankcalendar/core/internal/calendar"
)

// scheduleFields is a partial-response Fields() list: data minimisation so a
// colleague lookup never pulls descriptions, links or conference data into
// the daemon.
const scheduleFields = "accessRole,summary,nextPageToken,items(id,iCalUID,recurringEventId,originalStartTime,start,end,summary,location,status,visibility,transparency,attendees(email,displayName,responseStatus))"

// scheduleAccessHasDetails reports whether accessRole reveals event details,
// as opposed to freeBusyReader/none which see only availability.
func scheduleAccessHasDetails(accessRole string) bool {
	switch accessRole {
	case "reader", "writerWithoutPrivateAccess", "writer", "owner":
		return true
	default:
		return false
	}
}

// ReadSchedule reads a colleague's availability: full event details where
// they share the calendar, otherwise a free/busy fallback. Nothing it reads
// is persisted, and it logs nothing.
func (p *Provider) ReadSchedule(ctx context.Context, email string, from, to time.Time) (*cal.Schedule, error) {
	events, accessRole, spans, err := p.scheduleEventsList(ctx, email, from, to)
	switch {
	case err == nil && scheduleAccessHasDetails(accessRole):
		return &cal.Schedule{Access: cal.ScheduleDetails, Name: scheduleName(events, email), Events: events}, nil
	case err == nil:
		// freeBusyReader or none: no details, fall back to freebusy but keep
		// the spans events.list already returned in case the scope is missing.
		return p.readFreeBusy(ctx, email, from, to, spans)
	}

	if quotaLimited(err) || errors.As(err, new(*deferredRetry)) {
		return nil, fmt.Errorf("read google schedule: %w", classifyAuthErr(err))
	}

	var apiErr *googleapi.Error
	if errors.As(err, &apiErr) {
		switch apiErr.Code {
		case http.StatusNotFound, http.StatusForbidden, http.StatusBadRequest:
			if !isInsufficientScope(err) {
				return p.readFreeBusy(ctx, email, from, to, nil)
			}
		}
	}
	return nil, fmt.Errorf("read google schedule: %w", classifyAuthErr(err))
}

// scheduleEventsList pages through events.list for the colleague's primary
// calendar. It returns the mapped events (when the caller ends up wanting
// details), the resolved accessRole, and the raw start/end spans of every
// item (used as a fallback when a later freebusy call hits the missing
// scope).
func (p *Provider) scheduleEventsList(ctx context.Context, email string, from, to time.Time) ([]cal.ScheduleEvent, string, []cal.TimeSpan, error) {
	var (
		events     []cal.ScheduleEvent
		spans      []cal.TimeSpan
		accessRole string
		pageToken  string
	)

	for {
		call := p.svc.Events.List(email).
			Context(ctx).
			SingleEvents(true).
			ShowDeleted(false).
			MaxResults(maxPageSize).
			EventTypes("default", "focusTime", "outOfOffice").
			TimeMin(from.Format(time.RFC3339)).
			TimeMax(to.Format(time.RFC3339)).
			Fields(googleapi.Field(scheduleFields))
		if pageToken != "" {
			call = call.PageToken(pageToken)
		}

		res, err := googleCall(ctx, p, true, func() (*calendar.Events, error) { return call.Do() })
		if err != nil {
			return nil, "", nil, err
		}
		accessRole = res.AccessRole

		for _, item := range res.Items {
			if item.Status == "cancelled" || scheduleDeclined(item, email) {
				continue
			}
			ev := fromGoogleEvent(cal.Calendar{}, item)
			events = append(events, cal.ScheduleEvent{Event: *ev, ICalUID: item.ICalUID})
			if item.Transparency != "transparent" {
				spans = append(spans, cal.TimeSpan{Start: ev.Start, End: ev.End})
			}
		}

		if res.NextPageToken == "" {
			return events, accessRole, spans, nil
		}
		pageToken = res.NextPageToken
	}
}

// scheduleDeclined reports whether the looked-up person declined this
// occurrence, in which case they are free and it should not count as busy.
func scheduleDeclined(item *calendar.Event, email string) bool {
	for _, a := range item.Attendees {
		if strings.EqualFold(a.Email, email) {
			return a.ResponseStatus == "declined"
		}
	}
	return false
}

// scheduleName picks the looked-up person's display name from whichever
// event first carries it as an attendee.
func scheduleName(events []cal.ScheduleEvent, email string) string {
	for _, ev := range events {
		for _, a := range ev.Attendees {
			if strings.EqualFold(a.Email, email) && a.DisplayName != "" {
				return a.DisplayName
			}
		}
	}
	return ""
}

// readFreeBusy is the availability-only fallback: a single-calendar
// freebusy.query. spans carries whatever events.list already saw (possibly
// nil), used only to degrade gracefully if this call also lacks the scope.
func (p *Provider) readFreeBusy(ctx context.Context, email string, from, to time.Time, spans []cal.TimeSpan) (*cal.Schedule, error) {
	req := &calendar.FreeBusyRequest{
		TimeMin: from.Format(time.RFC3339),
		TimeMax: to.Format(time.RFC3339),
		Items:   []*calendar.FreeBusyRequestItem{{Id: email}},
	}

	res, err := googleCall(ctx, p, true, func() (*calendar.FreeBusyResponse, error) {
		return p.svc.Freebusy.Query(req).Context(ctx).Do()
	})
	if err != nil {
		switch {
		case isInsufficientScope(err):
			if len(spans) > 0 {
				return &cal.Schedule{Access: cal.ScheduleBusy, Busy: spans}, nil
			}
			return nil, fmt.Errorf("read google freebusy: %w", cal.ErrScheduleScope)
		default:
			return nil, fmt.Errorf("read google freebusy: %w", classifyAuthErr(err))
		}
	}

	entry, ok := res.Calendars[email]
	if !ok || len(entry.Errors) > 0 {
		return &cal.Schedule{Access: cal.ScheduleUnavailable}, nil
	}

	busy := make([]cal.TimeSpan, 0, len(entry.Busy))
	for _, period := range entry.Busy {
		start, err := time.Parse(time.RFC3339, period.Start)
		if err != nil {
			continue
		}
		end, err := time.Parse(time.RFC3339, period.End)
		if err != nil {
			continue
		}
		busy = append(busy, cal.TimeSpan{Start: start, End: end})
	}
	return &cal.Schedule{Access: cal.ScheduleBusy, Busy: busy}, nil
}
