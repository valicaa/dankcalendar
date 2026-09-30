package google

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	cal "github.com/AvengeMedia/dankcalendar/core/internal/calendar"
)

// eventWrites runs each event mutation against p so a test can assert how
// every write path reports the same server answer.
func eventWrites() map[string]func(p *Provider) error {
	c := cal.Calendar{ID: "cal", RemoteID: "primary"}
	start := time.Date(2026, 9, 30, 9, 0, 0, 0, time.UTC)
	ev := cal.Event{
		RemoteID: "evt1", Summary: "Standup", Start: start, End: start.Add(time.Hour),
		Attendees: []cal.Attendee{{Email: "me@acme.com"}},
	}
	return map[string]func(p *Provider) error{
		"create": func(p *Provider) error { _, err := p.CreateEvent(context.Background(), c, &ev); return err },
		"update": func(p *Provider) error { _, err := p.UpdateEvent(context.Background(), c, &ev); return err },
		"delete": func(p *Provider) error { return p.DeleteEvent(context.Background(), c, ev) },
		"respond": func(p *Provider) error {
			_, err := p.RespondToEvent(context.Background(), c, &ev, cal.ResponseAccepted)
			return err
		},
	}
}

func TestEventWritesMarkDeadCredentialsForReauth(t *testing.T) {
	for name, write := range eventWrites() {
		t.Run(name+" unauthorized", func(t *testing.T) {
			p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
				writeJSON(w, http.StatusUnauthorized, `{"error": {"code": 401, "message": "invalid credentials"}}`)
			})
			require.ErrorIs(t, write(p), cal.ErrReauthRequired)
		})
		t.Run(name+" dead refresh token", func(t *testing.T) {
			require.ErrorIs(t, write(scheduleTestProviderDeadToken(t)), cal.ErrReauthRequired)
		})
	}
}

func TestEventWritesKeepOtherFailuresUntagged(t *testing.T) {
	for name, write := range eventWrites() {
		t.Run(name, func(t *testing.T) {
			p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
				writeJSON(w, http.StatusForbidden, `{"error": {"code": 403, "message": "forbidden", "errors": [{"reason": "forbidden"}]}}`)
			})
			err := write(p)
			require.Error(t, err)
			require.NotErrorIs(t, err, cal.ErrReauthRequired)
		})
	}
}

func TestCreateEventUsesUIDAsIdempotentID(t *testing.T) {
	c := cal.Calendar{ID: "cal", RemoteID: "primary"}
	start := time.Date(2026, 9, 30, 9, 0, 0, 0, time.UTC)
	const uid = "0f3a9c2e7b1d4e6f8a0b1c2d3e4f5a6b"
	created := `{"id": "` + uid + `", "summary": "Lunch", "start": {"dateTime": "2026-09-30T09:00:00Z"}, "end": {"dateTime": "2026-09-30T10:00:00Z"}}`
	const (
		duplicate = `{"error": {"code": 409, "message": "The requested identifier already exists.", "errors": [{"reason": "duplicate"}]}}`
		deleted   = `{"error": {"code": 409, "message": "Resource has been deleted", "errors": [{"reason": "deleted"}]}}`
		forbidden = `{"error": {"code": 403, "message": "forbidden", "errors": [{"reason": "forbidden"}]}}`
	)

	cases := []struct {
		name       string
		uid        string
		insertCode int
		insertBody string
		putCode    int
		putBody    string
		wantID     string
		wantCalls  []string
		wantErr    bool
	}{
		{name: "first attempt", uid: uid, insertCode: http.StatusOK, insertBody: created, wantID: uid,
			wantCalls: []string{"POST /calendars/primary/events"}},
		{name: "retry after the first attempt landed", uid: uid, insertCode: http.StatusConflict, insertBody: duplicate,
			putCode: http.StatusOK, putBody: created, wantID: uid,
			wantCalls: []string{"POST /calendars/primary/events", "PUT /calendars/primary/events/" + uid}},
		{name: "retry whose update fails", uid: uid, insertCode: http.StatusConflict, insertBody: duplicate,
			putCode: http.StatusForbidden, putBody: forbidden, wantID: uid, wantErr: true,
			wantCalls: []string{"POST /calendars/primary/events", "PUT /calendars/primary/events/" + uid}},
		{name: "conflict for a deleted id is not resurrected", uid: uid, insertCode: http.StatusConflict, insertBody: deleted,
			wantID: uid, wantErr: true, wantCalls: []string{"POST /calendars/primary/events"}},
		{name: "uid outside google's id alphabet", uid: "abc@example.com", insertCode: http.StatusOK, insertBody: created,
			wantCalls: []string{"POST /calendars/primary/events"}},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			var calls []string
			var insertedID, putSummary string
			p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
				calls = append(calls, r.Method+" "+r.URL.Path)
				var body struct {
					ID      string `json:"id"`
					Summary string `json:"summary"`
				}
				require.NoError(t, json.NewDecoder(r.Body).Decode(&body))
				if r.Method == http.MethodPost {
					insertedID = body.ID
					writeJSON(w, tt.insertCode, tt.insertBody)
					return
				}
				putSummary = body.Summary
				writeJSON(w, tt.putCode, tt.putBody)
			})

			ev := cal.Event{UID: tt.uid, Summary: "Lunch", Start: start, End: start.Add(time.Hour)}
			out, err := p.CreateEvent(context.Background(), c, &ev)
			require.Equal(t, tt.wantID, insertedID)
			require.Equal(t, tt.wantCalls, calls)
			if tt.wantErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			require.Equal(t, uid, out.RemoteID)
			if tt.putCode != 0 {
				require.Equal(t, "Lunch", putSummary, "the update carries the retried content")
			}
		})
	}
}

// TestEventWriteFailuresSurfaceAsRetryableOrNot runs a real HTTP failure
// through googleCall: back-off answers become a deferred retry the UI offers
// to retry, other statuses stay plain errors.
func TestEventWriteFailuresSurfaceAsRetryableOrNot(t *testing.T) {
	cases := []struct {
		name         string
		code         int
		reason       string
		wantDeferred bool
	}{
		{"service unavailable", http.StatusServiceUnavailable, "backendError", true},
		{"too many requests", http.StatusTooManyRequests, "rateLimitExceeded", true},
		{"forbidden", http.StatusForbidden, "forbidden", false},
		{"not found", http.StatusNotFound, "notFound", false},
	}
	for name, write := range eventWrites() {
		for _, tt := range cases {
			t.Run(name+" "+tt.name, func(t *testing.T) {
				p := scheduleTestProvider(t, func(w http.ResponseWriter, _ *http.Request) {
					w.Header().Set("Retry-After", "1")
					writeJSON(w, tt.code, fmt.Sprintf(`{"error": {"code": %d, "message": "nope", "errors": [{"reason": %q}]}}`, tt.code, tt.reason))
				})
				err := write(p)
				if name == "delete" && tt.code == http.StatusNotFound {
					require.NoError(t, err, "an already-deleted event is a successful delete")
					return
				}
				require.Error(t, err)
				var retryLater interface{ RetryAfter() time.Duration }
				require.Equal(t, tt.wantDeferred, errors.As(err, &retryLater))
			})
		}
	}
}
