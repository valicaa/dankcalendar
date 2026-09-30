package google

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
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

	cases := []struct {
		name      string
		uid       string
		insert    int
		wantID    string
		wantCalls []string
	}{
		{"first attempt", uid, http.StatusOK, uid, []string{"POST /calendars/primary/events"}},
		{"retry after the first attempt landed", uid, http.StatusConflict, uid,
			[]string{"POST /calendars/primary/events", "PUT /calendars/primary/events/" + uid}},
		{"uid outside google's id alphabet", "abc@example.com", http.StatusOK, "", []string{"POST /calendars/primary/events"}},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			var calls []string
			var insertedID string
			p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
				calls = append(calls, r.Method+" "+r.URL.Path)
				var body struct {
					ID string `json:"id"`
				}
				require.NoError(t, json.NewDecoder(r.Body).Decode(&body))
				if r.Method == http.MethodPost {
					insertedID = body.ID
					if tt.insert == http.StatusConflict {
						writeJSON(w, http.StatusConflict, `{"error": {"code": 409, "message": "The requested identifier already exists.", "errors": [{"reason": "duplicate"}]}}`)
						return
					}
				}
				writeJSON(w, http.StatusOK, created)
			})

			ev := cal.Event{UID: tt.uid, Summary: "Lunch", Start: start, End: start.Add(time.Hour)}
			out, err := p.CreateEvent(context.Background(), c, &ev)
			require.NoError(t, err)
			require.Equal(t, tt.wantID, insertedID)
			require.Equal(t, tt.wantCalls, calls)
			require.Equal(t, uid, out.RemoteID)
		})
	}
}

func TestValidGoogleEventID(t *testing.T) {
	cases := map[string]bool{
		"0f3a9c2e7b1d4e6f8a0b1c2d3e4f5a6b": true,
		"vvvvv":                            true,
		"abcd":                             false,
		"ABCDE":                            false,
		"wxyz0":                            false,
		"0f3a9c2e-7b1d-4e6f":               false,
		strings.Repeat("a", 1024):          true,
		strings.Repeat("a", 1025):          false,
	}
	for id, want := range cases {
		require.Equal(t, want, validGoogleEventID(id), "%.12s… (len %d)", id, len(id))
	}
}
