package google

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"google.golang.org/api/calendar/v3"
	"google.golang.org/api/option"

	cal "github.com/AvengeMedia/dankcalendar/core/internal/calendar"
)

func scheduleTestProvider(t *testing.T, handler http.HandlerFunc) *Provider {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	svc, err := calendar.NewService(context.Background(), option.WithHTTPClient(server.Client()), option.WithEndpoint(server.URL+"/"))
	require.NoError(t, err)
	q, _ := fakeQuota()
	return &Provider{account: cal.Account{ID: "me@acme.com"}, svc: svc, quota: q}
}

func writeJSON(w http.ResponseWriter, code int, body string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_, _ = w.Write([]byte(body))
}

func TestReadScheduleEventsListDetails(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	var requests []*http.Request
	freebusyCalled := false
	page := 0
	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		requests = append(requests, r)
		switch {
		case strings.Contains(r.URL.Path, "/freeBusy"):
			freebusyCalled = true
			writeJSON(w, 200, `{}`)
		case page == 0:
			page++
			writeJSON(w, 200, `{
				"accessRole": "reader",
				"nextPageToken": "p2",
				"items": [
					{"id": "evt-1", "iCalUID": "ical-1", "summary": "Planning", "status": "confirmed",
					 "start": {"dateTime": "2026-09-02T10:00:00Z"}, "end": {"dateTime": "2026-09-02T11:00:00Z"},
					 "attendees": [{"email": "alice@acme.com", "displayName": "Alice Doe"}]},
					{"id": "evt-cancelled", "status": "cancelled",
					 "start": {"dateTime": "2026-09-02T12:00:00Z"}, "end": {"dateTime": "2026-09-02T13:00:00Z"}},
					{"id": "evt-declined", "summary": "Skip", "status": "confirmed",
					 "start": {"dateTime": "2026-09-02T14:00:00Z"}, "end": {"dateTime": "2026-09-02T15:00:00Z"},
					 "attendees": [{"email": "alice@acme.com", "responseStatus": "declined"}]}
				]
			}`)
		default:
			writeJSON(w, 200, `{"accessRole": "reader", "items": [
				{"id": "evt-2", "iCalUID": "ical-2", "summary": "Retro", "status": "confirmed",
				 "start": {"dateTime": "2026-09-03T10:00:00Z"}, "end": {"dateTime": "2026-09-03T11:00:00Z"}}
			]}`)
		}
	})

	sched, err := p.ReadSchedule(context.Background(), "alice@acme.com", from, to)
	require.NoError(t, err)
	require.Equal(t, cal.ScheduleDetails, sched.Access)
	require.False(t, freebusyCalled, "freebusy must not be called when events.list gave details")
	require.Equal(t, "Alice Doe", sched.Name)
	require.Len(t, sched.Events, 2, "cancelled and declined items are dropped")
	require.Equal(t, "ical-1", sched.Events[0].ICalUID)
	require.Equal(t, "Planning", sched.Events[0].Summary)
	require.Equal(t, "Retro", sched.Events[1].Summary)

	require.NotEmpty(t, requests)
	first := requests[0]
	require.Equal(t, "true", first.URL.Query().Get("singleEvents"))
	require.Equal(t, "2026-09-01T00:00:00Z", first.URL.Query().Get("timeMin"))
	require.Equal(t, "2026-09-08T00:00:00Z", first.URL.Query().Get("timeMax"))
	require.ElementsMatch(t, []string{"default", "focusTime", "outOfOffice"}, first.URL.Query()["eventTypes"])
	require.NotEmpty(t, first.URL.Query().Get("fields"))
}

func TestReadScheduleFreeBusyReaderFallsBackToBusy(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/freeBusy"):
			writeJSON(w, 200, `{"calendars": {"alice@acme.com": {"busy": [
				{"start": "2026-09-02T10:00:00Z", "end": "2026-09-02T11:00:00Z"}
			]}}}`)
		default:
			writeJSON(w, 200, `{"accessRole": "freeBusyReader", "items": []}`)
		}
	})

	sched, err := p.ReadSchedule(context.Background(), "alice@acme.com", from, to)
	require.NoError(t, err)
	require.Equal(t, cal.ScheduleBusy, sched.Access)
	require.Len(t, sched.Busy, 1)
	require.Equal(t, time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC), sched.Busy[0].Start)
}

func TestReadScheduleNotFoundFallsBackToFreeBusy(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/freeBusy"):
			writeJSON(w, 200, `{"calendars": {"alice@acme.com": {"busy": [
				{"start": "2026-09-02T10:00:00Z", "end": "2026-09-02T11:00:00Z"}
			]}}}`)
		default:
			writeJSON(w, 404, `{"error": {"code": 404, "message": "not found"}}`)
		}
	})

	sched, err := p.ReadSchedule(context.Background(), "alice@acme.com", from, to)
	require.NoError(t, err)
	require.Equal(t, cal.ScheduleBusy, sched.Access)
	require.Len(t, sched.Busy, 1)
}

func TestReadScheduleFreeBusyNotFoundIsUnavailable(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/freeBusy"):
			writeJSON(w, 200, `{"calendars": {"nobody@acme.com": {"errors": [{"reason": "notFound"}]}}}`)
		default:
			writeJSON(w, 404, `{"error": {"code": 404, "message": "not found"}}`)
		}
	})

	sched, err := p.ReadSchedule(context.Background(), "nobody@acme.com", from, to)
	require.NoError(t, err)
	require.Equal(t, cal.ScheduleUnavailable, sched.Access)
}

func TestReadScheduleMissingScopeAfterEventsNotFound(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/freeBusy"):
			writeJSON(w, 403, `{"error": {"code": 403, "errors": [{"reason": "insufficientPermissions"}]}}`)
		default:
			writeJSON(w, 404, `{"error": {"code": 404, "message": "not found"}}`)
		}
	})

	_, err := p.ReadSchedule(context.Background(), "alice@acme.com", from, to)
	require.ErrorIs(t, err, cal.ErrScheduleScope)
}

func TestReadScheduleMissingScopeDegradesToSpans(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "/freeBusy"):
			writeJSON(w, 403, `{"error": {"code": 403, "errors": [{"reason": "insufficientPermissions"}]}}`)
		default:
			writeJSON(w, 200, `{"accessRole": "freeBusyReader", "items": [
				{"id": "evt-1", "start": {"dateTime": "2026-09-02T10:00:00Z"}, "end": {"dateTime": "2026-09-02T11:00:00Z"}}
			]}`)
		}
	})

	sched, err := p.ReadSchedule(context.Background(), "alice@acme.com", from, to)
	require.NoError(t, err)
	require.Equal(t, cal.ScheduleBusy, sched.Access)
	require.Len(t, sched.Busy, 1)
	require.Equal(t, time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC), sched.Busy[0].Start)
}

func TestReadScheduleUnauthorizedIsReauth(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)

	p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 401, `{"error": {"code": 401, "message": "invalid credentials"}}`)
	})

	_, err := p.ReadSchedule(context.Background(), "alice@acme.com", from, to)
	require.ErrorIs(t, err, cal.ErrReauthRequired)
	require.False(t, errors.Is(err, cal.ErrScheduleScope))
}
